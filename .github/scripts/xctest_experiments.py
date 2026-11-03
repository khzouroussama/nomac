#!/usr/bin/env python3
"""Observe what `xcodebuild test` does with an app's test bundles on a device, for `nomac test`.

Runs on a macOS machine with Xcode 27.0 (docs/VERIFICATION.md "Without CI") and an iPhone with
Developer Mode on. The project is written here from scratch: a SwiftUI app (`App`, no macros: the offline sandbox stops the plugin server), a unit-test
bundle hosted in it (`AppTests`) and a UI-test bundle (`AppUITests`), each a synchronized folder,
and a shared scheme `App` that tests both. The build signs with a development identity and
profile (--identity, --profile; Apple Development, manual signing) in a temporary keychain, and
runs offline; the test run itself only talks to the device.

- build-for-testing: `xcodebuild build-for-testing` for `generic/platform=iOS`, with the
  products (`.xctestrun`, the hosted `.xctest`, `AppUITests-Runner.app`) listed by relative path,
  the `.xctestrun` as JSON, and each bundle's Info.plist keys.
- test-pass: `xcodebuild test-without-building -xctestrun` on --device with every test passing,
  for the exit status, the console log and the result bundle.
- test-mixed: the same with a failing, a skipped and an expected-failure test, and a Swift Testing
  test beside the XCTest ones.
- xctestrun-<variant>: build-for-testing unsigned, for the `.xctestrun` of each variant of the
  scheme and project (XCTESTRUN_VARIANTS): the base project, the test action's own environment
  and arguments (with a disabled variable and argument), the launch action's (shared with the test action), code coverage, the Release
  configuration, an unhosted unit test, the UI test alone, a test plan, and an app that does not compile.
  With --nomac, `nomac build ... build-for-testing` runs on the same project and its `.xctestrun`
  and products are compared with Xcode's.
- installed: the bundle identifiers on the device after a run (installed apps whose identifier
  starts with --bundle-prefix), then their removal.

Outputs go to --output (outside the repository): one folder per experiment with `stdout.txt` and `stderr.txt`
(xcodebuild's output with the device's identifier and the home folder replaced), `status`, and
the result bundle's `xcresulttool` summaries as JSON. Each experiment prints a one-line summary.
"""
import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

DEVELOPER_DIR = "/Applications/Xcode_27.app/Contents/Developer"
KEYCHAIN = Path.home() / "nomac-out/device/scripts/dev_keychain.py"

APP_SOURCE = """import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class Model: ObservableObject {
    @Published var count = 0
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack {
            Text("Count: \\(model.count)").accessibilityIdentifier("count")
            Button("Increment") { model.count = Counter.next(model.count) }.accessibilityIdentifier("increment")
        }
    }
}
"""

COUNTER_SOURCE = """enum Counter {
    static func next(_ value: Int) -> Int { value + 1 }
}
"""

UNIT_PASS = """import XCTest
@testable import App

final class CounterTests: XCTestCase {
    func testNext() {
        XCTAssertEqual(Counter.next(1), 2)
    }

    func testNextOfZero() {
        XCTAssertEqual(Counter.next(0), 1)
    }
}
"""

UNIT_MIXED = """import XCTest
@testable import App

final class CounterTests: XCTestCase {
    func testNext() {
        XCTAssertEqual(Counter.next(1), 2)
    }

    func testFails() {
        XCTAssertEqual(Counter.next(1), 3, "one more than one")
    }

    func testSkipped() throws {
        throw XCTSkip("not on this device")
    }

    func testExpectedFailure() {
        XCTExpectFailure("known")
        XCTAssertEqual(Counter.next(2), 4)
    }
}
"""

SWIFT_TESTING = """import Testing
@testable import App

@Test func nextOfTwo() {
    #expect(Counter.next(2) == 3)
}

@Test func nextFails() {
    #expect(Counter.next(2) == 5)
}
"""

UI_SOURCE = """import XCTest

final class AppUITests: XCTestCase {
    func testIncrement() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["increment"].tap()
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 1")
    }
}
"""

IDS = {name: f"A{index:023X}" for index, name in enumerate([
    "project", "main", "products", "app.product", "tests.product", "uitests.product",
    "app.folder", "tests.folder", "uitests.folder", "app.target", "tests.target", "uitests.target",
    "app.sources", "tests.sources", "uitests.sources", "app.frameworks", "tests.frameworks",
    "uitests.frameworks", "app.resources", "tests.resources", "uitests.resources",
    "project.list", "project.debug", "project.release", "app.list", "app.debug", "app.release",
    "tests.list", "tests.debug", "tests.release", "uitests.list", "uitests.debug",
    "uitests.release", "tests.dependency", "tests.proxy", "uitests.dependency", "uitests.proxy"], 1)}


def configuration_list(key, settings):
    lines = []
    for name in ("debug", "release"):
        body = "".join(f"\t\t\t\t{k} = {v};\n" for k, v in sorted(settings(name).items()))
        lines.append(f"\t\t{IDS[key + '.' + name]} = {{\n\t\t\tisa = XCBuildConfiguration;\n"
                     f"\t\t\tbuildSettings = {{\n{body}\t\t\t}};\n\t\t\tname = {name.capitalize()};\n\t\t}};\n")
    lines.append(f"\t\t{IDS[key + '.list']} = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                 f"\t\t\t\t{IDS[key + '.debug']},\n\t\t\t\t{IDS[key + '.release']},\n\t\t\t);\n"
                 f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
    return "".join(lines)


def target(key, name, product_type, dependency=None):
    phases = [key + ".sources", key + ".frameworks", key + ".resources"]
    dependencies = f"\t\t\t\t{IDS[dependency]},\n" if dependency else ""
    return (f"\t\t{IDS[key + '.target']} = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {IDS[key + '.list']};\n"
            f"\t\t\tbuildPhases = (\n" + "".join(f"\t\t\t\t{IDS[p]},\n" for p in phases) + "\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{dependencies}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{IDS[key + '.folder']},\n\t\t\t);\n"
            f"\t\t\tname = {name};\n\t\t\tproductName = {name};\n"
            f"\t\t\tproductReference = {IDS[key + '.product']};\n"
            f"\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")


def pbxproj(prefix, team, profile, variant):
    signing = {"CODE_SIGNING_ALLOWED": "NO"} if variant.get("unsigned") else {
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": '"Apple Development"', "DEVELOPMENT_TEAM": team,
        "PROVISIONING_PROFILE_SPECIFIER": f'"{profile}"'}
    common = {**signing, "GENERATE_INFOPLIST_FILE": "YES",
              "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": '"1,2"', "CURRENT_PROJECT_VERSION": "1",
              "MARKETING_VERSION": "1.0"}

    def project_settings(name):
        values = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "ALWAYS_SEARCH_USER_PATHS": "NO"}
        if name == "debug":
            values.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "ENABLE_TESTABILITY": "YES",
                           "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
                           "GCC_OPTIMIZATION_LEVEL": "0"})
        else:
            values.update({"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SWIFT_COMPILATION_MODE": "wholemodule"})
        return values

    def app_settings(_):
        return dict(common, PRODUCT_BUNDLE_IDENTIFIER=prefix, PRODUCT_NAME='"$(TARGET_NAME)"',
                    INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES",
                    INFOPLIST_KEY_UILaunchScreen_Generation="YES",
                    LD_RUNPATH_SEARCH_PATHS='"$(inherited) @executable_path/Frameworks"')

    def tests_settings(_):
        hosting = {} if variant.get("unhosted") else {
            "BUNDLE_LOADER": '"$(TEST_HOST)"', "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App"'}
        return dict(common, PRODUCT_BUNDLE_IDENTIFIER=f"{prefix}.tests", PRODUCT_NAME='"$(TARGET_NAME)"', **hosting)

    def uitests_settings(_):
        return dict(common, PRODUCT_BUNDLE_IDENTIFIER=f"{prefix}.uitests", PRODUCT_NAME='"$(TARGET_NAME)"',
                    TEST_TARGET_NAME="App")

    objects = []
    for key, name in (("app", "App.app"), ("tests", "AppTests.xctest"), ("uitests", "AppUITests.xctest")):
        file_type = "wrapper.application" if key == "app" else "wrapper.cfbundle"
        objects.append(f"\t\t{IDS[key + '.product']} = {{isa = PBXFileReference; explicitFileType = {file_type}; "
                       f"includeInIndex = 0; path = {name}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    for key, path in (("app", "App"), ("tests", "AppTests"), ("uitests", "AppUITests")):
        objects.append(f"\t\t{IDS[key + '.folder']} = {{isa = PBXFileSystemSynchronizedRootGroup; path = {path}; "
                       f"sourceTree = \"<group>\"; }};\n")
    for key in ("app", "tests", "uitests"):
        for phase, isa in (("sources", "PBXSourcesBuildPhase"), ("frameworks", "PBXFrameworksBuildPhase"),
                           ("resources", "PBXResourcesBuildPhase")):
            objects.append(f"\t\t{IDS[key + '.' + phase]} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
                           f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    for key in ("tests", "uitests"):
        objects.append(f"\t\t{IDS[key + '.proxy']} = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                       f"\t\t\tcontainerPortal = {IDS['project']};\n\t\t\tproxyType = 1;\n"
                       f"\t\t\tremoteGlobalIDString = {IDS['app.target']};\n\t\t\tremoteInfo = App;\n\t\t}};\n")
        objects.append(f"\t\t{IDS[key + '.dependency']} = {{\n\t\t\tisa = PBXTargetDependency;\n"
                       f"\t\t\ttarget = {IDS['app.target']};\n\t\t\ttargetProxy = {IDS[key + '.proxy']};\n\t\t}};\n")
    objects.append(f"\t\t{IDS['main']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                   + "".join(f"\t\t\t\t{IDS[k]},\n" for k in ("app.folder", "tests.folder", "uitests.folder", "products"))
                   + "\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
    objects.append(f"\t\t{IDS['products']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                   + "".join(f"\t\t\t\t{IDS[k]},\n" for k in ("app.product", "tests.product", "uitests.product"))
                   + "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
    objects.append(target("app", "App", "com.apple.product-type.application"))
    objects.append(target("tests", "AppTests", "com.apple.product-type.bundle.unit-test", "tests.dependency"))
    objects.append(target("uitests", "AppUITests", "com.apple.product-type.bundle.ui-testing", "uitests.dependency"))
    attributes = "".join(f"\t\t\t\t\t{IDS[k + '.target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n"
                         + (f"\t\t\t\t\t\tTestTargetID = {IDS['app.target']};\n" if k != "app" else "")
                         + "\t\t\t\t\t};\n" for k in ("app", "tests", "uitests"))
    objects.append(f"\t\t{IDS['project']} = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
                   f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2700;\n"
                   f"\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t\tTargetAttributes = {{\n{attributes}\t\t\t\t}};\n\t\t\t}};\n"
                   f"\t\t\tbuildConfigurationList = {IDS['project.list']};\n\t\t\tdevelopmentRegion = en;\n"
                   f"\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
                   f"\t\t\tmainGroup = {IDS['main']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
                   f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {IDS['products']};\n"
                   f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n"
                   + "".join(f"\t\t\t\t{IDS[k + '.target']},\n" for k in ("app", "tests", "uitests"))
                   + "\t\t\t);\n\t\t};\n")
    objects.append(configuration_list("project", project_settings))
    objects.append(configuration_list("app", app_settings))
    objects.append(configuration_list("tests", tests_settings))
    objects.append(configuration_list("uitests", uitests_settings))
    return ("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n"
            + "".join(objects) + f"\t}};\n\trootObject = {IDS['project']};\n}}\n")


def buildable(key, name, product):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{IDS[key + ".target"]}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:App.xcodeproj"/>')


def variables(tag, values, disabled=None):
    if not values and not disabled:
        return ""
    inner = "".join(f'<EnvironmentVariable key = "{k}" value = "{v}" isEnabled = "YES"/>' for k, v in (values or {}).items())
    inner += "".join(f'<EnvironmentVariable key = "{k}" value = "{v}" isEnabled = "NO"/>' for k, v in (disabled or {}).items())
    return f"<{tag}>{inner}</{tag}>"


def arguments(values, disabled=None):
    if not values and not disabled:
        return ""
    inner = "".join(f'<CommandLineArgument argument = "{v}" isEnabled = "YES"/>' for v in values or [])
    inner += "".join(f'<CommandLineArgument argument = "{v}" isEnabled = "NO"/>' for v in disabled or [])
    return f"<CommandLineArguments>{inner}</CommandLineArguments>"


def scheme(variant):
    unit = [] if variant.get("no_unit") else [("tests", "AppTests", "AppTests.xctest")]
    ui = [] if variant.get("no_ui") else [("uitests", "AppUITests", "AppUITests.xctest")]
    testables = "".join(f'<TestableReference skipped = "NO">{buildable(k, n, p)}</TestableReference>'
                        for k, n, p in unit + ui)
    coverage = ' codeCoverageEnabled = "YES"' if variant.get("coverage") else ""
    use_launch = "NO" if variant.get("test_env") or variant.get("test_args") else "YES"
    plan = ('<TestPlans><TestPlanReference reference = "container:App.xctestplan" default = "YES"/></TestPlans>'
            if variant.get("test_plan") else f"<Testables>{testables}</Testables>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion = "2700" version = "1.7">\n'
            '<BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES"><BuildActionEntries>'
            '<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
            f'buildForArchiving = "YES" buildForAnalyzing = "YES">{buildable("app", "App", "App.app")}</BuildActionEntry>'
            '</BuildActionEntries></BuildAction>\n'
            f'<TestAction buildConfiguration = "{variant.get("configuration", "Debug")}" '
            'selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
            f'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "{use_launch}"{coverage}>'
            f'{plan}{arguments(variant.get("test_args"), variant.get("test_args_off"))}'
            f'{variables("EnvironmentVariables", variant.get("test_env"), variant.get("test_env_off"))}</TestAction>\n'
            '<LaunchAction buildConfiguration = "Debug" launchStyle = "0" useCustomWorkingDirectory = "NO" '
            'ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" '
            'allowLocationSimulation = "YES"><BuildableProductRunnable runnableDebuggingMode = "0">'
            f'{buildable("app", "App", "App.app")}</BuildableProductRunnable>'
            f'{arguments(variant.get("launch_args"))}{variables("EnvironmentVariables", variant.get("launch_env"))}</LaunchAction>\n</Scheme>\n')


def test_plan():
    targets = "".join(f'{{"target": {{"containerPath": "container:App.xcodeproj", "identifier": "{IDS[k + ".target"]}", "name": "{n}"}}}},'
                      for k, n in (("tests", "AppTests"), ("uitests", "AppUITests")))
    return ('{"configurations": [{"id": "11111111-2222-3333-4444-555555555555", "name": "Configuration 1", "options": {}}], '
            '"defaultOptions": {"environmentVariableEntries": [{"key": "PLAN_VARIABLE", "value": "1"}]}, '
            f'"testTargets": [{targets.rstrip(",")}], "version": 1}}\n')


UNIT_UNHOSTED = """import XCTest

final class LogicTests: XCTestCase {
    func testAddition() {
        XCTAssertEqual(1 + 1, 2)
    }
}
"""


def write_project(directory, prefix, team, profile, mixed, variant=None):
    variant = variant or {}
    if directory.exists():
        shutil.rmtree(directory)
    for folder in ("App", "AppTests", "AppUITests", "App.xcodeproj/xcshareddata/xcschemes"):
        (directory / folder).mkdir(parents=True)
    (directory / "App/DemoApp.swift").write_text(APP_SOURCE)
    (directory / "App/Counter.swift").write_text(COUNTER_SOURCE)
    (directory / "AppTests/CounterTests.swift").write_text(UNIT_UNHOSTED if variant.get("unhosted") else UNIT_MIXED if mixed else UNIT_PASS)
    if mixed:
        (directory / "AppTests/SwiftTestingTests.swift").write_text(SWIFT_TESTING)
    (directory / "AppUITests/AppUITests.swift").write_text(UI_SOURCE)
    (directory / "App.xcodeproj/project.pbxproj").write_text(pbxproj(prefix, team, profile, variant))
    (directory / "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme").write_text(scheme(variant))
    if variant.get("test_plan"):
        (directory / "App.xctestplan").write_text(test_plan())
    if variant.get("broken"):
        (directory / "App/Broken.swift").write_text('let broken: Int = ""\n')


def environment():
    return dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)


def scrub(text, device):
    text = text.replace(str(Path.home()), "$HOME")
    return text.replace(device, "<DEVICE>") if device else text


OFFLINE = ["sandbox-exec", "-p", '(version 1)(allow default)(deny network-outbound (remote ip))']


def build_for_testing(work, out, signed=True):
    derived = work / "DerivedData"
    command = ([sys.executable, str(KEYCHAIN)] if signed else OFFLINE) + [
        "xcodebuild", "build-for-testing", "-project", "App.xcodeproj", "-scheme", "App", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(derived)]
    result = subprocess.run(command, cwd=work, env=environment(), capture_output=True, text=True)
    out.mkdir(parents=True, exist_ok=True)
    (out / "stdout.txt").write_text(scrub(result.stdout, None))
    (out / "stderr.txt").write_text(scrub(result.stderr, None))
    (out / "status").write_text(f"{result.returncode}\n")
    products = derived / "Build/Products"
    if result.returncode == 0:
        listing = sorted(str(p.relative_to(products)) for p in products.rglob("*") if not p.is_symlink() or p.is_file())
        (out / "products.txt").write_text("\n".join(listing) + "\n")
        for xctestrun in products.glob("*.xctestrun"):
            with open(xctestrun, "rb") as handle:
                value = plistlib.load(handle)
            (out / (xctestrun.name + ".json")).write_text(scrub(json.dumps(value, indent=1, sort_keys=True, default=str), None))
            shutil.copyfile(xctestrun, out / xctestrun.name)
        for bundle in [*products.rglob("*.xctest"), *products.rglob("*.app")]:
            plist = bundle / "Info.plist"
            if plist.exists():
                with open(plist, "rb") as handle:
                    value = plistlib.load(handle)
                name = str(bundle.relative_to(products)).replace("/", "_")
                (out / f"Info-{name}.json").write_text(json.dumps(value, indent=1, sort_keys=True, default=str))
    print(f"build-for-testing: status {result.returncode}, {len(list(products.glob('*.xctestrun')))} xctestrun")
    return result.returncode == 0


def product_files(products):
    return sorted(str(p.relative_to(products)) for p in products.rglob("*")
                  if ".swiftmodule" not in str(p) and ".dSYM" not in str(p) and (not p.is_symlink() or p.is_file()))


def compare_nomac(nomac, work, out):
    """`nomac build ... build-for-testing` on the same project: its status, its `.xctestrun`
    byte for byte against Xcode's, and its products' file names."""
    derived = work / "NomacDerivedData"
    shutil.rmtree(derived, ignore_errors=True)
    result = subprocess.run([nomac, "build", "-project", "App.xcodeproj", "-scheme", "App", "-destination", "generic/platform=iOS",
                             "-derivedDataPath", str(derived), "--developer-dir", DEVELOPER_DIR, "build-for-testing"],
                            cwd=work, env=environment(), capture_output=True, text=True)
    (out / "nomac-stdout.txt").write_text(scrub(result.stdout, None))
    (out / "nomac-stderr.txt").write_text(scrub(result.stderr, None))
    xcode = work / "DerivedData/Build/Products"
    mine = derived / "Build/Products"
    files = [f.name for f in xcode.glob("*.xctestrun")]
    same = [name for name in files if (mine / name).exists() and (mine / name).read_bytes() == (xcode / name).read_bytes()]
    products = product_files(xcode) == product_files(mine) if mine.exists() else False
    print(f"  nomac: status {result.returncode}, xctestrun {len(same)}/{len(files)} identical, products {'same' if products else 'differ'}")
    shutil.rmtree(derived, ignore_errors=True)


def xcresult(bundle, out, device):
    for name, arguments in (("summary", ["get", "test-results", "summary"]), ("tests", ["get", "test-results", "tests"]),
                            ("build", ["get", "build-results"]), ("metadata", ["get", "content-availability"])):
        result = subprocess.run(["xcrun", "xcresulttool", *arguments, "--path", str(bundle), "--compact"],
                                env=environment(), capture_output=True, text=True)
        (out / f"xcresult-{name}.json").write_text(scrub(result.stdout if result.returncode == 0 else result.stderr, device))
    listing = sorted(str(p.relative_to(bundle)) for p in bundle.rglob("*"))
    (out / "xcresult-files.txt").write_text("\n".join(listing) + "\n")


def test_without_building(work, out, device):
    products = work / "DerivedData/Build/Products"
    xctestrun = next(products.glob("*.xctestrun"))
    bundle = work / "Result.xcresult"
    if bundle.exists():
        shutil.rmtree(bundle)
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(xctestrun), "-destination", f"platform=iOS,id={device}",
               "-resultBundlePath", str(bundle), "-derivedDataPath", str(work / "TestDerivedData")]
    result = subprocess.run(command, cwd=work, env=environment(), capture_output=True, text=True)
    shutil.rmtree(work / "TestDerivedData", ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)
    (out / "stdout.txt").write_text(scrub(result.stdout, device))
    (out / "stderr.txt").write_text(scrub(result.stderr, device))
    (out / "status").write_text(f"{result.returncode}\n")
    if bundle.exists():
        xcresult(bundle, out, device)
    shutil.rmtree(bundle, ignore_errors=True)
    shutil.rmtree(work / "DerivedData", ignore_errors=True)
    summary = re.findall(r"^(\*\* .* \*\*|Executed .*)$", result.stdout, re.MULTILINE)
    print(f"{out.name}: status {result.returncode}; {'; '.join(summary[-2:])}")


def installed(device, prefix, out, remove):
    listing = out / "apps.json"
    subprocess.run(["xcrun", "devicectl", "device", "info", "apps", "--device", device, "--json-output", str(listing)],
                   env=environment(), capture_output=True, text=True)
    apps = json.loads(listing.read_text())["result"]["apps"]
    ours = sorted(app["bundleIdentifier"] for app in apps if app["bundleIdentifier"].startswith(prefix))
    listing.write_text(json.dumps(ours, indent=1) + "\n")
    print(f"installed: {', '.join(ours) or 'none'}")
    if remove:
        for identifier in ours:
            subprocess.run(["xcrun", "devicectl", "device", "uninstall", "app", "--device", device, identifier],
                           env=environment(), capture_output=True, text=True)


XCTESTRUN_VARIANTS = {
    "base": {},
    "test-env": {"test_env": {"TEST_VARIABLE": "1"}, "test_args": ["-TestArgument", "YES"], "test_env_off": {"OFF_VARIABLE": "1"},
                 "test_args_off": ["-OffArgument"]},
    "launch-env": {"launch_env": {"LAUNCH_VARIABLE": "1"}, "launch_args": ["-LaunchArgument"]},
    "coverage": {"coverage": True},
    "release": {"configuration": "Release", "unhosted": True},
    "unhosted": {"unhosted": True},
    "ui-only": {"no_unit": True},
    "unit-only": {"no_ui": True},
    "test-plan": {"test_plan": True},
    "failing": {"broken": True},
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("experiments", nargs="*", default=["test-pass", "test-mixed", "installed"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True, help="scratch folder for the projects and DerivedData")
    parser.add_argument("--device", help="the iPhone's identifier (from `xcrun devicectl list devices`)")
    parser.add_argument("--bundle-prefix", default="com.example.nomac.xctest")
    parser.add_argument("--team", required=True, help="the development team of --identity")
    parser.add_argument("--profile", default="nomac Development")
    parser.add_argument("--keep-apps", action="store_true", help="leave the test apps installed")
    parser.add_argument("--nomac", help="a nomac executable: also run its build-for-testing on each xctestrun variant and compare")
    arguments = parser.parse_args()
    for experiment in arguments.experiments:
        if experiment == "installed":
            installed(arguments.device, arguments.bundle_prefix, arguments.output, not arguments.keep_apps)
            continue
        if experiment.startswith("xctestrun-"):
            name = experiment.removeprefix("xctestrun-")
            variant = dict(XCTESTRUN_VARIANTS[name], unsigned=True)
            work = arguments.work / experiment
            write_project(work, arguments.bundle_prefix, arguments.team, arguments.profile, False, variant)
            build_for_testing(work, arguments.output / experiment, signed=False)
            if arguments.nomac:
                compare_nomac(arguments.nomac, work, arguments.output / experiment)
            shutil.rmtree(work / "DerivedData", ignore_errors=True)
            continue
        mixed = experiment == "test-mixed"
        work = arguments.work / ("mixed" if mixed else "pass")
        write_project(work, arguments.bundle_prefix, arguments.team, arguments.profile, mixed)
        if not build_for_testing(work, arguments.output / f"build-for-testing-{'mixed' if mixed else 'pass'}"):
            continue
        if experiment.startswith("test-"):
            test_without_building(work, arguments.output / experiment, arguments.device)


if __name__ == "__main__":
    main()

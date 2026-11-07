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
  configuration, an unhosted unit test, the UI test alone, a test plan, and an app that does not compile;
  for code coverage's buildable infos, source files in subfolders, a framework and a static library,
  and coverage limited to chosen targets; for test plans, several configurations, each kind of
  option the corpus's plans use, and two plans in one scheme.
  With --nomac, `nomac build ... build-for-testing` runs on the same project and its `.xctestrun`
  and products are compared with Xcode's.
- xcresult-pass, xcresult-mixed: `xcodebuild test` of the unit-test-only project on a simulator made
  and deleted for the run, keeping the result bundle in the experiment's folder, to dissect it.
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
    "uitests.release", "tests.dependency", "tests.proxy", "uitests.dependency", "uitests.proxy",
    "kit.product", "stat.product", "kit.folder", "stat.folder", "kit.target", "stat.target", "kit.sources", "stat.sources",
    "kit.frameworks", "stat.frameworks", "kit.resources", "stat.resources", "kit.list", "kit.debug", "kit.release",
    "stat.list", "stat.debug", "stat.release", "kit.dependency", "kit.proxy", "stat.dependency", "stat.proxy",
    "package.reference", "package.product", "package.file"], 1)}


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


def target(key, name, product_type, dependency=(), package=False):
    phases = [key + ".sources", key + ".frameworks", key + ".resources"]
    products = f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{IDS['package.product']},\n\t\t\t);\n" if package else ""
    dependencies = "".join(f"\t\t\t\t{IDS[item]},\n" for item in dependency)
    return (f"\t\t{IDS[key + '.target']} = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {IDS[key + '.list']};\n"
            f"\t\t\tbuildPhases = (\n" + "".join(f"\t\t\t\t{IDS[p]},\n" for p in phases) + "\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{dependencies}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{IDS[key + '.folder']},\n\t\t\t);\n"
            f"\t\t\tname = {name};\n{products}\t\t\tproductName = {name};\n"
            f"\t\t\tproductReference = {IDS[key + '.product']};\n"
            f"\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")


def pbxproj(prefix, team, profile, variant):
    signing = {"CODE_SIGNING_ALLOWED": "NO"} if variant.get("unsigned") else {
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": '"Apple Development"', "DEVELOPMENT_TEAM": team,
        "PROVISIONING_PROFILE_SPECIFIER": f'"{profile}"'}
    if variant.get("generated_symbols"):
        signing = {**signing, "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES", "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS": "YES"}
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

    def kit_settings(_):
        return dict(common, PRODUCT_BUNDLE_IDENTIFIER=f"{prefix}.kit", PRODUCT_NAME='"$(TARGET_NAME)"', DEFINES_MODULE="YES", SKIP_INSTALL="YES")

    def stat_settings(_):
        wrapper = {"WRAPPER_EXTENSION": "bundle", "INFOPLIST_FILE": '""'} if variant.get("stat_bundle") else {}
        return dict(common, PRODUCT_NAME='"$(TARGET_NAME)"', SKIP_INSTALL="YES", **wrapper)

    libraries = ("kit", "stat") if variant.get("libraries") else ()
    keys = ("app", "tests", "uitests") + libraries
    objects = []
    for key, name in (("app", "App.app"), ("tests", "AppTests.xctest"), ("uitests", "AppUITests.xctest"), ("kit", "Kit.framework"), ("stat", "Stat.bundle" if variant.get("stat_bundle") else "libStat.a")):
        if key not in keys:
            continue
        file_type = {"app": "wrapper.application", "kit": "wrapper.framework", "stat": "wrapper.cfbundle" if variant.get("stat_bundle") else "archive.ar"}.get(key, "wrapper.cfbundle")
        objects.append(f"\t\t{IDS[key + '.product']} = {{isa = PBXFileReference; explicitFileType = {file_type}; "
                       f"includeInIndex = 0; path = {name}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    for key, path in (("app", "App"), ("tests", "AppTests"), ("uitests", "AppUITests"), ("kit", "Kit"), ("stat", "Stat")):
        if key not in keys:
            continue
        objects.append(f"\t\t{IDS[key + '.folder']} = {{isa = PBXFileSystemSynchronizedRootGroup; path = {path}; "
                       f"sourceTree = \"<group>\"; }};\n")
    for key in keys:
        for phase, isa in (("sources", "PBXSourcesBuildPhase"), ("frameworks", "PBXFrameworksBuildPhase"),
                           ("resources", "PBXResourcesBuildPhase")):
            files = f"\t\t\t\t{IDS['package.file']},\n" if variant.get("package") and key == "app" and phase == "frameworks" else ""
            objects.append(f"\t\t{IDS[key + '.' + phase]} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
                           f"\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    if variant.get("package"):
        objects.append(f"\t\t{IDS['package.reference']} = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = Pkg;\n\t\t}};\n")
        objects.append(f"\t\t{IDS['package.product']} = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = PkgLib;\n\t\t}};\n")
        objects.append(f"\t\t{IDS['package.file']} = {{isa = PBXBuildFile; productRef = {IDS['package.product']}; }};\n")
    for key, needed, name in (("tests", "app", "App"), ("uitests", "app", "App"), ("kit", "kit", "Kit"), ("stat", "stat", "Stat")):
        if key not in keys:
            continue
        objects.append(f"\t\t{IDS[key + '.proxy']} = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                       f"\t\t\tcontainerPortal = {IDS['project']};\n\t\t\tproxyType = 1;\n"
                       f"\t\t\tremoteGlobalIDString = {IDS[needed + '.target']};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")
        objects.append(f"\t\t{IDS[key + '.dependency']} = {{\n\t\t\tisa = PBXTargetDependency;\n"
                       f"\t\t\ttarget = {IDS[needed + '.target']};\n\t\t\ttargetProxy = {IDS[key + '.proxy']};\n\t\t}};\n")
    objects.append(f"\t\t{IDS['main']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                   + "".join(f"\t\t\t\t{IDS[k + '.folder']},\n" for k in keys) + f"\t\t\t\t{IDS['products']},\n"
                   + "\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
    objects.append(f"\t\t{IDS['products']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                   + "".join(f"\t\t\t\t{IDS[k + '.product']},\n" for k in keys)
                   + "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
    objects.append(target("app", "App", "com.apple.product-type.application", tuple(k + ".dependency" for k in libraries), package=variant.get("package")))
    objects.append(target("tests", "AppTests", "com.apple.product-type.bundle.unit-test", ("tests.dependency",)))
    objects.append(target("uitests", "AppUITests", "com.apple.product-type.bundle.ui-testing", ("uitests.dependency",)))
    if libraries:
        objects.append(target("kit", "Kit", "com.apple.product-type.framework"))
        objects.append(target("stat", "Stat", "com.apple.product-type.bundle" if variant.get("stat_bundle") else "com.apple.product-type.library.static"))
    attributes = "".join(f"\t\t\t\t\t{IDS[k + '.target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n"
                         + (f"\t\t\t\t\t\tTestTargetID = {IDS['app.target']};\n" if k != "app" else "")
                         + "\t\t\t\t\t};\n" for k in keys)
    objects.append(f"\t\t{IDS['project']} = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
                   f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2700;\n"
                   f"\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t\tTargetAttributes = {{\n{attributes}\t\t\t\t}};\n\t\t\t}};\n"
                   f"\t\t\tbuildConfigurationList = {IDS['project.list']};\n\t\t\tdevelopmentRegion = en;\n"
                   f"\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
                   f"\t\t\tmainGroup = {IDS['main']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
                   + (f"\t\t\tpackageReferences = (\n\t\t\t\t{IDS['package.reference']},\n\t\t\t);\n" if variant.get("package") else "") +
                   f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {IDS['products']};\n"
                   f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n"
                   + "".join(f"\t\t\t\t{IDS[k + '.target']},\n" for k in (libraries + keys[:3] if variant.get("libraries_first") else keys))
                   + "\t\t\t);\n\t\t};\n")
    objects.append(configuration_list("project", project_settings))
    objects.append(configuration_list("app", app_settings))
    objects.append(configuration_list("tests", tests_settings))
    objects.append(configuration_list("uitests", uitests_settings))
    if libraries:
        objects.append(configuration_list("kit", kit_settings))
        objects.append(configuration_list("stat", stat_settings))
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
    coverage_targets = ""
    if variant.get("coverage_targets"):
        coverage += ' onlyGenerateCoverageForSpecifiedTargets = "YES"'
        coverage_targets = f'<CodeCoverageTargets>{buildable("app", "App", "App.app")}</CodeCoverageTargets>'
    if variant.get("autocreated_plan"):
        coverage += ' shouldAutocreateTestPlan = "YES"'
    use_launch = "NO" if variant.get("test_env") or variant.get("test_args") else "YES"
    plans = "".join(f'<TestPlanReference reference = "container:{name}.xctestplan"{" default = " + chr(34) + "YES" + chr(34) if index == 0 else ""}/>'
                    for index, name in enumerate(["App"] + list(variant.get("more_plans", {}))))
    plan = (f"<TestPlans>{plans}</TestPlans>" if variant.get("test_plan") else f"<Testables>{testables}</Testables>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion = "2700" version = "1.7">\n'
            '<BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES"><BuildActionEntries>'
            '<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
            f'buildForArchiving = "YES" buildForAnalyzing = "YES">{buildable("app", "App", "App.app")}</BuildActionEntry>'
            '</BuildActionEntries></BuildAction>\n'
            f'<TestAction buildConfiguration = "{variant.get("configuration", "Debug")}" '
            'selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
            f'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "{use_launch}"{coverage}>'
            f'{coverage_targets}{plan}{arguments(variant.get("test_args"), variant.get("test_args_off"))}'
            f'{variables("EnvironmentVariables", variant.get("test_env"), variant.get("test_env_off"))}</TestAction>\n'
            '<LaunchAction buildConfiguration = "Debug" launchStyle = "0" useCustomWorkingDirectory = "NO" '
            'ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" '
            'allowLocationSimulation = "YES"><BuildableProductRunnable runnableDebuggingMode = "0">'
            f'{buildable("app", "App", "App.app")}</BuildableProductRunnable>'
            f'{arguments(variant.get("launch_args"))}{variables("EnvironmentVariables", variant.get("launch_env"))}</LaunchAction>\n</Scheme>\n')


def container_target(key, name):
    return {"containerPath": "container:App.xcodeproj", "identifier": IDS[key + ".target"], "name": name}


def test_plan(plan=None):
    """A test plan as Xcode writes one; `plan` holds the variant's `configurations`, `default` options,
    and `targets` fields by target."""
    plan = plan or {}
    fields = plan.get("targets", {})
    configurations = plan.get("configurations", [{"name": "Configuration 1", "options": {}}])
    return json.dumps({
        "configurations": [dict(c, id=f"11111111-2222-3333-4444-5555555555{index:02d}") for index, c in enumerate(configurations)],
        "defaultOptions": plan.get("default", {"environmentVariableEntries": [{"key": "PLAN_VARIABLE", "value": "1"}]}),
        "testTargets": [dict(fields.get(n, {}), target=container_target(k, n))
                        for k, n in ((("uitests", "AppUITests"), ("tests", "AppTests")) if plan.get("reversed") else (("tests", "AppTests"), ("uitests", "AppUITests")))],
        "version": 1}, indent=2) + "\n"


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
        (directory / "App.xctestplan").write_text(test_plan(variant.get("plan")))
        for name, plan in variant.get("more_plans", {}).items():
            (directory / f"{name}.xctestplan").write_text(test_plan(plan))
    for path, source in variant.get("files", {}).items():
        (directory / path).parent.mkdir(parents=True, exist_ok=True)
        (directory / path).write_text(source)
    if variant.get("libraries"):
        for path, source in (("Kit/Kit.swift", "public let kit = 1\n"), ("Kit/Plain.m", '#import <Foundation/Foundation.h>\nint plain(void) { return 1; }\n'),
                             ("Stat/Notes.txt", "notes\n") if variant.get("stat_bundle") else ("Stat/Stat.swift", "public let stat = 1\n")):
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            (directory / path).write_text(source)
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
        "-derivedDataPath", str(derived)] + (["-IDEPackageSupportDisableManifestSandbox=YES"] if (work / "Pkg").exists() else [])
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
    """`nomac build ... build-for-testing` on the same project, against Xcode's capture in `out`: its
    status, its `.xctestrun` byte for byte, and its products' file names."""
    derived = work / "NomacDerivedData"
    shutil.rmtree(derived, ignore_errors=True)
    result = subprocess.run([nomac, "build", "-project", "App.xcodeproj", "-scheme", "App", "-destination", "generic/platform=iOS",
                             "-derivedDataPath", str(derived), "--developer-dir", DEVELOPER_DIR, "build-for-testing"],
                            cwd=work, env=environment(), capture_output=True, text=True)
    (out / "nomac-stdout.txt").write_text(scrub(result.stdout, None))
    (out / "nomac-stderr.txt").write_text(scrub(result.stderr, None))
    mine = derived / "Build/Products"
    files = sorted(f.name for f in out.glob("*.xctestrun"))
    same = [name for name in files if (mine / name).exists() and (mine / name).read_bytes() == (out / name).read_bytes()]
    for name in set(files) - set(same):
        if (mine / name).exists():
            shutil.copyfile(mine / name, out / ("nomac-" + name + ".txt"))
    expected = sorted(line for line in (out / "products.txt").read_text().splitlines() if ".swiftmodule" not in line and ".dSYM" not in line and not line.endswith(".xctestrun")) if (out / "products.txt").exists() else []
    listed = [path for path in product_files(mine) if not path.endswith(".xctestrun")] if mine.exists() else []
    print(f"  nomac: status {result.returncode}, xctestrun {len(same)}/{len(files)} identical, products {'same' if listed == expected else 'differ: ' + str(sorted(set(listed) ^ set(expected)))[:160]}", flush=True)
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


def simulator_result_bundle(work, out):
    """`xcodebuild test` on a new simulator; the result bundle stays in `out`, outside the repository."""
    simulator = subprocess.run(["xcrun", "simctl", "create", "nomac-xcresult", "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"],
                               env=environment(), capture_output=True, text=True, check=True).stdout.strip()
    bundle = out / "App.xcresult"
    out.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(bundle, ignore_errors=True)
    try:
        result = subprocess.run(OFFLINE + ["xcodebuild", "test", "-project", "App.xcodeproj", "-scheme", "App", "-destination", f"platform=iOS Simulator,id={simulator}",
                                           "-derivedDataPath", str(work / "DerivedData"), "-resultBundlePath", str(bundle)],
                                cwd=work, env=environment(), capture_output=True, text=True)
        (out / "stdout.txt").write_text(scrub(result.stdout, simulator))
        (out / "stderr.txt").write_text(scrub(result.stderr, simulator))
        (out / "status").write_text(f"{result.returncode}\n")
        print(f"xcresult: status {result.returncode}, bundle {'written' if bundle.exists() else 'missing'}", flush=True)
        if bundle.exists():
            xcresult(bundle, out, simulator)
    finally:
        subprocess.run(["xcrun", "simctl", "delete", simulator], env=environment(), capture_output=True)
        shutil.rmtree(work / "DerivedData", ignore_errors=True)


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
    "coverage-files": {"coverage": True, "files": {"App/Views/Screen.swift": "let screen = 1\n", "App/Model/Thing.swift": "let thing = 1\n", "App/Zed.swift": "let zed = 1\n",
                                                   "AppTests/Sub/MoreTests.swift": "import XCTest\nfinal class MoreTests: XCTestCase {}\n", "AppTests/Sub/Deep/Others.swift": "let others = 1\n"}},
    "coverage-libraries": {"coverage": True, "libraries": True},
    "coverage-specified": {"coverage": True, "coverage_targets": True},
    "coverage-release": {"coverage": True, "configuration": "Release", "unhosted": True},
    "coverage-order": {"coverage": True, "libraries": True, "libraries_first": True,
                       "files": {"Stat/Alpha.swift": "let alpha = 1\n", "Stat/Alpine.swift": "let alpine = 1\n", "App/apple.swift": "let apple = 1\n", "App/Sub/Only.swift": "let only = 1\n"}},
    "coverage-bundle": {"coverage": True, "libraries": True, "stat_bundle": True},
    "coverage-prefix": {"coverage": True, "files": {"AppTests/CounterMore.swift": "let more = 1\n"}},
    "coverage-package": {"coverage": True, "package": True, "files": {
        "Pkg/Package.swift": '// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "Pkg", products: [.library(name: "PkgLib", targets: ["PkgLib"])], targets: [.target(name: "PkgLib")])\n',
        "Pkg/Sources/PkgLib/PkgLib.swift": "public let pkg = 1\n", "Pkg/Sources/PkgLib/More.swift": "let more = 1\n"}},
    "coverage-assets": {"coverage": True, "generated_symbols": True,
                        "files": {"App/Assets.xcassets/Contents.json": '{"info":{"author":"xcode","version":1}}\n',
                                  "App/Assets.xcassets/Red.colorset/Contents.json": '{"colors":[{"idiom":"universal"}],"info":{"author":"xcode","version":1}}\n',
                                  "App/Plain.h": "int plain(void);\n", "App/Notes.txt": "notes\n"}},
    "autocreated-plan": {"autocreated_plan": True},
    "autocreated-plan-env": {"autocreated_plan": True, "test_env": {"TEST_VARIABLE": "1"}, "test_args": ["-TestArgument"]},
    "plan-launch-env": {"test_plan": True, "launch_env": {"LAUNCH_VARIABLE": "1"}, "launch_args": ["-LaunchArgument"], "plan": {"default": {"codeCoverage": False}}},
    "plan-expansion": {"test_plan": True, "plan": {"default": {"codeCoverage": False, "targetForVariableExpansion": container_target("app", "App"),
                                                               "environmentVariableEntries": [{"key": "EXPANDED", "value": "$(PRODUCT_NAME)"}], "commandLineArgumentEntries": [{"argument": "-Name $(PRODUCT_NAME)"}]}}},
    "plan-no-expansion": {"test_plan": True, "plan": {"default": {"codeCoverage": False, "environmentVariableEntries": [{"key": "EXPANDED", "value": "$(PRODUCT_NAME)"}]}}},
    "plan-languages": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "configurations": [
        {"name": "RTL", "options": {"language": "IDELaunchSchemeLanguageRLO"}}, {"name": "Double", "options": {"language": "IDELaunchSchemeLanguageDoubleLocalizedStrings"}},
        {"name": "Accented", "options": {"language": "IDELaunchSchemeLanguageAccentedPseudolanguage"}}, {"name": "Arabic", "options": {"language": "ar", "region": "AE"}},
        {"name": "Region", "options": {"region": "GB"}}, {"name": "Script", "options": {"language": "zh-Hans", "region": "CN"}}]}},
    "plan-never": {"test_plan": True, "plan": {"default": {"codeCoverage": False, "diagnosticCollectionPolicy": "Never", "performanceAntipatternCheckerEnabled": False,
                                                           "mainThreadCheckerEnabled": True, "uiTestingScreenshotsLifetime": "deleteOnSuccess", "userAttachmentLifetime": "deleteOnSuccess",
                                                           "testTimeoutsEnabled": False, "maximumTestExecutionTimeAllowance": None}}},
    "plan-config-overrides": {"test_plan": True, "plan": {"default": {"codeCoverage": False, "defaultTestExecutionTimeAllowance": 100, "commandLineArgumentEntries": [{"argument": "-Default"}]}, "configurations": [
        {"name": "A", "options": {"defaultTestExecutionTimeAllowance": 200, "maximumTestExecutionTimeAllowance": 400}}, {"name": "B", "options": {"commandLineArgumentEntries": [{"argument": "-B"}]}}]}},
    "plan-order": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "targets": {}, "reversed": True}},
    "plan-configurations": {"test_plan": True, "plan": {"default": {"environmentVariableEntries": [{"key": "SHARED", "value": "default"}], "language": "fr"}, "configurations": [
        {"name": "One", "options": {"language": "de", "region": "DE", "environmentVariableEntries": [{"key": "ONE", "value": "1"}, {"key": "OFF", "value": "1", "enabled": False}],
                                    "commandLineArgumentEntries": [{"argument": "-One"}, {"argument": "-Off", "enabled": False}]}},
        {"name": "Two", "options": {"environmentVariableEntries": [{"key": "SHARED", "value": "two"}]}}]}},
    "plan-no-coverage": {"test_plan": True, "plan": {"default": {"codeCoverage": False}}},
    "plan-coverage-true": {"test_plan": True, "plan": {"default": {"codeCoverage": True}}},
    "plan-coverage-targets": {"test_plan": True, "plan": {"default": {"codeCoverage": {"targets": [container_target("app", "App")]}}}},
    "plan-target-fields": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "targets": {
        "AppTests": {"parallelizable": True, "skippedTests": ["CounterTests/testNext"]}, "AppUITests": {"selectedTests": ["AppUITests/testIncrement"]}}}},
    "plan-target-disabled": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "targets": {"AppUITests": {"enabled": False}}}},
    "plan-options": {"test_plan": True, "plan": {"default": {
        "codeCoverage": False, "testTimeoutsEnabled": True, "defaultTestExecutionTimeAllowance": 300, "maximumTestExecutionTimeAllowance": 900, "testExecutionOrdering": "random",
        "testRepetitionMode": "retryOnFailure", "maximumTestRepetitions": 3, "mainThreadCheckerEnabled": False, "userAttachmentLifetime": "keepAlways", "uiTestingScreenshotsLifetime": "keepAlways",
        "diagnosticCollectionPolicy": "Always", "preferredScreenCaptureFormat": "screenshots", "performanceAntipatternCheckerEnabled": True,
        "targetForVariableExpansion": container_target("app", "App"), "commandLineArgumentEntries": [{"argument": "-DefaultArgument"}]}}},
    "plan-thread-sanitizer": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "configurations": [{"name": "Configuration 1", "options": {"threadSanitizerEnabled": True}}]}},
    "plan-address-sanitizer": {"test_plan": True, "plan": {"default": {"codeCoverage": False}, "configurations": [{"name": "Configuration 1", "options": {"addressSanitizer": {"enabled": True}}}]}},
    "plan-location": {"test_plan": True, "plan": {"default": {"codeCoverage": False, "locationScenario": {"identifier": "London, England", "referenceType": "built-in"}}}},
    "plan-two": {"test_plan": True, "plan": {"default": {"codeCoverage": False}}, "more_plans": {"Other": {"default": {"codeCoverage": False}, "targets": {"AppUITests": {"enabled": False}}}}},
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
    parser.add_argument("--compare-only", action="store_true", help="with --nomac, against the capture already in --output, without running xcodebuild")
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
            if not arguments.compare_only:
                build_for_testing(work, arguments.output / experiment, signed=False)
            if arguments.nomac:
                print(experiment, flush=True)
                compare_nomac(arguments.nomac, work, arguments.output / experiment)
            shutil.rmtree(work / "DerivedData", ignore_errors=True)
            continue
        if experiment.startswith("xcresult-"):
            work = arguments.work / experiment
            write_project(work, arguments.bundle_prefix, arguments.team, arguments.profile, experiment == "xcresult-mixed", {"unsigned": True, "no_ui": True})
            simulator_result_bundle(work, arguments.output / experiment)
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

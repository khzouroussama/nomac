#!/usr/bin/env python3
"""Compare nomac with Xcode on the features the coverage survey ranks first (BACKLOG B-081).

Runs on a Mac with Xcode 27.0 at /Applications/Xcode_27.app (docs/VERIFICATION.md "Without
CI"). Every project is written here from scratch. Each experiment has one or more cases; for
each case xcodebuild writes `-dumpPIF`, `-list` (text and `-json`) and `-showBuildSettings`
(text and `-json`, the default invocation, every target in every configuration and every scheme
in every configuration with `-destination generic/platform=iOS`) in capture_reference.py's
layout, then `nomac verify` compares nomac's outputs with them and `nomac list` its `-list`
text. An experiment's `observe` step compares Xcode's own outputs across its cases.

- object-versions: one project written as Xcode of each era wrote it, saved at every
  objectVersion from 41 to 111 with the keys that version uses (compatibilityVersion up to 63,
  preferredProjectObjectVersion from 70, file references with `name` and SOURCE_ROOT paths and
  English regions in the oldest, test bundles, frameworks, asset catalogs, Core Data models,
  entitlements and Swift from 46, a synchronized folder from 77): which versions Xcode 27.0
  reads, and whether its outputs depend on the version.
- object-versions-newest: the objectVersion-77 project, synchronized folder included, saved at
  older versions, for whether Xcode reads newer objects in an older format.
- object-ids: the objectVersion-77 project with object IDs that are not 24 hexadecimal digits
  (32 digits upper and lower case, 24 lower-case digits, short digits, `OBJ_<n>`, names with
  colons, words with dashes and dots), for how the PIF's GUIDs derive from them.
- same-name-targets: loader-experiments' project-reference-names and workspace-names, whose
  targets of different projects share names, scheme-name-clashes, whose target and local
  package product Kit do, and user-schemes-workspace, whose shared and per-user schemes of
  several containers do (B-065).
- xcconfig-missing: configurations based on xcconfig files that are not on disk (CocoaPods'
  before `pod install`, at objectVersion 77 and 46; the project's own), and xcconfigs that
  include missing files with `#include` and `#include?`.
- workspace-refs: workspaces that list files and folders other than projects (a Podfile, a
  README, a script, a test plan, an xcconfig, a missing file), and projects that are not on disk
  (first, last, in a group, by `container:`), next to a workspace of the project alone; `pods` and
  `pods-old` are CocoaPods' shape before `pod install`: the missing Pods project, the missing
  base xcconfigs, Pods_App.framework and the `[CP]` script phases.
- file-type-none: file references with neither `lastKnownFileType` nor `explicitFileType`
  (sources, headers, resources, folders, files without an extension, missing files; `sniffed`:
  every `#!` interpreter of Swift Build's script types, direct and through env, UTF-8, UTF-16
  and UTF-32 with and without a byte order mark, bytes above 127, control characters, XML,
  HTML, JSON, PDF and PNG heads, missing `.plist`s), for the PIF's `fileType`.
- additional-options: shared schemes whose launch and test actions have an empty
  `AdditionalOptions` element or one with options, next to a scheme without.
- survey-shapes: one case per feature the survey ranks next, each one change to the
  objectVersion-77 project: variant groups with a `path` (a folder, `.`) or SOURCE_ROOT, a
  header with ATTRIBUTES Project, a `sourcecode.module` module map, `<absolute>` references,
  ASSET_TAGS (one, two, none, on a source), the DevelopmentTeamName and LastTestingUpgradeCheck attributes, a named version
  group, plistStructureDefinitionIdentifier, a group child that does not exist, a UTF-16 file
  (fileEncoding 10), parallelizeBuildables NO, command-line arguments enabled and not, a
  playground in a workspace, and BuildSystemType Original and Latest.
- unresolved-proxies: an app that links a product of a referenced project not on disk
  (B-036), each case changing one input (an object ID, the remote ID or name, the product's
  path or type, the referenced project's path, the folder, the configurations and the default
  one, SDKROOT, SYMROOT, BUILD_DIR and CONFIGURATION_BUILD_DIR in the project, its xcconfig
  or the target, projectDirPath, the referenced project on disk without the product), for what
  the GUID of its build file is computed from.
- survey-shapes-2: one case per group of shapes the survey ranks next, each a change to the
  objectVersion-77 project: editor indentation and wrapping attributes; scheme launch, test,
  build, profile and archive options (location scenarios, StoreKit configurations, LLDB init
  files, environment variables, pre- and post-actions, a profile RemoteRunnable, scheme versions
  1.8 and 2.2); a copy-files phase run only when installing; productInstallPath; fileEncoding 9
  and 30; `explicitFileType = undefined`; config and several conditions on settings; macOS
  and Mac Catalyst platform filters; a missing local package; minimizedProjectReferenceProxies
  0; nested workspace groups.
- variant-groups: ordinary variant groups (B-025) with children outside a `.lproj` folder,
  alone, first or among others, in a nested or upper-case `.lproj`, in a Sources phase, and with
  regions knownRegions lacks or spells in another case, for the group tree, the build files and
  knownRegions.
- survey-shapes-3: environment variables set to NO, dangling build files, an OCUnit test
  bundle (with WRAPPER_EXTENSION xctest too, and a unit test bundle with octest), platform filters on a target dependency, a launch PathRunnable, archive post-actions,
  GPUProfilerEnabled and debugDocumentVersioning NO, an AutocreatedTestPlanReference build
  entry built for testing alone or for every action, a top-level validationLevel, an
  xcframework's expectedSignature, `fileEncoding = undefined`, and a test plan whose target is
  not parallelizable.
- survey-shapes-4: a local package with cxxSettings, and one whose manifest has no
  swift-tools-version line; a build file whose file reference is missing; a variant group whose
  source tree is `<absolute>`; `includeInIndex` on a group and `comments` on a file; a USDZ file
  and an Icon Composer icon; debugAsWhichUser, queueDebuggingEnabled, memoryGraphOnResourceException
  and ignoresPersistentStateOnLaunch; a pre-action's shellToInvoke; a StoreKit configuration in
  the test action; a workspace naming the project by its absolute path; and tvos, watchos, xros
  and driverkit platform filters on build files and target dependencies.
- symroot-locations: SYMROOT set in the project's or the app's configurations, the project
  opened alone or through a workspace, for where a scheme's settings put products.
- dst-subfolders: a copy-files phase whose destination is the `dstSubfolder` name Xcode 26 and
  later write instead of `dstSubfolderSpec`, one case per name.
- proxy-file-types: the objectVersion-77 project with a referenced project whose framework,
  bundle, app, app extension, test bundle and tool the app links, embeds and copies through
  reference proxies, with and without target dependencies on them.
- identity-conditions: targets that set no provisioning style and assign CODE_SIGN_IDENTITY
  both with and without an SDK condition, `-` or nothing on either side, in the target or in the
  project's base xcconfig, for the PIF's provisioningStyle.
- package-resolved: a remote package (a git repository at a file URL) pinned by an exact
  version, a version range or a branch, with no Package.resolved: what Xcode writes, and
  whether nomac resolves it the same way once Xcode's file and checkouts are removed; then a
  local package that depends on it, one that depends on nothing, and a root package folder
  that depends on it, unpinned and pinned by its own Package.resolved.

Usage: envelope_experiments.py <output-dir> [experiment ...] [--nomac PATH] [--jobs N] [--cases A,B]
       envelope_experiments.py <output-dir> --table [--nomac PATH]

Without experiment names every experiment runs. Each case's files, Xcode's outputs and nomac's
report go to `<output-dir>/<experiment>/<case>`; `<output-dir>/<experiment>.json` records the
results and the experiment's observations. The DerivedData folders and error result bundles
the runs create are removed.

`--table` writes Sources/NomacEnvelope/Loader/LoaderEnvelope+ExperimentCases.swift: a case whose
every comparison is identical is evidence for every loader feature it uses, as a corpus app is
(docs/adr/0011-feature-envelope.md); `nomac check --json` lists them, and each feature is credited
to the first experiment in EXPERIMENTS order whose case uses it.
"""

import argparse
import concurrent.futures
import hashlib
import json
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuzz_experiments as fuzz  # noqa: E402
import loader_experiments as loader  # noqa: E402

capture = fuzz.capture
capture.log = lambda message: None
DEVELOPER_DIR = fuzz.DEVELOPER_DIR
REPO_ROOT = fuzz.REPO_ROOT
DEFAULT_NOMAC = REPO_ROOT / ".build" / "debug" / "nomac"
MAX_JOBS = 4


# ---------------------------------------------------------------------------------------------
# Writing projects


class Project:
    """A project file built object by object. `ids` maps each object's key to its object ID."""

    def __init__(self, ids=None):
        self.objects = {}
        self.ids = ids or (lambda key: fuzz.object_id("envelope", key))

    def add(self, key, isa, **values):
        identifier = self.ids(key)
        self.objects[identifier] = {"isa": isa, **{name: value for name, value in values.items() if value is not None}}
        return identifier

    def text(self, root, object_version):
        body = "".join(f"\t\t{quote_id(identifier)} = {fuzz.pbx_value(value, 2)};\n" for identifier, value in self.objects.items())
        return (f"// !$*UTF8*$!\n{{\n\tarchiveVersion = 1;\n\tclasses = {{\n\t}};\n\tobjectVersion = {object_version};\n"
                f"\tobjects = {{\n{body}\t}};\n\trootObject = {quote_id(root)};\n}}\n")


def quote_id(identifier):
    return fuzz.pbx_quote(identifier) if re.fullmatch(r"[0-9A-Za-z_]+", identifier) else '"' + identifier + '"'


def workspace_data(locations):
    refs = "".join(f'   <FileRef\n      location = "{location}">\n   </FileRef>\n' for location in locations)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n{refs}</Workspace>\n'


def buildable(identifier, product, target, container):
    return (f'            <BuildableReference\n               BuildableIdentifier = "primary"\n'
            f'               BlueprintIdentifier = "{identifier}"\n               BuildableName = "{product}"\n'
            f'               BlueprintName = "{target}"\n               ReferencedContainer = "container:{container}">\n'
            f'            </BuildableReference>\n')


def scheme(build, tests=(), launch=None, version="1.7", upgrade="2700", launch_extra="", test_extra=""):
    """A shared scheme: `build` and `tests` are buildable references, `launch` the one it runs;
    `launch_extra` and `test_extra` go at the end of the launch and test actions."""
    entries = "".join('         <BuildActionEntry\n            buildForTesting = "YES"\n            buildForRunning = "YES"\n'
                      '            buildForProfiling = "YES"\n            buildForArchiving = "YES"\n            buildForAnalyzing = "YES">\n'
                      + reference + "         </BuildActionEntry>\n" for reference in build)
    testables = "".join('         <TestableReference\n            skipped = "NO">\n' + reference + "         </TestableReference>\n" for reference in tests)
    runnable = ('      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n' + launch + "      </BuildableProductRunnable>\n") if launch else ""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "{upgrade}"
   version = "{version}">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
{entries}      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
{testables}      </Testables>
{test_extra}   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
{runnable}{launch_extra}   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
{runnable}   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


# Each objectVersion's era: its `compatibilityVersion` (up to 63) or `preferredProjectObjectVersion`
# (from 70), and the release LastUpgradeCheck and CreatedOnToolsVersion name, as projects of the
# survey at those versions write them.
ERAS = [(42, "Xcode 2.4", None, "0240"), (44, "Xcode 3.0", None, "0300"), (45, "Xcode 3.1", None, "0310"),
        (46, "Xcode 3.2", None, "0830"), (47, "Xcode 6.3", None, "0730"), (48, "Xcode 8.0", None, "0900"),
        (50, "Xcode 9.3", None, "0930"), (51, "Xcode 10.0", None, "1000"), (52, "Xcode 11.0", None, "1100"),
        (53, "Xcode 11.4", None, "1140"), (54, "Xcode 12.0", None, "1200"), (55, "Xcode 13.0", None, "1300"),
        (56, "Xcode 14.0", None, "1400"), (60, "Xcode 15.0", None, "1500"), (63, "Xcode 15.3", None, "1530"),
        (70, None, 70, "1600"), (77, None, 77, "1610"), (90, None, 90, "2600"), (100, None, 100, "2640"), (110, None, 77, "2700")]


def era(version):
    """The era a version belongs to: the newest one at or below it (the oldest for lower ones)."""
    return max((entry for entry in ERAS if entry[0] <= version), default=ERAS[0], key=lambda entry: entry[0])


STORYBOARD = ('<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" '
              'version="3.0" toolsVersion="1" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES">\n'
              '    <scenes/>\n</document>\n')
XIB = ('<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" '
       'toolsVersion="1" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none">\n    <objects/>\n</document>\n')
INFO_PLIST = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
              '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n'
              '\t<key>CFBundleIdentifier</key>\n\t<string>{identifier}</string>\n\t<key>CFBundleExecutable</key>\n'
              '\t<string>$(EXECUTABLE_NAME)</string>\n</dict>\n</plist>\n')
ENTITLEMENTS = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n'
                '\t<key>aps-environment</key>\n\t<string>development</string>\n</dict>\n</plist>\n')
MODEL = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<model type="com.apple.IDECoreDataModeler.DataModel" '
         'documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="1" minimumToolsVersion="Automatic" sourceLanguage="Swift" '
         'userDefinedModelVersionIdentifier="">\n    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class"/>\n</model>\n')
CATALOG = '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
WORKSPACE_CHECKS = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n'
                    '\t<key>IDEDidComputeMac32BitWarning</key>\n\t<true/>\n</dict>\n</plist>\n')


def era_project(version, ids=None, content_version=None, scheme_extra=("", ""), edit=None):
    """An app with a framework (a static library before 46) and a unit test bundle (from 46),
    written as Xcode of `content_version`'s era (default `version`) wrote projects, saved with
    objectVersion `version`; `edit(project, files)` changes it before it is written. Returns
    {path: text}."""
    content = content_version or version
    _, compatibility, preferred, upgrade = era(content)
    old = content <= 45
    swift = content >= 46
    p = Project(ids)
    files = {}
    english = "English" if content < 51 else "en"
    regions = ["English", "Japanese", "French", "German"] if old else (["English", "en", "Base", "fr"] if content < 51 else ["en", "Base", "fr"])
    french = "French" if old else "fr"

    def reference(key, path, kind, name=None, tree="<group>", encoding=None, text=None):
        if text is not None:
            files[text[0]] = text[1]
        return p.add(key, "PBXFileReference", fileEncoding=encoding, lastKnownFileType=kind, name=name, path=path, sourceTree=tree)

    def build_file(key, file_ref, settings=None):
        return p.add(key, "PBXBuildFile", fileRef=file_ref, settings=settings)

    def phase(key, isa, members, **values):
        return p.add(key, isa, buildActionMask=2147483647, files=members, runOnlyForDeploymentPostprocessing=0, **values)

    def configurations(key, debug, release, base=None):
        entries = [p.add(f"{key}/{name}", "XCBuildConfiguration", baseConfigurationReference=base, buildSettings=values, name=name)
                   for name, values in (("Debug", debug), ("Release", release))]
        return p.add(key, "XCConfigurationList", buildConfigurations=entries, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    # App sources, as groups with a path or, in the oldest projects, a named group of SOURCE_ROOT paths.
    def app_file(key, name, kind, text, encoding=4):
        if old:
            return reference(key, f"App/{name}", kind, name=name, tree="SOURCE_ROOT", encoding=encoding, text=(f"App/{name}", text))
        return reference(key, name, kind, encoding=encoding, text=(f"App/{name}", text))

    app_sources = []
    app_children = []
    if swift:
        delegate = app_file("app/delegate", "AppDelegate.swift", "sourcecode.swift", "import UIKit\n\n@main\nclass AppDelegate: UIResponder, UIApplicationDelegate {}\n")
        bridging = app_file("app/bridging", "App-Bridging-Header.h", "sourcecode.c.h", '#import "Legacy.h"\n')
        app_children += [delegate, bridging]
        app_sources.append(build_file("app/delegate/build", delegate))
    else:
        delegate = app_file("app/delegate", "AppDelegate.m", "sourcecode.c.objc", '#import "AppDelegate.h"\n@implementation AppDelegate\n@end\n')
        delegate_header = app_file("app/delegate-h", "AppDelegate.h", "sourcecode.c.h", "#import <UIKit/UIKit.h>\n@interface AppDelegate : NSObject\n@end\n")
        main = app_file("app/main", "main.m", "sourcecode.c.objc", "int main(int argc, char *argv[]) { return 0; }\n")
        prefix = app_file("app/prefix", "App_Prefix.pch", "sourcecode.c.h", "#import <UIKit/UIKit.h>\n")
        app_children += [delegate, delegate_header, main, prefix]
        app_sources += [build_file("app/delegate/build", delegate), build_file("app/main/build", main)]
    legacy = app_file("app/legacy", "Legacy.m", "sourcecode.c.objc", '#import "Legacy.h"\n')
    legacy_header = app_file("app/legacy-h", "Legacy.h", "sourcecode.c.h", "void legacy(void);\n")
    info = app_file("app/info", "Info.plist", "text.plist.xml", INFO_PLIST.format(identifier="org.nomac.App"), encoding=None)
    app_children += [legacy, legacy_header, info]
    app_sources.append(build_file("app/legacy/build", legacy))

    interface_name, interface_folder = ("MainWindow.xib", english) if old else ("Main.storyboard", "Base")
    interface = reference("app/interface/base", f"{interface_folder}.lproj/{interface_name}", "file.xib" if old else "file.storyboard",
                          name=interface_folder, tree="SOURCE_ROOT" if old else "<group>")
    files[f"App/{interface_folder}.lproj/{interface_name}"] = XIB if old else STORYBOARD
    if old:
        p.objects[interface]["path"] = f"App/{interface_folder}.lproj/{interface_name}"
    interface_group = p.add("app/interface", "PBXVariantGroup", children=[interface], name=interface_name, sourceTree="<group>")
    strings = []
    for region in (english, french):
        path = f"{region}.lproj/Localizable.strings"
        files[f"App/{path}"] = f'"hello" = "{region}";\n'
        strings.append(reference(f"app/strings/{region}", f"App/{path}" if old else path, "text.plist.strings", name=region,
                                 tree="SOURCE_ROOT" if old else "<group>", encoding=4))
    strings_group = p.add("app/strings", "PBXVariantGroup", children=strings, name="Localizable.strings", sourceTree="<group>")
    app_children += [interface_group, strings_group]
    app_resources = [build_file("app/interface/build", interface_group), build_file("app/strings/build", strings_group)]
    if content >= 46:
        catalog_name = "Images.xcassets" if content == 46 else "Assets.xcassets"
        catalog = reference("app/catalog", catalog_name, "folder.assetcatalog")
        files[f"App/{catalog_name}/Contents.json"] = CATALOG
        model_file = reference("app/model/1", "Model.xcdatamodel", "wrapper.xcdatamodel")
        files["App/Model.xcdatamodeld/Model.xcdatamodel/contents"] = MODEL
        model = p.add("app/model", "XCVersionGroup", children=[model_file], currentVersion=model_file, path="Model.xcdatamodeld",
                      sourceTree="<group>", versionGroupType="wrapper.xcdatamodel")
        app_children += [catalog, model]
        app_resources.append(build_file("app/catalog/build", catalog))
        app_sources.append(build_file("app/model/build", model))
    else:
        icon = app_file("app/icon", "Icon.png", "image.png", "", encoding=None)
        app_children.append(icon)
        app_resources.append(build_file("app/icon/build", icon))
    if content >= 48:
        entitlements = app_file("app/entitlements", "App.entitlements", "text.plist.entitlements", ENTITLEMENTS, encoding=None)
        app_children.append(entitlements)
    app_group = p.add("group/app", "PBXGroup", children=app_children, name="Classes" if old else None, path=None if old else "App",
                      sourceTree="<group>")

    # The library: a framework from 46, a static library before.
    kit_header = reference("kit/header", "Kit.h", "sourcecode.c.h", encoding=4, text=("Kit/Kit.h", "void kit(void);\n"))
    kit_source = reference("kit/source", "Kit.m", "sourcecode.c.objc", encoding=4, text=("Kit/Kit.m", '#import "Kit.h"\nvoid kit(void) {}\n'))
    kit_children = [kit_header, kit_source]
    if content >= 46:
        kit_info = reference("kit/info", "Info.plist", "text.plist.xml", text=("Kit/Info.plist", INFO_PLIST.format(identifier="org.nomac.Kit")))
        kit_children.append(kit_info)
    kit_group = p.add("group/kit", "PBXGroup", children=kit_children, path="Kit", sourceTree="<group>")

    # Config files: the project's configurations are based on Base.xcconfig, which includes Shared.xcconfig.
    base = reference("config/base", "Base.xcconfig", "text.xcconfig", text=("Config/Base.xcconfig", '#include "Shared.xcconfig"\n\nOTHER_CFLAGS = $(inherited) -DNOMAC\n'))
    shared = reference("config/shared", "Shared.xcconfig", "text.xcconfig", text=("Config/Shared.xcconfig", "MARKETING_VERSION = 1.0\nCURRENT_PROJECT_VERSION = 7\n"))
    config_group = p.add("group/config", "PBXGroup", children=[base, shared], name="Config", path="Config", sourceTree="<group>")

    uikit = reference("framework/uikit", "System/Library/Frameworks/UIKit.framework", "wrapper.framework", name="UIKit.framework", tree="SDKROOT")
    zlib = (reference("framework/z", "usr/lib/libz.tbd", "sourcecode.text-based-dylib-definition", name="libz.tbd", tree="SDKROOT") if content >= 47
            else reference("framework/z", "usr/lib/libz.dylib", "compiled.mach-o.dylib", name="libz.dylib", tree="SDKROOT"))
    frameworks_group = p.add("group/frameworks", "PBXGroup", children=[uikit, zlib], name="Frameworks", sourceTree="<group>")

    # Products.
    def product(key, path, kind):
        return p.add(key, "PBXFileReference", explicitFileType=kind, includeInIndex=0, path=path, sourceTree="BUILT_PRODUCTS_DIR")
    app_product = product("product/app", "App.app", "wrapper.application")
    kit_product = product("product/kit", "Kit.framework", "wrapper.framework") if content >= 46 else product("product/kit", "libKit.a", "archive.ar")
    products = [app_product, kit_product]
    tests_product = None
    if content >= 46:
        tests_product = product("product/tests", "AppTests.xctest", "wrapper.cfbundle")
        products.append(tests_product)
    products_group = p.add("group/products", "PBXGroup", children=products, name="Products", sourceTree="<group>")

    main_children = [app_group, kit_group]
    tests_group = None
    if content >= 46:
        tests_source = reference("tests/source", "AppTests.swift", "sourcecode.swift", text=("AppTests/AppTests.swift", "import XCTest\n\nfinal class AppTests: XCTestCase {}\n"))
        tests_info = reference("tests/info", "Info.plist", "text.plist.xml", text=("AppTests/Info.plist", INFO_PLIST.format(identifier="org.nomac.AppTests")))
        tests_group = p.add("group/tests", "PBXGroup", children=[tests_source, tests_info], path="AppTests", sourceTree="<group>")
        main_children.append(tests_group)
    synchronized = None
    if content >= 77:
        synchronized = p.add("group/feature", "PBXFileSystemSynchronizedRootGroup", path="Feature", sourceTree="<group>")
        files["Feature/Feature.swift"] = "struct Feature {}\n"
        files["Feature/Feature.strings"] = '"feature" = "on";\n'
        main_children.append(synchronized)
    main_children += [config_group, frameworks_group, products_group]
    main_group = p.add("group/main", "PBXGroup", children=main_children, sourceTree="<group>")

    # Targets.
    project_key = "project"
    kit_target_id = p.ids("target/kit")
    app_target_id = p.ids("target/app")
    kit_headers = phase("kit/headers", "PBXHeadersBuildPhase", [build_file("kit/header/build", kit_header, {"ATTRIBUTES": ["Public"]})])
    kit_phases = [kit_headers, phase("kit/sources", "PBXSourcesBuildPhase", [build_file("kit/source/build", kit_source)]),
                  phase("kit/frameworks", "PBXFrameworksBuildPhase", [build_file("kit/uikit/build", uikit)])]
    kit_settings = {"PRODUCT_NAME": "$(TARGET_NAME)"}
    if content >= 46:
        kit_settings.update({"DEFINES_MODULE": "YES", "DYLIB_COMPATIBILITY_VERSION": 1, "DYLIB_CURRENT_VERSION": 1, "DYLIB_INSTALL_NAME_BASE": "@rpath",
                             "INFOPLIST_FILE": "Kit/Info.plist", "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks", "SKIP_INSTALL": "YES",
                             "VERSIONING_SYSTEM": "apple-generic", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.Kit"})
    else:
        kit_settings.update({"SKIP_INSTALL": "YES", "OTHER_LDFLAGS": "-ObjC"})
    p.add("target/kit", "PBXNativeTarget", buildConfigurationList=configurations("list/kit", kit_settings, kit_settings), buildPhases=kit_phases,
          buildRules=[], dependencies=[], name="Kit", productName="Kit", productReference=kit_product,
          productType="com.apple.product-type.framework" if content >= 46 else "com.apple.product-type.library.static")

    def dependency(key, target_id, name):
        proxy = p.add(f"{key}/proxy", "PBXContainerItemProxy", containerPortal=p.ids(project_key), proxyType=1, remoteGlobalIDString=target_id, remoteInfo=name)
        return p.add(key, "PBXTargetDependency", target=target_id, targetProxy=proxy)

    kit_link = build_file("app/kit/build", kit_product)
    app_phases = [phase("app/sources", "PBXSourcesBuildPhase", app_sources),
                  phase("app/frameworks", "PBXFrameworksBuildPhase", [kit_link, build_file("app/uikit/build", uikit), build_file("app/z/build", zlib)]),
                  phase("app/resources", "PBXResourcesBuildPhase", app_resources)]
    if content >= 46:
        app_phases.append(p.add("app/script", "PBXShellScriptBuildPhase", buildActionMask=2147483647, files=[], inputPaths=[], name="Run Script",
                                outputPaths=[], runOnlyForDeploymentPostprocessing=0, shellPath="/bin/sh", shellScript='echo "nomac"\n'))
        app_phases.append(phase("app/embed", "PBXCopyFilesBuildPhase",
                                [build_file("app/kit/embed", kit_product, {"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})],
                                dstPath="", dstSubfolderSpec=10, name="Embed Frameworks"))
    app_settings = {"INFOPLIST_FILE": "App/Info.plist", "PRODUCT_NAME": "$(TARGET_NAME)", "TARGETED_DEVICE_FAMILY": "1,2"}
    if old:
        app_settings.update({"GCC_PRECOMPILE_PREFIX_HEADER": "YES", "GCC_PREFIX_HEADER": "App/App_Prefix.pch", "ALWAYS_SEARCH_USER_PATHS": "NO"})
    if swift:
        app_settings.update({"SWIFT_OBJC_BRIDGING_HEADER": "App/App-Bridging-Header.h", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                             "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"] if content >= 53 else "$(inherited) @executable_path/Frameworks"})
    if content >= 47:
        app_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "org.nomac.App"
    if content >= 48:
        app_settings.update({"CODE_SIGN_ENTITLEMENTS": "App/App.entitlements", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "ABCDE12345",
                             "SWIFT_VERSION": "4.0" if content < 51 else "5.0"})
    app_debug = dict(app_settings, **({"SWIFT_OPTIMIZATION_LEVEL": "-Onone"} if swift else {}))
    p.add("target/app", "PBXNativeTarget", buildConfigurationList=configurations("list/app", app_debug, app_settings), buildPhases=app_phases, buildRules=[],
          dependencies=[dependency("app/dependency/kit", kit_target_id, "Kit")], fileSystemSynchronizedGroups=[synchronized] if synchronized else None,
          name="App", productName="App", productReference=app_product, productType="com.apple.product-type.application")
    targets = [app_target_id, kit_target_id]
    if content >= 46:
        tests_settings = {"BUNDLE_LOADER": "$(TEST_HOST)", "INFOPLIST_FILE": "AppTests/Info.plist", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.AppTests",
                          "PRODUCT_NAME": "$(TARGET_NAME)",
                          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/" + ("$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App" if content >= 51 else "App")}
        tests_phases = [phase("tests/sources", "PBXSourcesBuildPhase", [build_file("tests/source/build", tests_source)]),
                        phase("tests/frameworks", "PBXFrameworksBuildPhase", []), phase("tests/resources", "PBXResourcesBuildPhase", [])]
        targets.append(p.add("target/tests", "PBXNativeTarget", buildConfigurationList=configurations("list/tests", tests_settings, tests_settings),
                             buildPhases=tests_phases, buildRules=[], dependencies=[dependency("tests/dependency/app", app_target_id, "App")],
                             name="AppTests", productName="AppTests", productReference=tests_product,
                             productType="com.apple.product-type.bundle.unit-test"))

    # The project and its configurations, with the settings Xcode's templates of the era wrote.
    common = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES", "SDKROOT": "iphoneos",
              "IPHONEOS_DEPLOYMENT_TARGET": "4.0" if old else ("8.0" if content < 51 else ("12.0" if content < 60 else "17.0"))}
    if old:
        common.update({"ARCHS": "$(ARCHS_STANDARD_32_BIT)", "GCC_C_LANGUAGE_STANDARD": "c99", "PREBINDING": "NO",
                       "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "iPhone Developer"})
    else:
        common.update({"CLANG_ENABLE_MODULES": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
                       "GCC_C_LANGUAGE_STANDARD": "gnu99" if content < 51 else ("gnu11" if content < 56 else "gnu17")})
    debug = dict(common, COPY_PHASE_STRIP="NO", DEBUG_INFORMATION_FORMAT="dwarf", GCC_OPTIMIZATION_LEVEL=0, ONLY_ACTIVE_ARCH="YES",
                 GCC_PREPROCESSOR_DEFINITIONS=["DEBUG=1", "$(inherited)"])
    release = dict(common, COPY_PHASE_STRIP="YES" if old else "NO", DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", VALIDATE_PRODUCT="YES")
    if content >= 47:
        debug.update({"ENABLE_TESTABILITY": "YES", "MTL_ENABLE_DEBUG_INFO": "YES"})
        release.update({"MTL_ENABLE_DEBUG_INFO": "NO", "ENABLE_NS_ASSERTIONS": "NO"})
    if content >= 48:
        debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        release["SWIFT_COMPILATION_MODE"] = "wholemodule"
    project_list = configurations("list/project", debug, release, base=base)
    target_attributes = {}
    if content >= 46:
        created = f"{int(upgrade[:2])}.{int(upgrade[2])}"
        target_attributes = {app_target_id: {"CreatedOnToolsVersion": created}, kit_target_id: {"CreatedOnToolsVersion": created},
                             p.ids("target/tests"): {"CreatedOnToolsVersion": created, "TestTargetID": app_target_id}}
        if content < 48:
            target_attributes[app_target_id]["SystemCapabilities"] = {"com.apple.Push": {"enabled": 1}}
        else:
            target_attributes[app_target_id].update({"DevelopmentTeam": "ABCDE12345", "ProvisioningStyle": "Automatic"})
        if content >= 50:
            target_attributes[app_target_id]["LastSwiftMigration"] = "1000" if content < 52 else "1100"
    attributes = {"LastUpgradeCheck": upgrade, "ORGANIZATIONNAME": "nomac"}
    if swift:
        attributes["LastSwiftUpdateCheck"] = upgrade
    if content >= 56:
        attributes["BuildIndependentTargetsInParallel"] = 1
    if target_attributes:
        attributes["TargetAttributes"] = target_attributes
    root = p.add(project_key, "PBXProject", attributes=attributes, buildConfigurationList=project_list,
                 compatibilityVersion=compatibility, developmentRegion=english, hasScannedForEncodings=1 if old else 0, knownRegions=regions,
                 mainGroup=main_group, minimizedProjectReferenceProxies=1 if content >= 70 else None,
                 preferredProjectObjectVersion=preferred, productRefGroup=products_group,
                 projectDirPath="", projectRoot="", targets=targets)
    if edit:
        edit(p, files)
    result = dict(files)
    result["P.xcodeproj/project.pbxproj"] = p.text(root, version)
    result["P.xcodeproj/project.xcworkspace/contents.xcworkspacedata"] = workspace_data(["self:"])
    if content >= 50:
        result["P.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist"] = WORKSPACE_CHECKS
    if old:
        return result
    # Shared schemes arrived with Xcode 4 (objectVersion 46).
    app_reference = buildable(app_target_id, "App.app", "App", "P.xcodeproj")
    tests = [buildable(p.ids("target/tests"), "AppTests.xctest", "AppTests", "P.xcodeproj")]
    result["P.xcodeproj/xcshareddata/xcschemes/App.xcscheme"] = scheme(
        [app_reference], tests, app_reference, version="1.3" if content < 50 else "1.7", upgrade=upgrade,
        launch_extra=scheme_extra[0], test_extra=scheme_extra[1])
    return result


def object_versions():
    return {f"v{version}": (era_project(version), "P.xcodeproj") for version in range(41, 112)}


def object_versions_newest():
    return {f"v{version}": (era_project(version, content_version=77), "P.xcodeproj") for version in (42, 46, 48, 51, 55, 56, 63, 70, 77, 110)}


def id_scheme(kind):
    """Object IDs of one shape, for every key: as unique as the 24-digit ones they replace."""
    def digest(key):
        return fuzz.object_id("envelope", key) + fuzz.object_id("envelope-tail", key)
    numbers = {}

    def number(key):
        return numbers.setdefault(key, len(numbers) + 1)
    return {
        "hex24": lambda key: fuzz.object_id("envelope", key),
        "hex32": lambda key: digest(key)[:32],
        "lower32": lambda key: digest(key)[:32].lower(),
        "lower24": lambda key: digest(key)[:24].lower(),
        "short": lambda key: f"B{number(key):05X}",
        "obj": lambda key: f"OBJ_{number(key)}",
        "colons": lambda key: "P::" + "::".join(part.capitalize() for part in re.split(r"[/-]", key)),
        "words": lambda key: re.sub(r"[^A-Za-z0-9]", "_", key).upper() + f"-{number(key)}.x",
    }[kind]


def object_ids():
    return {kind: (era_project(77, ids=id_scheme(kind)), "P.xcodeproj")
            for kind in ("hex24", "hex32", "lower32", "lower24", "short", "obj", "colons", "words")}


def add_to_group(p, group_key, children):
    p.objects[p.ids(group_key)]["children"] += children


def pods_base_configurations(p, files):
    """The app's configurations based on CocoaPods' xcconfigs, in a `Pods` group, as `pod install`
    writes them; the files are not on disk until it runs."""
    references = []
    for name in ("Debug", "Release"):
        path = f"Pods/Target Support Files/Pods-App/Pods-App.{name.lower()}.xcconfig"
        reference = p.add(f"pods/xcconfig/{name}", "PBXFileReference", includeInIndex=1, lastKnownFileType="text.xcconfig",
                          name=f"Pods-App.{name.lower()}.xcconfig", path=path, sourceTree="<group>")
        p.objects[p.ids(f"list/app/{name}")]["baseConfigurationReference"] = reference
        references.append(reference)
    group = p.add("group/pods", "PBXGroup", children=references, name="Pods", sourceTree="<group>")
    add_to_group(p, "group/main", [group])


def pods_phases(p, files):
    """What `pod install` adds to the app: its framework, the manifest check and the embed script."""
    pods_base_configurations(p, files)
    framework = p.add("pods/framework", "PBXFileReference", explicitFileType="wrapper.framework", includeInIndex=0, path="Pods_App.framework",
                      sourceTree="BUILT_PRODUCTS_DIR")
    add_to_group(p, "group/frameworks", [framework])
    p.objects[p.ids("app/frameworks")]["files"].append(p.add("pods/framework/build", "PBXBuildFile", fileRef=framework))
    check = p.add("pods/check", "PBXShellScriptBuildPhase", buildActionMask=2147483647, files=[], inputFileListPaths=[],
                  inputPaths=["${PODS_PODFILE_DIR_PATH}/Podfile.lock", "${PODS_ROOT}/Manifest.lock"], name="[CP] Check Pods Manifest.lock",
                  outputFileListPaths=[], outputPaths=["$(DERIVED_FILE_DIR)/Pods-App-checkManifestLockResult.txt"],
                  runOnlyForDeploymentPostprocessing=0, shellPath="/bin/sh",
                  shellScript='diff "${PODS_PODFILE_DIR_PATH}/Podfile.lock" "${PODS_ROOT}/Manifest.lock" > /dev/null\n', showEnvVarsInLog=0)
    embed = p.add("pods/embed", "PBXShellScriptBuildPhase", buildActionMask=2147483647, files=[],
                  inputFileListPaths=["${PODS_ROOT}/Target Support Files/Pods-App/Pods-App-frameworks-${CONFIGURATION}-input-files.xcfilelist"],
                  name="[CP] Embed Pods Frameworks",
                  outputFileListPaths=["${PODS_ROOT}/Target Support Files/Pods-App/Pods-App-frameworks-${CONFIGURATION}-output-files.xcfilelist"],
                  runOnlyForDeploymentPostprocessing=0, shellPath="/bin/sh",
                  shellScript='"${PODS_ROOT}/Target Support Files/Pods-App/Pods-App-frameworks.sh"\n', showEnvVarsInLog=0)
    phases = p.objects[p.ids("target/app")]["buildPhases"]
    phases.insert(0, check)
    phases.append(embed)
    files["Podfile"] = "platform :ios, '17.0'\ntarget 'App' do\n  pod 'Kit'\nend\n"


def remove_file(path):
    def edit(p, files):
        del files[path]
    return edit


def include_in_base(line):
    def edit(p, files):
        files["Config/Base.xcconfig"] = line + "\n" + files["Config/Base.xcconfig"]
    return edit


def xcconfig_missing():
    cases = {
        "target-base-missing": era_project(77, edit=pods_base_configurations),
        "project-base-missing": era_project(77, edit=remove_file("Config/Base.xcconfig")),
        "include-missing": era_project(77, edit=include_in_base('#include "Missing.xcconfig"')),
        "include-missing-folder": era_project(77, edit=include_in_base('#include "../Pods/Target Support Files/Pods-App/Pods-App.debug.xcconfig"')),
        "include-optional-missing": era_project(77, edit=include_in_base('#include? "Missing.xcconfig"')),
        "old-target-base-missing": era_project(46, edit=pods_base_configurations),
    }
    return {name: (files, "P.xcodeproj") for name, files in cases.items()}


def in_workspace(files, locations, extra=None):
    files = dict(files, **(extra or {}))
    files["W.xcworkspace/contents.xcworkspacedata"] = (workspace_data(locations) if isinstance(locations, list) else locations)
    return files, "W.xcworkspace"


GROUPED_MISSING = ('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "group:P.xcodeproj">\n'
                   '   </FileRef>\n   <Group\n      location = "container:"\n      name = "Deps">\n      <FileRef\n'
                   '         location = "group:Missing/Missing.xcodeproj">\n      </FileRef>\n   </Group>\n</Workspace>\n')


def workspace_refs():
    base = era_project(77)
    others = {"Podfile": "platform :ios, '17.0'\n", "README.md": "# P\n", "Docs/Guide.md": "# Guide\n", "Scripts/build.sh": "#!/bin/sh\n",
              "Plans/All.xctestplan": '{\n  "configurations" : [],\n  "testTargets" : [],\n  "version" : 1\n}\n'}
    return {
        "baseline": in_workspace(base, ["group:P.xcodeproj"]),
        "other": in_workspace(base, ["group:P.xcodeproj", "group:Podfile", "group:README.md", "group:Docs", "group:Scripts/build.sh",
                                     "group:Plans/All.xctestplan", "container:Config/Base.xcconfig", "group:Notes.txt", "container:Scripts"], others),
        "project-missing": in_workspace(base, ["group:P.xcodeproj", "group:Pods/Pods.xcodeproj"]),
        "project-missing-first": in_workspace(base, ["group:Pods/Pods.xcodeproj", "group:P.xcodeproj"]),
        "project-missing-in-group": in_workspace(base, GROUPED_MISSING),
        "project-missing-container": in_workspace(base, ["container:P.xcodeproj", "container:Pods/Pods.xcodeproj"]),
        "pods": in_workspace(era_project(77, edit=pods_phases), ["group:P.xcodeproj", "group:Pods/Pods.xcodeproj"]),
        "pods-old": in_workspace(era_project(46, edit=pods_phases), ["group:P.xcodeproj", "group:Pods/Pods.xcodeproj"]),
    }


def untyped_references(p, files):
    """File references with neither `lastKnownFileType` nor `explicitFileType`, in phases and not."""
    def untyped(name, phase=None, text="", directory=False):
        reference = p.add(f"untyped/{name}", "PBXFileReference", path=name, sourceTree="<group>")
        if text is not None:
            files[f"App/{name}/Contents.json" if directory else f"App/{name}"] = text
        add_to_group(p, "group/app", [reference])
        if phase:
            p.objects[p.ids(phase)]["files"].append(p.add(f"untyped/{name}/build", "PBXBuildFile", fileRef=reference))
    untyped("Helper.swift", "app/sources", "struct Helper {}\n")
    untyped("Extra.m", "app/sources", "void extra(void) {}\n")
    untyped("Extra.h", None, "void extra(void);\n")
    untyped("Data.json", "app/resources", "{}\n")
    untyped("Picture.png", "app/resources", "")
    untyped("Readme.md", None, "# App\n")
    untyped("Notes", None, "notes\n")
    untyped("Folder", "app/resources", "inside\n", directory=True)
    untyped("Resources.bundle", "app/resources", "inside\n", directory=True)
    untyped("Missing.swift", "app/sources", None)
    untyped("Missing.png", "app/resources", None)
    untyped("Missing", None, None)
    untyped("Missing.xyz", None, None)
    untyped("Missing.bundle", "app/resources", None)
    untyped("Data.xyz", None, "data\n")
    untyped("Layout.xyz", None, '<?xml version="1.0" encoding="UTF-8"?>\n<root/>\n')
    untyped("Settings.plist", "app/resources", INFO_PLIST.format(identifier="org.nomac.Settings"))
    untyped("Binary.plist", "app/resources", b"bplist00\xd0\x08\x00\x00\x00\x00\x00\x00\x01\x01\x00\x00\x00\x00\x00\x00\x00\x01"
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x09")
    untyped("Thing.stuff", "app/resources", "inside\n", directory=True)
    untyped("Images.xcassets", "app/resources", CATALOG, directory=True)
    untyped("Upper.H", None, "void upper(void);\n")
    untyped("Script.SH", None, "#!/bin/sh\n")
    untyped("Blob.xyz", None, bytes(range(256)))
    untyped("Blob", None, bytes(range(256)))
    untyped("Empty.xyz", None, "")
    untyped("Empty", None, "")
    untyped("Old.plist", None, "{\n    key = value;\n}\n")
    untyped("Shell", None, "#!/bin/sh\necho\n")
    untyped("Bash", None, "#!/bin/bash\necho\n")
    untyped("Python", None, "#!/usr/bin/env python3\nprint()\n")
    untyped("Ruby", None, "#!/usr/bin/ruby\nputs\n")
    untyped("Perl", None, "#!/usr/bin/perl\nprint;\n")
    untyped("Zsh", None, "#!/bin/zsh\necho\n")
    untyped("Latin", None, b"caf\xe9\n")
    untyped("Shell.xyz", None, "#!/bin/sh\necho\n")
    untyped("Lproj.lproj", None, "inside\n", directory=True)
    untyped("Page", None, '<?xml version="1.0" encoding="UTF-8"?>\n<root/>\n')


SNIFFED = {  # name: contents of untyped files whose extension names no type
    **{f"Run-{name}": f"#!/bin/{name}\necho\n" for name in ("sh", "bash", "zsh", "csh", "tcsh", "ksh", "dash", "fish")},
    **{f"Env-{name}": f"#!/usr/bin/env {name}\nx\n" for name in ("sh", "bash", "zsh", "csh", "perl", "python", "python3", "ruby", "php", "node", "swift")},
    **{f"Usr-{name}": f"#!/usr/bin/{name}\nx\n" for name in ("python", "python3", "php", "osascript", "swift", "awk", "tclsh")},
    "Space-sh": "#! /bin/sh\necho\n", "Args-sh": "#!/bin/sh -e\necho\n", "Local-ruby": "#!/usr/local/bin/ruby\nputs\n",
    "Utf16le-bom": "text\n".encode("utf-16"), "Utf16be-bom": b"\xfe\xff" + "text\n".encode("utf-16-be"), "Utf16le": "text\n".encode("utf-16-le"),
    "Utf8-bom": b"\xef\xbb\xbftext\n", "Utf32": "text\n".encode("utf-32"), "High-bytes": bytes(range(128, 256)), "Control": b"text\x01\x02\x07\n",
    "Xml-bom": b"\xef\xbb\xbf<?xml version=\"1.0\"?>\n<root/>\n", "Plist-head": '<plist version="1.0"><dict/></plist>\n',
    "Html": "<!DOCTYPE html>\n<html></html>\n", "Json": '{"key": 1}\n', "Pdf": b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n", "Png": b"\x89PNG\r\n\x1a\n",
    "Bplist.data": b"bplist00\xd0\x08", "Old.plist2": "{ a = b; }\n",
    **{f"Late-nul-{size}": b"a" * size + b"\x00\n" for size in (200, 300, 600, 1000, 1023, 1024, 1025, 1100, 5000, 70000)},
    "Backspace": b"text\x08\n", "Vtab": b"text\x0b\n",
    "Formfeed": b"text\x0c\n", "Escape": b"text\x1b[0m\n", "Tab-cr": b"a\tb\r\n", "Del": b"text\x7f\n",
    "Utf16-xml": '<?xml version="1.0"?>\n<root/>\n'.encode("utf-16"), "Utf16-sh": "#!/bin/sh\necho\n".encode("utf-16"),
    "Bom-sh": b"\xef\xbb\xbf#!/bin/sh\necho\n",
}


def sniffed_references(p, files):
    """Untyped references whose type only their contents can give."""
    for name, text in SNIFFED.items():
        reference = p.add(f"sniffed/{name}", "PBXFileReference", path=name, sourceTree="<group>")
        files[f"App/{name}"] = text
        add_to_group(p, "group/app", [reference])
    for name in ("Missing.plist", "Missing.PLIST"):
        add_to_group(p, "group/app", [p.add(f"sniffed/{name}", "PBXFileReference", path=name, sourceTree="<group>")])


def file_type_none():
    return {"untyped": (era_project(77, edit=untyped_references), "P.xcodeproj"),
            "untyped-old": (era_project(46, edit=untyped_references), "P.xcodeproj"),
            "sniffed": (era_project(77, edit=sniffed_references), "P.xcodeproj")}


EMPTY_OPTIONS = "      <AdditionalOptions>\n      </AdditionalOptions>\n"
OPTIONS = ('      <AdditionalOptions>\n         <AdditionalOption\n            key = "NSZombieEnabled"\n            value = "YES"\n'
           '            isEnabled = "YES">\n         </AdditionalOption>\n         <AdditionalOption\n            key = "MallocStackLogging"\n'
           '            value = ""\n            isEnabled = "NO">\n         </AdditionalOption>\n      </AdditionalOptions>\n')


def additional_options():
    return {
        "none": (era_project(77), "P.xcodeproj"),
        "empty": (era_project(77, scheme_extra=(EMPTY_OPTIONS, EMPTY_OPTIONS)), "P.xcodeproj"),
        "options": (era_project(77, scheme_extra=(OPTIONS, OPTIONS)), "P.xcodeproj"),
        "empty-old": (era_project(48, scheme_extra=(EMPTY_OPTIONS, EMPTY_OPTIONS)), "P.xcodeproj"),
        "launch-only": (era_project(77, scheme_extra=(OPTIONS, "")), "P.xcodeproj"),
    }


SCHEME = "P.xcodeproj/xcshareddata/xcschemes/App.xcscheme"


def change(edit):
    """An edit of the objectVersion-77 project, for one survey shape each."""
    return era_project(77, edit=edit), "P.xcodeproj"


def variant_group_path(path):
    def edit(p, files):
        group = p.objects[p.ids("app/interface")]
        group["path"] = path
        files[f"App/{path}/Base.lproj/Main.storyboard".replace("/./", "/")] = files.pop("App/Base.lproj/Main.storyboard")
    return edit


def variant_group_source_root(p, files):
    group = p.objects[p.ids("app/strings")]
    group["sourceTree"] = "SOURCE_ROOT"
    for child in group["children"]:
        p.objects[child]["path"] = "App/" + p.objects[child]["path"]


def project_header(p, files):
    header = p.add("kit/internal", "PBXFileReference", fileEncoding=4, lastKnownFileType="sourcecode.c.h", path="Internal.h", sourceTree="<group>")
    files["Kit/Internal.h"] = "void internal(void);\n"
    add_to_group(p, "group/kit", [header])
    p.objects[p.ids("kit/headers")]["files"].append(p.add("kit/internal/build", "PBXBuildFile", fileRef=header, settings={"ATTRIBUTES": ["Project"]}))


def module_map(p, files):
    reference = p.add("kit/modulemap", "PBXFileReference", includeInIndex=1, lastKnownFileType="sourcecode.module", path="module.modulemap", sourceTree="<group>")
    files["Kit/module.modulemap"] = "module Kit { header \"Kit.h\" }\n"
    add_to_group(p, "group/kit", [reference])


def absolute_references(p, files):
    library = p.add("absolute/z", "PBXFileReference", lastKnownFileType="compiled.mach-o.dylib", name="libz.dylib", path="/usr/lib/libz.dylib", sourceTree="<absolute>")
    source = p.add("absolute/source", "PBXFileReference", lastKnownFileType="sourcecode.swift", name="Absolute.swift", path="@SRC@/App/Absolute.swift", sourceTree="<absolute>")
    files["App/Absolute.swift"] = "struct Absolute {}\n"
    add_to_group(p, "group/frameworks", [library])
    add_to_group(p, "group/app", [source])
    p.objects[p.ids("app/frameworks")]["files"].append(p.add("absolute/z/build", "PBXBuildFile", fileRef=library))
    p.objects[p.ids("app/sources")]["files"].append(p.add("absolute/source/build", "PBXBuildFile", fileRef=source))


def put_source_path(src):
    project_file = src / "P.xcodeproj" / "project.pbxproj"
    project_file.write_text(project_file.read_text().replace("@SRC@", str(src)))


def asset_tags(tags, phase="app/resources"):
    """A file of `phase` tagged with `tags` for on-demand resources."""
    def edit(p, files):
        data = p.add("tags/data", "PBXFileReference", lastKnownFileType="text.json", path="Level1.json", sourceTree="<group>")
        files["App/Level1.json"] = "{}\n"
        add_to_group(p, "group/app", [data])
        p.objects[p.ids(phase)]["files"].append(p.add("tags/data/build", "PBXBuildFile", fileRef=data, settings={"ASSET_TAGS": tags}))
        p.objects[p.ids("project")]["attributes"]["KnownAssetTags"] = sorted(tags)
    return edit


def target_attribute(name, value):
    def edit(p, files):
        p.objects[p.ids("project")]["attributes"]["TargetAttributes"][p.ids("target/app")][name] = value
    return edit


def project_attribute(name, value):
    def edit(p, files):
        p.objects[p.ids("project")]["attributes"][name] = value
    return edit


def version_group_name(p, files):
    p.objects[p.ids("app/model")]["name"] = "Model.xcdatamodeld"


def plist_structure(p, files):
    p.objects[p.ids("app/info")]["plistStructureDefinitionIdentifier"] = "com.apple.xcode.plist.structure-definition.iphone.info-plist"


def dangling_child(p, files):
    add_to_group(p, "group/app", [p.ids("missing/object")])


def utf16_file(p, files):
    reference = p.add("utf16/strings", "PBXFileReference", fileEncoding=10, lastKnownFileType="text.plist.strings", path="Other.strings", sourceTree="<group>")
    files["App/Other.strings"] = '"other" = "utf16";\n'.encode("utf-16")
    add_to_group(p, "group/app", [reference])
    p.objects[p.ids("app/resources")]["files"].append(p.add("utf16/strings/build", "PBXBuildFile", fileRef=reference))


ARGUMENTS = ('      <CommandLineArguments>\n         <CommandLineArgument\n            argument = "-verbose"\n            isEnabled = "NO">\n'
             '         </CommandLineArgument>\n         <CommandLineArgument\n            argument = "-trace"\n            isEnabled = "YES">\n'
             '         </CommandLineArgument>\n      </CommandLineArguments>\n')
PLAYGROUND = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<playground version="5.0" target-platform="ios" buildActiveScheme="true">\n    <timeline fileName="timeline.xctimeline"/>\n</playground>\n'
BUILD_SYSTEM = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0">\n<dict>\n\t<key>BuildSystemType</key>\n\t<string>{value}</string>\n</dict>\n</plist>\n')


def survey_shapes():
    base = era_project(77)
    return {
        "none": (base, "P.xcodeproj"),
        "variant-group-path": change(variant_group_path("Sub")),
        "variant-group-path-dot": change(variant_group_path(".")),
        "variant-group-source-root": change(variant_group_source_root),
        "attributes-project": change(project_header),
        "sourcecode-module": change(module_map),
        "absolute": change(absolute_references) + (put_source_path,),
        "asset-tags": change(asset_tags(["Level1"])),
        "asset-tags-two": change(asset_tags(["Zeta", "Alpha"])),
        "asset-tags-sources": change(asset_tags(["Level1"], phase="app/sources")),
        "asset-tags-empty": change(asset_tags([])),
        "development-team-name": change(target_attribute("DevelopmentTeamName", "Nomac Team")),
        "last-testing-upgrade": change(project_attribute("LastTestingUpgradeCheck", "0510")),
        "version-group-name": change(version_group_name),
        "plist-structure": change(plist_structure),
        "group-dangling": change(dangling_child),
        "file-encoding-utf16": change(utf16_file),
        "parallelize-no": (dict(base, **{SCHEME: base[SCHEME].replace('parallelizeBuildables = "YES"', 'parallelizeBuildables = "NO"')}), "P.xcodeproj"),
        "command-line-arguments": (dict(base, **{SCHEME: base[SCHEME].replace("   </LaunchAction>", ARGUMENTS + "   </LaunchAction>")}), "P.xcodeproj"),
        "playground": in_workspace(base, ["group:P.xcodeproj", "group:Notes.playground"],
                                   {"Notes.playground/contents.xcplayground": PLAYGROUND, "Notes.playground/Contents.swift": "import UIKit\n"}),
        "build-system-original": (dict(base, **{"P.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings": BUILD_SYSTEM.format(value="Original")}),
                                  "P.xcodeproj"),
        "build-system-latest": (dict(base, **{"P.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings": BUILD_SYSTEM.format(value="Latest")}),
                                "P.xcodeproj"),
    }


def unresolved_proxy(build_file="AB0000000000000000000001", proxy="AB0000000000000000000002", container="AB0000000000000000000003",
                     remote="CD0000000000000000000001", info="Gone", product="libGone.a", file_type="archive.ar", sub_ref="AB0000000000000000000004",
                     sub_path="Sub/Sub.xcodeproj", target="AB0000000000000000000005", phase="AB0000000000000000000006", folder="",
                     configurations=("Debug",), default="Debug", project_settings=None, target_settings=None, project_dir="", stale=False,
                     xcconfig=None):
    """An app that links a product of a referenced project that is not on disk (B-036), every ID,
    name and path a parameter, so that each case changes one: the configurations and the default
    one, settings of the project (None removes one) and the target, the text of the project's base
    xcconfig, `projectDirPath`, and, with `stale`, the referenced project on disk without the
    product."""
    p = Project(ids=lambda key: {"build": build_file, "proxy": proxy, "container": container, "sub": sub_ref, "target": target, "phase": phase}.get(
        key, fuzz.object_id("unresolved", key)))
    sub = p.add("sub", "PBXFileReference", lastKnownFileType="wrapper.pb-project", name="Sub.xcodeproj", path=sub_path, sourceTree="<group>")
    item = p.add("container", "PBXContainerItemProxy", containerPortal=sub, proxyType=2, remoteGlobalIDString=remote, remoteInfo=info)
    library = p.add("proxy", "PBXReferenceProxy", fileType=file_type, path=product, remoteRef=item, sourceTree="BUILT_PRODUCTS_DIR")
    products = p.add("sub/products", "PBXGroup", children=[library], name="Products", sourceTree="<group>")
    source = p.add("source", "PBXFileReference", lastKnownFileType="sourcecode.swift", path="App.swift", sourceTree="<group>")
    app_product = p.add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="App.app", sourceTree="BUILT_PRODUCTS_DIR")
    product_group = p.add("products", "PBXGroup", children=[app_product], name="Products", sourceTree="<group>")
    base = p.add("xcconfig", "PBXFileReference", lastKnownFileType="text.xcconfig", path="Base.xcconfig", sourceTree="<group>") if xcconfig else None
    main = p.add("main", "PBXGroup", children=[source, sub, product_group] + ([base] if base else []), sourceTree="<group>")
    sources = p.add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[p.add("source/build", "PBXBuildFile", fileRef=source)],
                    runOnlyForDeploymentPostprocessing=0)
    frameworks = p.add("phase", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[p.add("build", "PBXBuildFile", fileRef=library)],
                       runOnlyForDeploymentPostprocessing=0)

    def configuration_list(key, settings, base=None):
        entries = [p.add(f"{key}/{name}", "XCBuildConfiguration", baseConfigurationReference=base, buildSettings=settings, name=name)
                   for name in configurations]
        return p.add(key, "XCConfigurationList", buildConfigurations=entries, defaultConfigurationIsVisible=0, defaultConfigurationName=default)
    app_settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.App", **(target_settings or {})}
    p.add("target", "PBXNativeTarget", buildConfigurationList=configuration_list("list/app", app_settings),
          buildPhases=[sources, frameworks], buildRules=[], dependencies=[], name="App", productName="App", productReference=app_product,
          productType="com.apple.product-type.application")
    root = p.add("project", "PBXProject", attributes={"LastUpgradeCheck": "2700"},
                 buildConfigurationList=configuration_list("list/project", {key: value for key, value in {"SDKROOT": "iphoneos", **(project_settings or {})}.items()
                                                                            if value is not None}, base),
                 developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, productRefGroup=product_group,
                 projectDirPath=project_dir, projectReferences=[{"ProductGroup": products, "ProjectRef": sub}], projectRoot="", targets=[p.ids("target")])
    prefix = folder + "/" if folder else ""
    files = {prefix + "P.xcodeproj/project.pbxproj": p.text(root, 77), prefix + "App.swift": "@main struct App { static func main() {} }\n"}
    if stale:
        files[prefix + sub_path + "/project.pbxproj"] = sub_project()[0]
    if xcconfig:
        files[prefix + "Base.xcconfig"] = xcconfig
    return files, prefix + "P.xcodeproj"


def unresolved_proxies():
    """Each case changes one input of `unresolved_proxy`, for which inputs the GUID Xcode gives
    the build file depends on."""
    return {
        "base": unresolved_proxy(),
        "base-again": unresolved_proxy(),
        "build-file-id": unresolved_proxy(build_file="AB00000000000000000000F1"),
        "proxy-id": unresolved_proxy(proxy="AB00000000000000000000F2"),
        "container-id": unresolved_proxy(container="AB00000000000000000000F3"),
        "remote-id": unresolved_proxy(remote="CD00000000000000000000F1"),
        "remote-info": unresolved_proxy(info="Other"),
        "product-path": unresolved_proxy(product="libOther.a"),
        "file-type": unresolved_proxy(product="Gone.framework", file_type="wrapper.framework"),
        "sub-ref-id": unresolved_proxy(sub_ref="AB00000000000000000000F4"),
        "sub-path": unresolved_proxy(sub_path="Elsewhere/Sub.xcodeproj"),
        "target-id": unresolved_proxy(target="AB00000000000000000000F5"),
        "phase-id": unresolved_proxy(phase="AB00000000000000000000F6"),
        "folder": unresolved_proxy(folder="Deeper"),
        "configurations": unresolved_proxy(configurations=("Debug", "Release"), default="Release"),
        "configurations-release-first": unresolved_proxy(configurations=("Release", "Debug"), default="Release"),
        "configurations-named": unresolved_proxy(configurations=("Alpha", "Beta"), default="Beta"),
        "macos": unresolved_proxy(project_settings={"SDKROOT": "macosx"}),
        "simulator": unresolved_proxy(project_settings={"SDKROOT": "iphonesimulator"}),
        "target-sdk": unresolved_proxy(target_settings={"SDKROOT": "macosx"}),
        "symroot": unresolved_proxy(project_settings={"SYMROOT": "$(PROJECT_DIR)/Out"}),
        "symroot-target": unresolved_proxy(target_settings={"SYMROOT": "Out2"}),
        "configuration-build-dir": unresolved_proxy(project_settings={"CONFIGURATION_BUILD_DIR": "$(PROJECT_DIR)/Products"}),
        "product-folder": unresolved_proxy(product="Lib/libGone.a"),
        "project-dir-path": unresolved_proxy(project_dir="Code"),
        "stale": unresolved_proxy(stale=True),
        "tvos": unresolved_proxy(project_settings={"SDKROOT": "appletvos"}),
        "watchos": unresolved_proxy(project_settings={"SDKROOT": "watchos"}),
        "visionos": unresolved_proxy(project_settings={"SDKROOT": "xros"}),
        "sdk-unset": unresolved_proxy(project_settings={"SDKROOT": None}),
        "symroot-relative": unresolved_proxy(project_settings={"SYMROOT": "Rel"}),
        "symroot-xcconfig": unresolved_proxy(xcconfig="SYMROOT = $(SRCROOT)/FromConfig\n"),
        "build-dir": unresolved_proxy(project_settings={"BUILD_DIR": "$(PROJECT_DIR)/BD"}),
        "build-dir-relative": unresolved_proxy(project_settings={"BUILD_DIR": "RelBD"}),
        "configuration-build-dir-relative": unresolved_proxy(project_settings={"CONFIGURATION_BUILD_DIR": "RelCBD"}),
        "srcroot-project-dir": unresolved_proxy(project_dir="Code", project_settings={"SYMROOT": "$(SRCROOT)/S"}),
        "symroot-parent": unresolved_proxy(folder="Deeper", project_settings={"SYMROOT": "../Up"}),
        "symroot-braces": unresolved_proxy(project_settings={"SYMROOT": "${PROJECT_DIR}/Braces"}),
        "symroot-absolute": unresolved_proxy(project_settings={"SYMROOT": PROXY_ABSOLUTE_SYMROOT}),
        "folder-unicode": unresolved_proxy(folder="Caf\u00e9"),
    }


SUB_PRODUCTS = [  # target, product type, product path, file type; no name the referencing project's targets have
    ("SubKit", "framework", "SubKit.framework", "wrapper.framework"),
    ("SubRes", "bundle", "SubRes.bundle", "wrapper.cfbundle"),
    ("Helper", "application", "Helper.app", "wrapper.application"),
    ("Share", "app-extension", "Share.appex", "wrapper.app-extension"),
    ("SubKitTests", "bundle.unit-test", "SubKitTests.xctest", "wrapper.cfbundle"),
    ("Tool", "tool", "Tool", "compiled.mach-o.executable"),
]


def sub_project():
    """The referenced project: one target per product of SUB_PRODUCTS."""
    p = Project(ids=lambda key: fuzz.object_id("sub", key))
    products, targets = [], []
    for name, kind, path, file_type in SUB_PRODUCTS:
        product = p.add(f"product/{name}", "PBXFileReference", explicitFileType=file_type, includeInIndex=0, path=path, sourceTree="BUILT_PRODUCTS_DIR")
        products.append(product)
        settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.{name}"}
        if kind == "tool":
            settings["SDKROOT"] = "macosx"
        entry = p.add(f"list/{name}/debug", "XCBuildConfiguration", buildSettings=settings, name="Debug")
        listing = p.add(f"list/{name}", "XCConfigurationList", buildConfigurations=[entry], defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
        targets.append(p.add(f"target/{name}", "PBXNativeTarget", buildConfigurationList=listing, buildPhases=[], buildRules=[], dependencies=[],
                             name=name, productName=name, productReference=product, productType=f"com.apple.product-type.{kind}"))
    group = p.add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
    main = p.add("main", "PBXGroup", children=[group], sourceTree="<group>")
    entry = p.add("list/project/debug", "XCBuildConfiguration", buildSettings={"SDKROOT": "iphoneos"}, name="Debug")
    listing = p.add("list/project", "XCConfigurationList", buildConfigurations=[entry], defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    root = p.add("project", "PBXProject", attributes={"LastUpgradeCheck": "2700"}, buildConfigurationList=listing, developmentRegion="en",
                 hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, productRefGroup=group, projectDirPath="", projectRoot="",
                 targets=targets)
    return p.text(root, 77), {name: p.ids(f"target/{name}") for name, *_ in SUB_PRODUCTS}, {name: p.ids(f"product/{name}") for name, *_ in SUB_PRODUCTS}


def proxy_file_types(dependencies=True):
    """The objectVersion-77 project references Sub.xcodeproj: the app links and embeds its
    framework, copies its bundle as a resource, its app and extension and tool with copy-files
    phases, and depends on their targets when `dependencies`."""
    sub_text, sub_targets, sub_products = sub_project()

    def edit(p, files):
        sub = p.add("sub", "PBXFileReference", lastKnownFileType="wrapper.pb-project", name="Sub.xcodeproj", path="Sub/Sub.xcodeproj", sourceTree="<group>")
        proxies = {}
        for name, kind, path, file_type in SUB_PRODUCTS:
            item = p.add(f"sub/{name}/item", "PBXContainerItemProxy", containerPortal=sub, proxyType=2, remoteGlobalIDString=sub_products[name], remoteInfo=name)
            proxies[name] = p.add(f"sub/{name}/proxy", "PBXReferenceProxy", fileType=file_type, path=path, remoteRef=item, sourceTree="BUILT_PRODUCTS_DIR")
        group = p.add("sub/products", "PBXGroup", children=list(proxies.values()), name="Products", sourceTree="<group>")
        add_to_group(p, "group/main", [sub])
        p.objects[p.ids("project")]["projectReferences"] = [{"ProductGroup": group, "ProjectRef": sub}]

        def build(name, phase, settings=None):
            p.objects[p.ids(phase)]["files"].append(p.add(f"sub/{name}/build/{phase}", "PBXBuildFile", fileRef=proxies[name], settings=settings))
        build("SubKit", "app/frameworks")
        build("SubKit", "app/embed", {"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
        build("SubRes", "app/resources")
        for name, spec, path in (("Helper", 16, "$(CONTENTS_FOLDER_PATH)/Watch"), ("Share", 13, ""), ("Tool", 6, "")):
            phase = p.add(f"sub/{name}/phase", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath=path, dstSubfolderSpec=spec, files=[],
                          name=f"Embed {name}", runOnlyForDeploymentPostprocessing=0)
            p.objects[p.ids("target/app")]["buildPhases"].append(phase)
            build(name, f"sub/{name}/phase")
        if dependencies:
            for name in ("SubKit", "SubRes", "Helper", "Share"):
                item = p.add(f"sub/{name}/dependency/item", "PBXContainerItemProxy", containerPortal=sub, proxyType=1,
                             remoteGlobalIDString=sub_targets[name], remoteInfo=name)
                p.objects[p.ids("target/app")]["dependencies"].append(p.add(f"sub/{name}/dependency", "PBXTargetDependency", name=name, targetProxy=item))
        files["Sub/Sub.xcodeproj/project.pbxproj"] = sub_text
    return era_project(77, edit=edit), "P.xcodeproj"


PROXY_FOLDERS = [f"{root}/{configuration}{platform}" for root in ("build", "Out", "Out2", "Code/build", "Deeper/build", "Rel", "FromConfig", "BD",
                                                                   "RelBD", "Code/S", "S", "Deeper/../Up", "Up", "Braces", "Caf\u00e9/build")
                 for configuration in ("Debug", "Release", "Alpha", "Beta")
                 for platform in ("-iphoneos", "", "-iphonesimulator", "-macosx", "-appletvos", "-watchos", "-xros")] + ["Products", "RelCBD"]
PROXY_ABSOLUTE_SYMROOT = "/tmp/nomac-envelope-experiments-symroot"


def hashed_proxy_path(src, product, digest):
    """The path, relative to `src` (or absolute outside it), whose MD5 is `digest`: a folder of
    PROXY_FOLDERS or PROXY_ABSOLUTE_SYMROOT's, its text composed or decomposed, joined with the
    product's path."""
    for folder in PROXY_FOLDERS:
        for form in ("NFC", "NFD"):
            path = unicodedata.normalize(form, f"{src}/{folder}/{product}")
            if hashlib.md5(path.encode()).hexdigest() == digest:
                return f"{folder}/{product}" + ("" if path.isascii() else f" ({form})")
    for configuration in ("Debug", "Release"):
        path = f"{PROXY_ABSOLUTE_SYMROOT}/{configuration}-iphoneos/{product}"
        if hashlib.md5(path.encode()).hexdigest() == digest:
            return path
    return None


def observe_unresolved_proxies(out, experiment, results):
    """The GUID and keys of the build file that links the missing product, per case, and the path
    under the case's folder whose MD5 the GUID ends with, among PROXY_FOLDERS joined with the
    reference proxy's path."""
    files = {}
    specs = unresolved_proxies()
    for case in results:
        src = out / experiment / case / "src"
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        if not pif.exists():
            continue
        project_file = next(text for path, text in specs[case][0].items() if path.endswith("P.xcodeproj/project.pbxproj"))
        product = re.search(r'isa = PBXReferenceProxy;[^}]*?path = "?([^";]+)"?;', project_file).group(1)
        for item in json.loads(pif.read_text()):
            if item.get("type") == "project":
                project = item["contents"]["guid"]
            if item.get("type") == "target":
                for phase in item["contents"].get("buildPhases", []):
                    for build_file in phase.get("buildFiles", []):
                        if "fileType" in build_file:
                            files[case] = dict(build_file, projectGUID=project, hashedPath=hashed_proxy_path(src, product, build_file["guid"][32:]))
    return {"buildFiles": files}


def editor_attributes(p, files):
    """Indentation and wrapping a file reference and a group set for the editor."""
    p.objects[p.ids("app/delegate")].update(indentWidth=2, tabWidth=2, usesTabs=1)
    p.objects[p.ids("group/app")].update(indentWidth=4, tabWidth=4, usesTabs=0, wrapsLines=1)


def deployment_copy(p, files):
    """A copy-files phase that runs only when installing, and a script that shows its environment."""
    phase = p.objects[p.ids("app/embed")]
    phase.update(buildActionMask=8, runOnlyForDeploymentPostprocessing=1)
    p.objects[p.ids("app/script")]["showEnvVarsInLog"] = 1


def install_path(p, files):
    p.objects[p.ids("target/app")]["productInstallPath"] = "$(HOME)/Applications"


def encodings(p, files):
    """fileEncoding 9 (ISO Latin 2) and 30 (Mac OS Roman)."""
    p.objects[p.ids("app/legacy")]["fileEncoding"] = 9
    p.objects[p.ids("app/legacy-h")]["fileEncoding"] = 30


def undefined_type(p, files):
    """React Native's linker writes `explicitFileType = undefined` and `lastKnownFileType = unknown`
    (Xcode's PIF: `file`, no fileTextEncoding; file types without a specification are fix/filetypes')."""
    font = p.add("rn/font", "PBXFileReference", explicitFileType="undefined", fileEncoding=9, includeInIndex=0, lastKnownFileType="unknown",
                 name="Inter-Regular.otf", path="Fonts/Inter-Regular.otf", sourceTree="<group>")
    files["App/Fonts/Inter-Regular.otf"] = b"OTTO\x00\x01"
    add_to_group(p, "group/app", [font])
    p.objects[p.ids("app/resources")]["files"].append(p.add("rn/font/build", "PBXBuildFile", fileRef=font))


def setting_conditions(p, files):
    for name in ("Debug", "Release"):
        settings = p.objects[p.ids(f"list/app/{name}")]["buildSettings"]
        settings["OTHER_SWIFT_FLAGS[config=Debug]"] = "-DCONFIG_DEBUG"
        settings["OTHER_CFLAGS[sdk=iphoneos*][arch=arm64]"] = "-DDEVICE_ARM64"


def platform_filters(p, files):
    build = p.objects[p.ids("app/z/build")]
    build["platformFilters"] = ["macos"]
    p.objects[p.ids("app/uikit/build")]["platformFilter"] = "maccatalyst"


def missing_local_package(p, files):
    package = p.add("package/missing", "XCLocalSwiftPackageReference", relativePath="Packages/Missing")
    p.objects[p.ids("project")]["packageReferences"] = [package]


def minimized_proxies_off(p, files):
    p.objects[p.ids("project")]["minimizedProjectReferenceProxies"] = 0


LAUNCH_EXTRAS = ('      <LocationScenarioReference\n         identifier = "San Francisco, CA, USA"\n         referenceType = "1">\n'
                 '      </LocationScenarioReference>\n      <StoreKitConfigurationFileReference\n         identifier = "../Products.storekit">\n'
                 '      </StoreKitConfigurationFileReference>\n')
LAUNCH_ATTRIBUTES = ('      customLLDBInitFile = "$(SRCROOT)/.lldbinit"\n      migratedStopOnEveryIssue = "YES"\n'
                     '      notificationPayloadFile = "App/Payload.apns"\n      showNonLocalizedStrings = "YES"\n      viewDebuggingEnabled = "No"\n'
                     '      enableGPUFrameCaptureMode = "3"\n      consoleMode = "0"\n      structuredConsoleMode = "1"\n')
TEST_EXTRAS = ('      <CommandLineArguments>\n         <CommandLineArgument\n            argument = "-UITests"\n            isEnabled = "YES">\n'
               '         </CommandLineArgument>\n      </CommandLineArguments>\n      <EnvironmentVariables>\n         <EnvironmentVariable\n'
               '            key = "TEST_MODE"\n            value = "1"\n            isEnabled = "YES">\n         </EnvironmentVariable>\n'
               '      </EnvironmentVariables>\n')
TEST_ATTRIBUTES = '      customLLDBInitFile = "$(SRCROOT)/.lldbinit"\n      onlyGenerateCoverageForSpecifiedTargets = "NO"\n      disableMainThreadChecker = "YES"\n'
EXECUTION = ('      <{kind}>\n         <ExecutionAction\n            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">\n'
             '            <ActionContent\n               title = "Run Script"\n               scriptText = "echo nomac&#10;">\n'
             '               <EnvironmentBuildable>\n{buildable}               </EnvironmentBuildable>\n            </ActionContent>\n'
             '         </ExecutionAction>\n      </{kind}>\n')
REMOTE_PROFILE = ('      <RemoteRunnable\n         runnableDebuggingMode = "0"\n         BundleIdentifier = "com.apple.springboard"\n'
                  '         RemotePath = "/System/Library/CoreServices/SpringBoard.app">\n      </RemoteRunnable>\n')
NESTED_GROUPS = ('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <Group\n      location = "container:"\n      name = "Apps">\n'
                 '      <Group\n         location = "group:"\n         name = "Main">\n         <FileRef\n            location = "group:P.xcodeproj">\n'
                 '         </FileRef>\n      </Group>\n   </Group>\n</Workspace>\n')


def scheme_variant(base, *replacements):
    """`base` with its App scheme's text changed by (old, new) replacements, each applied once."""
    text = base[SCHEME]
    for old, new in replacements:
        assert old in text, old
        text = text.replace(old, new, 1)
    return dict(base, **{SCHEME: text}), "P.xcodeproj"


def survey_shapes_2():
    base = era_project(77)
    app = buildable(fuzz.object_id("envelope", "target/app"), "App.app", "App", "P.xcodeproj")
    return {
        "none": (base, "P.xcodeproj"),
        "editor-attributes": change(editor_attributes),
        "launch-extras": scheme_variant(base, ("   </LaunchAction>", LAUNCH_EXTRAS + "   </LaunchAction>"),
                                        ('      allowLocationSimulation = "YES">', LAUNCH_ATTRIBUTES + '      allowLocationSimulation = "YES">'),
                                        ('      launchStyle = "0"', '      launchStyle = "1"')),
        "test-extras": scheme_variant(base, ("   </TestAction>", TEST_EXTRAS + EXECUTION.format(kind="PostActions", buildable=app) + "   </TestAction>"),
                                      ('      shouldUseLaunchSchemeArgsEnv = "YES">\n      <Testables>',
                                       TEST_ATTRIBUTES + '      shouldUseLaunchSchemeArgsEnv = "NO">\n      <Testables>'),
                                      ('            skipped = "NO">', '            skipped = "NO"\n            parallelizable = "NO">')),
        "build-extras": scheme_variant(base, ('      buildImplicitDependencies = "YES">\n',
                                              '      buildImplicitDependencies = "NO"\n      runPostActionsOnFailure = "NO">\n'
                                              + EXECUTION.format(kind="PreActions", buildable=app) + EXECUTION.format(kind="PostActions", buildable=app))),
        "profile-extras": scheme_variant(base, ("   </ProfileAction>", TEST_EXTRAS.split("      <EnvironmentVariables>")[0] + "   </ProfileAction>"),
                                         ('      savedToolIdentifier = ""', '      savedToolIdentifier = ""\n      notificationPayloadFile = "App/Payload.apns"')),
        "profile-remote-runnable": scheme_variant(base, ("   <ProfileAction", "   <ProfileAction"), (
            '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n' + app + '      </BuildableProductRunnable>\n   </ProfileAction>',
            REMOTE_PROFILE + '      <MacroExpansion>\n' + app + '      </MacroExpansion>\n   </ProfileAction>')),
        "archive-name": scheme_variant(base, ('      revealArchiveInOrganizer = "YES">', '      customArchiveName = "Nomac"\n      revealArchiveInOrganizer = "YES">')),
        "scheme-version-1.8": scheme_variant(base, ('   version = "1.7">', '   version = "1.8">')),
        "scheme-version-2.2": scheme_variant(base, ('   version = "1.7">', '   version = "2.2">')),
        "deployment-copy": change(deployment_copy),
        "install-path": change(install_path),
        "encodings": change(encodings),
        "undefined-type": change(undefined_type),
        "setting-conditions": change(setting_conditions),
        "platform-filters": change(platform_filters),
        "missing-local-package": change(missing_local_package),
        "minimized-proxies-off": change(minimized_proxies_off),
        "workspace-nested-groups": in_workspace(base, NESTED_GROUPS),
    }


def dangling_build_files(p, files):
    """Phases that list build files the project does not have."""
    for phase in ("app/sources", "app/resources"):
        p.objects[p.ids(phase)]["files"].append(p.ids(f"missing/{phase}"))


def ocunit_tests(p, files):
    p.objects[p.ids("target/tests")]["productType"] = "com.apple.product-type.bundle.ocunit-test"


def tests_wrapper_extension(extension):
    def edit(p, files):
        for name in ("Debug", "Release"):
            p.objects[p.ids(f"list/tests/{name}")]["buildSettings"]["WRAPPER_EXTENSION"] = extension
    return edit


def dependency_filter(key, value):
    def edit(p, files):
        p.objects[p.ids("app/dependency/kit")][key] = value
    return edit


def expected_signature(p, files):
    reference = p.add("sig/xcframework", "PBXFileReference", expectedSignature="SelfSigned:" + "AB" * 32, lastKnownFileType="wrapper.xcframework",
                      path="Vendor.xcframework", sourceTree="<group>")
    add_to_group(p, "group/frameworks", [reference])


def undefined_encoding(p, files):
    p.objects[p.ids("app/legacy")]["fileEncoding"] = "undefined"


def with_validation_level(files):
    text = files["P.xcodeproj/project.pbxproj"]
    files = dict(files)
    files["P.xcodeproj/project.pbxproj"] = text.replace("\trootObject = ", "\tvalidationLevel = 1;\n\trootObject = ")
    return files, "P.xcodeproj"


ENVIRONMENT_NO = ('      <EnvironmentVariables>\n         <EnvironmentVariable\n            key = "VERBOSE"\n            value = "NO"\n'
                  '            isEnabled = "NO">\n         </EnvironmentVariable>\n      </EnvironmentVariables>\n')
PATH_RUNNABLE = ('      <PathRunnable\n         runnableDebuggingMode = "0"\n         FilePath = "/Applications/Safari.app">\n      </PathRunnable>\n')
TEST_PLAN = ('{{\n  "configurations" : [\n    {{\n      "id" : "8D2D2B1E-0F7A-4E0D-9C33-0D51C5A8E0B1",\n      "name" : "Default",\n      "options" : {{\n\n      }}\n'
             '    }}\n  ],\n  "defaultOptions" : {{\n\n  }},\n  "testTargets" : [\n    {{\n      "parallelizable" : false,\n      "target" : {{\n'
             '        "containerPath" : "container:P.xcodeproj",\n        "identifier" : "{identifier}",\n        "name" : "AppTests"\n      }}\n    }}\n'
             '  ],\n  "version" : 1\n}}\n')


def autocreated_test_plan(base, others):
    """A second build action entry holding an AutocreatedTestPlanReference, built for testing and
    `others` for every other action."""
    entry = ('         <BuildActionEntry\n            buildForTesting = "YES"\n'
             + "".join(f'            buildFor{action} = "{others}"\n' for action in ("Running", "Profiling", "Archiving"))
             + f'            buildForAnalyzing = "{others}">\n            <AutocreatedTestPlanReference>\n            </AutocreatedTestPlanReference>\n'
             + "         </BuildActionEntry>\n")
    last = "         </BuildActionEntry>\n      </BuildActionEntries>"
    return scheme_variant(base, (last, "         </BuildActionEntry>\n" + entry + "      </BuildActionEntries>"))


def survey_shapes_3():
    base = era_project(77)
    app = buildable(fuzz.object_id("envelope", "target/app"), "App.app", "App", "P.xcodeproj")
    tests = fuzz.object_id("envelope", "target/tests")
    plan = dict(base, **{"P.xcodeproj/AppTests.xctestplan": TEST_PLAN.format(identifier=tests)})
    return {
        "none": (base, "P.xcodeproj"),
        "environment-no": scheme_variant(base, ("   </TestAction>", ENVIRONMENT_NO + "   </TestAction>")),
        "dangling-build-files": change(dangling_build_files),
        "ocunit-tests": change(ocunit_tests),
        "ocunit-xctest-extension": change(both(ocunit_tests, tests_wrapper_extension("xctest"))),
        "unit-test-octest-extension": change(tests_wrapper_extension("octest")),
        "dependency-filter-catalyst": change(dependency_filter("platformFilter", "maccatalyst")),
        "dependency-filters-macos": change(dependency_filter("platformFilters", ["macos"])),
        "path-runnable": scheme_variant(base, ('      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n' + app
                                                + '      </BuildableProductRunnable>\n', PATH_RUNNABLE + "      <MacroExpansion>\n" + app + "      </MacroExpansion>\n")),
        "archive-post-actions": scheme_variant(base, ('      revealArchiveInOrganizer = "YES">\n',
                                                       '      revealArchiveInOrganizer = "YES">\n' + EXECUTION.format(kind="PostActions", buildable=app))),
        "launch-flags": scheme_variant(base, ('      allowLocationSimulation = "YES">', '      GPUProfilerEnabled = "NO"\n      allowLocationSimulation = "YES">'),
                                       ('      debugDocumentVersioning = "YES"\n      debugServiceExtension', '      debugDocumentVersioning = "NO"\n      debugServiceExtension')),
        "autocreated-test-plan": autocreated_test_plan(base, "NO"),
        "autocreated-test-plan-running": autocreated_test_plan(base, "YES"),
        "validation-level": with_validation_level(base),
        "expected-signature": change(expected_signature),
        "undefined-encoding": change(undefined_encoding),
        "test-plan-serial": scheme_variant(plan, ("      <Testables>", '      <TestPlans>\n         <TestPlanReference\n            reference = "container:P.xcodeproj/AppTests.xctestplan"\n'
                                                                   '            default = "YES">\n         </TestPlanReference>\n      </TestPlans>\n      <Testables>')),
    }


DST_SUBFOLDERS = ["AbsolutePath", "Wrapper", "Executables", "Resources", "Frameworks", "SharedFrameworks", "SharedSupport", "PlugIns",
                  "JavaResources", "Product", "Products", "XPCServices", "SystemExtensions", "ExtensionKitExtensions", "None", "ProductsDirectory",
                  "Other"]


def dangling_file_reference(p, files):
    """A build file whose file reference the project does not have."""
    p.objects[p.ids("app/sources")]["files"].append(p.add("dangling/build", "PBXBuildFile", fileRef=p.ids("dangling/ref")))


def absolute_variant_group(p, files):
    """A variant group whose source tree is `<absolute>`, its child an absolute path not on disk,
    as projects moved from another machine have."""
    child = p.add("absolute/en", "PBXFileReference", lastKnownFileType="text.plist.strings", name="en",
                  path="/Users/someone/Old/en.lproj/Absolute.strings", sourceTree="<absolute>")
    group = p.add("absolute", "PBXVariantGroup", children=[child], name="Absolute.strings", sourceTree="<absolute>")
    add_to_group(p, "group/app", [group])
    p.objects[p.ids("app/resources")]["files"].append(p.add("absolute/build", "PBXBuildFile", fileRef=group))


def group_attributes(p, files):
    """`includeInIndex` on a group and `comments` on a file reference."""
    p.objects[p.ids("group/app")]["includeInIndex"] = 1
    p.objects[p.ids("app/delegate")]["comments"] = "The app's delegate."


def every_platform_filter(name):
    """`name` as a build file's platformFilters and platformFilter and as a target dependency's."""
    def edit(p, files):
        p.objects[p.ids("app/z/build")]["platformFilters"] = [name]
        p.objects[p.ids("app/uikit/build")]["platformFilter"] = name
        p.objects[p.ids("app/dependency/kit")]["platformFilters"] = [name]
        p.objects[p.ids("tests/dependency/app")]["platformFilter"] = name
    return edit


def singular_platform_filter(name):
    """`name` as a build file's and a target dependency's singular platformFilter."""
    def edit(p, files):
        p.objects[p.ids("app/uikit/build")]["platformFilter"] = name
        p.objects[p.ids("tests/dependency/app")]["platformFilter"] = name
    return edit


def resource_types(p, files):
    """A USDZ file and an Icon Composer icon, typed as Xcode types them, in the app's resources."""
    usdz = p.add("types/usdz", "PBXFileReference", lastKnownFileType="file.usdz", path="Model.usdz", sourceTree="<group>")
    icon = p.add("types/icon", "PBXFileReference", lastKnownFileType="wrapper.icon", path="AppIcon.icon", sourceTree="<group>")
    add_to_group(p, "group/app", [usdz, icon])
    for key in ("types/usdz", "types/icon"):
        p.objects[p.ids("app/resources")]["files"].append(p.add(f"{key}/build", "PBXBuildFile", fileRef=p.ids(key)))
    files["App/Model.usdz"] = b"PK\x03\x04" + bytes(60)
    files["App/AppIcon.icon/icon.json"] = '{\n  "groups" : [],\n  "supported-platforms" : {\n    "squares" : "shared"\n  }\n}\n'


def absolute_workspace(src):
    """A workspace that names the project by its absolute path."""
    (src / "W.xcworkspace").mkdir(parents=True, exist_ok=True)
    (src / "W.xcworkspace/contents.xcworkspacedata").write_text(workspace_data([f"absolute:{src}/P.xcodeproj"]))


LAUNCH_ATTRIBUTES_4 = '      debugAsWhichUser = "root"\n      queueDebuggingEnabled = "No"\n      memoryGraphOnResourceException = "Yes"\n'
TEST_STOREKIT = '      <StoreKitConfigurationFileReference\n         identifier = "../Products.storekit">\n      </StoreKitConfigurationFileReference>\n'


def survey_shapes_4():
    base = era_project(77)
    app = buildable(fuzz.object_id("envelope", "target/app"), "App.app", "App", "P.xcodeproj")
    shell = EXECUTION.format(kind="PreActions", buildable=app).replace('               title = "Run Script"\n',
                                                                       '               title = "Run Script"\n               shellToInvoke = "/bin/zsh"\n')
    cases = {
        "none": (base, "P.xcodeproj"),
        "cxx-settings": change(local_package(False, target_arguments=', cxxSettings: [.define("NOMAC")]')),
        "tools-version-none": change(local_package(False, tools_version=False)),
        "dangling-file-reference": change(dangling_file_reference),
        "dangling-file-reference-70": (era_project(70, edit=dangling_file_reference), "P.xcodeproj"),
        "platform-filter-macos": change(singular_platform_filter("macos")),
        "absolute-variant-group": change(absolute_variant_group),
        "group-attributes": change(group_attributes),
        "resource-types": change(resource_types),
        "launch-attributes": scheme_variant(base, ('      allowLocationSimulation = "YES">', LAUNCH_ATTRIBUTES_4 + '      allowLocationSimulation = "YES">'),
                                            ('      ignoresPersistentStateOnLaunch = "NO"', '      ignoresPersistentStateOnLaunch = "YES"')),
        "shell-to-invoke": scheme_variant(base, ('      buildImplicitDependencies = "YES">\n', '      buildImplicitDependencies = "YES">\n' + shell)),
        "test-storekit": scheme_variant(base, ("   </TestAction>", TEST_STOREKIT + "   </TestAction>")),
        "workspace-absolute": (dict(base), "W.xcworkspace", absolute_workspace),
    }
    for name in ("tvos", "watchos", "xros", "driverkit"):
        cases[f"platform-filters-{name}"] = change(every_platform_filter(name))
    return cases


def symroot(level):
    """SYMROOT set in the project's (`project`) or the app's (`app`) configurations."""
    def edit(p, files):
        for name in ("Debug", "Release"):
            p.objects[p.ids(f"list/{level}/{name}")]["buildSettings"]["SYMROOT"] = "$(PROJECT_DIR)/Out"
    return edit


def symroot_locations():
    """Where a scheme's settings put products when a level sets SYMROOT, the project opened
    alone or through a workspace."""
    project, app = era_project(77, edit=symroot("project")), era_project(77, edit=symroot("app"))
    return {
        "project": (project, "P.xcodeproj"),
        "project-in-workspace": in_workspace(project, ["group:P.xcodeproj"]),
        "target": (app, "P.xcodeproj"),
        "target-in-workspace": in_workspace(app, ["group:P.xcodeproj"]),
    }


def dst_subfolder(name):
    """The app's embed phase names its destination with `dstSubfolder`, as Xcode 26 writes it."""
    def edit(p, files):
        phase = p.objects[p.ids("app/embed")]
        del phase["dstSubfolderSpec"]
        phase["dstSubfolder"] = name
    return edit


def dst_subfolders():
    return {name: change(dst_subfolder(name)) for name in DST_SUBFOLDERS}


def observe_destinations(out, experiment, results):
    """The PIF's destination of the embed phase, per case."""
    found = {}
    for case in results:
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        if pif.exists():
            for item in json.loads(pif.read_text()):
                if item.get("type") == "target" and item["contents"]["name"] == "App":
                    for phase in item["contents"]["buildPhases"]:
                        if phase["type"] == "com.apple.buildphase.copy-files":
                            found[case] = {key: phase.get(key) for key in ("destinationSubfolder", "destinationSubpath")}
        else:
            found[case] = results[case].get("xcode")
    return {"destinations": found}


def variant_children(*paths, phase="app/resources", group_name="Localizable.strings", key="strings2"):
    """A variant group `group_name` of the app whose children are at `paths` (relative to the App
    group), each child named after its folder's region as Xcode names them, in `phase`."""
    def edit(p, files):
        children = []
        for index, path in enumerate(paths):
            folder = path.rsplit("/", 1)[0] if "/" in path else ""
            region = folder.rsplit("/", 1)[-1].split(".")[0] if folder else "Other"
            children.append(p.add(f"{key}/{index}", "PBXFileReference", fileEncoding=4, lastKnownFileType="text.plist.strings", name=region, path=path,
                                  sourceTree="<group>"))
            files[f"App/{path}"] = f'"key{index}" = "{region}";\n'
        group = p.add(key, "PBXVariantGroup", children=children, name=group_name, sourceTree="<group>")
        add_to_group(p, "group/app", [group])
        p.objects[p.ids(phase)]["files"].append(p.add(f"{key}/build", "PBXBuildFile", fileRef=group))
    return edit


def both(*edits):
    def edit(p, files):
        for step in edits:
            step(p, files)
    return edit


def variant_groups():
    return {
        "none": change(lambda p, files: None),
        "one-outside": change(variant_children("Other.strings", group_name="Other.strings")),
        "mixed": change(variant_children("en.lproj/Extra.strings", "Extra/de.strings", "fr.lproj/Extra.strings", group_name="Extra.strings")),
        "outside-first": change(variant_children("Extra/de.strings", "en.lproj/Extra.strings", group_name="Extra.strings")),
        "nested-lproj": change(variant_children("es.lproj/sub/Extra.strings", group_name="Extra.strings")),
        "uppercase-lproj": change(variant_children("nl.LPROJ/Extra.strings", group_name="Extra.strings")),
        "sources-phase": change(variant_children("Code/Extra.strings", phase="app/sources", group_name="Extra.strings")),
        "region-missing": change(variant_children("en.lproj/Extra.strings", "de.lproj/Extra.strings", group_name="Extra.strings")),
        "region-case": change(variant_children("FR.lproj/Extra.strings", "en.lproj/Extra.strings", group_name="Extra.strings")),
        "regions-two-groups": change(both(variant_children("it.lproj/Extra.strings", "de.lproj/Extra.strings", group_name="Extra.strings"),
                                          variant_children("ja.lproj/More.strings", "it.lproj/More.strings", group_name="More.strings", key="strings3"))),
        "region-and-outside": change(variant_children("pt-BR.lproj/Extra.strings", "Extra/es.strings", group_name="Extra.strings")),
    }


def observe_variant_groups(out, experiment, results):
    """knownRegions and the App group's variant groups (or what replaced them) in Xcode's PIF."""
    found = {}
    for case in results:
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        if not pif.exists():
            continue
        for item in json.loads(pif.read_text()):
            if item.get("type") != "project":
                continue
            contents = item["contents"]
            app = next(child for child in contents["groupTree"]["children"] if child.get("path") == "App")
            found[case] = {"knownRegions": contents.get("knownRegions"),
                           "app": [{key: child.get(key) for key in ("type", "name", "path", "regionVariantName") if child.get(key) is not None}
                                   | ({"children": [{key: c.get(key) for key in ("path", "regionVariantName") if c.get(key)} for c in child["children"]]}
                                      if child.get("children") else {})
                                   for child in app["children"] if "Extra" in (child.get("name", "") + child.get("path", ""))
                                   or "Other" in child.get("path", "") or "More" in child.get("name", "")]}
    return {"variantGroups": found}


def identities(debug, release=None, xcconfig=False):
    """Kit and AppTests, which set no provisioning style, sign with `debug` and `release`
    (CODE_SIGN_IDENTITY assignments), in the target's configurations or in the project's base
    xcconfig."""
    def edit(p, files):
        if xcconfig:
            files["Config/Base.xcconfig"] += "".join(f"{key} = {value}\n" for key, value in debug.items())
            return
        for target in ("kit", "tests"):
            for name, values in (("Debug", debug), ("Release", release or debug)):
                p.objects[p.ids(f"list/{target}/{name}")]["buildSettings"].update(values)
    return edit


IDENTITY = "CODE_SIGN_IDENTITY"
DEVICE_IDENTITY = "CODE_SIGN_IDENTITY[sdk=iphoneos*]"


def identity_conditions():
    cases = {
        "dash-plain": identities({IDENTITY: "-", DEVICE_IDENTITY: "Apple Development"}, {DEVICE_IDENTITY: "Apple Development", IDENTITY: "-"}),
        "dash-conditional": identities({IDENTITY: "Apple Development", DEVICE_IDENTITY: "-"}),
        "empty-conditional": identities({IDENTITY: "Apple Development", DEVICE_IDENTITY: ""}),
        "empty-plain": identities({IDENTITY: "", DEVICE_IDENTITY: "Apple Development"}),
        "simulator-dash": identities({IDENTITY: "Apple Development", "CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"}),
        "xcconfig-dash-plain": identities({IDENTITY: "-", "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Development"}, xcconfig=True),
        "xcconfig-dash-conditional": identities({IDENTITY: "Apple Development", "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "-"}, xcconfig=True),
    }
    return {name: (era_project(77, edit=edit), "P.xcodeproj") for name, edit in cases.items()}


def observe_provisioning(out, experiment, results):
    """Each target's provisioningStyle per configuration in Xcode's PIF."""
    styles = {}
    for case in results:
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        if pif.exists():
            styles[case] = {item["contents"]["name"]: [data.get("provisioningStyle") for data in item["contents"].get("provisioningSourceData", [])]
                            for item in json.loads(pif.read_text()) if item.get("type") == "target"}
    return {"provisioningStyles": styles}


REMOTE_MANIFEST = ('// swift-tools-version: 5.9\nimport PackageDescription\n\nlet package = Package(\n    name: "Remote",\n'
                   '    platforms: [.iOS(.v17)],\n    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],\n'
                   '    targets: [.target(name: "RemoteKit")]\n)\n')


def remote_package(requirement):
    """The app links RemoteKit of a package in a git repository at a file URL (made by
    `publish_remote`), with `requirement`."""
    def edit(p, files):
        package = p.add("package/remote", "XCRemoteSwiftPackageReference", repositoryURL="file://@SRC@/Remote", requirement=requirement)
        p.objects[p.ids("project")]["packageReferences"] = [package]
        product = p.add("package/remote/kit", "XCSwiftPackageProductDependency", package=package, productName="RemoteKit")
        p.objects[p.ids("target/app")]["packageProductDependencies"] = [product]
        p.objects[p.ids("app/frameworks")]["files"].append(p.add("package/remote/kit/build", "PBXBuildFile", productRef=product))
        files["Remote/Package.swift"] = REMOTE_MANIFEST
        files["Remote/Sources/RemoteKit/RemoteKit.swift"] = "public let remote = 1\n"
    return edit


def local_package(with_remote, root=False, target_arguments="", tools_version=True):
    """The app links LocalKit of a local package, which depends on the remote package when
    `with_remote`; with `root`, the package is a folder of the group tree instead of a reference.
    `target_arguments` follow LocalKit's dependencies; without `tools_version` the manifest has no
    `swift-tools-version` line."""
    def edit(p, files):
        if root:
            add_to_group(p, "group/main", [p.add("package/root", "PBXFileReference", lastKnownFileType="wrapper", path="Local", sourceTree="<group>")])
            package = None
        else:
            package = p.add("package/local", "XCLocalSwiftPackageReference", relativePath="Local")
            p.objects[p.ids("project")]["packageReferences"] = [package]
        product = p.add("package/local/kit", "XCSwiftPackageProductDependency", package=package, productName="LocalKit")
        p.objects[p.ids("target/app")]["packageProductDependencies"] = [product]
        p.objects[p.ids("app/frameworks")]["files"].append(p.add("package/local/kit/build", "PBXBuildFile", productRef=product))
        dependency = '.package(url: "file://@SRC@/Remote", exact: "1.0.0")' if with_remote else ""
        uses = '.product(name: "RemoteKit", package: "Remote")' if with_remote else ""
        files["Local/Package.swift"] = (('// swift-tools-version: 5.9\n' if tools_version else '') + 'import PackageDescription\n\nlet package = Package(\n'
                                        '    name: "Local",\n    platforms: [.iOS(.v17)],\n    products: [.library(name: "LocalKit", targets: ["LocalKit"])],\n'
                                        f'    dependencies: [{dependency}],\n    targets: [.target(name: "LocalKit", dependencies: [{uses}]{target_arguments})]\n)\n')
        files["Local/Sources/LocalKit/LocalKit.swift"] = "public let local = 1\n"
        files["Remote/Package.swift"] = REMOTE_MANIFEST
        files["Remote/Sources/RemoteKit/RemoteKit.swift"] = "public let remote = 1\n"
    return edit


def pin_root(src):
    """Publishes the remote package, then pins it in the root package's own Package.resolved, as
    `swift package resolve` in the root package's folder writes it."""
    publish_remote(src)
    revision = subprocess.run(["git", "rev-parse", "1.0.0^{commit}"], cwd=src / "Remote", capture_output=True, text=True, check=True).stdout.strip()
    pins = {"originHash": "0" * 64, "pins": [{"identity": "remote", "kind": "localSourceControl", "location": str(src / "Remote"),
                                               "state": {"revision": revision, "version": "1.0.0"}}], "version": 3}
    (src / "Local" / "Package.resolved").write_text(json.dumps(pins, indent=2) + "\n")


def publish_remote(src):
    """Makes `Remote` a git repository with tags 1.0.0 and 1.2.0 on `main`, and points the project at it."""
    git = ["git", "-c", "user.name=nomac", "-c", "user.email=nomac@example.invalid", "-c", "init.defaultBranch=main"]
    steps = [["init", "-q"], ["add", "."], ["commit", "-q", "-m", "1.0.0"], ["tag", "1.0.0"],
             ["commit", "-q", "--allow-empty", "-m", "1.2.0"], ["tag", "1.2.0"], ["commit", "-q", "--allow-empty", "-m", "main"]]
    for arguments in steps:
        subprocess.run(git + arguments, cwd=src / "Remote", check=True)
    for manifest in (src / "P.xcodeproj" / "project.pbxproj", src / "Local" / "Package.swift"):
        if manifest.exists():
            manifest.write_text(manifest.read_text().replace("@SRC@", str(src)))


RESOLVED = "P.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def forget_resolution(runner, src, created):
    """Before nomac runs: keeps the Package.resolved Xcode wrote next to the case, and removes
    what Xcode created in the project and its checkouts, so that nomac resolves the packages
    itself."""
    resolved = src / RESOLVED
    written = resolved.exists()
    if written:
        shutil.copy(resolved, src.parent / "xcode-Package.resolved")
    for path in sorted(created, key=len, reverse=True):
        target = src / path
        if path.startswith("P.xcodeproj/"):
            shutil.rmtree(target) if target.is_dir() else target.unlink()
    runner.clean_derived_data(src / "P.xcodeproj")
    return {"xcodeWrotePackageResolved": written}


def package_resolved():
    requirements = {"exact": {"kind": "exactVersion", "version": "1.0.0"},
                    "up-to-next-major": {"kind": "upToNextMajorVersion", "minimumVersion": "1.0.0"},
                    "branch": {"kind": "branch", "branch": "main"}}
    cases = {name: (era_project(77, edit=remote_package(requirement)), "P.xcodeproj", publish_remote, forget_resolution)
             for name, requirement in requirements.items()}
    without_shared = era_project(77, edit=remote_package(requirements["exact"]))
    del without_shared["P.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist"]
    cases["no-shared-data"] = (without_shared, "P.xcodeproj", publish_remote, forget_resolution)
    without_workspace = {path: text for path, text in without_shared.items() if not path.startswith("P.xcodeproj/project.xcworkspace/")}
    cases["no-workspace"] = (without_workspace, "P.xcodeproj", publish_remote, forget_resolution)
    for name, with_remote, root in (("local-with-remote", True, False), ("local-only", False, False), ("root-with-remote", True, True),
                                    ("root-pinned", True, True)):
        files = {path: text for path, text in era_project(77, edit=local_package(with_remote, root)).items()
                 if not path.startswith("P.xcodeproj/project.xcworkspace/")}
        cases[name] = (files, "P.xcodeproj", pin_root if name == "root-pinned" else publish_remote, forget_resolution)
    return cases


# ---------------------------------------------------------------------------------------------
# Running Xcode and nomac on a case


class Runner:
    def __init__(self, out, nomac):
        self.out = out
        self.nomac = str(nomac)
        self.env = capture.reference_environment(DEVELOPER_DIR)
        self.host = capture.host_identity(DEVELOPER_DIR, self.env)
        expected = capture.expected_xcode_build(json.loads((REPO_ROOT / "corpus" / "corpus.json").read_text()))
        if self.host["xcodeBuild"] != expected:
            sys.exit(f"error: Xcode at {DEVELOPER_DIR} is {self.host['xcodeBuild']}, corpus expects {expected}")

    def xcodebuild(self, arguments, cwd, out_path):
        completed = subprocess.run(["xcodebuild"] + arguments, cwd=cwd, env=self.env, capture_output=True, timeout=fuzz.COMMAND_TIMEOUT)
        Path(out_path).write_bytes(completed.stdout)
        Path(str(out_path) + ".stderr").write_bytes(completed.stderr)
        Path(str(out_path) + ".cmd").write_text(json.dumps({"argv": ["xcodebuild"] + arguments, "exitStatus": completed.returncode}, indent=2) + "\n")
        self.remove_result_bundles(completed.stderr)
        return completed

    @staticmethod
    def remove_result_bundles(stderr):
        for match in re.finditer(rb"Writing error result bundle to (\S+\.xcresult)", stderr):
            shutil.rmtree(match.group(1).decode(), ignore_errors=True)

    def clean_derived_data(self, container):
        for form in ("NFD", "NFC"):
            suffix = "-" + fuzz.folder_hash(unicodedata.normalize(form, str(container)))
            for entry in fuzz.DERIVED_DATA.glob("*" + suffix):
                if entry.is_dir():
                    shutil.rmtree(entry, ignore_errors=True)

    def nomac_run(self, arguments, home):
        return subprocess.run([self.nomac] + arguments, env=dict(self.env, NOMAC_HOME=str(home)), capture_output=True, timeout=fuzz.COMMAND_TIMEOUT)

    def run_case(self, case_dir, files, container_path, prepare=None, before_nomac=None):
        if case_dir.exists():
            shutil.rmtree(case_dir)
        src, ref, home = case_dir / "src", case_dir / "ref", case_dir / "home"
        for path, text in files.items():
            target = src / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text if isinstance(text, bytes) else text.encode())
        if prepare:
            prepare(src)
        before = set(tree(src))
        container = src / container_path
        flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
        base = [flag, str(container)]
        result = {"container": container_path}
        try:
            (ref / "pif").mkdir(parents=True)
            (ref / "settings").mkdir()
            app = {"id": case_dir.name, "container": container_path}
            (ref / "app.json").write_text(json.dumps(app) + "\n")
            (ref / "source.json").write_text(json.dumps({"path": str(src)}) + "\n")
            (ref / "host.json").write_text(json.dumps(self.host, indent=2, sort_keys=True) + "\n")
            dump = self.xcodebuild(["-dumpPIF", str(ref / "pif" / "workspace.pif")] + base, src, ref / "pif" / "dumpPIF.stdout")
            listing = self.xcodebuild(base + ["-list"], src, ref / "xcodebuild-list.txt")
            result["xcode"] = {"dumpPIF": dump.returncode, "list": listing.returncode}
            if dump.returncode != 0 or listing.returncode != 0:
                result["xcodeError"] = [line for line in (dump.stderr + listing.stderr).decode(errors="replace").splitlines()
                                        if "error:" in line or "Reason:" in line or line.startswith("\tThe ")][:6]
            index = capture.capture_settings(app, src, ref, self.env)
            if not (ref / "settings" / "index.json").exists():
                (ref / "settings" / "index.json").write_text("[]\n")
            result["xcode"]["settings"] = {item["name"]: item["exitStatus"] for item in index}
            result["xcodeWarnings"] = sorted({without_paths(line, src).strip() for path in ref.rglob("*.stderr")
                                              for line in path.read_text(errors="replace").splitlines() if "warning:" in line})
            result["xcodeCreated"] = [path for path in tree(src) if path not in before]
            before = set(tree(src))
            if before_nomac:
                result["beforeNomac"] = before_nomac(self, src, result["xcodeCreated"])
                before = set(tree(src))
            verify = self.nomac_run(["verify", str(ref), "--source", str(src), "--developer-dir", DEVELOPER_DIR, "--report", str(case_dir / "verify.json")], home)
            (case_dir / "verify.log").write_bytes(verify.stdout + b"\n--- stderr\n" + verify.stderr)
            result["verifyExit"] = verify.returncode
            if (case_dir / "verify.json").exists():
                report = json.loads((case_dir / "verify.json").read_text())
                result["checks"] = len(report["checks"])
                result["different"] = [{"kind": check["kind"], "name": check["name"], "status": check["status"], "detail": check.get("detail", [])[:6]}
                                       for check in report["checks"] if check["status"] not in ("identical", "equivalent")]
                # Equivalent: a documented difference of Xcode's own (docs/VERIFICATION.md).
                result["equivalent"] = [{"kind": check["kind"], "name": check["name"], "detail": check.get("detail", [])[:2]}
                                        for check in report["checks"] if check["status"] == "equivalent"]
            else:
                result["nomacError"] = verify.stderr.decode(errors="replace").strip().splitlines()[-3:]
            result["nomacCreated"] = [path for path in tree(src) if path not in before]
            listed = self.nomac_run(["list", flag, str(container), "--developer-dir", DEVELOPER_DIR], home)
            (case_dir / "nomac-list.txt").write_bytes(listed.stdout + listed.stderr)
            result["listText"] = "identical" if (shell_status(listed.returncode) == shell_status(listing.returncode) and
                                                 list_body(listed.stdout) == list_body(listing.stdout)) else "different"
        finally:
            self.clean_derived_data(container)
            shutil.rmtree(home, ignore_errors=True)
        result["identical"] = (result.get("checks", 0) > 0 and not result.get("different") and result.get("listText") == "identical")
        (case_dir / "result.json").write_text(json.dumps(result, indent=1) + "\n")
        return result


def shell_status(code):
    """The status a shell reports for a return code: `128 + n` for a process signal `n` stopped,
    which subprocess gives as `-n`."""
    return 128 - code if code < 0 else code


def tree(directory):
    """Every file and folder under `directory` outside git repositories, relative and sorted."""
    return sorted(str(path.relative_to(directory)) for path in directory.rglob("*") if ".git" not in path.relative_to(directory).parts)


def list_body(text):
    """`-list` text without its command-line preamble."""
    lines = text.decode(errors="replace").splitlines()
    start = next((index for index, line in enumerate(lines) if line.startswith("Information about")), len(lines))
    return lines[start:]


# ---------------------------------------------------------------------------------------------
# Comparing Xcode's outputs across the cases of one experiment


def canonical_pif(path, src):
    """A PIF with its source path replaced and signatures dropped, which hash paths."""
    def walk(value):
        if isinstance(value, dict):
            return {key: walk(item) for key, item in value.items() if key != "signature"}
        if isinstance(value, list):
            return [walk(item) for item in value]
        if isinstance(value, str):
            return re.sub(r"^(PROJECT|TARGET|WORKSPACE)@v\d+_.*", r"\1@signature", without_paths(value, src))
        return value
    return walk(json.loads(path.read_text()))


def without_paths(text, src):
    """`text` with the case's source path and its DerivedData folder's hash replaced."""
    return re.sub(r"(DerivedData/[^/\s\"]+)-[a-z]{28}", r"\1-<hash>", text.replace(str(src), "<SRC>"))


def xcode_outputs(case_dir):
    """Xcode's outputs of a case with its source path replaced: {file: content}."""
    src, ref = case_dir / "src", case_dir / "ref"
    outputs = {}
    if (ref / "pif" / "workspace.pif").exists():
        outputs["pif"] = canonical_pif(ref / "pif" / "workspace.pif", src)
    for path in sorted(ref.glob("xcodebuild-list.*")) + sorted((ref / "settings").glob("*")):
        if path.suffix in (".txt", ".json") and path.name != "index.json":
            text = without_paths(path.read_text(errors="replace"), src)
            outputs[str(path.relative_to(ref))] = "\n".join(line for line in text.splitlines() if not line.startswith("    /Applications/Xcode"))
    return outputs


def compare_outputs(out, experiment, cases, baseline):
    """For each case, the outputs that differ from `baseline`'s."""
    expected = xcode_outputs(out / experiment / baseline)
    differences = {}
    for case in cases:
        if case == baseline:
            continue
        actual = xcode_outputs(out / experiment / case)
        differing = sorted(name for name in set(expected) | set(actual) if expected.get(name) != actual.get(name))
        differences[case] = differing
    return differences


def observe_object_versions(out, experiment, results):
    readable = [case for case, result in results.items() if result["xcode"]["dumpPIF"] == 0]
    return {
        "readable": [int(case[1:]) for case in readable],
        "refused": {case: result["xcode"]["dumpPIF"] for case, result in results.items() if result["xcode"]["dumpPIF"] != 0},
        "refusal": next((result.get("xcodeError") for result in results.values() if result["xcode"]["dumpPIF"] != 0), None),
    }


def observe_object_versions_newest(out, experiment, results):
    return {"differFromV77": compare_outputs(out, experiment, list(results), "v77")}


def observe_object_ids(out, experiment, results):
    guids = {}
    for case in results:
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        if pif.exists():
            objects = json.loads(pif.read_text())
            project = next((item["contents"] for item in objects if item.get("type") == "project"), {})
            guids[case] = {"project": project.get("guid"), "group": project.get("groupTree", {}).get("guid")}
    return {"guids": guids}


def observe_against(baseline):
    def observe(out, experiment, results):
        return {f"differFrom{baseline.capitalize()}": compare_outputs(out, experiment, list(results), baseline)}
    return observe


def observe_warnings(out, experiment, results):
    return {"xcodeWarnings": {case: result.get("xcodeWarnings", []) for case, result in results.items()}}


def observe_file_types(out, experiment, results):
    """The PIF's `fileType` of each untyped reference."""
    types = {}
    for case in results:
        pif = out / experiment / case / "ref" / "pif" / "workspace.pif"
        found = {}

        def walk(value):
            if isinstance(value, dict):
                if value.get("type") == "file" and Path(value.get("path", "")).stem in UNTYPED_STEMS:
                    found[value["path"]] = value.get("fileType")
                for item in value.values():
                    walk(item)
            elif isinstance(value, list):
                for item in value:
                    walk(item)
        if pif.exists():
            walk(json.loads(pif.read_text()))
        types[case] = found
    return {"fileTypes": types}


UNTYPED_STEMS = {"Run-sh", "Missing", "Old"} | {name.split(".")[0] for name in SNIFFED} | {"Helper", "Extra", "Data", "Picture", "Readme", "Notes", "Folder", "Resources", "Missing", "Layout", "Settings", "Binary",
                 "Thing", "Images", "Upper", "Script", "Blob", "Empty", "Old", "Shell", "Page", "Bash", "Python",
                 "Ruby", "Perl", "Zsh", "Latin", "Lproj"}


def observe_package_resolved(out, experiment, results):
    observations = {}
    for case in results:
        case_dir = out / experiment / case
        xcode, nomac = case_dir / "xcode-Package.resolved", case_dir / "src" / RESOLVED
        observations[case] = {"xcode": json.loads(xcode.read_text()) if xcode.exists() else None,
                              "xcodeCreated": [path for path in results[case].get("xcodeCreated", []) if path.startswith("P.xcodeproj/")],
                              "nomacCreated": [path for path in results[case].get("nomacCreated", []) if path.startswith("P.xcodeproj/")],
                              "nomacWroteTheSame": xcode.exists() and nomac.exists() and xcode.read_text() == nomac.read_text()}
    return observations


def same_name_targets():
    # Targets of different projects with one name: xcodebuild builds one of them for
    # the name's scheme, which one changing from one run to the next (loader-experiments
    # `project-reference-names`, `workspace-names`).
    return {"project-reference": (loader.project_reference_names(), "Q.xcodeproj"),
            "workspace": (loader.project_reference_names(workspace=True), "W.xcworkspace"),
            "target-and-product": (loader.scheme_name_clashes(), "W.xcworkspace"),
            "renamed-schemes": (loader.user_schemes_workspace(), "W.xcworkspace")}


EXPERIMENTS = {
    "object-versions": (object_versions, observe_object_versions),
    "object-versions-newest": (object_versions_newest, observe_object_versions_newest),
    "object-ids": (object_ids, observe_object_ids),
    "xcconfig-missing": (xcconfig_missing, observe_warnings),
    "same-name-targets": (same_name_targets, observe_warnings),
    "workspace-refs": (workspace_refs, observe_against("baseline")),
    "file-type-none": (file_type_none, observe_file_types),
    "additional-options": (additional_options, observe_against("none")),
    "package-resolved": (package_resolved, observe_package_resolved),
    "identity-conditions": (identity_conditions, observe_provisioning),
    "survey-shapes": (survey_shapes, observe_against("none")),
    "unresolved-proxies": (unresolved_proxies, observe_unresolved_proxies),
    "survey-shapes-2": (survey_shapes_2, observe_against("none")),
    "variant-groups": (variant_groups, observe_variant_groups),
    "dst-subfolders": (dst_subfolders, observe_destinations),
    "survey-shapes-3": (survey_shapes_3, observe_against("none")),
    "proxy-file-types": (lambda: {"linked": proxy_file_types(), "without-dependencies": proxy_file_types(dependencies=False)}, observe_warnings),
    "survey-shapes-4": (survey_shapes_4, observe_against("none")),
    "symroot-locations": (symroot_locations, observe_warnings),
}


TABLE = REPO_ROOT / "Sources" / "NomacEnvelope" / "Loader" / "LoaderEnvelope+ExperimentCases.swift"


def write_table(out, nomac):
    """Checks each identical case as it was compared: its files written again, before Xcode and
    nomac added any (Package.resolved, for one)."""
    first = {}
    cases = []
    scratch = out / "table"
    shutil.rmtree(scratch, ignore_errors=True)
    for name, (make, _) in EXPERIMENTS.items():
        record_path = out / f"{name}.json"
        if not record_path.exists():
            continue
        results = json.loads(record_path.read_text())["results"]
        for case, spec in sorted(make().items()):
            if not results.get(case, {}).get("identical"):
                continue
            src = scratch / name / case
            for path, text in spec[0].items():
                (src / path).parent.mkdir(parents=True, exist_ok=True)
                (src / path).write_bytes(text if isinstance(text, bytes) else text.encode())
            if len(spec) > 2 and spec[2]:
                spec[2](src)
            completed = subprocess.run([str(nomac), "check", "--json", str(src / spec[1])], capture_output=True, text=True)
            if not completed.stdout:
                sys.exit(f"nomac check failed for {name}/{case}: {completed.stderr}")
            cases.append(f"{name}/{case}")
            for feature in json.loads(completed.stdout)["features"]:
                if feature["domain"] == "loader":
                    first.setdefault(feature["id"], name)
    shutil.rmtree(scratch)
    lines = ["// Generated by .github/scripts/envelope_experiments.py --table from the cases identical to Xcode",
             f"// ({len(cases)} cases of {len(set(case.split('/')[0] for case in cases))} experiments).",
             "extension LoaderEnvelope {", "    static let experimentCases: [(feature: String, experiment: String)] = ["]
    lines += [f"        ({json.dumps(feature)}, {json.dumps(name)})," for feature, name in sorted(first.items())]
    lines += ["    ]", "}", ""]
    TABLE.write_text("\n".join(lines))
    print(f"{len(first)} features from {len(cases)} identical cases")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", type=Path)
    parser.add_argument("experiments", nargs="*")
    parser.add_argument("--nomac", type=Path, default=DEFAULT_NOMAC)
    parser.add_argument("--jobs", type=int, default=MAX_JOBS)
    parser.add_argument("--cases", default="", help="comma-separated case names to run (default: all)")
    parser.add_argument("--table", action="store_true", help="write the envelope table of identical cases' features")
    arguments = parser.parse_args()
    out = arguments.output.expanduser().resolve()
    if arguments.table:
        write_table(out, arguments.nomac.expanduser().resolve())
        return
    unknown = [name for name in arguments.experiments if name not in EXPERIMENTS]
    if unknown:
        sys.exit(f"error: unknown experiments {unknown}; known: {', '.join(EXPERIMENTS)}")
    runner = Runner(out, arguments.nomac.expanduser().resolve())
    only = {name for name in arguments.cases.split(",") if name}
    for name in arguments.experiments or list(EXPERIMENTS):
        cases, observe = EXPERIMENTS[name]
        selected = {case: spec for case, spec in cases().items() if not only or case in only}
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(arguments.jobs, MAX_JOBS)) as pool:
            futures = {case: pool.submit(runner.run_case, out / name / case, spec[0], spec[1], *spec[2:]) for case, spec in selected.items()}
            results = {case: future.result() for case, future in futures.items()}
        record_path = out / f"{name}.json"
        record = json.loads(record_path.read_text()) if only and record_path.exists() else {"results": {}}
        record["results"].update(results)
        record["observations"] = observe(out, name, record["results"])
        record_path.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
        identical = [case for case, result in record["results"].items() if result["identical"]]
        print(f"{name}: {len(identical)}/{len(record['results'])} cases identical; different: "
              f"{sorted(set(record['results']) - set(identical))}", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Observe how Xcode represents loader features no corpus app has confirmed yet.

Runs on a macOS machine with Xcode installed (the `loader-experiments` workflow). Every
project is written here from scratch, each exercising features docs/formats/pif.md lists as
open questions:

- version-group: a Core Data model with two versions (`XCVersionGroup`) in a sources phase.
- targets: an aggregate target with a script phase and a dependency, a legacy (external build
  tool) target, and a custom build rule.
- settings: list settings whose elements contain spaces and quotes (`-showBuildSettings`).
- workspace: a workspace with two projects of the same file name in different folders, and a
  third whose target depends on a target of another project (`PBXReferenceProxy`).
- workspace-order: four projects whose workspace order, path order and GUID order differ.
- target-names: targets whose names contain spaces and punctuation, for how the header of a
  `-showBuildSettings` block spells them. With `-alltargets`, settings and targets show which
  blocks xcodebuild prints for all targets.
- schemes: which schemes `xcodebuild -list` reports for Swift packages (root packages with and
  without shared schemes, a local dependency), and what `-showBuildSettings -scheme` prints or
  fails with for package schemes, test-only schemes, schemes naming missing targets and
  schemes whose targets do not support the destination.
- autocreate: targets that differ only in their `TargetAttributes` entry (none, empty, without
  `CreatedOnToolsVersion`, with it) and in being an extension another target depends on, for
  which of them Xcode autocreates a scheme.
- extension-points: app extensions that differ only in the `NSExtensionPointIdentifier` of their
  Info.plist and in their SDK, and Safari-extension Info.plists reached in different ways
  (a macro, one configuration only, an SDK condition, an xcconfig, a missing file, a generated
  plist) or used by other product types, for which of them Xcode autocreates a scheme.
- product-types: one target of each product type, for which of them Xcode autocreates a scheme.
- infoplist-macros: INFOPLIST_FILE values with macros or SDK conditions, for which Info.plist
  the PIF's `bundleIdentifierFromInfoPlist` comes from.
- file-encodings: file references of many types with a `fileEncoding`, for which of them the
  PIF keeps `fileTextEncoding`.
- coverage: schemes whose code coverage comes from the scheme or from its test plans, for which
  `-showBuildSettings -scheme` reports CLANG_COVERAGE_MAPPING.
- coverage-autocreated-plan: schemes with shouldAutocreateTestPlan, with and without tests,
  coverage and test plans, for the same.
- provisioning-style, provisioning-style-project: where the PIF's `provisioningStyle` comes from
  (the ProvisioningStyle attribute, CODE_SIGN_STYLE in a target, an xcconfig or the project).
- provisioning-defaults: targets of each product type and SDK that set neither, for the PIF's
  `provisioningStyle` when nothing sets it.
- source-languages: which language the PIF's `predominantSourceCodeLanguage` names for targets
  mixing headers and sources of several languages, ties included.
- build-rules: unnamed build rules with other compilers, file types and patterns, for the name
  the PIF gives them.
- build-rule-keys: build rules with one key added, changed or left out (runOncePerArchitecture,
  script, patterns, compiler flags, file lists, ...), for the keys and defaults of the PIF's rules.
- build-tool-plugin: an app applying a local package's build tool plugin (plugin:GenPlugin),
  which runs the package's executable to generate a Swift file; the PIF, -list, the schemes'
  settings and a build (B-009).
- symroot-targets: frameworks that assign SYMROOT a value, the default, a macro, an empty
  string or under a condition, and one that does not, with -scheme and -target;
  symroot-project-*: one project per case, a framework without SYMROOT beside one with it, also
  with -derivedDataPath; symroot-references-sub, -top: a project referencing another, one of
  the two assigning SYMROOT.
- simulator-sdks: frameworks whose SDKROOT is a simulator SDK, per configuration or under a
  condition, with and without SUPPORTED_PLATFORMS, each scheme with an iOS and an iOS Simulator
  destination and each configuration (B-089); -project: the project's SDKROOT.
- scheme-pairs: a shared and a per-user scheme of each of several names in one project (B-065);
  -kinds, -hints, -hints-reverse, -hints-shared-only, -hints-user-only, -workspace,
  -workspace-hints: one input changed; -many: forty names; -single-<name>-<n>: one pair alone; -count-<n>: the first n of
  the forty.
- simulator-sdk-conditions: frameworks whose SDKROOT has an SDK, configuration or architecture
  condition, in the project file, through a macro or in a base xcconfig (B-089); -project,
  -project-reverse: the project's SDKROOT with a Debug condition.
- dangling-synchronized: one target per case whose Sources phase lists regular build files,
  build files whose file reference is missing at given positions, and the members of the
  target's synchronized folder; -renamed, -ids, -members: the same cases under other
  target and file names, other object IDs, and other member names; -lengths,
  -lengths-members: two and three members behind 1 to 9 regular build files; -pairs: pairs of
  member names, one changed at a time, at each of those lengths.
- watch-schemes: watch apps with their extensions under several watchOS deployment targets, the
  extension's Info.plist declaring a complication or not, and storyboards with notification
  and glance scenes, or a source named as Xcode's watch templates name theirs, for the schemes
  -list reports; -apns: two watch apps and one `.apns`
  file in the group tree; -plist: extensions whose Info.plist is bare, found through a macro,
  missing or generated (fuzzer seed 70155); -missing, -written, -empty, -garbage, -xib,
  -type-only, -extension-only, -complication: a watch app and a file reference to an interface
  file missing, written, empty or unreadable, or named and typed otherwise; -variant,
  -variant-missing: a storyboard on disk or missing in a variant group; -referencing,
  -referenced, -workspace: the missing storyboard in the project referencing the watch app's,
  in the referenced one, or in another project of the workspace.
- root-group-name, -path, -name-path: a main group with a name, a path or both, for the PIF's
  group tree.
- dependency-proxies: target dependencies through proxies into their own project, to no target
  and to one, without `target`, with a `target` naming no object, without remoteInfo.
- mig-codegen: MiG `.defs` build files with the Client and Server attributes, alone, together,
  with others and in Resources, for the PIF's `migCodegenFiles`.
- swift-wholemodule: SWIFT_OPTIMIZATION_LEVEL = -Owholemodule in a target (with and without
  SWIFT_COMPILATION_MODE, with a condition), its xcconfig and the project, and in
  OTHER_SWIFT_FLAGS, for the PIF and -showBuildSettings; -46, -upgrade-1010, -46-upgrade-1010
  and one per objectVersion from 42 to 70: the project saved at another version or upgrade check.
- product-names-empty: tools, libraries, frameworks, bundles and apps whose PRODUCT_NAME is
  unset or empty, for the name of a product that would have none.
- product-names, -configurations, -order: PRODUCT_NAME set in many ways (unset, macros,
  conditions, per configuration, xcconfig, Unicode) and one target of each product type, for the
  name of the PIF's product reference; product-types-sdks, product-types-restricted,
  product-types-other, product-names-no-sdk: product types under each SDK.
- class-prefix, -empty, -unset: a native, an aggregate and a legacy target under a project with
  and without CLASSPREFIX, for the targets' `classPrefix`.
- language-synchronized, language-fallback, language-fallback-missing: synchronized members a
  target excludes or has no phase for, on disk or not, for when they decide
  `predominantSourceCodeLanguage` and how they count.
- synchronized-phases-all: one synchronized member of every extension Xcode's specifications name,
  for the phase each joins.
- scheme-extension-key: shared schemes with and without wasCreatedForAppExtension for each kind of
  target, for the schemes -list reports.
- pif-key-order: settings whose names hold every ASCII punctuation mark, both cases, digit runs
  and non-ASCII letters, for the order of a PIF object's keys.
- workspace-locations-*: each key of a WorkspaceSettings.xcsettings that places builds, in the
  current user's and in the shared copy, for BUILD_DIR, OBJROOT and the folders under them.
- info-plist-conditions: INFOPLIST_FILE and GENERATE_INFOPLIST_FILE with conditions, macros and
  boolean spellings, and one target of each product type without them, for
  `bundleIdentifierFromInfoPlist`.
- synchronized-search-paths, -project, -folders: libraries and frameworks in synchronized folders,
  for the search paths Xcode adds to the target's configurations.
- scheme-package-clashes: shared project schemes named after local packages' products, building a
  missing target, another target or the product, for the schemes -list reports.
- root-package-references: local packages referenced by the group tree (`wrapper`, `folder`), by
  an XCLocalSwiftPackageReference or both, each with a test target named after its product that
  tests an internal target and one that tests the product's target, for the schemes -list
  reports and the targets each product scheme tests.
- local-packages: local package dependencies without shared schemes (one product, several
  products and an executable, one the project uses none of), for the schemes -list reports.
- macros: a macro and an executable in a remote package (a git repository at a file URL), a
  local package reference and a root package folder, for the PIF's `approvedByUser`.
- unlinked-products: targets whose packageProductDependencies name products no build phase
  links (a Frameworks phase linking another product, an empty Frameworks phase, a Sources
  phase only), for which products the PIF's `dependencies` list.
- autocreate-contexts, -off, -on, -user-off, -shared-off-user-on, -workspace-off,
  -workspace-project-off: one project with targets, a root package and local dependencies, and
  IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded in the shared or per-user settings of
  the project's workspace or of a workspace that opens it, for the schemes -list reports;
  -off-user adds a per-user scheme to -off.
- package-target-kinds: a root package and a local dependency with a library, a binary, a
  system library, a plugin, an unused plugin, an executable and a target in no product, and a
  shared scheme building each, for which -showBuildSettings -scheme fails with 66; and
  executable products a shared scheme builds, launches, profiles or names in a RemoteRunnable's
  MacroExpansion, for which of them -list reports an autocreated scheme.
- project-references: a project referencing two projects (`projectReferences`, `PBXReferenceProxy`,
  `PBXContainerItemProxy`), one of which references a third, for the PIF's projects, GUIDs and
  dependencies, the schemes of their targets and `-showBuildSettings`; -workspace opens the
  same projects through a workspace that lists only the first; -missing references a project
  that is not on disk; -packages has a package only the referenced project uses; -stale depends
  on a target, and links a product, that the referenced project on disk no longer has; -bundles
  gives the referenced project a test bundle and an app extension, for the schemes -list reports.
- workspace-twins: two projects of a workspace written from one template, so with the same
  object IDs, each linking its own framework, for the PIF's `targetReference`s.
- project-reference-names, workspace-names: targets of different projects with one name, for
  which of them `-scheme` builds.
- intents-codegen, intents-codegen-fr: intent definitions and Core ML models with each
  build-file ATTRIBUTES value, in each phase, typed otherwise, and as variant groups with
  children of different types and regions (the second with developmentRegion fr), for the PIF's
  `intentsCodegenVisibility`.
- codegen-file-types: one build file of each file type in a Sources phase, for which types carry
  `intentsCodegenVisibility`.
- codegen-members: intent definitions and Core ML models in a synchronized folder, with the
  exception set's attributes, header visibility and compiler flags, for the same key.
- synchronized-headers: headers and other sources of a synchronized folder that publicHeaders
  or privateHeaders name, or whose attributes say Public or Private, for their headerVisibility.
- variant-regions: variant group children whose name and `.lproj` folder differ, or that have
  no name or no `.lproj` folder, for the PIF's `regionVariantName`.
- provisioning-fallback, provisioning-fallback-project(-debug), provisioning-profile,
  provisioning-profile-project: `provisioningStyle` where a configuration sets no
  CODE_SIGN_STYLE (default configuration, attribute, provisioning profiles in any
  configuration, SDK conditions, macros, xcconfigs, a project-level style or profile).
- provisioning-conditions, provisioning-conditions-project: CODE_SIGN_STYLE set both with and
  without an SDK condition, in one xcconfig in either order, across an #include, at the target
  and in its xcconfig, and home-assistant's shape at the project level, for provisioningStyle and
  what -showBuildSettings reports.
- test-plan-entries: schemes whose build action builds a test plan (a TestPlanReference in a
  BuildActionEntry), for what `-list` and `-showBuildSettings -scheme` make of it.
- copy-files: copy-files phases with every dstSubfolderSpec value, with and without a dstPath,
  for the PIF's `destinationSubfolder`; copy-files-18, a value above 17, for how xcodebuild
  fails.
- package-pins-root, -remote, -both, -two-roots, -two-roots-same, -unpinned, -workspace, -local:
  a project whose packages come from root package folders or local package references, each
  with or without a Package.resolved of its own, and from a remote package reference, with or
  without a Package.resolved of the project's workspace, for the versions Xcode checks out and
  the Package.resolved files it writes.
- synchronized-missing: synchronized folders that are not on disk (one no target lists, one a
  target lists with exceptions), whose path is a file, or that are empty, for the PIF's groups.
- product-target-dependencies: target dependencies that name a package product (a productRef),
  alone, next to target dependencies, also linked or listed, for the PIF's `dependencies`.
- product-duplicates: targets naming one package product through several product dependency
  objects (linked, embedded, listed, named by target dependencies) and one target through
  several dependencies, for which entries the PIF's `dependencies` keeps.
- blueprint-names: schemes whose BuildableReferences have no BlueprintName, or another target's,
  for -list and -showBuildSettings -scheme.

- unicode-nfc, unicode-nfd: one project whose project file, scheme files and most files on
  disk are written in NFC (or NFD), some files and keys in the other form: groups, files, a
  synchronized folder with exception sets, explicit file types and folders, header and
  attribute keys, compiler flags and anchored xcconfigs keyed in both forms, an xcconfig spelled
  otherwise on disk, targets, configurations and schemes with non-ASCII names; for which strings
  the PIF, -list and -showBuildSettings decompose, and which names -scheme, -target and
  -configuration find in the other form.
- unicode-project-dir, unicode-project-dir-nfd: a non-ASCII projectDirPath, for the spelling of
  projectDirectory.
- unicode-order, unicode-order-ascii: synchronized folders whose one non-ASCII member sits at
  the top level or in subfolders in every disk form, after thirty own build files, for the hash
  that places a folder's block in a phase (the second without the accents, as a control).
- unicode-list-order: shared schemes whose names tell how -list orders accented, decomposed and
  compatibility characters.
- derived-data-names, derived-data-packages: projects and workspaces named with spaces,
  control characters, punctuation and non-ASCII letters, for the DerivedData folder name, and a
  remote package checked out in such a folder.
- declared-types, declared-types-2, declared-language: file references declaring every type of
  Swift Build's specifications, types the specifications lack and none, on files, folders and
  paths not on disk, for the `fileType` the PIF gives them and the language it counts.
- regions-classic, regions-classic-2 to -5: ordinary variant groups whose children name
  regions `knownRegions` lacks, next to synchronized folders, with and without the development
  region and Base, and children outside a `.lproj` folder, for the PIF's `knownRegions`.
- variant-build-files: build files that name variant groups with children outside `.lproj`
  folders, in Resources and Sources of two targets, for the build files the PIF gives them.
- regions-case, regions-case-2 to -4: regions that differ from `knownRegions`, the development
  region or each other only in case, for how `knownRegions` matches and spells them.
- declared-language-2, language-weights, language-ties, language-pool, language-bisect,
  language-types, language-pairs: declared types against paths, types without a language,
  counts and ties, for `predominantSourceCodeLanguage`.
- synchronized-phases, -2: a synchronized folder with one member of each of 113 extensions, in
  a target with and without a Headers phase, for the phase each type joins.
- lproj-groups: variant groups inside groups whose path is a `.lproj` folder (mattermost's
  Localizable.strings), for which children the PIF keeps in the variant group.
- declared-encodings: references with a fileEncoding whose declared types Xcode types again,
  binary or text on disk or not there, for their fileTextEncoding.

The DerivedData folders xcodebuild creates for the experiments' projects are removed.
- user-schemes: schemes in the current user's and another user's xcuserdata of a project and of
  its project.xcworkspace, a shared and a per-user scheme with one name, and an
  xcschememanagement.plist hiding schemes, giving order hints and suppressing autocreation, for
  what -list shows, what each scheme covers and which scheme -scheme uses; -list also runs with
  USER and LOGNAME naming the other user. user-schemes-workspace, -references and -packages: the
  same names in a workspace, its projects, a referenced project and a package.
- own-test-schemes, own-test-schemes-hosts: test bundles linked to a target by a dependency, a
  test host or a TestTargetID, that target covered by no scheme, a shared or a per-user one, or
  suppressed, for which bundles get a scheme of their own; -more: skipped testables, apps whose
  SDKROOT is auto, and targets another project's target shares a name with.
- scheme-order: scheme names with numbers, accents, case, punctuation and other scripts, for the
  order of -list.
- scheme-destinations: schemes that build, launch or profile targets of different platforms, and
  aggregate targets depending on them, for which destinations -showBuildSettings accepts;
  same-name-destinations: an iOS and a macOS target with one name, six runs with and without -json.
- autocreate-testables: bundles a shared scheme tests, builds, skips or names in a test plan,
  the bundles of the apps an extension's scheme builds, and bundles and apps whose SDKROOT is
  auto, for what each autocreated scheme tests; autocreate-ui-targets: UI test bundles whose
  TestTargetID names each product type; autocreate-auto-hosts: apps whose SDKROOT is auto and the
  executables their bundles' TEST_HOST names.
- autocreate-debug-dev, -lower, -suffix, -both, -upper: configurations named like Debug, for the
  one autocreated schemes launch with.
- provisioning-auto: targets whose SDKROOT is auto, with and without a team or an identity, for
  the PIF's provisioningStyle.
- synchronized-exceptions, -2: platformFiltersByRelativePath and build phase membership exception
  sets on every kind of member, and paths that are not on disk named by each key of each set;
  synchronized-phase-order, -2: where a membership set's block goes in its phase;
  synchronized-missing-order: where paths not on disk in subfolders go among the members.
- scheme-name-clashes: an autocreated scheme with the name of shared schemes of other projects,
  and a target and a local package product with one name, for what -scheme uses, four runs each;
  test-host-clashes, -reversed, -project, -project-reversed: two apps with one product name and a
  bundle hosted by one of them, for which scheme tests it, three runs each.

For each, the PIF (`xcodebuild -dumpPIF`) and the output of the xcodebuild commands that matter
(standard output, standard error and exit status) are kept. `write_all()` writes the same projects anywhere, so nomac's output can be compared
locally. No Xcode output other than for these self-written projects is kept.

Usage: loader_experiments.py <output-dir> [experiment ...]

Without experiment names, every experiment runs and the output directory is recreated; with
names, only those run and only their outputs are replaced.
"""

import getpass
import hashlib
import itertools
import json
import os
import plistlib
import random
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

HEADER = """// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{
{objects}	}};
	rootObject = {root} /* Project object */;
}}
"""


def configurations(list_id, debug_id, release_id, settings, release_settings=None, base=None):
    """Debug and Release with `settings` (Release with `release_settings` when given), both based
    on the xcconfig file reference `base` when given."""
    def body(values):
        return "".join(f"\t\t\t\t{key} = {value};\n" for key, value in values.items())
    base_line = f"\t\t\tbaseConfigurationReference = {base};\n" if base else ""
    return f"""		{debug_id} /* Debug */ = {{
			isa = XCBuildConfiguration;
{base_line}			buildSettings = {{
{body(settings)}			}};
			name = Debug;
		}};
		{release_id} /* Release */ = {{
			isa = XCBuildConfiguration;
{base_line}			buildSettings = {{
{body(settings if release_settings is None else release_settings)}			}};
			name = Release;
		}};
		{list_id} = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_id} /* Debug */,
				{release_id} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
"""


def named_configurations(list_id, entries, default):
    """A configuration list of `entries` (identifier, name, settings) in that order."""
    text, references = "", ""
    for identifier, name, values in entries:
        body = "".join(f"\t\t\t\t{key} = {value};\n" for key, value in values.items())
        text += f"""		{identifier} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}			}};
			name = {name};
		}};
"""
        references += f"\t\t\t\t{identifier} /* {name} */,\n"
    return text + f"""		{list_id} = {{
			isa = XCConfigurationList;
			buildConfigurations = (
{references}			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = {default};
		}};
"""


def project(root_id, main_group, targets, objects, project_settings=None, project_references="", package_references="", attributes="",
            project_configurations=None, known_regions=("en", "Base"), development_region="en"):
    """A project file: `objects` holds everything except the project and its configurations, which
    are Debug and Release with `project_settings` unless `project_configurations` (a list of
    (name, settings) and the default name) names others."""
    target_list = "".join(f"\t\t\t\t{t},\n" for t in targets)
    regions = "".join(f"\t\t\t\t{region},\n" for region in known_regions)
    if project_configurations:
        entries, default = project_configurations
        text = objects + named_configurations("F000000000000000000000PL", [(f"F0000000000000000000PC{index:02d}", name, values)
                                                                          for index, (name, values) in enumerate(entries)], default)
    else:
        text = objects + configurations("F000000000000000000000PL", "F000000000000000000000PD", "F000000000000000000000PR",
                                        project_settings or {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"})
    text += f"""		{root_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 2700;
{attributes}			}};
			buildConfigurationList = F000000000000000000000PL;
			developmentRegion = {development_region};
			hasScannedForEncodings = 0;
			knownRegions = (
{regions}			);
			mainGroup = {main_group};
			minimizedProjectReferenceProxies = 1;
{package_references}			preferredProjectObjectVersion = 77;
			projectDirPath = "";
{project_references}			projectRoot = "";
			targets = (
{target_list}			);
		}};
"""
    return HEADER.format(objects=text, root=root_id)


def pbx_string(text):
    """`text` as a quoted property-list string."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t").replace("\n", "\\n") + '"'


def app_target(target_id, name, phases, list_ids, settings, extra="", product_type="com.apple.product-type.application",
               release_settings=None, base=None, product_reference=None, configuration_list=None):
    """A native target whose configurations are Debug and Release, or the configuration list
    `configuration_list` (identified by list_ids[0]) when given."""
    phase_list = "".join(f"\t\t\t\t{p},\n" for p in phases)
    reference = f"\t\t\tproductReference = {product_reference};\n" if product_reference else ""
    configuration_text = configuration_list or configurations(list_ids[0], list_ids[1], list_ids[2], settings, release_settings, base)
    return configuration_text + f"""		{target_id} = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {list_ids[0]};
			buildPhases = (
{phase_list}			);
{extra}			name = {pbx_string(name)};
			productName = {pbx_string(name)};
{reference}			productType = "{product_type}";
		}};
"""


# The file type and the file name of a product, by product type (without the
# `com.apple.product-type.` prefix), as Xcode's target templates write them.
PRODUCT_FILES = {
    "application": ("wrapper.application", "{}.app"), "app-extension": ("wrapper.app-extension", "{}.appex"),
    "extensionkit-extension": ("wrapper.extensionkit-extension", "{}.appex"), "framework": ("wrapper.framework", "{}.framework"),
    "xpc-service": ("wrapper.xpc-service", "{}.xpc"), "library.static": ("archive.ar", "lib{}.a"),
    "library.dynamic": ("compiled.mach-o.dylib", "lib{}.dylib"), "bundle": ("wrapper.cfbundle", "{}.bundle"),
    "tool": ("compiled.mach-o.executable", "{}"), "application.on-demand-install-capable": ("wrapper.application", "{}.app"),
    "app-extension.messages-sticker-pack": ("wrapper.app-extension", "{}.appex"),
    "application.watchapp2-container": ("wrapper.application", "{}.app"), "application.watchapp2": ("wrapper.application", "{}.app"),
    "watchkit2-extension": ("wrapper.app-extension", "{}.appex"), "system-extension": ("wrapper.system-extension", "{}.systemextension"),
    "xcode-extension": ("wrapper.app-extension", "{}.appex"), "driver-extension": ("wrapper.driver-extension", "{}.dext"),
    "instruments-package": ("com.apple.instruments.instrdst", "{}.instrdst"), "metal-library": ("archive.metal-library", "{}.metallib"),
    "bundle.unit-test": ("wrapper.cfbundle", "{}.xctest"), "bundle.ui-testing": ("wrapper.cfbundle", "{}.xctest"),
    "application.watchapp": ("wrapper.application", "{}.app"), "watchkit-extension": ("wrapper.app-extension", "{}.appex"),
    "application.messages": ("wrapper.application", "{}.app"), "app-extension.messages": ("wrapper.app-extension", "{}.appex"),
    "tv-app-extension": ("wrapper.app-extension", "{}.appex"), "framework.static": ("wrapper.framework.static", "{}.framework"),
    "kernel-extension": ("wrapper.kernel-extension", "{}.kext"),
}


def product_file(reference_id, name, product_type):
    """The PBXFileReference of a target's product in BUILT_PRODUCTS_DIR."""
    file_type, pattern = PRODUCT_FILES[product_type.removeprefix("com.apple.product-type.")]
    path = pbx_string(pattern.format(name))
    return (f"\t\t{reference_id} = {{isa = PBXFileReference; explicitFileType = {pbx_string(file_type)}; includeInIndex = 0; "
            f"path = {path}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")


APPLICATION = "com.apple.product-type.application"
UNIT_TEST = "com.apple.product-type.bundle.unit-test"
APP_SETTINGS = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment", "PRODUCT_NAME": '"$(TARGET_NAME)"'}

MODEL = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="1" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">
    <entity name="Item" representedClassName="Item" syncable="YES" codeGenerationType="class"/>
</model>
"""


def version_group():
    objects = """		A00000000000000000000001 /* Model.xcdatamodeld in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000002 /* Model.xcdatamodeld */; };
		A00000000000000000000003 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; };
		A00000000000000000000004 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
		A00000000000000000000005 /* Model.xcdatamodel */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = Model.xcdatamodel; sourceTree = "<group>"; };
		A00000000000000000000006 /* Model 2.xcdatamodel */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = "Model 2.xcdatamodel"; sourceTree = "<group>"; };
		A00000000000000000000002 /* Model.xcdatamodeld */ = {
			isa = XCVersionGroup;
			children = (
				A00000000000000000000005 /* Model.xcdatamodel */,
				A00000000000000000000006 /* Model 2.xcdatamodel */,
			);
			currentVersion = A00000000000000000000006 /* Model 2.xcdatamodel */;
			path = Model.xcdatamodeld;
			sourceTree = "<group>";
			versionGroupType = wrapper.xcdatamodel;
		};
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000004 /* App.swift */,
				A00000000000000000000002 /* Model.xcdatamodeld */,
			);
			sourceTree = "<group>";
		};
		F00000000000000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000003 /* App.swift in Sources */,
				A00000000000000000000001 /* Model.xcdatamodeld in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
""" + app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS)
    files = {
        "App.swift": "@main struct App { static func main() {} }\n",
        "Model.xcdatamodeld/Model.xcdatamodel/contents": MODEL,
        "Model.xcdatamodeld/Model 2.xcdatamodel/contents": MODEL,
        "Model.xcdatamodeld/.xccurrentversion": '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>_XCCurrentVersionName</key>\n\t<string>Model 2.xcdatamodel</string>\n</dict>\n</plist>\n',
    }
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects), **files}


def targets():
    objects = """		A00000000000000000000003 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; };
		A00000000000000000000007 /* gen.foo in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000008 /* gen.foo */; };
		A00000000000000000000004 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
		A00000000000000000000008 /* gen.foo */ = {isa = PBXFileReference; lastKnownFileType = text; path = gen.foo; sourceTree = "<group>"; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000004 /* App.swift */,
				A00000000000000000000008 /* gen.foo */,
			);
			sourceTree = "<group>";
		};
		F00000000000000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000003 /* App.swift in Sources */,
				A00000000000000000000007 /* gen.foo in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		B00000000000000000000001 /* PBXBuildRule */ = {
			isa = PBXBuildRule;
			compilerSpec = com.apple.compilers.proxy.script;
			filePatterns = "*.foo";
			fileType = pattern.proxy;
			inputFiles = (
				"$(SRCROOT)/rule-input.txt",
			);
			isEditable = 1;
			name = "Foo files";
			outputFiles = (
				"$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).swift",
			);
			runOncePerArchitecture = 0;
			script = "cp \\"$INPUT_FILE_PATH\\" \\"$SCRIPT_OUTPUT_FILE_0\\"\\n";
		};
		B00000000000000000000002 /* Script */ = {
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = Script;
			outputFileListPaths = (
			);
			outputPaths = (
				"$(DERIVED_FILE_DIR)/stamp",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "touch \\"$DERIVED_FILE_DIR/stamp\\"\\n";
		};
		B00000000000000000000003 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = F00000000000000000000006 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = C00000000000000000000001;
			remoteInfo = App;
		};
		B00000000000000000000004 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = C00000000000000000000001 /* App */;
			targetProxy = B00000000000000000000003 /* PBXContainerItemProxy */;
		};
		C00000000000000000000002 /* Agg */ = {
			isa = PBXAggregateTarget;
			buildConfigurationList = F000000000000000000000AL;
			buildPhases = (
				B00000000000000000000002 /* Script */,
			);
			dependencies = (
				B00000000000000000000004 /* PBXTargetDependency */,
			);
			name = Agg;
			productName = Agg;
		};
		C00000000000000000000003 /* Legacy */ = {
			isa = PBXLegacyTarget;
			buildArgumentsString = "$(ACTION) VERBOSE=1";
			buildConfigurationList = F000000000000000000000LL;
			buildPhases = (
			);
			buildToolPath = /usr/bin/make;
			buildWorkingDirectory = "$(SRCROOT)/tool";
			dependencies = (
			);
			name = Legacy;
			passBuildSettingsInEnvironment = 1;
			productName = Legacy;
		};
""" + app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra="\t\t\tbuildRules = (\n\t\t\t\tB00000000000000000000001 /* PBXBuildRule */,\n\t\t\t);\n") \
      + configurations("F000000000000000000000AL", "F000000000000000000000AD", "F000000000000000000000AR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'}) \
      + configurations("F000000000000000000000LL", "F000000000000000000000LD", "F000000000000000000000LR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'})
    return {
        "P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002",
                                               ["C00000000000000000000001 /* App */", "C00000000000000000000002 /* Agg */", "C00000000000000000000003 /* Legacy */"], objects),
        "App.swift": "@main struct App { static func main() {} }\n",
        "gen.foo": "let generated = 1\n",
        "rule-input.txt": "input\n",
        "tool/Makefile": "all:\n\t@true\n",
    }


def settings():
    objects = """		A00000000000000000000003 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; };
		A00000000000000000000004 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000004 /* App.swift */,
			);
			sourceTree = "<group>";
		};
		F00000000000000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000003 /* App.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
""" + app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], {
                     **APP_SETTINGS,
                     "OTHER_SWIFT_FLAGS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"-D",\n\t\t\t\t\t"FLAG WITH SPACE",\n\t\t\t\t\t"-Xfrontend",\n\t\t\t\t\t"quote\\"inside",\n\t\t\t\t\t"back\\\\slash",\n\t\t\t\t)',
                     "OTHER_LDFLAGS": '"-framework Foo -weak_framework \\"Bar Baz\\""',
                     "HEADER_SEARCH_PATHS": '(\n\t\t\t\t\t"$(SRCROOT)/with space",\n\t\t\t\t\t"$(SRCROOT)/plain",\n\t\t\t\t)',
                     "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"NAME=\\"a b\\"",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
                 })
    return {
        "P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects),
        "App.swift": "@main struct App { static func main() {} }\n",
    }


def simple_project(app_name, extra_objects="", extra_target="", group_children="", project_references=""):
    objects = f"""		A00000000000000000000003 /* App.swift in Sources */ = {{isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; }};
		A00000000000000000000004 /* App.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; }};
		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
				A00000000000000000000004 /* App.swift */,
{group_children}			);
			sourceTree = "<group>";
		}};
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000003 /* App.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
{extra_objects}""" + app_target("C00000000000000000000001", app_name, ["F00000000000000000000004 /* Sources */"],
                               ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS, extra=extra_target)
    return project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects,
                   project_references=project_references)


def workspace_contents(paths):
    """A workspace's contents.xcworkspacedata, listing the projects at `paths` in that order."""
    refs = "".join(f'   <FileRef\n      location = "group:{path}">\n   </FileRef>\n' for path in paths)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n{refs}</Workspace>\n'


def workspace():
    # Third project: its App depends on the App target of One/P.xcodeproj through a project reference.
    reference_objects = """		B00000000000000000000001 /* P.xcodeproj */ = {isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; name = P.xcodeproj; path = ../One/P.xcodeproj; sourceTree = "<group>"; };
		B00000000000000000000002 /* Products */ = {
			isa = PBXGroup;
			children = (
				B00000000000000000000003 /* App.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		B00000000000000000000003 /* App.app */ = {
			isa = PBXReferenceProxy;
			fileType = wrapper.application;
			path = App.app;
			remoteRef = B00000000000000000000004 /* PBXContainerItemProxy */;
			sourceTree = BUILT_PRODUCTS_DIR;
		};
		B00000000000000000000004 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = B00000000000000000000001 /* P.xcodeproj */;
			proxyType = 2;
			remoteGlobalIDString = F00000000000000000000001;
			remoteInfo = App;
		};
		B00000000000000000000005 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = B00000000000000000000001 /* P.xcodeproj */;
			proxyType = 1;
			remoteGlobalIDString = C00000000000000000000001;
			remoteInfo = App;
		};
		B00000000000000000000006 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			name = App;
			targetProxy = B00000000000000000000005 /* PBXContainerItemProxy */;
		};
"""
    references = """			projectReferences = (
				{
					ProductGroup = B00000000000000000000002 /* Products */;
					ProjectRef = B00000000000000000000001 /* P.xcodeproj */;
				},
			);
"""
    return {
        "W.xcworkspace/contents.xcworkspacedata": workspace_contents(["One/P.xcodeproj", "Two/P.xcodeproj", "Three/Q.xcodeproj"]),
        "One/P.xcodeproj/project.pbxproj": simple_project("App"),
        "One/App.swift": "@main struct App { static func main() {} }\n",
        "Two/P.xcodeproj/project.pbxproj": simple_project("Other"),
        "Two/App.swift": "@main struct App { static func main() {} }\n",
        "Three/Q.xcodeproj/project.pbxproj": simple_project(
            "Client", extra_objects=reference_objects,
            extra_target="\t\t\tdependencies = (\n\t\t\t\tB00000000000000000000006 /* PBXTargetDependency */,\n\t\t\t);\n",
            group_children="\t\t\t\tB00000000000000000000001 /* P.xcodeproj */,\n", project_references=references),
        "Three/App.swift": "@main struct App { static func main() {} }\n",
    }


def workspace_order():
    # Workspace order, path order and project-GUID order all differ for these four projects.
    paths = ["Kit/M.xcodeproj", "Apps/A.xcodeproj", "Core/A.xcodeproj", "Zeta/M.xcodeproj"]
    files = {"W.xcworkspace/contents.xcworkspacedata": workspace_contents(paths)}
    for index, path in enumerate(paths):
        folder = path.split("/")[0]
        files[f"{path}/project.pbxproj"] = simple_project(f"T{index}")
        files[f"{folder}/App.swift"] = "@main struct App { static func main() {} }\n"
    return files


# Every printable ASCII punctuation character, spaces at either end, a tab and non-ASCII letters.
TARGET_NAMES = [
    "Plain", "With Space", "Dash-Name", "Dot.Name", "Under_Score", "Plus+Name", "At@Name", "Comma,Name",
    "Colon:Name", "Semi;Name", "Quote'Name", 'Double"Name', "Dollar$Name", "Paren(Name)", "Bracket[Name]",
    "Brace{Name}", "Star*Name", "Question?Name", "Bang!Name", "Hash#Name", "Percent%Name", "Amp&Name",
    "Pipe|Name", "Back\\Name", "Tilde~Name", "Equals=Name", "Angle<Name>", "Caret^Name", "Grave`Name",
    "Slash/Name", "Ünïcödé", "Trailing ", " Leading", "Tab\tName",
]


def target_names():
    objects = """		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
			);
			sourceTree = "<group>";
		};
"""
    ids = []
    for index, name in enumerate(TARGET_NAMES, 1):
        target_id = f"C{index:023d}"
        ids.append(target_id)
        objects += app_target(target_id, name, [], [f"L{index:023d}", f"D{index:023d}", f"R{index:023d}"], APP_SETTINGS)
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ids, objects)}


def observe_target_names(run):
    run("alltargets", "-showBuildSettings", "-alltargets")
    for index, name in enumerate(TARGET_NAMES, 1):
        run(f"target-{index:02d}", "-showBuildSettings", "-target", name)


def scheme_buildable(blueprint, buildable_name, blueprint_name, container):
    """A BuildableReference; without BlueprintName when `blueprint_name` is None."""
    name = f'               BlueprintName = "{blueprint_name}"\n' if blueprint_name is not None else ""
    return ("            <BuildableReference\n"
            '               BuildableIdentifier = "primary"\n'
            f'               BlueprintIdentifier = "{blueprint}"\n'
            f'               BuildableName = "{buildable_name}"\n'
            f"{name}"
            f'               ReferencedContainer = "{container}">\n'
            "            </BuildableReference>\n")


def runnable_text(runnable):
    """A launch or profile runnable: (kind, buildable) with kind `product`, `remote` (with a macro
    expansion of the buildable) or `path` (no buildable)."""
    if runnable is None:
        return ""
    kind, buildable = runnable

    def indent(text):
        return "".join("   " + line + "\n" for line in text.splitlines())

    if kind == "product":
        return '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n' + indent(scheme_buildable(*buildable)) + "      </BuildableProductRunnable>\n"
    if kind == "remote":
        return ('      <RemoteRunnable\n         runnableDebuggingMode = "1"\n         BundleIdentifier = "org.nomac.experiment"\n'
                '         RemotePath = "/private/var/containers/Bundle/Application/App.app">\n      </RemoteRunnable>\n'
                "      <MacroExpansion>\n" + indent(scheme_buildable(*buildable)) + "      </MacroExpansion>\n")
    return '      <PathRunnable\n         runnableDebuggingMode = "0"\n         FilePath = "/Applications/Safari.app">\n      </PathRunnable>\n'


def scheme_file(build=(), testables=(), launch=None, profile=None, ask_for_app=False, coverage=False, plans=(), skipped=False,
                coverage_targets=(), only_specified=False, version="1.7", autocreate_plan=False):
    """A shared scheme. `build` holds (blueprint, buildable name, blueprint name, container,
    built for running), or (test plan container path, built for running) for an entry that builds
    a test plan; `testables` (blueprint, buildable name, blueprint name, container),
    skipped when `skipped`; `launch` and `profile` are runnables (`runnable_text`); `coverage`
    sets codeCoverageEnabled, `only_specified` onlyGenerateCoverageForSpecifiedTargets for the
    buildables `coverage_targets`; `plans` holds (container path, default) test plan references;
    `version` is the scheme format version; `autocreate_plan` sets shouldAutocreateTestPlan."""
    entries = ""
    for item in build:
        if len(item) == 2:
            path, running = item
            flag = "YES" if running else "NO"
            entries += ("         <BuildActionEntry\n"
                        '            buildForTesting = "YES"\n'
                        f'            buildForRunning = "{flag}"\n'
                        f'            buildForProfiling = "{flag}"\n'
                        f'            buildForArchiving = "{flag}"\n'
                        f'            buildForAnalyzing = "{flag}">\n'
                        f'            <TestPlanReference\n               reference = "{path}">\n            </TestPlanReference>\n'
                        "         </BuildActionEntry>\n")
            continue
        blueprint, buildable_name, blueprint_name, container, running = item
        flag = "YES" if running else "NO"
        entries += ("         <BuildActionEntry\n"
                    '            buildForTesting = "YES"\n'
                    f'            buildForRunning = "{flag}"\n'
                    f'            buildForProfiling = "{flag}"\n'
                    f'            buildForArchiving = "{flag}"\n'
                    '            buildForAnalyzing = "YES">\n'
                    + scheme_buildable(blueprint, buildable_name, blueprint_name, container)
                    + "         </BuildActionEntry>\n")
    build_entries = f"      <BuildActionEntries>\n{entries}      </BuildActionEntries>\n" if entries else ""
    flag = "YES" if skipped else "NO"
    tests = "".join(f'         <TestableReference\n            skipped = "{flag}">\n' + scheme_buildable(*testable) + "         </TestableReference>\n"
                    for testable in testables)
    test_list = f"      <Testables>\n{tests}      </Testables>\n" if tests else ""
    plan_list = "".join(f'         <TestPlanReference\n            reference = "{path}"{chr(10) + "            default = " + chr(34) + "YES" + chr(34) if default else ""}>\n'
                        "         </TestPlanReference>\n" for path, default in plans)
    test_list = (f"      <TestPlans>\n{plan_list}      </TestPlans>\n" if plan_list else "") + test_list
    targets_list = "".join(scheme_buildable(*target) for target in coverage_targets)
    test_list = (f"      <CodeCoverageTargets>\n{targets_list}      </CodeCoverageTargets>\n" if targets_list else "") + test_list
    coverage_line = ('\n      codeCoverageEnabled = "YES"' if coverage else "") + ('\n      onlyGenerateCoverageForSpecifiedTargets = "YES"' if only_specified else "") \
        + ('\n      shouldAutocreateTestPlan = "YES"' if autocreate_plan else "")
    ask = '\n      askForAppToLaunch = "Yes"\n      launchAutomaticallySubstyle = "2"' if ask_for_app else ""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "{version}">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
{build_entries}   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"{coverage_line}>
{test_list}   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES"{ask}>
{runnable_text(launch)}   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
{runnable_text(profile)}   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def package_files(directory, name, products, targets, schemes=None):
    """A package at `directory`: `targets` maps each target name to its kind (library, executable,
    test) and dependencies; every target gets one source file."""
    declarations = []
    files = {}
    for target, (kind, dependencies) in targets.items():
        function = {"library": "target", "executable": "executableTarget", "test": "testTarget"}[kind]
        dependency_list = f", dependencies: [{', '.join(chr(34) + d + chr(34) for d in dependencies)}]" if dependencies else ""
        declarations.append(f'.{function}(name: "{target}"{dependency_list})')
        folder = "Tests" if kind == "test" else "Sources"
        source = {"library": f"public let {target.lower()} = 1\n", "executable": f'print("{target}")\n',
                  "test": f"import Testing\n\n@Test func {target.lower()}() {{}}\n"}[kind]
        files[f"{directory}/{folder}/{target}/{'main' if kind == 'executable' else target}.swift"] = source
    files[f"{directory}/Package.swift"] = (
        "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n"
        f'    name: "{name}",\n    platforms: [.iOS(.v17), .macOS(.v14)],\n'
        f"    products: [{', '.join(products)}],\n    targets: [{', '.join(declarations)}]\n)\n")
    for scheme, text in (schemes or {}).items():
        files[f"{directory}/.swiftpm/xcode/xcshareddata/xcschemes/{scheme}.xcscheme"] = text
    return files


def schemes():
    files = {}
    # Root packages (folders in the file tree): Kit has no shared schemes; Lib shares a scheme
    # for its library whose test action leaves LibTests out; Solo shares a test-only scheme and
    # schemes naming targets it does not have.
    files.update(package_files("Kit", "Kit", [
        '.library(name: "Kit", targets: ["Kit"])', '.library(name: "KitExtras", targets: ["KitExtras"])',
        '.executable(name: "kit-cli", targets: ["KitCLI"])',
    ], {
        "Kit": ("library", []), "KitExtras": ("library", ["Kit"]), "KitCLI": ("executable", ["Kit"]),
        "KitInternal": ("library", []), "KitTests": ("test", ["Kit"]), "KitExtrasTests": ("test", ["KitExtras"]),
        "LooseTests": ("test", ["KitInternal"]),
    }))
    files.update(package_files("Lib", "Lib", ['.library(name: "Lib", targets: ["Lib"])'],
                               {"Lib": ("library", []), "LibTests": ("test", ["Lib"])},
                               {"Lib": scheme_file(build=[("Lib", "Lib", "Lib", "container:", True)])}))
    files.update(package_files("Solo", "Solo", ['.library(name: "Solo", targets: ["Solo"])'],
                               {"Solo": ("library", []), "SoloTests": ("test", ["Solo"])}, {
                                   "SoloTests": scheme_file(testables=[("SoloTests", "SoloTests", "SoloTests", "container:")]),
                                   "Ghost": scheme_file(testables=[("Ghost", "Ghost", "Ghost", "container:")]),
                                   "Broken": scheme_file(build=[("Nope", "Nope", "Nope", "container:", True)]),
                               }))
    # A local dependency (XCLocalSwiftPackageReference) with a shared scheme.
    files.update(package_files("Deps/Dep", "Dep", ['.library(name: "Dep", targets: ["Dep"])'],
                               {"Dep": ("library", []), "DepTests": ("test", ["Dep"])},
                               {"DepShared": scheme_file(build=[("Dep", "Dep", "Dep", "container:", True)])}))
    app, tests, mac = "C00000000000000000000001", "C00000000000000000000002", "C00000000000000000000003"
    project_container = "container:P.xcodeproj"
    files.update({
        "P.xcodeproj/xcshareddata/xcschemes/AppTestsOnly.xcscheme": scheme_file(testables=[(tests, "AppTests.xctest", "AppTests", project_container)]),
        "P.xcodeproj/xcshareddata/xcschemes/GhostApp.xcscheme": scheme_file(build=[("C00000000000000000000099", "Ghost.app", "Ghost", project_container, True)]),
        "P.xcodeproj/xcshareddata/xcschemes/TestingOnly.xcscheme": scheme_file(build=[(app, "App.app", "App", project_container, False)]),
        "P.xcodeproj/xcshareddata/xcschemes/Both.xcscheme": scheme_file(build=[(app, "App.app", "App", project_container, True),
                                                                               (mac, "MacTool.app", "MacTool", project_container, True)]),
        "P.xcodeproj/xcshareddata/xcschemes/AppAndKit.xcscheme": scheme_file(build=[(app, "App.app", "App", project_container, True),
                                                                                    ("Kit", "Kit", "Kit", "container:Kit", True)]),
        "App.swift": "@main struct App { static func main() {} }\n",
    })
    objects = """		A00000000000000000000003 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; };
		A00000000000000000000004 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
		A00000000000000000000005 /* Kit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Kit; sourceTree = "<group>"; };
		A00000000000000000000006 /* Lib */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Lib; sourceTree = "<group>"; };
		A00000000000000000000007 /* Solo */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Solo; sourceTree = "<group>"; };
		A00000000000000000000008 /* Dep in Frameworks */ = {isa = PBXBuildFile; productRef = E00000000000000000000001 /* Dep */; };
		D00000000000000000000001 /* XCLocalSwiftPackageReference "Deps/Dep" */ = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Dep; };
		E00000000000000000000001 /* Dep */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = Dep; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000004 /* App.swift */,
				A00000000000000000000005 /* Kit */,
				A00000000000000000000006 /* Lib */,
				A00000000000000000000007 /* Solo */,
				P00000000000000000000001,
				P00000000000000000000002,
				P00000000000000000000003,
			);
			sourceTree = "<group>";
		};
		F00000000000000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000003 /* App.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		F00000000000000000000005 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000008 /* Dep in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
""" + product_file("P00000000000000000000001", "App", APPLICATION) + product_file("P00000000000000000000002", "AppTests", UNIT_TEST) \
      + product_file("P00000000000000000000003", "MacTool", APPLICATION) \
      + app_target(app, "App", ["F00000000000000000000004 /* Sources */", "F00000000000000000000005 /* Frameworks */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra="\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* Dep */,\n\t\t\t);\n",
                 product_reference="P00000000000000000000001") \
      + app_target(tests, "AppTests", [], ["F000000000000000000000UL", "F000000000000000000000UD", "F000000000000000000000UR"],
                   {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.tests", "PRODUCT_NAME": '"$(TARGET_NAME)"'},
                   product_type="com.apple.product-type.bundle.unit-test", product_reference="P00000000000000000000002") \
      + app_target(mac, "MacTool", [], ["F000000000000000000000ML", "F000000000000000000000MD", "F000000000000000000000MR"],
                   {**APP_SETTINGS, "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0"}, product_reference="P00000000000000000000003")
    attributes = f"\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{tests} = {{\n\t\t\t\t\t\tTestTargetID = {app};\n\t\t\t\t\t}};\n\t\t\t\t}};\n"
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001 /* XCLocalSwiftPackageReference \"Deps/Dep\" */,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", [app, tests, mac], objects,
                                                   package_references=references, attributes=attributes)
    return files


def local_packages():
    # swiftfin's local packages (XCLocalSwiftPackageReference), with no shared schemes, have
    # schemes in -list; `schemes`' Dep had one only because a shared scheme builds its product.
    files = {}
    files.update(package_files("Deps/Plain", "Plain", ['.library(name: "Plain", targets: ["Plain"])'],
                               {"Plain": ("library", []), "PlainTests": ("test", ["Plain"])}))
    files.update(package_files("Deps/Multi", "Multi", ['.library(name: "MultiA", targets: ["MultiA"])', '.library(name: "MultiB", targets: ["MultiB"])',
                                                       '.executable(name: "multi-tool", targets: ["MultiTool"])'],
                               {"MultiA": ("library", []), "MultiB": ("library", []), "MultiTool": ("executable", []),
                                "MultiInternal": ("library", []), "MultiATests": ("test", ["MultiA"])}))
    files.update(package_files("Deps/Unused", "Unused", ['.library(name: "Unused", targets: ["Unused"])'], {"Unused": ("library", [])}))
    # Inner is a path dependency of Plain only, which the project does not reference.
    files.update(package_files("Deps/Inner", "Inner", ['.library(name: "Inner", targets: ["Inner"])'], {"Inner": ("library", [])}))
    manifest = files["Deps/Plain/Package.swift"]
    manifest = manifest.replace("    targets:", '    dependencies: [.package(path: "../Inner")],\n    targets:')
    files["Deps/Plain/Package.swift"] = manifest.replace('.target(name: "Plain")', '.target(name: "Plain", dependencies: [.product(name: "Inner", package: "Inner")])')
    references = "".join(f"\t\t\t\tD0000000000000000000000{index} /* XCLocalSwiftPackageReference */,\n" for index in (1, 2, 3))
    objects = ""
    for index, path in ((1, "Deps/Plain"), (2, "Deps/Multi"), (3, "Deps/Unused")):
        objects += f'\t\tD0000000000000000000000{index} = {{isa = XCLocalSwiftPackageReference; relativePath = "{path}"; }};\n'
    objects += """		E00000000000000000000001 /* Plain */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = Plain; };
		E00000000000000000000002 /* MultiA */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000002; productName = MultiA; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
			);
			sourceTree = "<group>";
		};
"""
    objects += app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                          extra="\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* Plain */,\n\t\t\t\tE00000000000000000000002 /* MultiA */,\n\t\t\t);\n")
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references=f"\t\t\tpackageReferences = (\n{references}\t\t\t);\n")
    return files


ROOT_REFERENCES = [  # package, group-tree reference type (None: none), XCLocalSwiftPackageReference
    ("PkgWrapper", "wrapper", False), ("PkgFolder", "folder", False), ("PkgBoth", "folder", True), ("PkgBothWrapper", "wrapper", True),
    ("PkgLocal", None, True),
]


def root_package_references():
    # element-x's `Components/BuildExtensions` is a `folder` reference in its group tree and an
    # XCLocalSwiftPackageReference; Xcode lists no scheme for its test target, which tests no
    # product's target. Each package here is referenced one way, with such a test target and one
    # that tests the product's target.
    files, objects, children, references = {}, "", "", ""
    for index, (name, kind, local) in enumerate(ROOT_REFERENCES, 1):
        files.update(package_files(f"Deps/{name}", name, [f'.library(name: "{name}", targets: ["{name}"])'],
                                   {name: ("library", []), f"{name}Internal": ("library", []), f"{name}Tests": ("test", [f"{name}Internal"]),
                                    f"{name}ProductTests": ("test", [name])}))
        if kind:
            objects += f'\t\tA0000000000000000000000{index} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = Deps/{name}; sourceTree = "<group>"; }};\n'
            children += f"\t\t\t\tA0000000000000000000000{index} /* {name} */,\n"
        if local:
            objects += f'\t\tD0000000000000000000000{index} = {{isa = XCLocalSwiftPackageReference; relativePath = "Deps/{name}"; }};\n'
            references += f"\t\t\t\tD0000000000000000000000{index} /* XCLocalSwiftPackageReference */,\n"
    # PkgMulti: two products; a test target named after one that tests the other, one that tests
    # a product without its name, one named after no product.
    files.update(package_files("Deps/PkgMulti", "PkgMulti", ['.library(name: "Alpha", targets: ["Alpha"])', '.library(name: "Beta", targets: ["Beta"])'],
                               {"Alpha": ("library", []), "Beta": ("library", []), "AlphaTests": ("test", ["Beta"]), "BetaChecks": ("test", ["Beta"]),
                                "GammaTests": ("test", ["Alpha"])}))
    objects += '\t\tA00000000000000000000009 /* PkgMulti */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Deps/PkgMulti; sourceTree = "<group>"; };\n'
    children += "\t\t\t\tA00000000000000000000009 /* PkgMulti */,\n"
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}			);
			sourceTree = "<group>";
		}};
"""
    objects += app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS)
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references=f"\t\t\tpackageReferences = (\n{references}\t\t\t);\n")
    return files


def scheme_package_clashes():
    # wordpress's shared `WordPressKit` scheme builds a target its project no longer has, and a
    # local package has a `WordPressKit` product: -list names it twice. Shared project schemes
    # named after local packages' products: one building a missing target (Stale), one building
    # the app (Other), one building the product (Built).
    files = {}
    references, objects = "", ""
    for index, name in enumerate(("Stale", "Other", "Built"), 1):
        files.update(package_files(f"Deps/{name}", name, [f'.library(name: "{name}", targets: ["{name}"])'], {name: ("library", [])}))
        objects += f'\t\tD0000000000000000000000{index} = {{isa = XCLocalSwiftPackageReference; relativePath = "Deps/{name}"; }};\n'
        references += f"\t\t\t\tD0000000000000000000000{index} /* XCLocalSwiftPackageReference */,\n"
    shared = "P.xcodeproj/xcshareddata/xcschemes"
    files[f"{shared}/Stale.xcscheme"] = scheme_file(build=[("C99999999999999999999999", "Gone.app", "Gone", "container:P.xcodeproj", True)])
    files[f"{shared}/Other.xcscheme"] = scheme_file(build=[("C00000000000000000000001", "App.app", "App", "container:P.xcodeproj", True)])
    files[f"{shared}/Built.xcscheme"] = scheme_file(build=[("Built", "Built", "Built", "container:Deps/Built", True)])
    objects += """		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
			);
			sourceTree = "<group>";
		};
"""
    objects += app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS)
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references=f"\t\t\tpackageReferences = (\n{references}\t\t\t);\n")
    return files


def macro_package(directory, name):
    """A package with a library that uses a macro, and an executable."""
    return {
        f"{directory}/Package.swift": (
            "// swift-tools-version: 6.0\nimport CompilerPluginSupport\nimport PackageDescription\n\nlet package = Package(\n"
            f'    name: "{name}",\n    platforms: [.iOS(.v17), .macOS(.v14)],\n'
            f'    products: [.library(name: "{name}Kit", targets: ["{name}Kit"]), .executable(name: "{name.lower()}-tool", targets: ["{name}Tool"])],\n'
            f'    targets: [.macro(name: "{name}Macros"), .target(name: "{name}Kit", dependencies: ["{name}Macros"]), .executableTarget(name: "{name}Tool")]\n)\n'),
        f"{directory}/Sources/{name}Macros/Plugin.swift": "struct Plugin {}\n",
        f"{directory}/Sources/{name}Kit/{name}Kit.swift": f"public let {name.lower()}Kit = 1\n",
        f"{directory}/Sources/{name}Tool/main.swift": f'print("{name}")\n',
    }


def macros():
    # swiftfin's PIF has approvedByUser false for the macro targets of its remote packages and
    # true for its local macro package's.
    files = {**macro_package("Remote", "Remote"), **macro_package("Deps/Local", "Local"), **macro_package("Root", "Root")}
    objects = """		A00000000000000000000001 /* Root */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Root; sourceTree = "<group>"; };
		D00000000000000000000001 /* XCRemoteSwiftPackageReference "Remote" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "file://@EXPERIMENT@/Remote";
			requirement = {
				kind = exactVersion;
				version = 1.0.0;
			};
		};
		D00000000000000000000002 /* XCLocalSwiftPackageReference "Deps/Local" */ = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Local; };
		E00000000000000000000001 /* RemoteKit */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = RemoteKit; };
		E00000000000000000000002 /* LocalKit */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000002; productName = LocalKit; };
		E00000000000000000000003 /* RootKit */ = {isa = XCSwiftPackageProductDependency; productName = RootKit; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000001 /* Root */,
				P00000000000000000000001,
			);
			sourceTree = "<group>";
		};
""" + product_file("P00000000000000000000001", "App", APPLICATION) \
      + app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                   extra="\t\t\tpackageProductDependencies = (\n" + "".join(f"\t\t\t\tE0000000000000000000000{index},\n" for index in (1, 2, 3)) + "\t\t\t);\n",
                   product_reference="P00000000000000000000001")
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t\tD00000000000000000000002,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references=references)
    return files


def unlinked_products():
    files = {**macro_package("Deps/Local", "Local"), **macro_package("Deps/Other", "Other"), **macro_package("Root", "Root")}
    packages = {"LocalKit": "D00000000000000000000001", "OtherKit": "D00000000000000000000002", "RootKit": None}
    # name: ([(phase isa, the products its build files name)], packageProductDependencies)
    frameworks, embed = "PBXFrameworksBuildPhase", "PBXCopyFilesBuildPhase; dstPath = \"\"; dstSubfolderSpec = 10"
    targets = {
        "App1": ([(frameworks, ["LocalKit"])], ["LocalKit", "RootKit"]),
        "App2": ([("PBXSourcesBuildPhase", [])], ["RootKit"]),
        "App3": ([(frameworks, [])], ["LocalKit"]),
        "App4": ([(frameworks, ["OtherKit"])], ["LocalKit", "OtherKit", "RootKit"]),
        "App5": ([(frameworks, ["OtherKit", "LocalKit"])], ["OtherKit", "LocalKit", "RootKit"]),
        "App6": ([(frameworks, ["OtherKit", "LocalKit"])], ["RootKit", "OtherKit", "LocalKit"]),
        "App7": ([(frameworks, ["OtherKit"])], ["RootKit", "OtherKit", "LocalKit"]),
        # A product an embed phase copies but no phase links, and two Frameworks phases.
        "App8": ([(frameworks, []), (embed, ["LocalKit"])], ["LocalKit"]),
        "App9": ([(frameworks, ["OtherKit"]), (frameworks, [])], ["OtherKit", "LocalKit"]),
    }
    objects = """		A00000000000000000000001 /* Root */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Root; sourceTree = "<group>"; };
		D00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Local; };
		D00000000000000000000002 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Other; };
"""
    ids, products = [], ""
    for index, (name, (phases, dependencies)) in enumerate(targets.items(), 1):
        target = f"C{index:023d}"
        ids.append(target)
        dependency_ids = {product: f"E{index:021d}{position:02d}" for position, product in enumerate(dependencies)}
        for product, dependency in dependency_ids.items():
            package = f" package = {packages[product]};" if packages[product] else ""
            objects += f"\t\t{dependency} = {{isa = XCSwiftPackageProductDependency;{package} productName = {product}; }};\n"
        phase_ids = []
        for phase_index, (phase, linked) in enumerate(phases):
            build_files = []
            for product in linked:
                build_file = f"B{index:020d}{phase_index}{dependencies.index(product):02d}"
                objects += f"\t\t{build_file} = {{isa = PBXBuildFile; productRef = {dependency_ids[product]}; }};\n"
                build_files.append(build_file)
            phase_ids.append(f"F{index:020d}PH{phase_index}")
            objects += f"\t\t{phase_ids[-1]} = {{isa = {phase}; buildActionMask = 2147483647; files = ({''.join(f + ',' for f in build_files)}); runOnlyForDeploymentPostprocessing = 0; }};\n"
        products += f"\t\t\t\tP{index:023d},\n"
        objects += product_file(f"P{index:023d}", name, APPLICATION) + app_target(
            target, name, phase_ids, [f"F{index:021d}TL", f"F{index:021d}TD", f"F{index:021d}TR"],
            {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.app{index}"},
            extra="\t\t\tpackageProductDependencies = (\n" + "".join(f"\t\t\t\t{dependency},\n" for dependency in dependency_ids.values()) + "\t\t\t);\n",
            product_reference=f"P{index:023d}")
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
				A00000000000000000000001 /* Root */,
{products}			);
			sourceTree = "<group>";
		}};
"""
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t\tD00000000000000000000002,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ids, objects, package_references=references)
    return files


def publish_remote(directory, container="P.xcodeproj"):
    """Makes `Remote` a git repository tagged 1.0.0 and points the reference of the project
    `container` at it."""
    git = ["git", "-c", "user.name=nomac", "-c", "user.email=nomac@example.invalid", "-c", "init.defaultBranch=main"]
    for arguments in (["init", "-q"], ["add", "."], ["commit", "-q", "-m", "1.0.0"], ["tag", "1.0.0"]):
        subprocess.run(git + arguments, cwd=directory / "Remote", check=True)
    project_file = directory / container / "project.pbxproj"
    project_file.write_text(project_file.read_text().replace("@EXPERIMENT@", str(directory)))


WORKSPACE_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
	{value}
</dict>
</plist>
"""

PROJECT_SETTINGS = "P.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings"


def user_settings(container):
    return f"{container}/xcuserdata/{getpass.getuser()}.xcuserdatad/WorkspaceSettings.xcsettings"


def autocreate_contexts(settings=(), workspace=False):
    # kickstarter's project.xcworkspace sets IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded
    # to false; -list shows none of the schemes Xcode autocreates for its local packages. One
    # project: an app, a framework and a test bundle no shared scheme covers, an app a shared
    # scheme launches, a root package (Kit), a local dependency without shared schemes (Plain)
    # and one with a shared scheme (Dep). `settings` holds (path, plist value) for each
    # WorkspaceSettings.xcsettings; with `workspace` the project is opened through W.xcworkspace.
    files = {}
    files.update(package_files("Kit", "Kit", ['.library(name: "Kit", targets: ["Kit"])', '.executable(name: "kit-cli", targets: ["KitCLI"])'],
                               {"Kit": ("library", []), "KitCLI": ("executable", ["Kit"]), "KitTests": ("test", ["Kit"]),
                                "LooseKitTests": ("test", [])}))
    files.update(package_files("Deps/Plain", "Plain", ['.library(name: "Plain", targets: ["Plain"])'],
                               {"Plain": ("library", []), "PlainTests": ("test", ["Plain"])}))
    files.update(package_files("Deps/Dep", "Dep", ['.library(name: "Dep", targets: ["Dep"])'], {"Dep": ("library", [])},
                               {"DepShared": scheme_file(build=[("Dep", "Dep", "Dep", "container:", True)])}))
    app, framework, tests, hosted = (f"C{index:023d}" for index in (1, 2, 3, 4))
    container = "container:P.xcodeproj"
    files["P.xcodeproj/xcshareddata/xcschemes/Hosted.xcscheme"] = scheme_file(
        build=[(hosted, "Hosted.app", "Hosted", container, True)], launch=("product", (hosted, "Hosted.app", "Hosted", container)))
    objects = """		A00000000000000000000005 /* Kit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Kit; sourceTree = "<group>"; };
		D00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Plain; };
		D00000000000000000000002 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Dep; };
		E00000000000000000000001 /* Plain */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = Plain; };
		E00000000000000000000002 /* Dep */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000002; productName = Dep; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000005 /* Kit */,
				P00000000000000000000001,
				P00000000000000000000002,
				P00000000000000000000003,
				P00000000000000000000004,
			);
			sourceTree = "<group>";
		};
"""
    objects += (product_file("P00000000000000000000001", "App", APPLICATION) + product_file("P00000000000000000000002", "Fw", "com.apple.product-type.framework")
                + product_file("P00000000000000000000003", "LooseTests", UNIT_TEST) + product_file("P00000000000000000000004", "Hosted", APPLICATION))
    products = "\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* Plain */,\n\t\t\t\tE00000000000000000000002 /* Dep */,\n\t\t\t);\n"
    for target, name, product_type, letter, extra in [(app, "App", APPLICATION, "T", products), (framework, "Fw", "com.apple.product-type.framework", "U", ""),
                                                      (tests, "LooseTests", UNIT_TEST, "V", ""), (hosted, "Hosted", APPLICATION, "W", "")]:
        objects += app_target(target, name, [], [f"F000000000000000000000{letter}L", f"F000000000000000000000{letter}D", f"F000000000000000000000{letter}R"],
                              {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.{name.lower()}"}, extra=extra,
                              product_type=product_type, product_reference=f"P0000000000000000000000{int(target[-1])}")
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t\tD00000000000000000000002,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", [app, framework, tests, hosted], objects,
                                                   package_references=references)
    if workspace:
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj"])
    for path, value in settings:
        files[path] = WORKSPACE_SETTINGS.format(value=value)
    return files


AUTOCREATE_CONTEXT_SCHEMES = ["App", "Fw", "LooseTests", "Hosted", "DepShared", "Kit", "kit-cli", "KitTests", "LooseKitTests", "Plain", "PlainTests", "Dep"]


def observe_autocreate_contexts(run):
    run("list", "-list", "-json")
    run("settings-target-App", "-showBuildSettings", "-target", "App")
    for name in AUTOCREATE_CONTEXT_SCHEMES:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")


XCFRAMEWORK_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array/>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
"""

KIND_SCHEMES = {"ByLibTarget": "Lib", "ByLibProduct": "LibProduct", "ByBinary": "Bin", "ByBinaryProduct": "BinProduct", "BySystem": "CSys",
                "ByPlugin": "Gen", "ByUsedPlugin": "Used", "ByOrphan": "Orphan", "ByToolTarget": "Tool", "ByToolProduct": "tool",
                "ByMissing": "Nope"}


def kinds_package(directory, prefix):
    # facebook-ios-sdk's shared scheme FBSDKCoreKit builds only FBSDKCoreKit, a binary target:
    # xcodebuild fails with 66. One package with a target of each kind and a shared scheme naming
    # each target and product (Orphan is in no product; Lib uses the Used plugin); `prefix` keeps
    # names unique when two such packages are loaded.
    p = prefix
    manifest = f"""// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{p}Kinds",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "{p}LibProduct", targets: ["{p}Lib"]),
        .library(name: "{p}BinProduct", targets: ["{p}Bin"]),
        .executable(name: "{p}tool", targets: ["{p}Tool"]),
        .executable(name: "{p}tool2", targets: ["{p}Tool2"]),
        .executable(name: "{p}tool3", targets: ["{p}Tool3"]),
        .executable(name: "{p}tool4", targets: ["{p}Tool4"]),
    ],
    targets: [
        .target(name: "{p}Lib", dependencies: ["{p}CSys"], plugins: ["{p}Used"]),
        .target(name: "{p}Orphan"),
        .binaryTarget(name: "{p}Bin", path: "{p}Bin.xcframework"),
        .systemLibrary(name: "{p}CSys", path: "Sources/{p}CSys"),
        .plugin(name: "{p}Gen", capability: .buildTool()),
        .plugin(name: "{p}Used", capability: .buildTool()),
        .executableTarget(name: "{p}Tool"),
        .executableTarget(name: "{p}Tool2"),
        .executableTarget(name: "{p}Tool3"),
        .executableTarget(name: "{p}Tool4"),
    ]
)
"""
    files = {
        f"{directory}/Package.swift": manifest,
        f"{directory}/Sources/{p}Lib/{p}Lib.swift": f"public let {p.lower()}lib = 1\n",
        f"{directory}/Sources/{p}Tool/main.swift": 'print("tool")\n',
        f"{directory}/Sources/{p}Tool2/main.swift": 'print("tool2")\n',
        f"{directory}/Sources/{p}Tool3/main.swift": 'print("tool3")\n',
        f"{directory}/Sources/{p}Tool4/main.swift": 'print("tool4")\n',
        f"{directory}/Sources/{p}Orphan/{p}Orphan.swift": f"public let {p.lower()}orphan = 1\n",
        f"{directory}/Sources/{p}CSys/module.modulemap": f'module {p}CSys [system] {{\n    header "shim.h"\n    export *\n}}\n',
        f"{directory}/Sources/{p}CSys/shim.h": "#include <stdio.h>\n",
        f"{directory}/Plugins/{p}Gen/plugin.swift": ("import PackagePlugin\n\n@main struct Gen: BuildToolPlugin {\n"
                                                     "    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] { [] }\n}\n"),
        f"{directory}/Plugins/{p}Used/plugin.swift": ("import PackagePlugin\n\n@main struct Used: BuildToolPlugin {\n"
                                                      "    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] { [] }\n}\n"),
        f"{directory}/{p}Bin.xcframework/Info.plist": XCFRAMEWORK_PLIST,
    }
    for scheme, name in KIND_SCHEMES.items():
        files[f"{directory}/.swiftpm/xcode/xcshareddata/xcschemes/{p}{scheme}.xcscheme"] = scheme_file(build=[(p + name, p + name, p + name, "container:", True)])
    # ByToolProduct builds tool for running; LaunchesTool2 launches tool2; ProfilesTool3 builds
    # tool3 for testing only and profiles it; RemoteTool4 builds tool4 for running and launches a
    # RemoteRunnable whose MacroExpansion names it.
    tool2, tool3, tool4 = ((p + name, p + name, p + name, "container:") for name in ["tool2", "tool3", "tool4"])
    files[f"{directory}/.swiftpm/xcode/xcshareddata/xcschemes/{p}LaunchesTool2.xcscheme"] = scheme_file(build=[(*tool2, True)], launch=("product", tool2))
    files[f"{directory}/.swiftpm/xcode/xcshareddata/xcschemes/{p}ProfilesTool3.xcscheme"] = scheme_file(build=[(*tool3, False)], profile=("product", tool3))
    files[f"{directory}/.swiftpm/xcode/xcshareddata/xcschemes/{p}RemoteTool4.xcscheme"] = scheme_file(build=[(*tool4, True)], launch=("remote", tool4))
    return files


def package_target_kinds():
    # A root package (folder in the file tree) and a local dependency (XCLocalSwiftPackageReference).
    files = {**kinds_package("Kinds", ""), **kinds_package("Deps/DepKinds", "Dep")}
    objects = """		A00000000000000000000005 /* Kinds */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Kinds; sourceTree = "<group>"; };
		D00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/DepKinds; };
		E00000000000000000000001 /* DepLibProduct */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = DepLibProduct; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000005 /* Kinds */,
				P00000000000000000000001,
			);
			sourceTree = "<group>";
		};
""" + product_file("P00000000000000000000001", "App", APPLICATION)
    objects += app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                          extra="\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* DepLibProduct */,\n\t\t\t);\n",
                          product_reference="P00000000000000000000001")
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references="\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t);\n")
    return files


def observe_package_target_kinds(run):
    run("list", "-list", "-json")
    for prefix in ["", "Dep"]:
        for scheme in [*KIND_SCHEMES, "LaunchesTool2", "ProfilesTool3", "RemoteTool4"]:
            run(f"scheme-{prefix}{scheme}", "-showBuildSettings", "-scheme", prefix + scheme, "-destination", "generic/platform=iOS")


def observe_schemes(run):
    run("list-text", "-list")
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)["project"]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}-iphoneos", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
    for name in ["Kit", "MacTool", "Both", "AppAndKit"]:
        run(f"scheme-{name}-macosx", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=macOS")
    run("scheme-Kit-nodestination", "-showBuildSettings", "-scheme", "Kit")
    run("test-KitExtras", "-showBuildSettings", "-scheme", "KitExtras", "test")


def autocreate():
    # netnewswire's "Subscribe to Feed" gets no autocreated scheme; it is the only target whose
    # TargetAttributes entry has no CreatedOnToolsVersion. Each target here differs in one way.
    variants = [
        ("NoEntry", None, False),
        ("EmptyEntry", {}, False),
        ("TeamOnly", {"DevelopmentTeam": "ABCDE12345", "ProvisioningStyle": "Automatic"}, False),
        ("Created", {"CreatedOnToolsVersion": "16.0"}, False),
        ("ExtCreated", {"CreatedOnToolsVersion": "16.0"}, True),
        ("ExtTeamOnly", {"DevelopmentTeam": "ABCDE12345", "ProvisioningStyle": "Automatic"}, True),
        ("ExtNoEntry", None, True),
    ]
    host = "C00000000000000000000099"
    objects = """		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
			);
			sourceTree = "<group>";
		};
"""
    ids, attributes, dependencies = [], "", ""
    for index, (name, entry, embedded) in enumerate(variants, 1):
        target_id = f"C{index:023d}"
        ids.append(target_id)
        product_type = "com.apple.product-type.app-extension" if embedded else "com.apple.product-type.application"
        objects += app_target(target_id, name, [], [f"L{index:023d}", f"D{index:023d}", f"R{index:023d}"],
                              {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.{name.lower()}"}, product_type=product_type)
        if entry is not None:
            body = "".join(f"\t\t\t\t\t\t{key} = {value};\n" for key, value in entry.items())
            attributes += f"\t\t\t\t\t{target_id} = {{\n{body}\t\t\t\t\t}};\n"
        if embedded:
            objects += f"""		P{index:023d} = {{isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; remoteGlobalIDString = {target_id}; remoteInfo = {name}; }};
		T{index:023d} = {{isa = PBXTargetDependency; target = {target_id}; targetProxy = P{index:023d}; }};
"""
            dependencies += f"\t\t\t\tT{index:023d},\n"
    objects += app_target(host, "Host", [], ["L000000000000000000000HL", "D000000000000000000000HD", "R000000000000000000000HR"],
                          {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment"},
                          extra=f"\t\t\tdependencies = (\n{dependencies}\t\t\t);\n")
    attributes += f"\t\t\t\t\t{host} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ids + [host], objects,
                                                   attributes=f"\t\t\t\tTargetAttributes = {{\n{attributes}\t\t\t\t}};\n")}


def info_plist(point, principal_class=False, extension_kit=False):
    """An Info.plist whose NSExtension (EXAppExtensionAttributes with `extension_kit`) names `point`
    (no such dictionary when None)."""
    extension = ""
    if point is not None:
        key, point_key = ("EXAppExtensionAttributes", "EXExtensionPointIdentifier") if extension_kit else ("NSExtension", "NSExtensionPointIdentifier")
        entries = f"\t\t<key>{point_key}</key>\n\t\t<string>{point}</string>\n" if point else ""
        if principal_class:
            entries += "\t\t<key>NSExtensionPrincipalClass</key>\n\t\t<string>Handler</string>\n"
        extension = f"\t<key>{key}</key>\n\t<dict>\n{entries}\t</dict>\n"
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
{extension}</dict>
</plist>
"""


SAFARI = "com.apple.Safari.extension"
SHARE = "com.apple.share-services"
# (SDK, extension point) of the app extensions `extension-points` sweeps; each target is named
# after its index so that only the Info.plist tells them apart.
EXTENSION_POINTS = [
    ("iphoneos", SHARE), ("iphoneos", SAFARI), ("iphoneos", "com.apple.Safari.web-extension"),
    ("iphoneos", "com.apple.Safari.content-blocker"), ("iphoneos", "com.apple.widgetkit-extension"),
    ("iphoneos", "com.apple.widget-extension"), ("iphoneos", "com.apple.ui-services"), ("iphoneos", "com.apple.services"),
    ("iphoneos", "com.apple.keyboard-service"), ("iphoneos", "com.apple.photo-editing"),
    ("iphoneos", "com.apple.usernotifications.service"), ("iphoneos", "com.apple.usernotifications.content-extension"),
    ("iphoneos", "com.apple.intents-service"), ("iphoneos", "com.apple.intents-ui-service"),
    ("iphoneos", "com.apple.message-payload-provider"), ("iphoneos", "com.apple.fileprovider-nonui"),
    ("iphoneos", "com.apple.authentication-services-credential-provider-ui"), ("iphoneos", "com.apple.broadcast-services-upload"),
    ("iphoneos", "com.apple.networkextension.packet-tunnel"), ("iphoneos", "com.apple.callkit.call-directory"),
    ("iphoneos", "com.apple.appintents-extension"), ("iphoneos", "com.apple.deviceactivity.monitor-extension"),
    ("iphoneos", "com.apple.background-asset-downloader-extension"), ("iphoneos", "org.nomac.unknown-point"),
    ("iphoneos", ""), ("iphoneos", None),
    ("macosx", SHARE), ("macosx", SAFARI), ("macosx", "com.apple.Safari.web-extension"),
    ("macosx", "com.apple.Safari.content-blocker"), ("macosx", "com.apple.FinderSync"), ("macosx", "com.apple.quicklook.preview"),
    ("macosx", "com.apple.widgetkit-extension"), ("macosx", "org.nomac.unknown-point"),
    ("iphoneos", "com.apple.Safari"), ("iphoneos", "com.apple.Safari.extension.other"), ("iphoneos", "com.apple.safari.extension"),
    ("iphoneos", "com.apple.Safari.web-extension.other"), ("iphoneos", "com.apple.fileprovider-actionsui"),
    ("iphoneos", "com.apple.identitylookup.message-filter"), ("iphoneos", "com.apple.classkit.context-provider"),
    ("iphoneos", "com.apple.location.push.service"), ("iphoneos", "com.apple.AudioUnit-UI"), ("iphoneos", "com.apple.watchkit"),
    ("appletvos", "com.apple.tv-top-shelf"), ("macosx", "com.apple.ctk-tokens"), ("macosx", "com.apple.AudioUnit"),
]


def extension_points():
    # netnewswire's "Subscribe to Feed" gets no autocreated scheme because its Info.plist names the
    # Safari app extension point (found by editing that one value in a copy of netnewswire). Point-NN
    # targets differ only in the point and the SDK; the others in how INFOPLIST_FILE is reached,
    # with the Safari point, and in the product type.
    main_children = "\t\t\t\tA00000000000000000000001 /* Base.xcconfig */,\n"
    objects = """		A00000000000000000000001 /* Base.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; };
"""
    files = {"Base.xcconfig": "INFOPLIST_FILE = Safari.plist\n", "Safari.plist": info_plist(SAFARI, True),
             "Share.plist": info_plist(SHARE, True), "Value.plist": info_plist("$(NOMAC_POINT)", True),
             "KitSafari.plist": info_plist(SAFARI, True, extension_kit=True)}
    extension = "com.apple.product-type.app-extension"
    targets = []  # (name, product type, Debug settings, Release settings, base xcconfig)
    for index, (sdk, point) in enumerate(EXTENSION_POINTS, 1):
        name = f"Point-{index:02d}"
        files[f"{name}/Info.plist"] = info_plist(point, True)
        targets.append((name, extension, {"SDKROOT": sdk, "INFOPLIST_FILE": pbx_string(f"{name}/Info.plist")}, None, None))
    targets += [
        ("MacroPath", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": pbx_string("$(NOMAC_PLIST).plist"), "NOMAC_PLIST": "Safari"}, None, None),
        ("DebugSafari", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Share.plist"}, None),
        ("ReleaseSafari", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Share.plist"}, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None),
        ("SDKConditional", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Share.plist", '"INFOPLIST_FILE[sdk=macosx*]"': "Safari.plist"}, None, None),
        ("FromXcconfig", extension, {"SDKROOT": "macosx"}, None, "A00000000000000000000001 /* Base.xcconfig */"),
        ("MissingPlist", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Missing.plist"}, None, None),
        ("Generated", extension, {"SDKROOT": "macosx", "GENERATE_INFOPLIST_FILE": "YES"}, None, None),
        ("GeneratedSafari", extension, {"SDKROOT": "macosx", "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("ValueMacro", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Value.plist", "NOMAC_POINT": SAFARI}, None, None),
        ("AppSafari", "com.apple.product-type.application", {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("FrameworkSafari", "com.apple.product-type.framework", {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("ExtensionKitSafari", "com.apple.product-type.extensionkit-extension", {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("XPCSafari", "com.apple.product-type.xpc-service", {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("NoProductReference", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "Safari.plist"}, None, None),
        ("ExtensionKitEXSafari", "com.apple.product-type.extensionkit-extension", {"SDKROOT": "macosx", "INFOPLIST_FILE": "KitSafari.plist"}, None, None),
        ("AppExtensionEXSafari", extension, {"SDKROOT": "macosx", "INFOPLIST_FILE": "KitSafari.plist"}, None, None),
    ]
    ids = []
    for index, (name, product_type, debug, release, base) in enumerate(targets, 1):
        target_id, reference = f"C{index:023d}", None
        ids.append(target_id)
        if name != "NoProductReference":
            reference = f"P{index:023d}"
            objects += product_file(reference, name, product_type)
            main_children += f"\t\t\t\t{reference},\n"
        common = {"PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        objects += app_target(target_id, name, [], [f"L{index:023d}", f"D{index:023d}", f"R{index:023d}"], {**common, **debug},
                              product_type=product_type, release_settings=None if release is None else {**common, **release}, base=base,
                              product_reference=reference)
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{main_children}			);
			sourceTree = "<group>";
		}};
"""
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ids, objects)
    return files


# Product types `product-types` gives three targets each (Type-NN with a product reference, Bare-NN
# without, Built-NN with one and built by the shared scheme Build-NN), with SDK; their Info.plists
# are generated.
PRODUCT_TYPES = [
    ("application", "iphoneos"), ("framework", "iphoneos"), ("library.static", "iphoneos"), ("library.dynamic", "macosx"),
    ("bundle", "iphoneos"), ("tool", "macosx"), ("application.on-demand-install-capable", "iphoneos"),
    ("app-extension", "iphoneos"), ("extensionkit-extension", "iphoneos"), ("app-extension.messages-sticker-pack", "iphoneos"),
    ("application.watchapp2-container", "iphoneos"), ("application.watchapp2", "watchos"), ("watchkit2-extension", "watchos"),
    ("xpc-service", "macosx"), ("system-extension", "macosx"), ("xcode-extension", "macosx"), ("driver-extension", "driverkit"),
    ("instruments-package", "macosx"), ("metal-library", "iphoneos"), ("bundle.unit-test", "iphoneos"),
    ("bundle.ui-testing", "iphoneos"), ("application.watchapp", "watchos"), ("watchkit-extension", "watchos"),
    ("application.messages", "iphoneos"), ("app-extension.messages", "iphoneos"), ("tv-app-extension", "appletvos"),
    ("framework.static", "iphoneos"), ("kernel-extension", "macosx"),
]


def product_types():
    objects = """		C00000000000000000000998 /* Agg */ = {
			isa = PBXAggregateTarget;
			buildConfigurationList = F000000000000000000000AL;
			buildPhases = (
			);
			dependencies = (
			);
			name = Agg;
			productName = Agg;
		};
		C00000000000000000000999 /* Legacy */ = {
			isa = PBXLegacyTarget;
			buildArgumentsString = "$(ACTION)";
			buildConfigurationList = F000000000000000000000LL;
			buildPhases = (
			);
			buildToolPath = /usr/bin/make;
			dependencies = (
			);
			name = Legacy;
			passBuildSettingsInEnvironment = 1;
			productName = Legacy;
		};
""" + configurations("F000000000000000000000AL", "F000000000000000000000AD", "F000000000000000000000AR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'}) \
      + configurations("F000000000000000000000LL", "F000000000000000000000LD", "F000000000000000000000LR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'})
    ids, children, files = [], "", {}
    for index, (product_type, sdk) in enumerate(PRODUCT_TYPES, 1):
        for offset, prefix in ((0, "Type"), (50, "Bare"), (100, "Built")):
            target_id, reference, name = f"C{index + offset:023d}", None, f"{prefix}-{index:02d}"
            ids.append(target_id)
            if prefix != "Bare":
                reference = f"P{index + offset:023d}"
                objects += product_file(reference, name, product_type)
                children += f"\t\t\t\t{reference},\n"
            if prefix == "Built":
                product = PRODUCT_FILES[product_type][1].format(name)
                files[f"P.xcodeproj/xcshareddata/xcschemes/Build-{index:02d}.xcscheme"] = scheme_file(
                    build=[(target_id, product, name, "container:P.xcodeproj", True)])
            objects += app_target(target_id, name, [], [f"L{index + offset:023d}", f"D{index + offset:023d}", f"R{index + offset:023d}"],
                                  {**APP_SETTINGS, "SDKROOT": sdk, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.type{index + offset}"},
                                  product_type=f"com.apple.product-type.{product_type}", product_reference=reference)
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}			);
			sourceTree = "<group>";
		}};
"""
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002",
                                                   ids + ["C00000000000000000000998", "C00000000000000000000999"], objects)
    return files


class Targets:
    """Native targets of one project, each with a product reference, and the objects that embed
    one target's product in another's (a copy-files phase) or make one depend on another."""

    def __init__(self):
        self.objects, self.ids, self.products, self.attributes = "", [], "", ""
        self.phases, self.dependencies, self.count = {}, {}, 0

    def next_id(self, prefix):
        self.count += 1
        return f"{prefix}{self.count:023d}"

    def add(self, name, product_type, settings, sdk="iphoneos", configuration_list=None, list_ids=None):
        """Adds a native target, or with `product_type` AGGREGATE or LEGACY an aggregate or legacy
        target, which has no product."""
        target_id, reference = self.next_id("C"), self.next_id("P")
        self.ids.append(target_id)
        if product_type not in (AGGREGATE, LEGACY):
            self.products += product_file(reference, name, product_type)
        self.phases[target_id], self.dependencies[target_id] = [], []
        common = {**APP_SETTINGS, "SDKROOT": sdk, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{len(self.ids)}"}
        values = {key: value for key, value in {**common, **settings}.items() if value is not None}
        self.pending = getattr(self, "pending", []) + [(target_id, name, product_type, values, reference, configuration_list, list_ids)]
        return target_id, reference

    def embed(self, host, product_reference, name, kit=False):
        """Copies `product_reference` into `host`'s PlugIns (or Extensions, for ExtensionKit)."""
        phase, build_file = self.next_id("B"), self.next_id("E")
        title = "Embed ExtensionKit Extensions" if kit else "Embed Foundation Extensions"
        destination = 'dstPath = "$(EXTENSIONS_FOLDER_PATH)";\n\t\t\tdstSubfolderSpec = 16;' if kit else 'dstPath = "";\n\t\t\tdstSubfolderSpec = 13;'
        self.objects += f"""		{build_file} = {{isa = PBXBuildFile; fileRef = {product_reference}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
		{phase} /* {title} */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			{destination}
			files = (
				{build_file},
			);
			name = {pbx_string(title)};
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
        self.phases[host].append(f"{phase} /* {title} */")

    def depend(self, target, on, name):
        proxy, dependency = self.next_id("X"), self.next_id("T")
        self.objects += f"""		{proxy} = {{isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; remoteGlobalIDString = {on}; remoteInfo = {pbx_string(name)}; }};
		{dependency} = {{isa = PBXTargetDependency; target = {on}; targetProxy = {proxy}; }};
"""
        self.dependencies[target].append(dependency)

    def attribute(self, target, text):
        self.attributes += f"\t\t\t\t\t{target} = {{\n{text}\t\t\t\t\t}};\n"

    def project(self, files=None, project_configurations=None, group_children="", path="P.xcodeproj", project_settings=None,
                known_regions=("en", "Base"), development_region="en", attributes=""):
        objects = self.objects
        for target_id, name, product_type, settings, reference, configuration_list, list_ids in self.pending:
            index = int(target_id[1:])
            extra = ""
            if target_id in getattr(self, "rules", {}):
                extra += f"\t\t\tbuildRules = (\n\t\t\t\t{self.rules[target_id]},\n\t\t\t);\n"
            if self.dependencies[target_id]:
                extra += "\t\t\tdependencies = (\n" + "".join(f"\t\t\t\t{d},\n" for d in self.dependencies[target_id]) + "\t\t\t);\n"
            if getattr(self, "synchronized", {}).get(target_id):
                extra += "\t\t\tfileSystemSynchronizedGroups = (\n" + "".join(f"\t\t\t\t{g},\n" for g in self.synchronized[target_id]) + "\t\t\t);\n"
            ids = list_ids or [f"L{index:023d}", f"D{index:023d}", f"R{index:023d}"]
            if product_type in (AGGREGATE, LEGACY):
                legacy = ('\t\t\tbuildArgumentsString = "$(ACTION)";\n\t\t\tbuildToolPath = /usr/bin/make;\n'
                          '\t\t\tbuildWorkingDirectory = "$(SRCROOT)";\n\t\t\tpassBuildSettingsInEnvironment = 1;\n')
                objects += (configuration_list or configurations(ids[0], ids[1], ids[2], settings)) + f"""		{target_id} = {{
			isa = {product_type};
{legacy if product_type == LEGACY else ""}			buildConfigurationList = {ids[0]};
			buildPhases = (
			);
{extra}			name = {pbx_string(name)};
			productName = {pbx_string(name)};
		}};
"""
                continue
            objects += app_target(target_id, name, self.phases[target_id], ids,
                                  settings, extra=extra, product_type=product_type, product_reference=reference,
                                  configuration_list=configuration_list)
        children = "".join(f"\t\t\t\t{line.split()[0]},\n" for line in self.products.splitlines())
        objects += self.products + f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{group_children}{children}			);
			sourceTree = "<group>";
		}};
"""
        attributes += f"\t\t\t\tTargetAttributes = {{\n{self.attributes}\t\t\t\t}};\n" if self.attributes else ""
        result = dict(files or {})
        result[f"{path}/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", self.ids, objects,
                                                    attributes=attributes, project_configurations=project_configurations,
                                                    project_settings=project_settings, known_regions=known_regions,
                                                    development_region=development_region)
        return result


APPEX = "com.apple.product-type.app-extension"
AGGREGATE = "PBXAggregateTarget"
LEGACY = "PBXLegacyTarget"


def autocreate_hosts():
    # netnewswire's autocreated "NetNewsWire iOS Widget Extension" scheme builds the extension, then
    # NetNewsWire-iOS, which embeds it and depends on it. Each extension here reaches its app in one way.
    targets = Targets()
    files = {}

    def pair(host_name, extension_name, embed=True, depend=True, kit=False, host_type=APPLICATION):
        host, _ = targets.add(host_name, host_type, {})
        extension, product = targets.add(extension_name, "com.apple.product-type.extensionkit-extension" if kit else APPEX, {})
        if embed:
            targets.embed(host, product, extension_name, kit=kit)
        if depend:
            targets.depend(host, extension, extension_name)
        return host, extension, product

    pair("HostA", "EmbedAndDepend")
    pair("HostB", "DependOnly", embed=False)
    pair("HostC", "EmbedOnly", depend=False)
    host_d1, two_hosts, two_hosts_product = pair("HostD1", "TwoHosts")
    host_d2, _ = targets.add("HostD2", APPLICATION, {})
    targets.embed(host_d2, two_hosts_product, "TwoHosts")
    targets.depend(host_d2, two_hosts, "TwoHosts")
    targets.add("Lone", APPEX, {})
    host_e, _, _ = pair("HostE", "SharedHost")
    later, later_product = targets.add("BeforeHost", APPEX, {})
    host_f, _ = targets.add("HostF", APPLICATION, {})
    targets.embed(host_f, later_product, "BeforeHost")
    targets.depend(host_f, later, "BeforeHost")
    pair("FrameworkHost", "InFramework", host_type="com.apple.product-type.framework")
    pair("HostG", "Kit", kit=True)
    # An extension embedded in an extension that HostH embeds.
    host_h, outer, outer_product = pair("HostH", "Outer")
    inner, inner_product = targets.add("Inner", APPEX, {})
    targets.embed(outer, inner_product, "Inner")
    targets.depend(outer, inner, "Inner")
    files["P.xcodeproj/xcshareddata/xcschemes/HostE.xcscheme"] = scheme_file(build=[(host_e, "HostE.app", "HostE", "container:P.xcodeproj", True)])
    # Three hosts whose project order, name order and depth differ; chains without an app; a
    # framework and other runnable types between or as hosts.
    many, _ = targets.add("ManyHosts", APPEX, {})
    for name in ["Zeta", "Alpha", "Mu"]:
        host, _ = targets.add(name, APPLICATION, {})
        targets.depend(host, many, "ManyHosts")
    lonely_inner, _ = targets.add("InnerNoApp", APPEX, {})
    lonely_outer, _ = targets.add("OuterNoApp", APPEX, {})
    targets.depend(lonely_outer, lonely_inner, "InnerNoApp")
    via, _ = targets.add("ViaFramework", APPEX, {})
    framework, _ = targets.add("Middle", "com.apple.product-type.framework", {})
    app, _ = targets.add("FrameworkUser", APPLICATION, {})
    targets.depend(framework, via, "ViaFramework")
    targets.depend(app, framework, "Middle")
    deepest, _ = targets.add("Deepest", APPEX, {})
    top, _ = targets.add("DeepApp", APPLICATION, {})
    second, _ = targets.add("Second", APPEX, {})
    first, _ = targets.add("First", APPEX, {})
    targets.depend(first, deepest, "Deepest")
    targets.depend(second, first, "First")
    targets.depend(top, second, "Second")
    targets.depend(top, deepest, "Deepest")
    clip_extension, _ = targets.add("ClipExtension", APPEX, {})
    clip, _ = targets.add("Clip", "com.apple.product-type.application.on-demand-install-capable", {})
    targets.depend(clip, clip_extension, "ClipExtension")
    tool_extension, _ = targets.add("ToolExtension", APPEX, {}, sdk="macosx")
    tool, _ = targets.add("Tool", "com.apple.product-type.tool", {}, sdk="macosx")
    targets.depend(tool, tool_extension, "ToolExtension")
    # A chain of three extensions between an extension and its app, listed out of chain order.
    chain = {name: targets.add(name, APPLICATION if name == "ChainApp" else APPEX, {})[0]
             for name in ["Link2", "ChainStart", "Link3", "ChainApp", "Link1"]}
    for dependent, dependency in [("Link1", "ChainStart"), ("Link2", "Link1"), ("Link3", "Link2"), ("ChainApp", "Link3")]:
        targets.depend(chain[dependent], chain[dependency], dependency)
    watch_extension, _ = targets.add("WatchWidget", APPEX, {}, sdk="watchos")
    watch, _ = targets.add("Watch", "com.apple.product-type.application.watchapp2", {}, sdk="watchos")
    targets.depend(watch, watch_extension, "WatchWidget")
    phone, _ = targets.add("Phone", APPLICATION, {})
    targets.depend(phone, watch, "Watch")
    # An app one hop away and another two hops away.
    mixed, _ = targets.add("Mixed", APPEX, {})
    near, _ = targets.add("NearApp", APPLICATION, {})
    middle, _ = targets.add("MixedMiddle", APPEX, {})
    far, _ = targets.add("FarApp", APPLICATION, {})
    targets.depend(near, mixed, "Mixed")
    targets.depend(middle, mixed, "Mixed")
    targets.depend(far, middle, "MixedMiddle")
    # Other product types an app depends on: which of them list the app in their scheme.
    for index, (product_type, sdk, host_type) in enumerate([
        ("app-extension.messages-sticker-pack", "iphoneos", APPLICATION), ("app-extension.messages", "iphoneos", APPLICATION),
        ("application.on-demand-install-capable", "iphoneos", APPLICATION), ("framework", "iphoneos", APPLICATION),
        ("library.static", "iphoneos", APPLICATION), ("bundle", "iphoneos", APPLICATION), ("tv-app-extension", "appletvos", APPLICATION),
        ("xpc-service", "macosx", APPLICATION), ("system-extension", "macosx", APPLICATION), ("xcode-extension", "macosx", APPLICATION),
        ("application", "iphoneos", APPLICATION), ("app-extension", "iphoneos", "com.apple.product-type.application.messages"),
    ], 1):
        dependency, _ = targets.add(f"Kind{index:02d}", f"com.apple.product-type.{product_type}", {}, sdk=sdk)
        host, _ = targets.add(f"Kind{index:02d}Host", host_type, {}, sdk=sdk)
        targets.depend(host, dependency, f"Kind{index:02d}")
    return targets.project(files)


WATCH_VARIANTS = [  # watch app, WATCHOS_DEPLOYMENT_TARGET, the extension's Info.plist declares a complication
    ("W30", "3.0", True), ("W50", "5.0", True), ("W50Plain", "5.0", False), ("W70", "7.0", True), ("W100", "10.0", True), ("WNone", None, True),
]


def watch_extension_plist(complication):
    complication_keys = ("\t<key>CLKComplicationPrincipalClass</key>\n\t<string>$(PRODUCT_MODULE_NAME).ComplicationController</string>\n"
                         if complication else "")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>\n'
            f"{complication_keys}\t<key>NSExtension</key>\n\t<dict>\n\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>com.apple.watchkit</string>\n"
            "\t</dict>\n</dict>\n</plist>\n")


# Sources of a watch extension named as Xcode's watch templates name theirs, and not: label, the
# reference's path and name, the watch deployment target.
WATCH_SOURCES = [("NotificationController", "NotificationController.swift", None, None), ("GlanceController", "GlanceController.swift", None, None),
                 ("ComplicationController", "ComplicationController.swift", None, None),
                 ("MyNotificationController", "MyNotificationController.swift", None, None),
                 ("Lowercase", "notificationcontroller.swift", None, None), ("ObjC", "NotificationController.m", None, None),
                 ("Glance3", "GlanceController.swift", None, "3.0"), ("Glance2", "GlanceController.swift", None, "2.0"),
                 ("NamedNotification", "Other.swift", "NotificationController.swift", None),
                 ("PathNotification", "NotificationController.swift", "Other.swift", None)]
WATCH_STORYBOARD_SCENES = {
    "notification": '<notificationController id="N01-aa-aaa"><notificationCategory key="notificationCategory" identifier="nomac" id="N02-aa-aaa"/></notificationController>',
    "glance": '<glanceController id="G01-aa-aaa"/>',
    "plain": "",
}


def watch_storyboard(scene):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder.WatchKit.Storyboard" version="3.0" '
            'targetRuntime="watchKit" propertyAccessControl="none" useAutolayout="YES" initialViewController="C01-aa-aaa">\n    <scenes>\n'
            '        <scene sceneID="S01-aa-aaa"><objects><controller id="C01-aa-aaa"/></objects></scene>\n'
            + (f'        <scene sceneID="S02-aa-aaa"><objects>{scene}</objects></scene>\n' if scene else "")
            + "    </scenes>\n</document>\n")


def watch_schemes():
    # octopod's watch app gets `(Complication)` and `(Notification)` schemes, the fuzzer's seed
    # 70155 `(Glance)` and `(Notification)` (BACKLOG B-091). One iOS app, watch app and watch
    # extension per variant of the watch deployment target and of the extension's Info.plist,
    # then watch apps whose Resources hold a storyboard with a notification or a glance scene.
    targets, files, children = Targets(), {}, ""
    for index, (kind, scene) in enumerate(WATCH_STORYBOARD_SCENES.items(), 1):
        name = f"WStoryboard{kind.capitalize()}"
        files[f"{name}Ext/Info.plist"] = watch_extension_plist(False)
        files[f"{name}/Interface.storyboard"] = watch_storyboard(scene)
        extension, _ = targets.add(f"{name}Ext", "com.apple.product-type.watchkit2-extension",
                                   {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string(f"{name}Ext/Info.plist")}, sdk="watchos")
        watch, _ = targets.add(name, "com.apple.product-type.application.watchapp2", {}, sdk="watchos")
        reference, build_file, phase = f"A{index:023d}", f"Z{index:023d}", f"W{index:023d}"
        targets.objects += (f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = file.storyboard; path = "{name}/Interface.storyboard"; sourceTree = "<group>"; }};\n'
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n"
                            f"\t\t{phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({build_file}, ); runOnlyForDeploymentPostprocessing = 0; }};\n")
        targets.phases[watch].append(phase)
        targets.depend(watch, extension, f"{name}Ext")
        phone, _ = targets.add(f"{name}Phone", APPLICATION, {})
        targets.depend(phone, watch, name)
    for index, (label, source, display, deployment) in enumerate(WATCH_SOURCES, 10):
        name = f"WSource{label}"
        files[f"{name}Ext/Info.plist"] = watch_extension_plist(False)
        files[f"{name}Ext/{source}"] = "import WatchKit\n"
        extension, _ = targets.add(f"{name}Ext", "com.apple.product-type.watchkit2-extension",
                                   {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string(f"{name}Ext/Info.plist"), "WATCHOS_DEPLOYMENT_TARGET": deployment},
                                   sdk="watchos")
        reference, build_file, phase, group = f"A{index:023d}", f"Z{index:023d}", f"W{index:023d}", f"V{index:023d}"
        named = f'name = "{display}"; ' if display else ""
        targets.objects += (f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; {named}path = "{source}"; sourceTree = "<group>"; }};\n'
                            f'\t\t{group} = {{isa = PBXGroup; children = ({reference}, ); path = "{name}Ext"; sourceTree = "<group>"; }};\n'
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n"
                            f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build_file}, ); runOnlyForDeploymentPostprocessing = 0; }};\n")
        targets.phases[extension].append(phase)
        watch, _ = targets.add(name, "com.apple.product-type.application.watchapp2", {"WATCHOS_DEPLOYMENT_TARGET": deployment}, sdk="watchos")
        targets.depend(watch, extension, f"{name}Ext")
        children += f"\t\t\t\t{group},\n"
    for name, deployment, complication in WATCH_VARIANTS:
        files[f"{name}Ext/Info.plist"] = watch_extension_plist(complication)
        extension_settings = {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string(f"{name}Ext/Info.plist"), "WATCHOS_DEPLOYMENT_TARGET": deployment}
        extension, _ = targets.add(f"{name}Ext", "com.apple.product-type.watchkit2-extension", extension_settings, sdk="watchos")
        watch, _ = targets.add(name, "com.apple.product-type.application.watchapp2", {"WATCHOS_DEPLOYMENT_TARGET": deployment}, sdk="watchos")
        targets.depend(watch, extension, f"{name}Ext")
        phone, _ = targets.add(f"{name}Phone", APPLICATION, {})
        targets.depend(phone, watch, name)
    return targets.project(files, group_children=children)


def watch_schemes_apns():
    # octopod's group tree holds a `PushNotificationPayload.apns` in no build phase. Two watch
    # apps, without complications, and one `.apns` file in the main group.
    targets, files = Targets(), {"Payload.apns": '{"aps": {"alert": "nomac"}}\n'}
    for name in ("WA", "WB"):
        files[f"{name}Ext/Info.plist"] = watch_extension_plist(False)
        extension, _ = targets.add(f"{name}Ext", "com.apple.product-type.watchkit2-extension",
                                   {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string(f"{name}Ext/Info.plist")}, sdk="watchos")
        watch, _ = targets.add(name, "com.apple.product-type.application.watchapp2", {}, sdk="watchos")
        targets.depend(watch, extension, f"{name}Ext")
    targets.objects += '\t\tA00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = text; path = Payload.apns; sourceTree = "<group>"; };\n'
    return targets.project(files, group_children="\t\t\t\tA00000000000000000000001,\n")


BARE_WATCH_EXTENSION_PLIST = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                              '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n'
                              "\t<key>CFBundleExecutable</key>\n\t<string>$(EXECUTABLE_NAME)</string>\n"
                              "\t<key>CFBundleIdentifier</key>\n\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>\n</dict>\n</plist>\n")
# Watch extensions' Info.plists as the fuzzer's seed 70155 has its (BACKLOG B-091): label, the
# extension's settings, the Info.plist written at <label>Ext/Info.plist (None: no file).
WATCH_PLISTS = [
    ("WBare", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("WBareExt/Info.plist")}, BARE_WATCH_EXTENSION_PLIST),
    ("WMacro", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("$(NOMAC_PLIST_ROOT)/Info.plist"),
                "NOMAC_PLIST_ROOT": pbx_string("$(SRCROOT)/WMacroExt")}, None),
    ("WMacroBare", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("$(NOMAC_PLIST_ROOT)/Info.plist"),
                    "NOMAC_PLIST_ROOT": pbx_string("$(SRCROOT)/WMacroBareExt")}, BARE_WATCH_EXTENSION_PLIST),
    ("WSrcroot", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("$(SRCROOT)/WSrcrootExt/Info.plist")}, None),
    ("WMissing", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("WMissingExt/Info.plist")}, False),
    ("WUnresolved", {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("$(NOMAC_UNDEFINED)/Info.plist")}, False),
    ("WGenerated", {"GENERATE_INFOPLIST_FILE": "YES"}, False),
]


def watch_schemes_plist():
    # One watch app and extension per entry of WATCH_PLISTS; None writes the usual extension
    # Info.plist (watch_extension_plist, no complication), False none.
    targets, files = Targets(), {}
    for name, settings, plist in WATCH_PLISTS:
        if plist is not False:
            files[f"{name}Ext/Info.plist"] = plist or watch_extension_plist(False)
        extension, _ = targets.add(f"{name}Ext", "com.apple.product-type.watchkit2-extension", settings, sdk="watchos")
        watch, _ = targets.add(name, "com.apple.product-type.application.watchapp2", {}, sdk="watchos")
        targets.depend(watch, extension, f"{name}Ext")
    return targets.project(files)


def watch_project(path="P.xcodeproj", interface=None, file_type=None, content=None, complication=False, variant=False):
    """A project with one watch app and its extension (naming a complication with
    `complication`), and in its main group a file reference to `interface` of `file_type`
    (by default the type its extension names), written with `content` unless that is None. With
    `variant`, the reference is `Base.lproj/<interface>` in a variant group named `interface`."""
    targets, files = Targets(), {"WExt/Info.plist": watch_extension_plist(complication)}
    extension, _ = targets.add("WExt", "com.apple.product-type.watchkit2-extension",
                               {"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": pbx_string("WExt/Info.plist")}, sdk="watchos")
    watch, _ = targets.add("W", "com.apple.product-type.application.watchapp2", {}, sdk="watchos")
    targets.depend(watch, extension, "WExt")
    children = ""
    if interface:
        file_type = file_type or ("file.storyboard" if interface.endswith(".storyboard") else "file.xib")
        location = f"Base.lproj/{interface}" if variant else interface
        named = "name = Base; " if variant else ""
        targets.objects += f'\t\tA00000000000000000000001 = {{isa = PBXFileReference; lastKnownFileType = {file_type}; {named}path = {pbx_string(location)}; sourceTree = "<group>"; }};\n'
        children = "\t\t\t\tA00000000000000000000001,\n"
        if variant:
            targets.objects += f'\t\tA00000000000000000000002 = {{isa = PBXVariantGroup; children = (A00000000000000000000001, ); name = {pbx_string(interface)}; sourceTree = "<group>"; }};\n'
            children = "\t\t\t\tA00000000000000000000002,\n"
        if content is not None:
            files[location] = content
    return targets.project(files, group_children=children, path=path)


EMPTY_STORYBOARD = ('<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" '
                    'version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch"/>\n')
# The fuzzer's seed 70155 (BACKLOG B-091): its watch app gets `(Glance)` and `(Notification)`
# schemes when App.xcodeproj, which references the watch app's project and holds a storyboard
# missing from disk, is opened; not when the watch app's project is opened alone. One watch app
# per case, with a file reference in the same project: name, file type, content (None: none).
WATCH_INTERFACES = {
    "missing": ("Missing.storyboard", None, None),
    "written": ("Present.storyboard", None, EMPTY_STORYBOARD),
    "empty": ("Empty.storyboard", None, ""),
    "garbage": ("Garbage.storyboard", None, "nomac\n"),
    "xib": ("Missing.xib", None, None),
    "type-only": ("Missing.txt", "file.storyboard", None),
    "extension-only": ("Missing.storyboard", "text", None),
}


def app_with_product(name, extra_objects="", group_children="", project_references=""):
    """simple_project with a product reference for its app, which Swift Build needs (BACKLOG B-012)."""
    product = f'\t\tB00000000000000000000009 = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
    return simple_project(name, extra_objects=extra_objects + product, extra_target="\t\t\tproductReference = B00000000000000000000009;\n",
                          group_children=group_children, project_references=project_references)


def watch_schemes_missing(case):
    if case in WATCH_INTERFACES:
        return watch_project(*(("P.xcodeproj",) + WATCH_INTERFACES[case]))
    if case == "complication":
        return watch_project(interface="Missing.storyboard", complication=True)
    if case in ("variant", "variant-missing"):
        return watch_project(interface="Main.storyboard", content=None if case == "variant-missing" else EMPTY_STORYBOARD, variant=True)
    sub = {("Sub/" + name if not name.startswith("Sub/") else name): text
           for name, text in watch_project(path="Sub/W.xcodeproj", interface="Missing.storyboard" if case == "referenced" else None).items()}
    if case == "workspace":
        missing = '\t\tA00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = file.storyboard; path = Missing.storyboard; sourceTree = "<group>"; };\n'
        return {**sub, "Other/O.xcodeproj/project.pbxproj": app_with_product("App", extra_objects=missing, group_children="\t\t\t\tA00000000000000000000001,\n"),
                "Other/App.swift": "@main struct App { static func main() {} }\n",
                "All.xcworkspace/contents.xcworkspacedata": workspace_contents(["Sub/W.xcodeproj", "Other/O.xcodeproj"])}
    objects = """\t\tB00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = Sub/W.xcodeproj; sourceTree = "<group>"; };
\t\tB00000000000000000000002 = {isa = PBXGroup; children = (); name = Products; sourceTree = "<group>"; };
"""
    children = "\t\t\t\tB00000000000000000000001,\n"
    if case == "referencing":
        objects += '\t\tA00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = file.storyboard; path = Missing.storyboard; sourceTree = "<group>"; };\n'
        children += "\t\t\t\tA00000000000000000000001,\n"
    references = "\t\t\tprojectReferences = (\n\t\t\t\t{\n\t\t\t\t\tProductGroup = B00000000000000000000002;\n\t\t\t\t\tProjectRef = B00000000000000000000001;\n\t\t\t\t},\n\t\t\t);\n"
    return {**sub, "Q.xcodeproj/project.pbxproj": app_with_product("Client", extra_objects=objects, group_children=children, project_references=references),
            "App.swift": "@main struct App { static func main() {} }\n"}


# Phases that list a synchronized folder's members beside build files whose file reference is
# missing (envelope-experiments `dangling-file-reference` moved the members from
# the front). One target per case: `regular` build files, `members` files in the target's
# synchronized folder, and dangling build files at `dangling`, positions in the phase's list.
DANGLING_CASES = ([(regular, members, (position,)) for regular in range(1, 5) for members in (1, 2, 3) for position in range(regular + 1)]
                  + [(3, members, pair) for members in (1, 2) for pair in itertools.combinations(range(5), 2)]
                  + [(0, 2, (0,)), (2, 1, (0, 1, 2))])


# Two and three members behind 1 to 9 regular build files and one dangling entry at the front.
DANGLING_LENGTHS = [(regular, members, (0,)) for members in (2, 3) for regular in range(1, 10)]


# Pairs of member names, one changed at a time, behind 1 to 9 regular build files and one dangling
# entry at the front; members given by name are named `<name>.swift`.
DANGLING_PAIR_NAMES = [("m0", other) for other in ("m1", "a", "z", "mm", "x1", "b2", "Q", "m0x", "zz1")] \
                      + [(other, "m1") for other in ("a", "Q", "b2")] + [("m0",)]
DANGLING_PAIRS = [(regular, names, (0,)) for names in DANGLING_PAIR_NAMES for regular in range(1, 10)]


def dangling_synchronized(prefix="", first_id=1, member="m", cases=DANGLING_CASES):
    # With `prefix`, the same cases under other target, folder and file names; with `first_id`,
    # other object IDs; with `member`, members named to sort otherwise against the regular files;
    # a case's members are a count, or the names of its members.
    objects, files, targets, children, products = "", {}, [], "", []
    for t, (regular, members, dangling) in enumerate(cases, first_id):
        member_files = [f"{n}.swift" for n in members] if isinstance(members, tuple) else [f"{member}{j}.swift" for j in range(members)]
        label = "-".join(members) if isinstance(members, tuple) else members
        name = f"{prefix}N{regular}M{label}D{''.join(map(str, dangling))}"
        group = f"DG{t:022d}"
        objects += f'\t\t{group} = {{isa = PBXFileSystemSynchronizedRootGroup; path = {name}; sourceTree = "<group>"; }};\n'
        children += f"\t\t\t\t{group},\n"
        for j, member_file in enumerate(member_files):
            files[f"{name}/{member_file}"] = f"// member {j}\n"
        entries, regulars = [], iter(range(regular))
        for position in range(regular + len(dangling)):
            build = f"DB{t:03d}{position:019d}"
            if position in dangling:
                objects += f"\t\t{build} = {{isa = PBXBuildFile; fileRef = DY{t:03d}{position:019d}; }};\n"
            else:
                index = next(regulars)
                reference = f"DR{t:03d}{index:019d}"
                files[f"{name}-r{index}.swift"] = f"// regular {index}\n"
                objects += (f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}-r{index}.swift"; sourceTree = "<group>"; }};\n'
                            f"\t\t{build} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
                children += f"\t\t\t\t{reference},\n"
            entries.append(build)
        phase = f"DP{t:022d}"
        objects += (f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ("
                    + "".join(f"{e}, " for e in entries) + "); runOnlyForDeploymentPostprocessing = 0; };\n")
        target, product = f"DT{t:022d}", f"DQ{t:022d}"
        objects += f'\t\t{product} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{name}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        products.append(product)
        objects += app_target(target, name, [phase], [f"DL{t:022d}", f"DD{t:022d}", f"DE{t:022d}"],
                              {"PRODUCT_NAME": pbx_string("$(TARGET_NAME)"), "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.dangling{t}",
                               "GENERATE_INFOPLIST_FILE": "YES"},
                              extra=f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{group},\n\t\t\t);\n", product_reference=product)
        targets.append(target)
    objects += f'\t\tDZ0000000000000000000001 = {{isa = PBXGroup; children = ({", ".join(products)}, ); name = Products; sourceTree = "<group>"; }};\n'
    children += "\t\t\t\tDZ0000000000000000000001,\n"
    objects += f'\t\tF00000000000000000000002 = {{isa = PBXGroup; children = (\n{children}\t\t\t); sourceTree = "<group>"; }};\n'
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", targets, objects)
    return files


# BACKLOG B-089: with `-destination generic/platform=iOS`, xcodebuild refuses (64) a scheme whose
# target's SDKROOT is iphonesimulator, where Swift Build evaluates the target for iphoneos. One
# framework per case: name, SDKROOT, other settings.
SIMULATOR_SDK_CASES = [
    ("SimIOS", "iphonesimulator", {}),
    ("SimIOSBoth", "iphonesimulator", {"SUPPORTED_PLATFORMS": pbx_string("iphoneos iphonesimulator")}),
    ("SimIOSDeviceOnly", "iphonesimulator", {"SUPPORTED_PLATFORMS": "iphoneos"}),
    ("DevIOSSimOnly", "iphoneos", {"SUPPORTED_PLATFORMS": "iphonesimulator"}),
    ("DevIOS", "iphoneos", {}),
    ("SimTV", "appletvsimulator", {}),
    ("SimWatch", "watchsimulator", {}),
    ("SimXR", "xrsimulator", {}),
    ("SimIOSConditional", "iphoneos", {'"SDKROOT[config=Debug]"': "iphonesimulator"}),
    ("SimIOSConditionalRelease", "iphoneos", {'"SDKROOT[config=Release]"': "iphonesimulator"}),
    ("DevIOSConditional", "iphonesimulator", {'"SDKROOT[config=Debug]"': "iphoneos"}),
    ("SimIOSSdkCondition", "iphoneos", {'"SDKROOT[sdk=iphoneos*]"': "iphonesimulator"}),
]


def simulator_sdks(project_sdk=None):
    # With `project_sdk`, one framework that sets no SDKROOT in a project whose SDKROOT it is.
    targets = Targets()
    if project_sdk:
        targets.add("Inherits", FRAMEWORK, {}, sdk=None)
        return targets.project(project_settings={"SDKROOT": project_sdk, "IPHONEOS_DEPLOYMENT_TARGET": "18.0"})
    for name, sdk, settings in SIMULATOR_SDK_CASES:
        targets.add(name, FRAMEWORK, settings, sdk=sdk)
    # A simulator SDKROOT in the Debug configuration only, and in Release only; a shared scheme
    # that builds the first and launches in Release.
    for index, (name, debug, release) in enumerate([("PerConfigSimDebug", "iphonesimulator", "iphoneos"),
                                                    ("PerConfigSimRelease", "iphoneos", "iphonesimulator")]):
        ids = [f"Q{index:023d}", f"QD{index:022d}", f"QR{index:022d}"]
        common = {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.perconfig{index}"}
        target, _ = targets.add(name, FRAMEWORK, {}, configuration_list=configurations(*ids, {**common, "SDKROOT": debug},
                                                                                       {**common, "SDKROOT": release}), list_ids=ids)
        if index == 0:
            buildable = (target, f"{name}.framework", name, "container:P.xcodeproj")
            scheme = scheme_file(build=[(*buildable, True)])
            launch = scheme.index("<LaunchAction")
            scheme = scheme[:launch] + scheme[launch:].replace('buildConfiguration = "Debug"', 'buildConfiguration = "Release"', 1)
            files = {"P.xcodeproj/xcshareddata/xcschemes/LaunchRelease.xcscheme": scheme}
    return targets.project(files)


# BACKLOG B-089: which conditions on SDKROOT xcodebuild's destination check applies. One framework
# per case: name, SDKROOT (None: unset), other settings, base xcconfig text.
SIMULATOR_SDK_CONDITION_CASES = [
    ("SdkOfDestination", "macosx", {'"SDKROOT[sdk=iphoneos*]"': "iphonesimulator",
                                     "SUPPORTED_PLATFORMS": pbx_string("macosx iphoneos iphonesimulator")}, None),
    ("ConfigWildcard", "iphoneos", {'"SDKROOT[config=*]"': "iphonesimulator"}, None),
    ("SdkAndConfig", "iphoneos", {'"SDKROOT[sdk=iphoneos*][config=Debug]"': "iphonesimulator"}, None),
    ("Arch", "iphoneos", {'"SDKROOT[arch=arm64]"': "iphonesimulator"}, None),
    ("MacroConfig", pbx_string("$(NOMAC_SDK)"), {"NOMAC_SDK": "iphoneos", '"NOMAC_SDK[config=Debug]"': "iphonesimulator"}, None),
    ("MacroConfigReverse", pbx_string("$(NOMAC_SDK)"), {"NOMAC_SDK": "iphonesimulator", '"NOMAC_SDK[config=Debug]"': "iphoneos"}, None),
    ("Xcconfig", None, {}, "SDKROOT = iphoneos\nSDKROOT[config=Debug] = iphonesimulator\n"),
    ("XcconfigReverse", None, {}, "SDKROOT = iphonesimulator\nSDKROOT[config=Debug] = iphoneos\n"),
    ("XcconfigUnderTarget", "iphonesimulator", {}, "SDKROOT = iphoneos\n"),
    ("XcconfigWildcard", None, {}, "SDKROOT = iphoneos\nSDKROOT[config=*] = iphonesimulator\n"),
    ("XcconfigArch", None, {}, "SDKROOT = iphoneos\nSDKROOT[arch=arm64] = iphonesimulator\n"),
    ("XcconfigSdkOfDestination", None, {"SUPPORTED_PLATFORMS": pbx_string("macosx iphoneos iphonesimulator")},
     "SDKROOT = macosx\nSDKROOT[sdk=iphoneos*] = iphonesimulator\n"),
    ("XcconfigConditionFirst", None, {}, "SDKROOT[config=Debug] = iphonesimulator\nSDKROOT = iphoneos\n"),
    ("XcconfigMacroFromProjectFile", None, {"NOMAC_SDK": "iphoneos", '"NOMAC_SDK[config=Debug]"': "iphonesimulator"},
     "SDKROOT = $(NOMAC_SDK)\n"),
    ("ProjectFileMacroFromXcconfig", pbx_string("$(NOMAC_SDK)"), {}, "NOMAC_SDK = iphoneos\nNOMAC_SDK[config=Debug] = iphonesimulator\n"),
    ("ArchWildcard", "iphoneos", {'"SDKROOT[arch=*]"': "iphonesimulator"}, None),
    ("ConfigPattern", "iphoneos", {'"SDKROOT[config=D*]"': "iphonesimulator"}, None),
]


def simulator_sdk_conditions(project_settings=None):
    # With `project_settings`, a project whose settings they are and one framework that sets no
    # SDKROOT, and one that sets SDKROOT for the Debug configuration only.
    targets = Targets()
    if project_settings:
        targets.add("Inherits", FRAMEWORK, {}, sdk=None)
        targets.add("DebugOnly", FRAMEWORK, {'"SDKROOT[config=Debug]"': "iphonesimulator"}, sdk=None)
        return targets.project(project_settings={**project_settings, "IPHONEOS_DEPLOYMENT_TARGET": "18.0"})
    files, children = {}, ""
    for index, (name, sdk, settings, xcconfig) in enumerate(SIMULATOR_SDK_CONDITION_CASES, 1):
        if xcconfig is None:
            targets.add(name, FRAMEWORK, settings, sdk=sdk)
            continue
        reference = f"A{index:023d}"
        files[f"{name}.xcconfig"] = xcconfig
        targets.objects += f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {name}.xcconfig; sourceTree = "<group>"; }};\n'
        children += f"\t\t\t\t{reference},\n"
        values = {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.conditions{index}", **settings}
        if sdk:
            values["SDKROOT"] = sdk
        ids = [f"H{index:023d}", f"G{index:023d}", f"J{index:023d}"]
        targets.add(name, FRAMEWORK, {}, configuration_list=configurations(*ids, values, base=reference), list_ids=ids)
    return targets.project(files, group_children=children)


def observe_simulator_sdks(run):
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)["project"]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
        run(f"scheme-{name}-simulator", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS Simulator")
        for configuration in ("Debug", "Release"):
            run(f"scheme-{name}-{configuration}", "-showBuildSettings", "-scheme", name, "-configuration", configuration,
                "-destination", "generic/platform=iOS")


# In a project opened alone, Xcode's scheme builds put a target under SYMROOT where
# a level sets it. One framework per case, its SYMROOT settings; shared schemes build Custom and
# Plain together, and Plain alone.
SYMROOT_TARGETS = [
    ("Custom", {"SYMROOT": "Custom"}),
    ("Plain", {}),
    ("Default", {"SYMROOT": pbx_string("$(SRCROOT)/build")}),
    ("Macro", {"SYMROOT": pbx_string("$(NOMAC_ROOT)/out"), "NOMAC_ROOT": "Other"}),
    ("Empty", {"SYMROOT": pbx_string("")}),
    ("MacOnly", {'"SYMROOT[sdk=macosx*]"': "MacOut"}),
    ("IOSOnly", {'"SYMROOT[sdk=iphoneos*]"': "IOSOut"}),
]


def symroot_targets():
    targets = SchemeTargets()
    buildables = {name: targets.buildable(name, FRAMEWORK, settings) for name, settings in SYMROOT_TARGETS}
    targets.scheme("P.xcodeproj/xcshareddata/xcschemes", "Both", [buildables["Custom"], buildables["Plain"]])
    targets.scheme("P.xcodeproj/xcshareddata/xcschemes", "PlainOnly", [buildables["Plain"]])
    return targets.project(targets.files)


def symroot_project(case):
    # One project per case: Plain, which sets no SYMROOT, and Other with the case's settings
    # (none: the control); a shared scheme builds Plain alone.
    settings = dict(SYMROOT_TARGETS).get(case, {})
    targets = SchemeTargets()
    plain = targets.buildable("Plain", FRAMEWORK, {})
    if case in ("ReleaseOnly", "DebugOnly"):
        # SYMROOT in one of Other's configurations only.
        ids = ["Q00000000000000000000001", "QD0000000000000000000001", "QR0000000000000000000001"]
        common = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.other"}
        debug, release = (common, {**common, "SYMROOT": "ReleaseOut"}) if case == "ReleaseOnly" else ({**common, "SYMROOT": "DebugOut"}, common)
        targets.add("Other", FRAMEWORK, {}, configuration_list=configurations(*ids, debug, release), list_ids=ids)
    else:
        targets.buildable("Other", FRAMEWORK, settings)
    targets.scheme("P.xcodeproj/xcshareddata/xcschemes", "PlainOnly", [plain])
    return targets.project(targets.files)


def observe_symroot_project(run):
    for scheme in ("PlainOnly", "Other"):
        run(f"scheme-{scheme}", "-showBuildSettings", "-scheme", scheme, "-destination", "generic/platform=iOS")
        run(f"scheme-{scheme}-derived", "-showBuildSettings", "-scheme", scheme, "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(run.output / "DD"))


def symroot_references(assigning):
    # Q.xcodeproj, opened alone, references Sub/W.xcodeproj; `assigning` ("sub" or "top") is the
    # project whose target assigns SYMROOT. Q's Client and W's Inner each get a scheme.
    inner = Targets()
    inner.add("Inner", FRAMEWORK, {"SYMROOT": "Custom"} if assigning == "sub" else {})
    files = {f"Sub/{path}": text for path, text in inner.project(path="W.xcodeproj").items()}
    objects = """\t\tB00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = Sub/W.xcodeproj; sourceTree = "<group>"; };
\t\tB00000000000000000000002 = {isa = PBXGroup; children = (); name = Products; sourceTree = "<group>"; };
"""
    references = "\t\t\tprojectReferences = (\n\t\t\t\t{\n\t\t\t\t\tProductGroup = B00000000000000000000002;\n\t\t\t\t\tProjectRef = B00000000000000000000001;\n\t\t\t\t},\n\t\t\t);\n"
    top = app_with_product("Client", extra_objects=objects, group_children="\t\t\t\tB00000000000000000000001,\n", project_references=references)
    if assigning == "top":
        top = top.replace('PRODUCT_NAME = "$(TARGET_NAME)";', 'PRODUCT_NAME = "$(TARGET_NAME)";\n\t\t\t\tSYMROOT = Custom;')
    files["Q.xcodeproj/project.pbxproj"] = top
    files["App.swift"] = "@main struct App { static func main() {} }\n"
    return files


def observe_symroot_references(run):
    for scheme in ("Client", "Inner"):
        run(f"scheme-{scheme}", "-showBuildSettings", "-scheme", scheme, "-destination", "generic/platform=iOS")


def observe_symroot(run):
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)["project"]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
    for name, _ in SYMROOT_TARGETS:
        run(f"target-{name}", "-showBuildSettings", "-target", name)


GEN_PACKAGE = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gen",
    products: [.plugin(name: "GenPlugin", targets: ["GenPlugin"])],
    targets: [
        .executableTarget(name: "GenTool"),
        .plugin(name: "GenPlugin", capability: .buildTool(), dependencies: ["GenTool"]),
    ]
)
"""
GEN_TOOL = """import Foundation

try "let generated = 1\\n".write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
"""
GEN_PLUGIN = """import PackagePlugin

@main
struct GenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] { [] }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GenPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let output = context.pluginWorkDirectoryURL.appending(path: "Generated.swift")
        return [.buildCommand(displayName: "Generate", executable: try context.tool(named: "GenTool").url,
                              arguments: [output.path], outputFiles: [output])]
    }
}
#endif
"""


def build_tool_plugin():
    # BACKLOG B-009: an app that applies a local package's build tool plugin (`plugin:GenPlugin`, a
    # PBXTargetDependency naming the product), which runs the package's GenTool to generate a
    # Swift file the app compiles.
    files = {"Deps/Gen/Package.swift": GEN_PACKAGE, "Deps/Gen/Sources/GenTool/main.swift": GEN_TOOL,
             "Deps/Gen/Plugins/GenPlugin/plugin.swift": GEN_PLUGIN,
             "App.swift": "@main struct App { static func main() { print(generated) } }\n"}
    objects = """		B00000000000000000000001 = {isa = PBXTargetDependency; productRef = E00000000000000000000002; };
		D00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Gen; };
		E00000000000000000000002 = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = "plugin:GenPlugin"; };
		P00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
		G00000000000000000000001 = {isa = PBXGroup; children = (P00000000000000000000001, ); name = Products; sourceTree = "<group>"; };
"""
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = simple_project(
        "App", extra_objects=objects, project_references=references, group_children="\t\t\t\tG00000000000000000000001,\n",
        extra_target="\t\t\tdependencies = (\n\t\t\t\tB00000000000000000000001,\n\t\t\t);\n\t\t\tproductReference = P00000000000000000000001;\n")
    return files


def observe_build_tool_plugin(run):
    run("list", "-list", "-json")
    for scheme in ("App", "GenPlugin", "GenTool"):
        run(f"scheme-{scheme}", "-showBuildSettings", "-scheme", scheme, "-destination", "generic/platform=iOS")
    derived = run.output / "DerivedData"
    run("build", "build", "-scheme", "App", "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived),
        "-skipPackagePluginValidation", "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=6.0")
    generated = sorted(str(path.relative_to(derived)) for path in derived.rglob("Generated.swift"))
    (run.output / "generated.txt").write_text("".join(f"{path}\n" for path in generated))
    shutil.rmtree(derived, ignore_errors=True)


def root_group(keys):
    # wordpress's main group is `{ name = CustomTemplate; }`, the name old Xcode templates gave it.
    # The main group with `keys` (name, path) added.
    targets = Targets()
    targets.add("App", APPLICATION, {})
    files = targets.project()
    text = files["P.xcodeproj/project.pbxproj"]
    head = "\t\tF00000000000000000000002 = {\n\t\t\tisa = PBXGroup;\n"
    assert head in text
    files["P.xcodeproj/project.pbxproj"] = text.replace(head, head + "".join(f"\t\t\t{key} = {value};\n" for key, value in keys))
    return files


def observe_every_scheme(run, destination="generic/platform=iOS", key="project"):
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)[key]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", destination)


def configuration_experiment(names, default):
    # Which configuration's INFOPLIST_FILE decides (extension-points: Debug's, not Release's, with
    # Debug listed first), which configuration autocreated schemes launch with, and in which one
    # TEST_HOST must name App for App's scheme to test a bundle (test-hosts: Debug's).
    entries = [(name, {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}) for name in names]
    targets = Targets()

    def add(name, product_type, changes):
        """A target whose configurations are `names`, each with the settings `changes` gives it."""
        index = len(targets.ids) + 1
        values = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        list_id = f"H{index:023d}"
        settings = [(f"G{index:02d}{position:021d}", configuration, {**values, **changes(configuration)})
                    for position, configuration in enumerate(names)]
        return targets.add(name, product_type, {}, configuration_list=named_configurations(list_id, settings, default), list_ids=[list_id])[0]

    app = add("App", APPLICATION, lambda configuration: {})
    for chosen in names:
        add(f"{chosen}Safari", APPEX, lambda configuration, chosen=chosen: {
            "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Safari.plist" if configuration == chosen else "Share.plist"})
    # Unit test bundles whose TEST_HOST names App in some configurations only: Hosted-<those>
    # depend on App and set BUNDLE_LOADER with it, Loose-<those> do neither.
    subsets = [[name for bit, name in enumerate(names) if mask >> bit & 1] for mask in range(1, 2 ** len(names))]
    host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App")}
    for kind in ["Hosted", "Loose"]:
        for chosen in subsets:
            values = {**host, "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")} if kind == "Hosted" else host
            bundle = add(f"{kind}-{'-'.join(chosen)}", UNIT_TEST, lambda configuration, chosen=chosen, values=values:
                         values if configuration in chosen else {})
            if kind == "Hosted":
                targets.depend(bundle, app, "App")
    return targets.project({"Safari.plist": info_plist(SAFARI, True), "Share.plist": info_plist(SHARE, True)}, project_configurations=(entries, default))


def observe_configurations(run):
    run("list", "-list", "-json")
    run("scheme-App", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS")
    run("scheme-App-test", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS", "test")


UI_TEST = "com.apple.product-type.bundle.ui-testing"


def test_bundles():
    # tofu's and netnewswire's test bundles, whose TestTargetID names an app, get no scheme;
    # product-types: test bundles with neither a TestTargetID nor a scheme testing them get one.
    targets = Targets()
    app, _ = targets.add("App", APPLICATION, {})
    library, _ = targets.add("Lib", "com.apple.product-type.framework", {})
    shared, _ = targets.add("Shared", APPLICATION, {})
    hosted, _ = targets.add("HostedTests", UNIT_TEST, {})
    targets.attribute(hosted, f"\t\t\t\t\t\tTestTargetID = {app};\n")
    targets.add("LooseTests", UNIT_TEST, {})
    dependent, _ = targets.add("DependentTests", UNIT_TEST, {})
    targets.depend(dependent, app, "App")
    targets.add("TestHostTests", UNIT_TEST, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")})
    ghost, _ = targets.add("GhostHostTests", UNIT_TEST, {})
    targets.attribute(ghost, "\t\t\t\t\t\tTestTargetID = C0000000000000000000BEEF;\n")
    library_tests, _ = targets.add("LibTests", UNIT_TEST, {})
    targets.attribute(library_tests, f"\t\t\t\t\t\tTestTargetID = {library};\n")
    hosted_ui, _ = targets.add("HostedUITests", UI_TEST, {})
    targets.attribute(hosted_ui, f"\t\t\t\t\t\tTestTargetID = {app};\n")
    targets.add("LooseUITests", UI_TEST, {})
    shared_host, _ = targets.add("SharedHostTests", UNIT_TEST, {})
    targets.attribute(shared_host, f"\t\t\t\t\t\tTestTargetID = {shared};\n")
    scheme_tested, _ = targets.add("SchemeTestedTests", UNIT_TEST, {})
    container = "container:P.xcodeproj"
    files = {"P.xcodeproj/xcshareddata/xcschemes/Shared.xcscheme": scheme_file(
        build=[(shared, "Shared.app", "Shared", container, True)],
        testables=[(scheme_tested, "SchemeTestedTests.xctest", "SchemeTestedTests", container)])}
    return targets.project(files)


def observe_test_bundles(run):
    observe_every_scheme(run)
    for name in ["App", "Lib", "Shared"]:
        run(f"scheme-{name}-test", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS", "test")


def test_hosts():
    # test-bundles: a bundle whose TestTargetID names App gets a scheme of its own, one that
    # depends on App or names it in TEST_HOST does not, and App's autocreated scheme tests none of
    # them; tofu's bundles, with a TestTargetID and a dependency, are tested by Tofu's scheme.
    # Each pair here links a bundle to its own app (or framework) in one way.
    targets = Targets()
    framework = "com.apple.product-type.framework"
    test_host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}
    test_target = {"TEST_TARGET_NAME": "{0}"}
    xcconfig = '\t\t\t\tA00000000000000000000001 /* Host.xcconfig */,\n'
    files = {"Host.xcconfig": "TEST_HOST = $(BUILT_PRODUCTS_DIR)/App16.app/App16\nBUNDLE_LOADER = $(TEST_HOST)\n"}
    targets.objects += 'A00000000000000000000001 /* Host.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Host.xcconfig; sourceTree = "<group>"; };\n'.join(["\t\t", ""])
    first_app = None
    # (tested product type, bundle type, TestTargetID, dependency, bundle settings, Release-only settings, xcconfig)
    for index, (product_type, bundle_type, target_id, depends, settings, release, base) in enumerate([
        (APPLICATION, UNIT_TEST, True, True, {}, None, False),
        (APPLICATION, UNIT_TEST, True, False, {}, None, False),
        (APPLICATION, UNIT_TEST, False, True, {}, None, False),
        (APPLICATION, UNIT_TEST, False, False, test_host, None, False),
        (APPLICATION, UNIT_TEST, True, False, test_host, None, False),
        (framework, UNIT_TEST, True, True, {}, None, False),
        (framework, UNIT_TEST, False, True, {}, None, False),
        (APPLICATION, UI_TEST, True, True, {}, None, False),
        (APPLICATION, UI_TEST, False, True, {}, None, False),
        (APPLICATION, UNIT_TEST, "first", True, {}, None, False),
        (APPLICATION, UNIT_TEST, True, True, test_host, None, False),
        (APPLICATION, UNIT_TEST, False, True, test_host, None, False),
        (APPLICATION, UI_TEST, True, True, test_target, None, False),
        (APPLICATION, UI_TEST, False, True, test_target, None, False),
        (APPLICATION, UI_TEST, True, False, test_target, None, False),
        (APPLICATION, UNIT_TEST, True, True, {}, None, True),
        (APPLICATION, UNIT_TEST, True, True, {}, test_host, False),
        (APPLICATION, UNIT_TEST, True, True, {"BUNDLE_LOADER": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}")}, None, False),
        (APPLICATION, UNIT_TEST, "first", True, test_host, None, False),
        (APPLICATION, UNIT_TEST, False, False, {}, test_host, False),
        (APPLICATION, UNIT_TEST, False, False, {}, None, True),
        (APPLICATION, UNIT_TEST, True, True, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/Product {0}.app/Product {0}")}, None, False),
        (APPLICATION, UNIT_TEST, True, True, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/Elsewhere.app/Elsewhere")}, None, False),
        (APPLICATION, UNIT_TEST, True, True, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app")}, None, False),
        (APPLICATION, UNIT_TEST, False, False, test_host, {}, False),
        (APPLICATION, UNIT_TEST, False, False, {"BUNDLE_LOADER": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}")}, None, False),
        (APPLICATION, UNIT_TEST, False, True, {"BUNDLE_LOADER": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}")}, None, False),
        (APPLICATION, UNIT_TEST, False, True, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}"),
                                               "BUNDLE_LOADER": pbx_string("$(BUILT_PRODUCTS_DIR)/Elsewhere.app/Elsewhere")}, None, False),
    ], 1):
        name = f"{'Fw' if product_type == framework else 'App'}{index:02d}"
        # App22's product is named "Product App22", which its bundle's TEST_HOST names.
        tested, _ = targets.add(name, product_type, {"PRODUCT_NAME": pbx_string(f"Product {name}")} if index == 22 else {})
        first_app = first_app or tested
        values = {key: value.replace("{0}", name) for key, value in settings.items()}
        if release is None and not base:
            bundle, _ = targets.add(f"{name}Tests", bundle_type, values)
        else:
            index_id = len(targets.ids) + 1
            common = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index_id}"}
            release_values = {**common, **{key: value.replace("{0}", name) for key, value in (release or {}).items()}}
            list_id = f"H{index_id:023d}"
            configuration_list = configurations(list_id, f"G{index_id:023d}", f"J{index_id:023d}", {**common, **values},
                                                release_values if release is not None else None,
                                                "A00000000000000000000001 /* Host.xcconfig */" if base else None)
            bundle, _ = targets.add(f"{name}Tests", bundle_type, {}, configuration_list=configuration_list, list_ids=[list_id])
        if target_id:
            targets.attribute(bundle, f"\t\t\t\t\t\tTestTargetID = {first_app if target_id == 'first' else tested};\n")
        if depends:
            targets.depend(bundle, tested, name)
    return targets.project(files, group_children=xcconfig)


def observe_test_hosts(run):
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)["project"]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
        run(f"scheme-{name}-test", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS", "test")


def infoplist_macros():
    # flappy-fly-bird's INFOPLIST_FILE is "$(SRCROOT)/FlappyFlyBird/Info.plist", and the PIF's
    # bundleIdentifierFromInfoPlist is that plist's CFBundleIdentifier. Each target names its
    # own plist, whose identifier names the target, through another macro.
    targets = Targets()
    files = {}
    variants = {
        "Srcroot": "$(SRCROOT)/Srcroot/Info.plist", "SrcrootBraces": "${SRCROOT}/SrcrootBraces/Info.plist",
        "ProjectDir": "$(PROJECT_DIR)/ProjectDir/Info.plist", "SourceRoot": "$(SOURCE_ROOT)/SourceRoot/Info.plist",
        "TargetName": "$(TARGET_NAME)/Info.plist", "Custom": "$(NOMAC_FOLDER)/Info.plist",
        "Nested": "$(SRCROOT)/$(TARGET_NAME)/Info.plist", "ProductName": "$(PRODUCT_NAME)/Info.plist",
        "Plain": "Plain/Info.plist",
        # Settings with an SDK condition: for the target's SDK, and for another beside a plain value.
        "ConditionIphoneos": {'"INFOPLIST_FILE[sdk=iphoneos*]"': pbx_string("ConditionIphoneos/Info.plist")},
        "ConditionMacosx": {"INFOPLIST_FILE": pbx_string("ConditionMacosx/Info.plist"), '"INFOPLIST_FILE[sdk=macosx*]"': pbx_string("Plain/Info.plist")},
    }
    for name, value in variants.items():
        settings = {"GENERATE_INFOPLIST_FILE": "NO", **(value if isinstance(value, dict) else {"INFOPLIST_FILE": pbx_string(value)})}
        if name == "Custom":
            settings["NOMAC_FOLDER"] = "Custom"
        targets.add(name, APPLICATION, settings)
        files[f"{name}/Info.plist"] = info_plist(None).replace("$(PRODUCT_BUNDLE_IDENTIFIER)", f"org.nomac.from-plist.{name.lower()}")
    return targets.project(files)


# File types `file-encodings` gives one file reference each, with fileEncoding = 4 (UTF-8): every
# FileType of Swift Build's specifications, and the common types Xcode has that they do not.
ENCODED_FILE_TYPES = [
    "archive", "archive.ar", "archive.asdictionary", "archive.binhex", "archive.ear",
    "archive.gzip", "archive.jar", "archive.macbinary", "archive.metal-library", "archive.ppob",
    "archive.rsrc", "archive.stuffit", "archive.tar", "archive.war", "archive.zip", "audio",
    "audio.aiff", "audio.au", "audio.midi", "audio.mp3", "audio.wav",
    "com.apple.instruments.instrdst", "com.apple.instruments.package-definition", "compiled",
    "compiled.air", "compiled.cfm", "compiled.javaclass", "compiled.mach-o",
    "compiled.mach-o.bundle", "compiled.mach-o.corefile", "compiled.mach-o.dylib",
    "compiled.mach-o.dylinker", "compiled.mach-o.executable", "compiled.mach-o.fvmlib",
    "compiled.mach-o.objfile", "compiled.mach-o.preload", "compiled.object-library", "compiled.rcx",
    "file", "file.bplist", "file.icon", "file.intentdefinition", "file.mlmodel", "file.playground",
    "file.referenceobject", "file.scp", "file.sks", "file.skybox", "file.storyboard",
    "file.strings", "file.swiftpm-manifest", "file.uicatalog", "file.usdz", "file.xcplaygroundpage",
    "file.xib", "folder", "folder.abstractassetcatalog", "folder.assetcatalog",
    "folder.documentationcatalog", "folder.iconcomposer.icon", "folder.iconset",
    "folder.imagecatalog", "folder.mlpackage", "folder.rkassets", "folder.skatlas",
    "folder.stickers", "image", "image.bmp", "image.gif", "image.heic", "image.icns", "image.ico",
    "image.jpeg", "image.pdf", "image.pict", "image.png", "image.svg", "image.tiff",
    "net.daringfireball.markdown", "sourcecode", "sourcecode.ada", "sourcecode.applescript",
    "sourcecode.asm", "sourcecode.asm.asm", "sourcecode.asm.llvm", "sourcecode.c", "sourcecode.c.c",
    "sourcecode.c.c.preprocessed", "sourcecode.c.h", "sourcecode.c.objc",
    "sourcecode.c.objc.preprocessed", "sourcecode.clips", "sourcecode.cpp", "sourcecode.cpp.cpp",
    "sourcecode.cpp.cpp.preprocessed", "sourcecode.cpp.h", "sourcecode.cpp.objcpp",
    "sourcecode.cpp.objcpp.preprocessed", "sourcecode.dtrace", "sourcecode.dylan",
    "sourcecode.exports", "sourcecode.fortran", "sourcecode.fortran.f77", "sourcecode.fortran.f90",
    "sourcecode.glsl", "sourcecode.iig", "sourcecode.java", "sourcecode.javascript",
    "sourcecode.lex", "sourcecode.make", "sourcecode.metal", "sourcecode.mig",
    "sourcecode.module-map", "sourcecode.nasm", "sourcecode.nqc", "sourcecode.opencl",
    "sourcecode.pascal", "sourcecode.protobuf", "sourcecode.rez", "sourcecode.swift",
    "sourcecode.text-based-dylib-definition", "sourcecode.typescript", "sourcecode.yacc", "text",
    "text.apinotes", "text.css", "text.html", "text.html.documentation", "text.html.other",
    "text.json", "text.json.sarif", "text.json.xcstrings", "text.man", "text.pbxproject",
    "text.plist", "text.plist.app-privacy", "text.plist.entitlements",
    "text.plist.ibClassDescription", "text.plist.info", "text.plist.pbfilespec",
    "text.plist.pblangspec", "text.plist.scriptSuite", "text.plist.scriptTerminology",
    "text.plist.strings", "text.plist.stringsdict", "text.plist.vocabulary",
    "text.plist.xcappextensionpoints", "text.plist.xcbuildrules", "text.plist.xclangspec",
    "text.plist.xcspec", "text.plist.xcsynspec", "text.plist.xctxtmacro", "text.plist.xml",
    "text.rtf", "text.script", "text.script.csh", "text.script.perl", "text.script.php",
    "text.script.python", "text.script.ruby", "text.script.sh", "text.script.worksheet",
    "text.xcconfig", "text.xcfilelist", "text.xml", "text.xml.dae",
    "text.xml.ibArchivingDescription", "text.yaml", "video", "video.avi", "video.mpeg",
    "video.quartz-composer", "video.quicktime", "wrapper", "wrapper.app-extension",
    "wrapper.application", "wrapper.artifactbundle", "wrapper.cfbundle", "wrapper.driver-extension",
    "wrapper.dsym", "wrapper.extensionkit-extension", "wrapper.framework",
    "wrapper.framework.static", "wrapper.htmld", "wrapper.installer-mpkg", "wrapper.installer-pkg",
    "wrapper.java-classfolder", "wrapper.kernel-extension", "wrapper.nib", "wrapper.pb-project",
    "wrapper.pb-target", "wrapper.plug-in", "wrapper.rcproject", "wrapper.rtfd",
    "wrapper.scnassets", "wrapper.scncache", "wrapper.spotlight-importer", "wrapper.storyboardc",
    "wrapper.system-extension", "wrapper.workspace", "wrapper.xcclassmodel", "wrapper.xcdatamodel",
    "wrapper.xcdatamodeld", "wrapper.xcframework", "wrapper.xcmappingmodel", "wrapper.xpc-service",
]


def file_encodings():
    # cwa's file.xib references have fileEncoding = 4 but no fileTextEncoding in the PIF, while
    # its Swift, JSON and plist references keep it.
    targets = Targets()
    targets.add("App", APPLICATION, {})
    children = ""
    for index, file_type in enumerate(ENCODED_FILE_TYPES, 1):
        reference = f"A{index:023d}"
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = {pbx_string(file_type)}; "
                            f"path = {pbx_string(f'file{index:03d}')}; sourceTree = \"<group>\"; }};\n")
        children += f"\t\t\t\t{reference},\n"
    return targets.project(group_children=children)



# Signal's Pods project declares its module maps `lastKnownFileType = sourcecode.module`, which
# the PIF types `sourcecode.module-map`, and file-encodings, whose files are not on disk, shows
# eight declared types typed `text`. Every type of ENCODED_FILE_TYPES and a few more is declared
# on a text file, on a folder and on a path that is not on disk, all without an extension. Then
# chosen types on chosen names, as lastKnownFileType or explicitFileType, references with
# neither, and references relative to other source trees.
DECLARED_FILE_TYPES = ENCODED_FILE_TYPES + ["file.rcproject", "sourcecode.jam", "sourcecode.module", "wrapper.mlmodelc",
                                            "nomac.unknown", "wrapper.nomac", "folder.nomac", "Sourcecode.Swift"]
SH = "#!/bin/sh\necho hi\n"
XML_PLIST = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
             '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n')
# (declared types {attribute: type}, path, contents: text, "dir" for a folder, None for not on disk, source tree)
DECLARED_CASES = [
    ({"lastKnownFileType": "sourcecode.module"}, "Mod/Signal.modulemap", "framework module Signal {}\n"),
    ({"lastKnownFileType": "sourcecode.module"}, "Mod/module.map", "module M {}\n"),
    ({"lastKnownFileType": "sourcecode.module"}, "Mod/m.zzz", "module M {}\n"),
    ({"lastKnownFileType": "sourcecode.module"}, "Mod/gone.modulemap", None),
    ({"lastKnownFileType": "sourcecode.module"}, "Mod/Dir.modulemap", "dir"),
    ({"explicitFileType": "sourcecode.module"}, "Mod/explicit.modulemap", "module E {}\n"),
    ({"lastKnownFileType": "sourcecode.module-map"}, "Mod/known.modulemap", "module K {}\n"),
    ({"lastKnownFileType": "file"}, "Named/a.swift", "let a = 1\n"),
    ({"lastKnownFileType": "file"}, "Named/Makefile", "all:\n"),
    ({"lastKnownFileType": "file"}, "Named/script", SH),
    ({"lastKnownFileType": "file"}, "Named/Info.plist", XML_PLIST),
    ({"lastKnownFileType": "file"}, "Named/blob.zzz", "a\x00\x01b\n"),
    ({"lastKnownFileType": "file"}, "Named/empty.zzz", ""),
    ({"lastKnownFileType": "nomac.unknown"}, "Named/b.swift", "let b = 1\n"),
    ({"lastKnownFileType": "wrapper.framework.static"}, "Named/Static.framework", "dir"),
    ({"lastKnownFileType": "wrapper.framework.static"}, "Named/Gone.framework", None),
    ({"lastKnownFileType": "wrapper.mlmodelc"}, "Kinds/N.mlmodelc", "x\n"),
    ({"lastKnownFileType": "wrapper.mlmodelc"}, "Kinds/D.mlmodelc", "dir"),
    ({"lastKnownFileType": "wrapper.framework"}, "Kinds/F.framework", "x\n"),
    ({"lastKnownFileType": "folder.assetcatalog"}, "Kinds/A.xcassets", "x\n"),
    ({"lastKnownFileType": "folder"}, "Kinds/plain.txt", "x\n"),
    ({"lastKnownFileType": "sourcecode.swift"}, "Kinds/S.swift", "dir"),
    ({"lastKnownFileType": "text"}, "Kinds/T.txt", "dir"),
    ({"lastKnownFileType": "sourcecode.c.objc"}, "Kept/k1.swift", "let k = 1\n"),
    ({"lastKnownFileType": "text"}, "Kept/k2.swift", "let k = 1\n"),
    ({"lastKnownFileType": "image.png"}, "Kept/k3.txt", "x\n"),
    ({"lastKnownFileType": "text.plist"}, "Kept/x.plist", XML_PLIST),
    ({"lastKnownFileType": "text.plist.xml"}, "Kept/b.plist", "bplist00\n"),
    ({"explicitFileType": "nomac.unknown", "lastKnownFileType": "sourcecode.swift"}, "Explicit/e1.swift", "let e = 1\n"),
    ({"explicitFileType": "file"}, "Explicit/e2.swift", "let e = 1\n"),
    ({"explicitFileType": "wrapper.mlmodelc"}, "Explicit/e3.mlmodelc", "x\n"),
    ({"explicitFileType": "sourcecode.swift", "lastKnownFileType": "nomac.unknown"}, "Explicit/e4.swift", "let e = 1\n"),
    ({}, "None/n1.swift", "let n = 1\n"),
    ({}, "None/n2.zzz", "x\n"),
    ({}, "None/n3", "a\x00\x01b\n"),
    ({}, "None/n4.swift", None),
    ({}, "None/N5.framework", "dir"),
    ({}, "None/n6", None),
    ({"lastKnownFileType": "file"}, "usr/lib/libz.tbd", None, "SDKROOT"),
    ({"lastKnownFileType": "sourcecode.module"}, "gen.modulemap", None, "BUILT_PRODUCTS_DIR"),
    ({"lastKnownFileType": "file"}, "gen-text", None, "BUILT_PRODUCTS_DIR"),
    ({"lastKnownFileType": "nomac.unknown"}, "Trees/src-text", "x\n", "SOURCE_ROOT"),
]


def declared_types():
    targets = Targets()
    targets.add("App", APPLICATION, {})
    files, children = {}, ""
    cases = [({"lastKnownFileType": file_type}, f"{kind}{index:03d}", contents)
             for kind, contents in [("t", "x\n"), ("d", "dir"), ("m", None)] for index, file_type in enumerate(DECLARED_FILE_TYPES, 1)]
    for index, (types, path, contents, *tree) in enumerate(cases + DECLARED_CASES, 1):
        reference = f"A{index:023d}"
        declared = "".join(f"{attribute} = {pbx_string(value)}; " for attribute, value in sorted(types.items()))
        source_tree = pbx_string(tree[0] if tree else "<group>")
        targets.objects += f"\t\t{reference} = {{isa = PBXFileReference; {declared}path = {pbx_string(path)}; sourceTree = {source_tree}; }};\n"
        children += f"\t\t\t\t{reference},\n"
        if contents == "dir":
            files[f"{path}/x"] = "x\n"
        elif contents is not None:
            files[path] = contents
    return targets.project(files, group_children=children)



# What declared types Xcode does not know become: folders and plain files whose extension names
# a type, explicitFileType, fileTextEncoding, other source trees, a group's path and a variant
# group's child.
PACKAGE = "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"{}\")\n"
DECLARED_CASES_2 = [
    *[({"lastKnownFileType": "file"}, f"Dirs/X.{extension}", "dir") for extension in
      ["zzz", "txt", "swift", "bundle", "xcassets", "app", "docc", "xcdatamodel", "mlpackage", "rkassets", "storyboardc",
       "scnassets", "lproj", "plist", "a", "xcframework", "icon", "appex"]],
    ({"lastKnownFileType": "file"}, "Dirs/Pkg", "package"),
    ({"lastKnownFileType": "file"}, "Dirs/Pkg2.zzz", "package"),
    *[({"lastKnownFileType": "file"}, f"Plain/P.{extension}", "x\n") for extension in
      ["framework", "xcassets", "bundle", "app", "mlpackage", "docc", "xcdatamodel"]],
    ({"explicitFileType": "nomac.unknown", "lastKnownFileType": "sourcecode.c.objc"}, "Explicit/e5.swift", "let e = 1\n"),
    ({"explicitFileType": "file", "lastKnownFileType": "sourcecode.c.objc"}, "Explicit/e6.swift", "let e = 1\n"),
    ({"explicitFileType": "wrapper.framework.static"}, "Explicit/ES.framework", "dir"),
    ({"explicitFileType": "file"}, "Explicit/EF", "dir"),
    ({"explicitFileType": "file"}, "Explicit/ef.swift", None),
    ({"lastKnownFileType": "nomac.unknown", "fileEncoding": "4"}, "Enc/x.png", "x\n"),
    ({"lastKnownFileType": "nomac.unknown", "fileEncoding": "4"}, "Enc/dir", "dir"),
    ({"lastKnownFileType": "image.svg", "fileEncoding": "4"}, "Enc/y.json", "{}\n"),
    ({"lastKnownFileType": "file", "fileEncoding": "4"}, "Enc/z.a", "!<arch>\n"),
    ({"lastKnownFileType": "nomac.unknown"}, "Trees/src-binary", "a\x00\x01b\n", "SOURCE_ROOT"),
    ({"lastKnownFileType": "nomac.unknown"}, "usr/include", None, "SDKROOT"),
    ({"lastKnownFileType": "nomac.unknown"}, "usr/bin/xcodebuild", None, "DEVELOPER_DIR"),
]


def declared_types_2():
    targets = Targets()
    targets.add("App", APPLICATION, {})
    files, children = {"Grp/inner-bin": "a\x00\x01b\n", "en.lproj/V.strings": '"k" = "v";\n'}, ""
    for index, (types, path, contents, *tree) in enumerate(DECLARED_CASES_2, 1):
        reference = f"A{index:023d}"
        declared = "".join(f"{attribute} = {pbx_string(value)}; " for attribute, value in sorted(types.items()))
        source_tree = pbx_string(tree[0] if tree else "<group>")
        targets.objects += f"\t\t{reference} = {{isa = PBXFileReference; {declared}path = {pbx_string(path)}; sourceTree = {source_tree}; }};\n"
        children += f"\t\t\t\t{reference},\n"
        if contents == "dir":
            files[f"{path}/x"] = "x\n"
        elif contents == "package":
            files[f"{path}/Package.swift"] = PACKAGE.format(path.rsplit("/", 1)[-1].split(".")[0])
        elif contents is not None:
            files[path] = contents
    targets.objects += """		G00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = nomac.unknown; path = "inner-bin"; sourceTree = "<group>"; };
		G00000000000000000000002 = {isa = PBXGroup; children = (G00000000000000000000001, ); path = Grp; sourceTree = "<group>"; };
		G00000000000000000000003 = {isa = PBXFileReference; lastKnownFileType = file; name = en; path = en.lproj/V.strings; sourceTree = "<group>"; };
		G00000000000000000000004 = {isa = PBXVariantGroup; children = (G00000000000000000000003, ); name = V.strings; sourceTree = "<group>"; };
"""
    children += "\t\t\t\tG00000000000000000000002,\n\t\t\t\tG00000000000000000000004,\n"
    return targets.project(files, group_children=children)



# Whether predominantSourceCodeLanguage counts a build file's declared type or the type Xcode
# gives a declared type it does not know: two Swift files declared `file` and one Objective-C file.
def declared_language():
    targets = Targets()
    app, _ = targets.add("App", APPLICATION, {})
    files, children, build_files = {}, "", ""
    for index, (declared, path) in enumerate([("file", "x.swift"), ("file", "y.swift"), ("sourcecode.c.objc", "z.m")], 1):
        reference, build_file = f"A{index:023d}", f"E{index:023d}"
        files[path] = "let x = 1\n"
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {declared}; path = {path}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
        children += f"\t\t\t\t{reference},\n"
        build_files += f"{build_file}, "
    targets.objects += f"\t\tB00000000000000000000001 = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build_files}); runOnlyForDeploymentPostprocessing = 0; }};\n"
    targets.phases[app].append("B00000000000000000000001")
    return targets.project(files, group_children=children)

# Which regions variant groups add when knownRegions lacks the development region or Base, where
# a child's region comes from when it has no name or a name unlike its folder, and children
# outside a `.lproj` folder. Each variant group is (name, [(child name or None, path)]).
def variant_groups_project(groups, known_regions, development_region="en", synchronized=None):
    targets = Targets()
    targets.add("App", APPLICATION, {})
    files, children = dict(synchronized or {}), ""
    for key, (name, variants) in groups.items():
        references = ""
        for index, (region, path) in enumerate(variants, 1):
            files[path] = '"k" = "v";\n'
            named = f"name = {pbx_string(region)}; " if region else ""
            reference = f"A{key}{index:021d}"
            targets.objects += f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; {named}path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n"
            references += f"\t\t\t\t{reference},\n"
        targets.objects += (f"\t\tG{key}{0:021d} = {{\n\t\t\tisa = PBXVariantGroup;\n\t\t\tchildren = (\n{references}\t\t\t);\n"
                            f"\t\t\tname = {pbx_string(name)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
        children += f"\t\t\t\tG{key}{0:021d},\n"
    if synchronized:
        targets.objects += '\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = Alpha; sourceTree = "<group>"; };\n'
        children = "\t\t\t\tS00000000000000000000001,\n" + children
    return targets.project(files, group_children=children, known_regions=known_regions, development_region=development_region)


def regions_classic_2():
    return variant_groups_project({
        "VB": ("B.strings", [("Base", "Base.lproj/B.strings")]), "VE": ("E.strings", [("en", "en.lproj/E.strings")]),
        "VD": ("D.strings", [("de", "de.lproj/D.strings")]), "VX": ("X.strings", [(None, "X.strings")]),
        "VF": ("F.strings", [("Foo", "it.lproj/F.strings")]), "VP": ("P.strings", [("pt", "es.lproj/P.strings")]),
        "VN": ("N.strings", [(None, "nl.lproj/sub/N.strings")])},
        ("fr",), synchronized={"Alpha/Base.lproj/S.strings": '"k" = "v";\n', "Alpha/en.lproj/S.strings": '"k" = "v";\n'})


REGION_GROUPS_3 = {"VB": ("B.strings", [("Base", "Base.lproj/B.strings")]), "VI": ("I.strings", [("it", "it.lproj/I.strings")]),
                   "VM": ("M.strings", [("ko", "ko.lproj/M.strings"), (None, "M.strings"), ("ja", "ja.lproj/M.strings")]),
                   "VR": ("R.strings", [(None, "R.strings"), (None, "sub/R.strings")])}

# variant-regions: knownRegions (en, Base) gained `fr` but not the `FR` of a later group. Regions
# that differ from knownRegions or from each other only in case, within one variant group (child
# order is stable, group order is not), and a child in a folder named `.lproj`.
REGION_CASE_GROUPS = {"VA": ("A.strings", [("FR", "FR.lproj/A.strings"), ("BASE", "x/BASE.lproj/A.strings"), ("EN", "y/EN.lproj/A.strings"),
                                           ("De", "De.lproj/A.strings"), ("de", "z/de.lproj/A.strings"), ("MUL", "MUL.lproj/A.strings"),
                                           ("PT-br", "PT-br.lproj/A.strings"), ("pt-BR", "w/pt-BR.lproj/A.strings")]),
                      "VB": ("B.strings", [(None, ".lproj/B.strings"), ("ko", "ko.lproj/B.strings")])}

# regions-case gained `de` and `pt-BR` from children `De`, `de`, `PT-br`, `pt-BR` in that order:
# whether the spelling is the last one's or a canonical form (`de` before `De`), next to regions
# a canonical form would change, and a knownRegions entry (`Fr`) a canonical form would not match.
REGION_CASE_GROUPS_4 = {"VA": ("A.strings", [("de", "de.lproj/A.strings"), ("De", "x/De.lproj/A.strings")]),
                        "VB": ("B.strings", [("pt-BR", "pt-BR.lproj/B.strings"), ("PT-br", "x/PT-br.lproj/B.strings")]),
                        "VC": ("C.strings", [("ZH-hans", "ZH-hans.lproj/C.strings")]), "VD": ("D.strings", [("Es", "Es.lproj/D.strings")]),
                        "VE": ("E.strings", [("fr", "fr.lproj/E.strings")]), "VF": ("F.strings", [("ENGLISH", "ENGLISH.lproj/F.strings")]),
                        "VG": ("G.strings", [("base", "base.lproj/G.strings")]), "VH": ("H.strings", [("Mul", "Mul.lproj/H.strings")])}
# regions-case-4 kept `English` as written but wrote `ENGLISH` as `english`: which spellings are
# kept (the language names of old Mac localizations, made-up words) and how the subtags of
# others are cased, one region per variant group.
REGION_CASE_GROUPS_5 = {f"V{index:02d}": (f"R{index:02d}.strings", [(region, f"{region}.lproj/R{index:02d}.strings")]) for index, region in enumerate([
    "French", "German", "Japanese", "Spanish", "Italian", "Dutch", "Swedish", "Danish", "Portuguese", "Korean", "Chinese", "Norwegian",
    "Russian", "Klingon", "Elvish", "Fr", "EN-us", "Sr-latn-RS", "zh_hans", "ES-419", "Zh-HANT-tw", "aBc", "x-Private", "FRENCH",
    "german", "Nl-be"])}
# regions-case-5 kept the English names of 13 languages as written: which other names of
# languages are kept, one region per variant group.
LANGUAGE_NAMES = [
    "Hebrew", "Arabic", "Finnish", "Greek", "Icelandic", "Maltese", "Turkish", "Croatian", "Urdu", "Hindi", "Thai", "Lithuanian",
    "Polish", "Hungarian", "Estonian", "Latvian", "Sami", "Faroese", "Farsi", "Persian", "Irish", "Albanian", "Romanian", "Czech",
    "Slovak", "Slovenian", "Yiddish", "Serbian", "Macedonian", "Bulgarian", "Ukrainian", "Byelorussian", "Belarusian", "Uzbek",
    "Kazakh", "Azerbaijani", "Armenian", "Georgian", "Moldavian", "Kirghiz", "Tajiki", "Turkmen", "Mongolian", "Pashto", "Kurdish",
    "Kashmiri", "Sindhi", "Tibetan", "Nepali", "Sanskrit", "Marathi", "Bengali", "Assamese", "Gujarati", "Punjabi", "Oriya",
    "Malayalam", "Kannada", "Tamil", "Telugu", "Sinhalese", "Burmese", "Khmer", "Lao", "Vietnamese", "Indonesian", "Tagalog", "Malay",
    "Amharic", "Tigrinya", "Oromo", "Somali", "Swahili", "Kinyarwanda", "Rundi", "Nyanja", "Malagasy", "Esperanto", "Welsh", "Basque",
    "Catalan", "Latin", "Quechua", "Guarani", "Aymara", "Tatar", "Uighur", "Dzongkha", "Javanese", "Sundanese", "Galician",
    "Afrikaans", "Breton", "Inuktitut", "Scottish", "Manx", "Tongan", "Greenlandic", "Flemish", "Brazilian", "Portuguese_BR",
    "Swiss", "Austrian", "Canadian", "Australian", "British", "American", "Taiwanese", "Cantonese", "Mandarin", "Hawaiian", "Maori",
    "Samoan", "Fijian", "Gaelic", "Frisian", "Luxembourgish", "Romansh", "Corsican", "Occitan", "Sardinian", "Sicilian", "Bosnian",
    "Montenegrin", "Norwegian_Nynorsk", "Nynorsk", "Bokmal", "Zulu", "Xhosa", "Yoruba", "Igbo", "Hausa", "Klingon2"]
REGION_CASE_GROUPS_6 = {f"V{index:03d}": (f"N{index:03d}.strings", [(name, f"{name}.lproj/N{index:03d}.strings")])
                        for index, name in enumerate(LANGUAGE_NAMES)}

# variant-regions: a variant group whose only child is not directly in a `.lproj` folder is
# replaced by that child, in the group tree and in its build file, which gets another GUID.
# Groups with one or two such children, next to a child in a `.lproj` folder or none, empty,
# in Resources and Sources, in two targets; each group is (name, [(region or None, path, type)],
# phase).
VARIANT_BUILD_FILES = [
    ("V1.strings", [("de", "V1.strings", "text.plist.strings")], "Resources"),
    ("V2.strings", [("fr", "fr.lproj/V2.strings", "text.plist.strings"), (None, "V2.strings", "text.plist.strings")], "Resources"),
    ("V3.strings", [(None, "a/V3.strings", "text.plist.strings"), (None, "b/V3.strings", "text.plist.strings")], "Resources"),
    ("V4.strings", [], "Resources"),
    ("V5.swift", [(None, "V5.swift", "sourcecode.swift")], "Sources"),
    ("V6.intentdefinition", [(None, "V6.intentdefinition", "file.intentdefinition")], "Sources"),
    ("V7.strings", [(None, "V7.strings", "text.plist.strings"), ("de", "de.lproj/V7.strings", "text.plist.strings")], "Resources"),
    ("V8.intentdefinition", [(None, "x/V8.intentdefinition", "file.intentdefinition"),
                             ("Base", "Base.lproj/V8.intentdefinition", "file.intentdefinition")], "Sources"),
]


def variant_build_files():
    targets = Targets()
    apps = [targets.add(name, APPLICATION, {})[0] for name in ("App", "Other")]
    files, children = {}, ""
    listed = {(app, phase): "" for app in apps for phase in ("Sources", "Resources")}
    for index, (name, variants, phase) in enumerate(VARIANT_BUILD_FILES, 1):
        references = ""
        for number, (region, path, file_type) in enumerate(variants, 1):
            files[path] = '"k" = "v";\n'
            named = f"name = {pbx_string(region)}; " if region else ""
            reference = f"H{index:02d}{number:021d}"
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; {named}"
                                f"path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n")
            references += f"{reference}, "
        group = f"G{index:023d}"
        targets.objects += f"\t\t{group} = {{isa = PBXVariantGroup; children = ({references}); name = {pbx_string(name)}; sourceTree = \"<group>\"; }};\n"
        children += f"\t\t\t\t{group},\n"
        for number, app in enumerate(apps, 1):
            build_file = f"Y{number}{index:022d}"
            targets.objects += f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {group}; }};\n"
            listed[(app, phase)] += f"{build_file}, "
    for number, app in enumerate(apps, 1):
        for phase, isa in (("Sources", "PBXSourcesBuildPhase"), ("Resources", "PBXResourcesBuildPhase")):
            phase_id = f"W{number}{isa[3]}{0:021d}"
            targets.objects += (f"\t\t{phase_id} = {{isa = {isa}; buildActionMask = 2147483647; files = ({listed[(app, phase)]}); "
                                f"runOnlyForDeploymentPostprocessing = 0; }};\n")
            targets.phases[app].append(phase_id)
    return targets.project(files, group_children=children)


# declared-language: two `.swift` files declared `file` count for Swift. In codegen-file-types, a
# Sources phase of files without an extension, not on disk, declared each source code type, has
# no language. Each target here has two files that one reading counts for one language and one
# Objective-C or C file: declared types against extensions, files on disk or not, and
# explicitFileType. (name, [(path, declared type, on disk, explicit)]).
LANGUAGE_CASES = [
    ("MissingNoExtension", [("a1", "sourcecode.swift", False, False), ("a2", "sourcecode.swift", False, False),
                            ("a3.m", "sourcecode.c.objc", True, False)]),
    ("MissingExtension", [("b1.swift", "sourcecode.c.objc", False, False), ("b2.swift", "sourcecode.c.objc", False, False),
                          ("b3.c", "sourcecode.c.c", True, False)]),
    ("PresentText", [("c1.txt", "sourcecode.swift", True, False), ("c2.txt", "sourcecode.swift", True, False),
                     ("c3.m", "sourcecode.c.objc", True, False)]),
    ("PresentNoExtension", [("d1", "sourcecode.swift", True, False), ("d2", "sourcecode.swift", True, False),
                            ("d3.m", "sourcecode.c.objc", True, False)]),
    ("PresentMismatch", [("e1.m", "sourcecode.swift", True, False), ("e2.m", "sourcecode.swift", True, False),
                         ("e3.c", "sourcecode.c.c", True, False)]),
    ("Explicit", [("f1.m", "sourcecode.swift", True, True), ("f2.m", "sourcecode.swift", True, True), ("f3.c", "sourcecode.c.c", True, False)]),
    ("MissingSwift", [("g1.swift", "sourcecode.swift", False, False)]),
    ("MissingNoExtensionOnly", [("h1", "sourcecode.swift", False, False)]),
    ("MissingUnknown", [("i1.swift", "nomac.unknown", False, False), ("i2.swift", "nomac.unknown", False, False),
                        ("i3.m", "sourcecode.c.objc", True, False)]),
    ("PresentDeclaredText", [("j1.swift", "text", True, False), ("j2.swift", "text", True, False), ("j3.m", "sourcecode.c.objc", True, False)]),
    ("MissingDeclaredText", [("k1.swift", "text", False, False), ("k2.swift", "text", False, False), ("k3.m", "sourcecode.c.objc", True, False)]),
]


# codegen-file-types has no language although Objective-C++ has the most files of any language:
# which types without a language of their own still count. Each target has two files of one type
# and one Objective-C file.
# language-ties: one file of each language next to one `sourcecode.ada` file, for where the
# language those types count for sorts among ties.
LANGUAGE_TIE_TYPES = ["sourcecode.swift", "net.daringfireball.markdown", "sourcecode.applescript", "sourcecode.asm.llvm", "sourcecode.c.c",
                      "sourcecode.cpp.objcpp", "sourcecode.clips", "sourcecode.cpp.cpp", "sourcecode.dtrace", "sourcecode.fortran",
                      "sourcecode.fortran.f90", "sourcecode.glsl", "sourcecode.java", "sourcecode.javascript", "sourcecode.make",
                      "sourcecode.metal", "sourcecode.module-map", "sourcecode.nasm", "sourcecode.opencl", "sourcecode.protobuf",
                      "sourcecode.c.objc", "sourcecode.pascal"]


def language_weights(file_types=None, other="sourcecode.c.objc", copies=2):
    targets = Targets()
    children, count = "", 0
    if file_types is None:
        file_types = ENCODED_FILE_TYPES + ["text.script.python", "text.script.ruby", "text.script.perl", "text.script.csh", "text.script.php"]
    for file_type in file_types:
        target, _ = targets.add(f"Two-{file_type}", "com.apple.product-type.framework", {"GENERATE_INFOPLIST_FILE": "YES"})
        build_files = ""
        for path, declared in [(name, file_type) for name in "ab"[:copies]] + [("c.other", other)]:
            count += 1
            reference, build_file = f"A{count:023d}", f"E{count:023d}"
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {pbx_string(declared)}; "
                                f"path = {pbx_string(f'{file_type}/{path}')}; sourceTree = \"<group>\"; }};\n"
                                f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
            children += f"\t\t\t\t{reference},\n"
            build_files += f"{build_file}, "
        count += 1
        phase = f"W{count:023d}"
        targets.objects += (f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build_files}); "
                            f"runOnlyForDeploymentPostprocessing = 0; }};\n")
        targets.phases[target].append(phase)
    return targets.project(group_children=children)


# language-weights and language-ties: whether those types count together or each for its own
# language, against two or three Objective-C files.
LANGUAGE_POOL = {"P1": ["sourcecode.ada"] + ["sourcecode.c.objc"] * 2, "P2": ["sourcecode.ada", "sourcecode.pascal"] + ["sourcecode.c.objc"] * 2,
                 "P3": ["sourcecode.ada", "sourcecode.pascal"] + ["sourcecode.c.objc"] * 3,
                 "P4": ["sourcecode.rez", "sourcecode.asm"] + ["sourcecode.c.objc"] * 3,
                 "P5": ["sourcecode.dylan", "sourcecode.nqc", "sourcecode.asm.asm"] + ["sourcecode.swift"] * 2 + ["sourcecode.c.c"] * 2}


def language_pool(cases=None):
    targets = Targets()
    children, count = "", 0
    for name, file_types in (cases or LANGUAGE_POOL).items():
        target, _ = targets.add(name, "com.apple.product-type.framework", {"GENERATE_INFOPLIST_FILE": "YES"})
        build_files = ""
        for index, file_type in enumerate(file_types):
            count += 1
            reference, build_file = f"A{count:023d}", f"E{count:023d}"
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {name}/f{index}; "
                                f"sourceTree = \"<group>\"; }};\n\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
            children += f"\t\t\t\t{reference},\n"
            build_files += f"{build_file}, "
        count += 1
        targets.objects += (f"\t\tW{count:023d} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build_files}); "
                            f"runOnlyForDeploymentPostprocessing = 0; }};\n")
        targets.phases[target].append(f"W{count:023d}")
    return targets.project(group_children=children)


# None of those explains codegen-file-types: parts of its Sources phase, one target each.
def language_bisect_cases():
    every = ENCODED_FILE_TYPES + ["folder.mlmodelc", "wrapper.mlmodelc", "file.mlmodelc", "folder.rcproject", "file.realitycomposerpro", "file.skybox"]
    hidden = ["sourcecode.ada", "sourcecode.asm", "sourcecode.asm.asm", "sourcecode.dylan", "sourcecode.nqc", "sourcecode.pascal", "sourcecode.rez"]
    objcpp = ["sourcecode.c.h", "sourcecode.cpp.objcpp", "sourcecode.cpp.objcpp.preprocessed", "sourcecode.iig", "sourcecode.lex", "sourcecode.yacc"]
    sources = [t for t in every if t.startswith("sourcecode") or t in ("file.swiftpm-manifest", "net.daringfireball.markdown")]
    return {"Every": every, "FirstHalf": every[:len(every) // 2], "SecondHalf": every[len(every) // 2:], "Sources": sources,
            "EveryButHidden": [t for t in every if t not in hidden], "SourcesButHidden": [t for t in sources if t not in hidden],
            "ObjCppAndHidden": objcpp + hidden, "ObjCppAndAsm": objcpp + ["sourcecode.asm", "sourcecode.asm.asm", "sourcecode.nasm"],
            "SourcesButAsm": [t for t in sources if t not in ("sourcecode.asm", "sourcecode.asm.asm")]}


# language-bisect fits counting files by type rather than by language. Cases where the two differ,
# and each type of language-weights' against one file of each language, for the ties.
def language_type_cases():
    cases = {"SwiftOverObjCpp": ["sourcecode.swift"] * 3 + ["sourcecode.c.h"] * 2 + ["sourcecode.cpp.objcpp"] * 2,
             "ObjCOverC": ["sourcecode.c.objc"] * 3 + ["sourcecode.c.c"] * 2 + ["sourcecode.c", "sourcecode.c.c.preprocessed"],
             "SwiftOverFortran": ["sourcecode.swift"] * 3 + ["sourcecode.fortran"] * 2 + ["sourcecode.fortran.f77"] * 2,
             "ManifestAndSwift": ["file.swiftpm-manifest", "sourcecode.swift", "sourcecode.c.objc"],
             "TypeScriptAndJavaScript": ["sourcecode.typescript", "sourcecode.javascript", "sourcecode.c.objc"]}
    for hidden in ["sourcecode.asm", "sourcecode.asm.asm", "sourcecode.dylan", "sourcecode.nqc", "sourcecode.pascal", "sourcecode.rez", "sourcecode.ada"]:
        for other in LANGUAGE_TIE_TYPES[:-2] + ["sourcecode.c.objc"]:
            cases[f"Tie-{hidden[11:]}-{other}"] = [hidden, other]
    return cases


# language-types: the language that wins a tie is neither the identifier nor the type that sorts
# first. One target for each pair of the types that count for a language, for the whole order.
LANGUAGE_TYPES = ["file.swiftpm-manifest", "net.daringfireball.markdown", "sourcecode.ada", "sourcecode.applescript", "sourcecode.asm",
                  "sourcecode.asm.asm", "sourcecode.asm.llvm", "sourcecode.c", "sourcecode.c.c", "sourcecode.c.c.preprocessed", "sourcecode.c.h",
                  "sourcecode.c.objc", "sourcecode.c.objc.preprocessed", "sourcecode.clips", "sourcecode.cpp", "sourcecode.cpp.cpp",
                  "sourcecode.cpp.cpp.preprocessed", "sourcecode.cpp.h", "sourcecode.cpp.objcpp", "sourcecode.cpp.objcpp.preprocessed",
                  "sourcecode.dtrace", "sourcecode.dylan", "sourcecode.fortran", "sourcecode.fortran.f77", "sourcecode.fortran.f90",
                  "sourcecode.glsl", "sourcecode.iig", "sourcecode.java", "sourcecode.javascript", "sourcecode.lex", "sourcecode.make",
                  "sourcecode.metal", "sourcecode.module-map", "sourcecode.nasm", "sourcecode.nqc", "sourcecode.opencl", "sourcecode.pascal",
                  "sourcecode.protobuf", "sourcecode.rez", "sourcecode.swift", "sourcecode.typescript", "sourcecode.yacc"]


def language_pair_cases():
    return {f"Pair-{a}-{b}": [a, b] for i, a in enumerate(LANGUAGE_TYPES) for b in LANGUAGE_TYPES[i + 1:]}

# mattermost's Localizable.strings variant groups sit in groups whose path is `ar.lproj`, their
# children's path is `Localizable.strings`, and Xcode keeps them. Variant groups in groups with and
# without a `.lproj` path, a variant group with a path of its own, and children relative to the
# project or named for another region; each is (group name, group path, variant group path,
# [(child name, child path, source tree)]), all in Resources.
LPROJ_GROUPS = [
    ("ar.lproj", "x/ar.lproj", None, [("ar", "L1.strings", "<group>")]),
    ("fr.lproj", "fr.lproj", None, [("de", "L2.strings", "<group>")]),
    ("it.lproj", None, None, [("it", "L3.strings", "<group>")]),
    ("es.lproj", "es.lproj", "sub", [("es", "L4.strings", "<group>")]),
    ("other", "other", None, [("pt", "pt.lproj/L5.strings", "SOURCE_ROOT")]),
    ("ja.lproj", "ja.lproj", None, [("ko", "ko.lproj/L6.strings", "<group>")]),
    ("nl.lproj", "y/nl.lproj", None, [("nl", "L7.strings", "<group>"), ("sv", "../sv.lproj/L7.strings", "<group>")]),
    ("pl.lproj", "pl.lproj", None, [("pl", "L8.strings", "<group>"), (None, "L8b.strings", "<group>")]),
]


def lproj_groups():
    targets = Targets()
    app, _ = targets.add("App", APPLICATION, {})
    files, children, listed = {}, "", ""
    for index, (name, path, variant_path, variants) in enumerate(LPROJ_GROUPS, 1):
        references = ""
        for number, (region, child_path, tree) in enumerate(variants, 1):
            reference = f"H{index:02d}{number:021d}"
            on_disk = child_path if tree == "SOURCE_ROOT" else "/".join(p for p in [path, variant_path, child_path] if p)
            files[os.path.normpath(on_disk)] = '"k" = "v";\n'
            named = f"name = {pbx_string(region)}; " if region else ""
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; {named}"
                                f"path = {pbx_string(child_path)}; sourceTree = {pbx_string(tree)}; }};\n")
            references += f"{reference}, "
        variant, group, build_file = f"V{index:023d}", f"G{index:023d}", f"Y{index:023d}"
        variant_attribute = f"path = {variant_path}; " if variant_path else ""
        targets.objects += (f"\t\t{variant} = {{isa = PBXVariantGroup; children = ({references}); name = L{index}.strings; {variant_attribute}sourceTree = \"<group>\"; }};\n"
                            f"\t\t{group} = {{isa = PBXGroup; children = ({variant}, ); name = {pbx_string(name)}; "
                            + (f"path = {pbx_string(path)}; " if path else "") + "sourceTree = \"<group>\"; };\n"
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {variant}; }};\n")
        children += f"\t\t\t\t{group},\n"
        listed += f"{build_file}, "
    targets.objects += f"\t\tW00000000000000000000001 = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({listed}); runOnlyForDeploymentPostprocessing = 0; }};\n"
    targets.phases[app].append("W00000000000000000000001")
    return targets.project(files, group_children=children)


# mattermost's fonts are declared `explicitFileType = undefined; lastKnownFileType = unknown;
# fileEncoding = 9`: Xcode types them `file` from disk and writes no fileTextEncoding, where a
# declared `file` keeps it (file-encodings). Each reference has fileEncoding = 9: (path, declared
# attributes, contents or None for not on disk).
BINARY = "\x00\x01\x02binary\n"
DECLARED_ENCODINGS = [
    ("e01.ttf", "explicitFileType = undefined; lastKnownFileType = unknown;", BINARY),
    ("e02.ttf", "explicitFileType = undefined; lastKnownFileType = unknown;", "plain text\n"),
    ("e03.swift", "explicitFileType = undefined; lastKnownFileType = unknown;", "let a = 1\n"),
    ("e04.ttf", "explicitFileType = undefined; lastKnownFileType = unknown;", None),
    ("e05.ttf", "lastKnownFileType = file;", BINARY),
    ("e06.ttf", "lastKnownFileType = file;", "plain text\n"),
    ("e07.ttf", "lastKnownFileType = text;", BINARY),
    ("e08.ttf", "lastKnownFileType = unknown;", BINARY),
    ("e09.ttf", "explicitFileType = undefined;", BINARY),
    ("e10.ttf", "", BINARY),
    ("e11.dat", "lastKnownFileType = nomac.unknown;", BINARY),
    ("e12.dat", "lastKnownFileType = nomac.unknown;", "plain text\n"),
    ("e13.txt", "explicitFileType = undefined; lastKnownFileType = unknown;", BINARY),
    ("e14", "explicitFileType = undefined; lastKnownFileType = unknown;", "plain text\n"),
    ("e15.ttf", "explicitFileType = file;", BINARY),
    ("e16.png", "lastKnownFileType = nomac.unknown;", "plain text\n"),
]


def declared_encodings():
    targets = Targets()
    targets.add("App", APPLICATION, {})
    files, children = {}, ""
    for index, (path, declared, contents) in enumerate(DECLARED_ENCODINGS, 1):
        reference = f"A{index:023d}"
        if contents is not None:
            files[f"Fonts/{path}"] = contents
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; {declared} fileEncoding = 9; includeInIndex = 0; "
                            f"path = {pbx_string('Fonts/' + path)}; sourceTree = \"<group>\"; }};\n")
        children += f"\t\t\t\t{reference},\n"
    return targets.project(files, group_children=children)


def declared_language_2():
    targets = Targets()
    files, children, count = {}, "", 0
    for name, members in LANGUAGE_CASES:
        target, _ = targets.add(name, "com.apple.product-type.framework", {"GENERATE_INFOPLIST_FILE": "YES"})
        build_files = ""
        for path, declared, on_disk, explicit in members:
            count += 1
            reference, build_file = f"A{count:023d}", f"E{count:023d}"
            if on_disk:
                files[f"{name}/{path}"] = "let x = 1\n"
            key = "explicitFileType" if explicit else "lastKnownFileType"
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; {key} = {declared}; path = {pbx_string(name + '/' + path)}; "
                                f"sourceTree = \"<group>\"; }};\n\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
            children += f"\t\t\t\t{reference},\n"
            build_files += f"{build_file}, "
        phase = f"W{count:023d}"
        targets.objects += (f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({build_files}); "
                            f"runOnlyForDeploymentPostprocessing = 0; }};\n")
        targets.phases[target].append(phase)
    return targets.project(files, group_children=children)


# The triage of nextcloud found that knownRegions gains the regions of ordinary variant groups'
# children too. Two synchronized folders and four variant groups, in a group and at the top,
# with new regions, regions the project or an earlier group has, `mul`, Base, and a child with
# no name; only the first variant group is in a target.
def regions_classic():
    targets = Targets()
    app, _ = targets.add("App", APPLICATION, {})
    files = {"Alpha/af.lproj/S.strings": '"k" = "v";\n', "Beta/ko.lproj/S.strings": '"k" = "v";\n'}
    groups = {"V1": ("L.strings", [("en", None), ("zu", None), ("fr", None)]),
              "V2": ("M.strings", [("Base", None), ("mul", None), ("de", None), (None, "ja"), ("es-419", None)]),
              "V3": ("Main.storyboard", [("Base", None), ("it", None)]),
              "V4": ("Q.strings", [("af", None), ("pt-BR", None)])}
    references = {}
    for key, (name, variants) in groups.items():
        children = ""
        for index, (region, unnamed) in enumerate(variants, 1):
            folder = region or unnamed
            file_name = name if region == "Base" or name.endswith(".strings") else name.rsplit(".", 1)[0] + ".strings"
            path = f"{folder}.lproj/{file_name}"
            prefix = "G/" if key == "V1" else ""
            files[prefix + path] = '"k" = "v";\n' if file_name.endswith(".strings") else "<document/>\n"
            file_type = "text.plist.strings" if file_name.endswith(".strings") else "file.storyboard"
            named = f"name = {pbx_string(region)}; " if region else ""
            reference = f"A{key}{index:021d}"
            targets.objects += f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; {named}path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n"
            children += f"\t\t\t\t{reference},\n"
        references[key] = f"G{key}{0:021d}"
        targets.objects += (f"\t\t{references[key]} = {{\n\t\t\tisa = PBXVariantGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n"
                            f"\t\t\tname = {pbx_string(name)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    resources, build_file = targets.next_id("B"), targets.next_id("E")
    targets.objects += f"""		{build_file} = {{isa = PBXBuildFile; fileRef = {references["V1"]}; }};
		{resources} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({build_file}, ); runOnlyForDeploymentPostprocessing = 0; }};
		S00000000000000000000001 = {{isa = PBXFileSystemSynchronizedRootGroup; path = Alpha; sourceTree = "<group>"; }};
		S00000000000000000000002 = {{isa = PBXFileSystemSynchronizedRootGroup; path = Beta; sourceTree = "<group>"; }};
		S00000000000000000000003 = {{isa = PBXGroup; children = ({references["V1"]}, ); path = G; sourceTree = "<group>"; }};
"""
    targets.phases[app].append(resources)
    children = "".join(f"\t\t\t\t{reference},\n" for reference in ["S00000000000000000000001", "S00000000000000000000003", references["V2"],
                                                                 references["V3"], "S00000000000000000000002", references["V4"]])
    return targets.project(files, group_children=children)

def coverage():
    # cwa's ENAScreenshots scheme enables code coverage, but its default test plan sets
    # "codeCoverage": false, and xcodebuild reports no CLANG_COVERAGE_MAPPING for it. Each scheme
    # here builds App for running and differs in how coverage and tests are set.
    targets = Targets()
    host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}
    app, _ = targets.add("App", APPLICATION, {})
    tests, _ = targets.add("AppTests", UNIT_TEST, host)
    targets.depend(tests, app, "App")
    container = "container:P.xcodeproj"
    build = [(app, "App.app", "App", container, True)]
    testable = [(tests, "AppTests.xctest", "AppTests", container)]

    def plan(options, with_targets=True):
        test_targets = [{"target": {"containerPath": container, "identifier": tests, "name": "AppTests"}}] if with_targets else []
        # Xcode ignores a plan's options when a configuration's id is not a UUID.
        return json.dumps({"configurations": [{"id": "A11977F5-134B-4CB5-B798-B2F3F30138CD", "name": "Configuration 1", "options": {}}],
                           "defaultOptions": options, "testTargets": test_targets, "version": 1}, indent=2) + "\n"

    files = {
        "On.xctestplan": plan({"codeCoverage": True}), "Off.xctestplan": plan({"codeCoverage": False}),
        "Unset.xctestplan": plan({}), "Targets.xctestplan": plan({"codeCoverage": {"targets": [{"containerPath": container, "identifier": app, "name": "App"}]}}),
        "OnWithoutTests.xctestplan": plan({"codeCoverage": True}, with_targets=False), "Plans/On.xctestplan": plan({"codeCoverage": True}),
        "NotUUID.xctestplan": plan({"codeCoverage": True}).replace("A11977F5-134B-4CB5-B798-B2F3F30138CD", "C1"),
    }
    schemes = {
        "S01-Testables": dict(coverage=True, testables=testable),
        "S02-NoTestables": dict(coverage=True),
        "S03-Skipped": dict(coverage=True, testables=testable, skipped=True),
        "S04-PlanOnSchemeOff": dict(plans=[("container:On.xctestplan", True)]),
        "S05-PlanOffSchemeOn": dict(coverage=True, plans=[("container:Off.xctestplan", True)], testables=testable),
        "S06-PlanUnsetSchemeOn": dict(coverage=True, plans=[("container:Unset.xctestplan", True)]),
        "S07-PlanTargets": dict(plans=[("container:Targets.xctestplan", True)]),
        "S08-NoDefaultPlan": dict(plans=[("container:On.xctestplan", False), ("container:Off.xctestplan", False)]),
        "S09-SecondPlanDefault": dict(plans=[("container:Off.xctestplan", False), ("container:On.xctestplan", True)]),
        "S10-MissingPlan": dict(coverage=True, plans=[("container:Missing.xctestplan", True)], testables=testable),
        "S11-PlanWithoutTests": dict(plans=[("container:OnWithoutTests.xctestplan", True)]),
        "S12-PlanOnSchemeOn": dict(coverage=True, plans=[("container:On.xctestplan", True)]),
        "S13-PlanTargetsSchemeOn": dict(coverage=True, plans=[("container:Targets.xctestplan", True)]),
        "S14-NoDefaultPlanFirstOn": dict(coverage=True, plans=[("container:On.xctestplan", False), ("container:Off.xctestplan", False)]),
        "S15-NoDefaultPlanFirstOff": dict(coverage=True, plans=[("container:Off.xctestplan", False), ("container:On.xctestplan", False)]),
        "S16-SecondPlanDefaultOn": dict(coverage=True, plans=[("container:Off.xctestplan", False), ("container:On.xctestplan", True)]),
        "S17-PlanWithoutTestsSchemeOn": dict(coverage=True, plans=[("container:OnWithoutTests.xctestplan", True)]),
        # As cwa's ENA and ENAScreenshots schemes: coverage for specified targets, and test plans.
        "S18-SpecifiedPlanTargets": dict(coverage=True, only_specified=True, coverage_targets=[build[0][:4]], plans=[("container:Targets.xctestplan", True)]),
        "S19-SpecifiedPlanOff": dict(coverage=True, only_specified=True, coverage_targets=[build[0][:4]], plans=[("container:Off.xctestplan", True)]),
        "S20-SpecifiedPlanOn": dict(coverage=True, only_specified=True, coverage_targets=[build[0][:4]], plans=[("container:On.xctestplan", True)]),
        "S21-SpecifiedNoPlans": dict(coverage=True, only_specified=True, coverage_targets=[build[0][:4]], testables=testable),
        "S22-TargetsOnlyPlanTargets": dict(coverage=True, coverage_targets=[build[0][:4]], plans=[("container:Targets.xctestplan", True)]),
        "S23-SpecifiedOffPlanTargets": dict(only_specified=True, coverage_targets=[build[0][:4]], plans=[("container:Targets.xctestplan", True)]),
        "S24-PlanOnTestables": dict(coverage=True, plans=[("container:On.xctestplan", True)], testables=testable),
        "S25-PlanTargetsTestables": dict(coverage=True, plans=[("container:Targets.xctestplan", True)], testables=testable),
        "S26-SpecifiedPlanTargetsTestables": dict(coverage=True, only_specified=True, coverage_targets=[build[0][:4]],
                                                  plans=[("container:Targets.xctestplan", True)], testables=testable),
        "S27-PlanInFolder": dict(coverage=True, plans=[("container:Plans/On.xctestplan", True)], testables=testable),
        "S28-PlanOffSchemeOffTestables": dict(plans=[("container:On.xctestplan", True)], testables=testable),
        # Scheme format 2.0, as cwa's schemes.
        "S29-V2PlanOn": dict(version="2.0", coverage=True, plans=[("container:On.xctestplan", True)]),
        "S30-V2PlanOff": dict(version="2.0", coverage=True, plans=[("container:Off.xctestplan", True)]),
        "S31-V2PlanOnSchemeOff": dict(version="2.0", plans=[("container:On.xctestplan", True)]),
        "S32-V2PlanTargets": dict(version="2.0", coverage=True, plans=[("container:Targets.xctestplan", True)]),
        "S33-V2PlanUnset": dict(version="2.0", coverage=True, plans=[("container:Unset.xctestplan", True)]),
        "S34-V2NoDefaultPlanFirstOn": dict(version="2.0", coverage=True, plans=[("container:On.xctestplan", False), ("container:Off.xctestplan", False)]),
        "S35-V2MissingPlan": dict(version="2.0", coverage=True, plans=[("container:Missing.xctestplan", True)]),
        "S36-V2NoPlans": dict(version="2.0", coverage=True),
        "S37-PlanNotUUID": dict(coverage=True, plans=[("container:NotUUID.xctestplan", True)]),
        "S38-PlanUnsetSchemeOff": dict(plans=[("container:Unset.xctestplan", True)]),
        "S39-NoPlansSchemeOff": dict(testables=testable),
    }
    for name, options in schemes.items():
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(build=build, launch=("product", build[0][:4]), **options)
    return targets.project(files)


def coverage_autocreated_plan():
    # pocket-casts' "Pocket Casts Prototype Build" scheme tests a bundle with
    # shouldAutocreateTestPlan and no codeCoverageEnabled, and xcodebuild reports
    # CLANG_COVERAGE_MAPPING for it. Each scheme here builds App for running and sets
    # shouldAutocreateTestPlan, except the control A07, and differs in its tests and coverage.
    targets = Targets()
    host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}
    app, _ = targets.add("App", APPLICATION, {})
    tests, _ = targets.add("AppTests", UNIT_TEST, host)
    targets.depend(tests, app, "App")
    container = "container:P.xcodeproj"
    build = [(app, "App.app", "App", container, True)]
    testable = [(tests, "AppTests.xctest", "AppTests", container)]

    def plan(options):
        return json.dumps({"configurations": [{"id": "A11977F5-134B-4CB5-B798-B2F3F30138CD", "name": "Configuration 1", "options": {}}],
                           "defaultOptions": options, "testTargets": [{"target": {"containerPath": container, "identifier": tests, "name": "AppTests"}}],
                           "version": 1}, indent=2) + "\n"

    files = {"On.xctestplan": plan({"codeCoverage": True}), "Off.xctestplan": plan({"codeCoverage": False})}
    schemes = {
        "A01-Testables": dict(autocreate_plan=True, testables=testable),
        "A02-NoTestables": dict(autocreate_plan=True),
        "A03-Skipped": dict(autocreate_plan=True, testables=testable, skipped=True),
        "A04-CoverageOn": dict(autocreate_plan=True, coverage=True, testables=testable),
        "A05-PlanOff": dict(autocreate_plan=True, plans=[("container:Off.xctestplan", True)], testables=testable),
        "A06-PlanOn": dict(autocreate_plan=True, plans=[("container:On.xctestplan", True)]),
        "A07-TestablesWithoutAutocreate": dict(testables=testable),
        "A08-Specified": dict(autocreate_plan=True, only_specified=True, coverage_targets=[build[0][:4]], testables=testable),
        "A09-Version2": dict(autocreate_plan=True, testables=testable, version="2.0"),
    }
    for name, arguments in schemes.items():
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(build=build, **arguments)
    return targets.project(files)

def provisioning_style(project_style=None):
    # cwa's provisioningStyle follows each configuration's CODE_SIGN_STYLE (Manual: 1), where
    # netnewswire's follows the targets' ProvisioningStyle attribute. Each target differs in
    # where the two are set; `project_style` sets CODE_SIGN_STYLE at the project level.
    targets = Targets()
    files = {"Manual.xcconfig": "CODE_SIGN_STYLE = Manual\n"}
    targets.objects += '\t\tA00000000000000000000001 /* Manual.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Manual.xcconfig; sourceTree = "<group>"; };\n'
    variants = [
        ("AttrManual", "Manual", {}, {}, False), ("AttrAutomatic", "Automatic", {}, {}, False),
        ("SettingManual", None, {"CODE_SIGN_STYLE": "Manual"}, {"CODE_SIGN_STYLE": "Manual"}, False),
        ("SettingAutomatic", None, {"CODE_SIGN_STYLE": "Automatic"}, {"CODE_SIGN_STYLE": "Automatic"}, False),
        ("AttrManualSettingAutomatic", "Manual", {"CODE_SIGN_STYLE": "Automatic"}, {"CODE_SIGN_STYLE": "Automatic"}, False),
        ("AttrAutomaticSettingManual", "Automatic", {"CODE_SIGN_STYLE": "Manual"}, {"CODE_SIGN_STYLE": "Manual"}, False),
        ("DebugManual", None, {"CODE_SIGN_STYLE": "Manual"}, {}, False),
        ("FromXcconfig", None, {}, {}, True),
        ("Macro", None, {"CODE_SIGN_STYLE": pbx_string("$(NOMAC_STYLE)"), "NOMAC_STYLE": "Manual"}, {"CODE_SIGN_STYLE": pbx_string("$(NOMAC_STYLE)"), "NOMAC_STYLE": "Manual"}, False),
        ("Lowercase", None, {"CODE_SIGN_STYLE": "manual"}, {"CODE_SIGN_STYLE": "manual"}, False),
        ("Nothing", None, {}, {}, False),
    ]
    for name, attribute, debug, release, xcconfig in variants:
        index = len(targets.ids) + 1
        values = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        list_id = f"H{index:023d}"
        configuration_list = configurations(list_id, f"G{index:023d}", f"J{index:023d}", {**values, **debug}, {**values, **release},
                                            "A00000000000000000000001 /* Manual.xcconfig */" if xcconfig else None)
        target, _ = targets.add(name, APPLICATION, {}, configuration_list=configuration_list, list_ids=[list_id])
        if attribute:
            targets.attribute(target, f"\t\t\t\t\t\tProvisioningStyle = {attribute};\n")
    entries = None
    if project_style:
        entries = ([(name, {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "CODE_SIGN_STYLE": project_style}) for name in ["Debug", "Release"]], "Release")
    return targets.project(files, project_configurations=entries, group_children="\t\t\t\tA00000000000000000000001 /* Manual.xcconfig */,\n")


def provisioning_defaults():
    # provisioning-style's targets are iOS apps; a macOS command-line tool with neither
    # CODE_SIGN_STYLE nor a ProvisioningStyle attribute has provisioningStyle 1 (copy-files).
    # One target per product type and SDK, none setting either, then macOS tools that set
    # one signing setting each.
    targets = Targets()
    for sdk in ["iphoneos", "macosx"]:
        for product_type in ["application", "framework", "library.static", "library.dynamic", "tool", "bundle", "bundle.unit-test",
                             "app-extension", "xpc-service"]:
            name = product_type.replace(".", "-").title().replace("-", "") + ("Mac" if sdk == "macosx" else "iOS")
            targets.add(name, f"com.apple.product-type.{product_type}", {}, sdk=sdk)
    tool = "com.apple.product-type.tool"
    targets.add("ToolStyleAutomatic", tool, {"CODE_SIGN_STYLE": "Automatic"}, sdk="macosx")
    attributed, _ = targets.add("ToolAttributeAutomatic", tool, {}, sdk="macosx")
    targets.attribute(attributed, "\t\t\t\t\t\tProvisioningStyle = Automatic;\n")
    targets.add("ToolIdentityDash", tool, {"CODE_SIGN_IDENTITY": pbx_string("-")}, sdk="macosx")
    targets.add("ToolIdentityDeveloper", tool, {"CODE_SIGN_IDENTITY": pbx_string("Apple Development")}, sdk="macosx")
    targets.add("ToolTeam", tool, {"DEVELOPMENT_TEAM": "ABCDE12345"}, sdk="macosx")
    targets.add("ToolNoBundleIdentifier", tool, {"PRODUCT_BUNDLE_IDENTIFIER": pbx_string("")}, sdk="macosx")
    targets.add("ToolNoInfoPlist", tool, {"GENERATE_INFOPLIST_FILE": "NO"}, sdk="macosx")
    targets.add("ToolSupportedPlatforms", tool, {"SUPPORTED_PLATFORMS": pbx_string("iphoneos iphonesimulator")}, sdk="macosx")
    # The identity and the team, each way they can be set, on both SDKs.
    identity, team, specifier = "CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER"
    for name, settings, sdk in [
        ("AppIdentityDash", {identity: pbx_string("-")}, "iphoneos"), ("AppIdentityEmpty", {identity: pbx_string("")}, "iphoneos"),
        ("AppTeam", {team: "ABCDE12345"}, "iphoneos"), ("AppIdentityDashTeam", {identity: pbx_string("-"), team: "ABCDE12345"}, "iphoneos"),
        ("ToolIdentityEmpty", {identity: pbx_string("")}, "macosx"),
        ("ToolIdentityDeveloperID", {identity: pbx_string("Developer ID Application")}, "macosx"),
        ("ToolIdentityDashTeam", {identity: pbx_string("-"), team: "ABCDE12345"}, "macosx"),
        ("ToolTeamEmpty", {team: pbx_string("")}, "macosx"),
        ("ToolIdentityConditional", {pbx_string(identity + "[sdk=macosx*]"): pbx_string("Apple Development")}, "macosx"),
        ("ToolIdentityMacro", {identity: pbx_string("$(NOMAC_IDENTITY)"), "NOMAC_IDENTITY": pbx_string("Apple Development")}, "macosx"),
        ("ToolTeamMacro", {team: pbx_string("$(NOMAC_TEAM)"), "NOMAC_TEAM": "ABCDE12345"}, "macosx"),
        ("ToolProfileSpecifier", {"PROVISIONING_PROFILE_SPECIFIER": pbx_string("Profile")}, "macosx"),
        ("ToolStyleManualTeam", {"CODE_SIGN_STYLE": "Manual", team: "ABCDE12345"}, "macosx"),
    ]:
        targets.add(name, tool if sdk == "macosx" else APPLICATION, settings, sdk=sdk)
    # Debug signs with a development identity, Release does not set one.
    index = len(targets.ids) + 1
    common = {**APP_SETTINGS, "SDKROOT": "macosx", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
    list_id = f"H{index:023d}"
    targets.add("ToolDebugIdentity", tool, {}, configuration_list=configurations(
        list_id, f"G{index:023d}", f"J{index:023d}", {**common, identity: pbx_string("Apple Development")}, common), list_ids=[list_id])
    # Release signs with a development identity; then the same with Debug as the target's default
    # configuration, and with Debug and Release in the other order.
    for name, default, order in [("ToolReleaseIdentity", "Release", ("Debug", "Release")), ("ToolReleaseIdentityDefaultDebug", "Debug", ("Debug", "Release")),
                                 ("ToolReleaseIdentityFirst", "Debug", ("Release", "Debug"))]:
        index = len(targets.ids) + 1
        common = {**APP_SETTINGS, "SDKROOT": "macosx", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        values = {"Debug": common, "Release": {**common, identity: pbx_string("Apple Development")}}
        entries = [(f"{letter}{index:023d}", configuration, values[configuration]) for letter, configuration in zip("GJ", order)]
        targets.add(name, tool, {}, configuration_list=named_configurations(f"H{index:023d}", entries, default), list_ids=[f"H{index:023d}"])
    # Debug sets the style and signs to run locally, Release sets neither and signs with a
    # development identity; then the same with Debug signing with one too.
    for name, debug_identity in [("ToolDebugStyle", None), ("ToolDebugStyleIdentity", "Apple Development")]:
        index = len(targets.ids) + 1
        common = {**APP_SETTINGS, "SDKROOT": "macosx", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        debug = {**common, "CODE_SIGN_STYLE": "Automatic", **({identity: pbx_string(debug_identity)} if debug_identity else {})}
        targets.add(name, tool, {}, configuration_list=configurations(
            f"H{index:023d}", f"G{index:023d}", f"J{index:023d}", debug, {**common, identity: pbx_string("Apple Development")}), list_ids=[f"H{index:023d}"])
    # Distribution identities on iOS (mastodon's Release: Manual, with iPhone Distribution for
    # iphoneos; its Profile sets nothing and has provisioningStyle 1).
    for name, debug, release in [
        ("AppAppleDistribution", {identity: pbx_string("Apple Distribution")}, {identity: pbx_string("Apple Distribution")}),
        ("AppIPhoneDistribution", {identity: pbx_string("iPhone Distribution")}, {identity: pbx_string("iPhone Distribution")}),
        ("AppIPhoneDeveloper", {identity: pbx_string("iPhone Developer")}, {identity: pbx_string("iPhone Developer")}),
        ("AppReleaseDistribution", {}, {identity: pbx_string("iPhone Distribution")}),
        ("AppReleaseDistributionConditional", {}, {pbx_string(identity + "[sdk=iphoneos*]"): pbx_string("iPhone Distribution")}),
        ("AppReleaseManualDistribution", {}, {"CODE_SIGN_STYLE": "Manual", identity: pbx_string("Apple Distribution")}),
        ("AppReleaseManualDevelopment", {}, {"CODE_SIGN_STYLE": "Manual", identity: pbx_string("Apple Development")}),
        ("AppReleaseAutomaticDistribution", {}, {"CODE_SIGN_STYLE": "Automatic", identity: pbx_string("Apple Distribution")}),
        # Provisioning profiles, as mastodon's Release names one for iphoneos.
        ("AppReleaseSpecifier", {}, {specifier: pbx_string("Profile")}),
        ("AppReleaseSpecifierConditional", {}, {pbx_string(specifier + "[sdk=iphoneos*]"): pbx_string("Profile")}),
        ("AppReleaseSpecifierEmpty", {}, {specifier: pbx_string("")}),
        ("AppReleaseProfile", {}, {"PROVISIONING_PROFILE": pbx_string("00000000-0000-0000-0000-000000000000")}),
        ("AppDebugAutomaticReleaseSpecifier", {"CODE_SIGN_STYLE": "Automatic"}, {specifier: pbx_string("Profile")}),
        ("AppReleaseManualSpecifier", {}, {"CODE_SIGN_STYLE": "Manual", specifier: pbx_string("Profile")}),
        ("AppMastodonRelease", {"CODE_SIGN_STYLE": "Automatic", team: "ABCDE12345"},
         {"CODE_SIGN_STYLE": "Manual", pbx_string(identity + "[sdk=iphoneos*]"): pbx_string("iPhone Distribution"),
          pbx_string(specifier + "[sdk=iphoneos*]"): pbx_string("match AppStore org.nomac"), team: "ABCDE12345"}),
    ]:
        index = len(targets.ids) + 1
        common = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        targets.add(name, APPLICATION, {}, configuration_list=configurations(
            f"H{index:023d}", f"G{index:023d}", f"J{index:023d}", {**common, **debug}, {**common, **release}), list_ids=[f"H{index:023d}"])
    # Aggregate targets on each SDK.
    for index, sdk in enumerate(["macosx", "iphoneos"], 1):
        target, list_id = f"K{index:023d}", f"M{index:023d}"
        targets.ids.append(target)
        targets.objects += configurations(list_id, f"N{index:023d}", f"O{index:023d}", {"SDKROOT": sdk}) + f"""		{target} = {{
			isa = PBXAggregateTarget;
			buildConfigurationList = {list_id};
			buildPhases = (
			);
			dependencies = (
			);
			name = Aggregate{"Mac" if sdk == "macosx" else "iOS"};
			productName = Aggregate;
		}};
"""
    return targets.project()


def observe_provisioning_defaults(run):
    project = json.loads(run("list", "-list", "-json").stdout or "{}").get("project", {})
    for name in project.get("targets", []):
        run(f"target-{name}", "-showBuildSettings", "-target", name, "-configuration", "Debug")


# (target name, [(file name, file type, phase)]), phase one of Headers, Sources, Resources or
# None (in the group tree only).
LANGUAGE_TARGETS = [
    ("OneHeader", [("a.h", "sourcecode.c.h", "Headers")]),
    ("HeaderAndC", [("a.h", "sourcecode.c.h", "Headers"), ("a.c", "sourcecode.c.c", "Sources")]),
    ("TwoHeadersAndC", [("a.h", "sourcecode.c.h", "Headers"), ("b.h", "sourcecode.c.h", "Headers"), ("a.c", "sourcecode.c.c", "Sources")]),
    ("HeaderAndSwift", [("a.h", "sourcecode.c.h", "Headers"), ("a.swift", "sourcecode.swift", "Sources")]),
    ("HeaderAndObjC", [("a.h", "sourcecode.c.h", "Headers"), ("a.m", "sourcecode.c.objc", "Sources")]),
    ("HeaderAndObjCpp", [("a.h", "sourcecode.c.h", "Headers"), ("a.mm", "sourcecode.cpp.objcpp", "Sources")]),
    ("HeaderInSources", [("a.h", "sourcecode.c.h", "Sources"), ("b.h", "sourcecode.c.h", "Sources"), ("a.c", "sourcecode.c.c", "Sources")]),
    ("CppHeaders", [("a.hpp", "sourcecode.cpp.h", "Headers"), ("b.hpp", "sourcecode.cpp.h", "Headers"), ("a.c", "sourcecode.c.c", "Sources")]),
    ("HeaderInGroupOnly", [("a.h", "sourcecode.c.h", None), ("b.h", "sourcecode.c.h", None), ("a.c", "sourcecode.c.c", "Sources")]),
    ("SwiftAndObjC", [("a.swift", "sourcecode.swift", "Sources"), ("a.m", "sourcecode.c.objc", "Sources")]),
    ("CAndObjC", [("a.c", "sourcecode.c.c", "Sources"), ("a.m", "sourcecode.c.objc", "Sources")]),
    ("CAndCpp", [("a.c", "sourcecode.c.c", "Sources"), ("a.cpp", "sourcecode.cpp.cpp", "Sources")]),
    ("ObjCAndObjCpp", [("a.m", "sourcecode.c.objc", "Sources"), ("a.mm", "sourcecode.cpp.objcpp", "Sources")]),
    ("SwiftAndC", [("a.swift", "sourcecode.swift", "Sources"), ("a.c", "sourcecode.c.c", "Sources")]),
    ("SwiftAndCpp", [("a.swift", "sourcecode.swift", "Sources"), ("a.cpp", "sourcecode.cpp.cpp", "Sources")]),
    ("ObjCAndSwift", [("a.m", "sourcecode.c.objc", "Sources"), ("a.swift", "sourcecode.swift", "Sources")]),
    ("JavaScriptAndSwift", [("a.js", "sourcecode.javascript", "Resources"), ("a.swift", "sourcecode.swift", "Sources")]),
    ("MetalAndSwift", [("a.metal", "sourcecode.metal", "Sources"), ("a.swift", "sourcecode.swift", "Sources")]),
] + [(f"Only-{file_type}", [("a", file_type, "Sources")]) for file_type in ENCODED_FILE_TYPES + [
    "text.script.python", "text.script.ruby", "text.script.perl", "text.script.csh", "text.script.php",
]]


def source_languages():
    # cwa's CWASQLite framework, two .h headers and one .c source, reports Objective-C++.
    targets = Targets()
    children, count = "", 0
    for name, files in LANGUAGE_TARGETS:
        phases = {"Headers": "PBXHeadersBuildPhase", "Sources": "PBXSourcesBuildPhase", "Resources": "PBXResourcesBuildPhase"}
        members = {phase: [] for phase in phases}
        for file_name, file_type, phase in files:
            count += 1
            reference, build_file = f"A{count:023d}", f"Z{count:023d}"
            targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; "
                                f"path = {pbx_string(name + '/' + file_name)}; sourceTree = \"<group>\"; }};\n")
            children += f"\t\t\t\t{reference},\n"
            if phase:
                targets.objects += f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n"
                members[phase].append(build_file)
        target, _ = targets.add(name, "com.apple.product-type.framework", {"GENERATE_INFOPLIST_FILE": "YES"})
        for phase, isa in phases.items():
            count += 1
            phase_id = f"W{count:023d}"
            listed = "".join(f"\t\t\t\t{member},\n" for member in members[phase])
            targets.objects += (f"\t\t{phase_id} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
                                f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
            targets.phases[target].append(phase_id)
    return targets.project(group_children=children)


# (compiler specification, file type, file patterns) of the unnamed build rules `build-rules`
# gives one target each.
BUILD_RULES = [
    ("com.apple.compilers.proxy.script", "pattern.proxy", "*.secret"),
    ("com.apple.compilers.proxy.script", "pattern.proxy", "*.a *.b"),
    ("com.apple.compilers.proxy.script", "sourcecode.c.c", None),
    ("com.apple.compilers.proxy.script", "text.json", None),
    ("com.apple.compilers.llvm.clang.1_0", "pattern.proxy", "*.x"),
    ("com.apple.compilers.llvm.clang.1_0", "sourcecode.c.c", None),
    ("com.apple.xcode.tools.swift.compiler", "sourcecode.swift", None),
    ("com.apple.xcode.tools.ibtool.compiler", "file.xib", None),
    ("com.apple.compilers.yacc", "sourcecode.yacc", None),
    ("com.apple.build-tasks.copy-png-file", "image.png", None),
    ("com.apple.compilers.proxy.script", "pattern.proxy", ""),
] + [(compiler, "pattern.proxy", "*.x") for compiler in [
    "com.apple.build-tasks.compile-rk-assets.xcplugin",
    "com.apple.build-tasks.compile-scenekit-shadercache",
    "com.apple.build-tasks.compile-skybox.xcplugin",
    "com.apple.build-tasks.copy-plist-file",
    "com.apple.build-tasks.copy-png-file",
    "com.apple.build-tasks.copy-scenekit-assets",
    "com.apple.build-tasks.copy-strings-file",
    "com.apple.build-tasks.copy-tiff-file",
    "com.apple.build-tasks.generate-texture-atlas.xcplugin",
    "com.apple.build-tasks.ls-register-url",
    "com.apple.build-tools.codesign",
    "com.apple.build-tools.module-verifier-input-generator",
    "com.apple.build-tools.modules-verifier",
    "com.apple.build-tools.platform.validate",
    "com.apple.build-tools.strip",
    "com.apple.build-tools.swift-abi-checker",
    "com.apple.build-tools.swift-abi-generation",
    "com.apple.build-tools.swift-stdlib-tool",
    "com.apple.build-tools.tapi.installapi",
    "com.apple.build-tools.tapi.stubify",
    "com.apple.commands.shell-script",
    "com.apple.compilers.appextension-plist-generator",
    "com.apple.compilers.appintents-ssu-training",
    "com.apple.compilers.appintentsmetadata",
    "com.apple.compilers.appshortcutstringsmetadata",
    "com.apple.compilers.assetcatalog",
    "com.apple.compilers.clang-stat-cache",
    "com.apple.compilers.coreml",
    "com.apple.compilers.cpp",
    "com.apple.compilers.documentation",
    "com.apple.compilers.documentation.objc-symbol-extract",
    "com.apple.compilers.documentation.swift-symbol-extract",
    "com.apple.compilers.dtrace",
    "com.apple.compilers.extract-appextensionpoints",
    "com.apple.compilers.gcc",
    "com.apple.compilers.iconutil",
    "com.apple.compilers.iig",
    "com.apple.compilers.instruments-package-builder",
    "com.apple.compilers.intents",
    "com.apple.compilers.lex",
    "com.apple.compilers.llvm.clang.1_0",
    "com.apple.compilers.llvm.clang.1_0.analyzer",
    "com.apple.compilers.llvm.clang.1_0.astbuilder",
    "com.apple.compilers.llvm.clang.1_0.compiler",
    "com.apple.compilers.metal",
    "com.apple.compilers.metal-linker",
    "com.apple.compilers.mig",
    "com.apple.compilers.model.coredata",
    "com.apple.compilers.model.coredatamapping",
    "com.apple.compilers.opencl",
    "com.apple.compilers.osacompile",
    "com.apple.compilers.pbxcp",
    "com.apple.compilers.process-xcappextensionpoints",
    "com.apple.compilers.referenceobject",
    "com.apple.compilers.rez",
    "com.apple.compilers.scntool",
    "com.apple.compilers.tiffutil",
    "com.apple.compilers.xcstrings",
    "com.apple.compilers.yacc",
    "com.apple.pbx.linkers.ld",
    "com.apple.pbx.linkers.libtool",
    "com.apple.pbx.linkers.resmerger",
    "com.apple.tools.ditto",
    "com.apple.tools.dsymutil",
    "com.apple.tools.generate-app-playground-asset-catalog",
    "com.apple.tools.info-plist-utility",
    "com.apple.tools.mkdir",
    "com.apple.tools.plutil",
    "com.apple.tools.product-pkg-utility",
    "com.apple.tools.symlink",
    "com.apple.tools.touch",
    "com.apple.tools.validate-embedded-binary-utility",
    "com.apple.xcode.linkers.lipo",
    "com.apple.xcode.tools.ibtool.compiler",
    "com.apple.xcode.tools.ibtool.postprocessor",
    "com.apple.xcode.tools.ibtool.storyboard.compiler",
    "com.apple.xcode.tools.ibtool.storyboard.linker",
    "com.apple.xcode.tools.ibtool.storyboard.postprocessor",
    "com.apple.xcode.tools.swift.compiler",
    "org.swift.linkers.object-library-assembler",
    "org.swift.test-entry-point-generator",
    "public.build-task.unifdef",
]] + [("com.apple.compilers.proxy.script", file_type, None) for file_type in ENCODED_FILE_TYPES]


def build_rules():
    # gomap's build rule has no name; the PIF names it "Files '*.secret' using Script".
    targets = Targets()
    for index, (compiler, file_type, patterns) in enumerate(BUILD_RULES, 1):
        rule = f"B{index:023d}"
        pattern_line = f"\t\t\tfilePatterns = {pbx_string(patterns)};\n" if patterns is not None else ""
        targets.objects += (f"\t\t{rule} = {{\n\t\t\tisa = PBXBuildRule;\n\t\t\tcompilerSpec = {compiler};\n{pattern_line}"
                            f"\t\t\tfileType = {pbx_string(file_type)};\n\t\t\tinputFiles = (\n\t\t\t);\n\t\t\tisEditable = 1;\n"
                            f"\t\t\toutputFiles = (\n\t\t\t);\n\t\t\tscript = \"true\\n\";\n\t\t}};\n")
        target, _ = targets.add(f"Rule{index:03d}", APPLICATION, {})
        targets.rules = getattr(targets, "rules", {})
        targets.rules[target] = rule
    return targets.project()



def pbx_list(items):
    """`items` as a property-list array of quoted strings."""
    return "(\n" + "".join(f"\t\t\t\t{pbx_string(item)},\n" for item in items) + "\t\t\t)"


def pbx_object(identifier, isa, entries):
    """One object whose keys are `entries`, written as they are."""
    body = "".join(f"\t\t\t{key} = {value};\n" for key, value in entries.items())
    return f"\t\t{identifier} = {{\n\t\t\tisa = {isa};\n{body}\t\t}};\n"


SCRIPT_RULE = {"compilerSpec": "com.apple.compilers.proxy.script", "filePatterns": pbx_string("*.x"), "fileType": "pattern.proxy",
               "inputFiles": pbx_list([]), "isEditable": "1", "outputFiles": pbx_list([]), "script": pbx_string("true\n")}
CLANG = "com.apple.compilers.llvm.clang.1_0"
OUTPUTS = ["$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).c", "$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).m"]
# One rule per target, each the script rule with one key added, changed or left out.
RULE_VARIANTS = {
    "Bare": {"compilerSpec": SCRIPT_RULE["compilerSpec"], "filePatterns": pbx_string("*.x"), "fileType": "pattern.proxy"},
    "Script": SCRIPT_RULE,
    "PerArchitectureNo": {**SCRIPT_RULE, "runOncePerArchitecture": "0"},
    "PerArchitectureYes": {**SCRIPT_RULE, "runOncePerArchitecture": "1"},
    "DependencyFile": {**SCRIPT_RULE, "dependencyFile": pbx_string("$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).d")},
    "EmptyDependencyFile": {**SCRIPT_RULE, "dependencyFile": '""'},
    "OutputFlags": {**SCRIPT_RULE, "outputFiles": pbx_list(OUTPUTS), "outputFilesCompilerFlags": pbx_list(["-DONE", "-DTWO -O2"])},
    "OutputFlagsShort": {**SCRIPT_RULE, "outputFiles": pbx_list(OUTPUTS), "outputFilesCompilerFlags": pbx_list(["-DONE"])},
    "FlagsWithoutOutputs": {**SCRIPT_RULE, "outputFilesCompilerFlags": pbx_list(["-DONE"])},
    "EmptyFlags": {**SCRIPT_RULE, "outputFiles": pbx_list(OUTPUTS), "outputFilesCompilerFlags": pbx_list([])},
    "FileLists": {**SCRIPT_RULE, "inputFileListPaths": pbx_list(["$(SRCROOT)/in.xcfilelist"]),
                  "outputFileListPaths": pbx_list(["$(SRCROOT)/out.xcfilelist"])},
    "Inputs": {**SCRIPT_RULE, "inputFiles": pbx_list(["$(SRCROOT)/a.txt", "$(SRCROOT)/b.txt"]), "outputFiles": pbx_list(OUTPUTS)},
    "NotEditable": {**SCRIPT_RULE, "isEditable": "0"},
    "EmptyName": {**SCRIPT_RULE, "name": '""'},
    "EmptyScript": {**SCRIPT_RULE, "script": '""'},
    "NoScript": {key: value for key, value in SCRIPT_RULE.items() if key != "script"},
    "NoInputs": {key: value for key, value in SCRIPT_RULE.items() if key != "inputFiles"},
    "NoOutputs": {key: value for key, value in SCRIPT_RULE.items() if key != "outputFiles"},
    "EmptyPatterns": {**SCRIPT_RULE, "filePatterns": '""'},
    "PatternsWithType": {**SCRIPT_RULE, "fileType": "sourcecode.c.c", "filePatterns": pbx_string("*.c")},
    "ClangWithScript": {**SCRIPT_RULE, "compilerSpec": CLANG, "fileType": "sourcecode.c.c"},
    "ClangBare": {"compilerSpec": CLANG, "fileType": "sourcecode.c.c"},
    "ClangPerArchitectureNo": {"compilerSpec": CLANG, "fileType": "sourcecode.c.c", "runOncePerArchitecture": "0"},
    "ClangPatterns": {"compilerSpec": CLANG, "fileType": "pattern.proxy", "filePatterns": pbx_string("*.y"), "script": pbx_string("true\n")},
    "ProxyWithoutPatterns": {key: value for key, value in SCRIPT_RULE.items() if key != "filePatterns"},
    "QuotedFlags": {**SCRIPT_RULE, "outputFiles": pbx_list(OUTPUTS[:1]),
                    "outputFilesCompilerFlags": pbx_list(['-DA="x y" -DB=\'p q\' -DC\\ D  -E', ""])},
    "Everything": {**SCRIPT_RULE, "dependencyFile": pbx_string("$(DERIVED_FILE_DIR)/x.d"), "inputFiles": pbx_list(["$(SRCROOT)/a.txt"]),
                   "name": pbx_string("All keys"), "outputFiles": pbx_list(OUTPUTS), "outputFilesCompilerFlags": pbx_list(["-DONE", "-DTWO"]),
                   "runOncePerArchitecture": "0"},
}


def build_rule_keys():
    # The fuzzer's rules have no runOncePerArchitecture key, and the PIF says "true" for them.
    # Each target here has one rule with one key added, changed or left out; TwoRules has two.
    targets = Targets()
    targets.rules = {}
    for index, (name, entries) in enumerate(RULE_VARIANTS.items(), 1):
        rule = f"B{index:023d}"
        targets.objects += pbx_object(rule, "PBXBuildRule", entries)
        target, _ = targets.add(name, APPLICATION, {})
        targets.rules[target] = rule
    target, _ = targets.add("TwoRules", APPLICATION, {})
    targets.objects += pbx_object("B00000000000000000000098", "PBXBuildRule", RULE_VARIANTS["PerArchitectureNo"])
    targets.objects += pbx_object("B00000000000000000000099", "PBXBuildRule", RULE_VARIANTS["Bare"])
    targets.rules[target] = "B00000000000000000000098,\n\t\t\t\tB00000000000000000000099"
    return targets.project()


def product_names(configuration_names=("Debug", "Release"), default="Release", project_settings=None):
    # The fuzzer's targets without PRODUCT_NAME have a product named `.app`, and a dynamic
    # library's is `Dynamic.dylib` where the project file names `libDynamic.dylib`. Each target
    # sets PRODUCT_NAME in one way; its product reference keeps the name Xcode's templates give it.
    targets = Targets()
    files = {"Name.xcconfig": "PRODUCT_NAME = FromXcconfig\n"}
    targets.objects += '\t\tA00000000000000000000001 /* Name.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Name.xcconfig; sourceTree = "<group>"; };\n'
    first, *rest = configuration_names
    variants = [
        ("Unset", APPLICATION, {}, {}, None),
        ("TargetName", APPLICATION, {"PRODUCT_NAME": pbx_string("$(TARGET_NAME)")}, {}, None),
        ("Literal", APPLICATION, {"PRODUCT_NAME": "Literal"}, {}, None),
        ("PerConfiguration", APPLICATION, {}, {name: {"PRODUCT_NAME": f"{name}Name"} for name in configuration_names}, None),
        ("FirstOnly", APPLICATION, {}, {first: {"PRODUCT_NAME": "FirstOnly"}}, None),
        ("RestOnly", APPLICATION, {}, {name: {"PRODUCT_NAME": f"{name}Only"} for name in rest}, None),
        ("Xcconfig", APPLICATION, {}, {}, "A00000000000000000000001 /* Name.xcconfig */"),
        ("XcconfigOverridden", APPLICATION, {"PRODUCT_NAME": "OverXcconfig"}, {}, "A00000000000000000000001 /* Name.xcconfig */"),
        ("Custom", APPLICATION, {"PRODUCT_NAME": pbx_string("$(NOMAC_NAME)"), "NOMAC_NAME": "Custom"}, {}, None),
        ("Inherited", APPLICATION, {"PRODUCT_NAME": pbx_string("$(inherited)Tail")}, {}, None),
        ("Café", APPLICATION, {"PRODUCT_NAME": pbx_string("$(TARGET_NAME)")}, {}, None),
        ("UnicodeLiteral", APPLICATION, {"PRODUCT_NAME": pbx_string("Ünï Literal")}, {}, None),
        ("Conditional", APPLICATION, {"PRODUCT_NAME": "Base", pbx_string("PRODUCT_NAME[sdk=iphoneos*]"): "Device"}, {}, None),
        ("ConditionalOnly", APPLICATION, {pbx_string("PRODUCT_NAME[sdk=iphoneos*]"): "DeviceOnly"}, {}, None),
        ("SimulatorConditional", APPLICATION, {"PRODUCT_NAME": "Base", pbx_string("PRODUCT_NAME[sdk=iphonesimulator*]"): "Simulator"}, {}, None),
        ("ArchConditional", APPLICATION, {"PRODUCT_NAME": "Base", pbx_string("PRODUCT_NAME[arch=arm64]"): "Arm"}, {}, None),
        ("My-App 2", APPLICATION, {"PRODUCT_NAME": pbx_string("$(TARGET_NAME:c99extidentifier)")}, {}, None),
        ("ProjectName", APPLICATION, {"PRODUCT_NAME": pbx_string("$(PROJECT_NAME)")}, {}, None),
        ("Space", APPLICATION, {"PRODUCT_NAME": pbx_string("With Space")}, {}, None),
        ("Wrapper", "com.apple.product-type.bundle", {"PRODUCT_NAME": "Wrapper", "WRAPPER_EXTENSION": "plugin"}, {}, None),
        ("ExecutableExtension", "com.apple.product-type.library.dynamic", {"PRODUCT_NAME": "Exec", "EXECUTABLE_EXTENSION": "so"}, {}, None),
        ("NoPrefix", "com.apple.product-type.library.static", {"PRODUCT_NAME": "NoPrefix", "EXECUTABLE_PREFIX": '""'}, {}, None),
    ] + [(f"Type{index:02d}", f"com.apple.product-type.{kind}", {"PRODUCT_NAME": f"Name{index:02d}"}, {}, None)
         for index, kind in enumerate(PRODUCT_FILES, 1)]
    for name, product_type, common, per_configuration, xcconfig in variants:
        index = len(targets.ids) + 1
        sdk = "macosx" if any(kind in product_type for kind in ["tool", "xpc", "system-extension", "driver-extension", "kernel-extension",
                                                                   "xcode-extension", "instruments-package"]) else "iphoneos"
        values = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}", "SDKROOT": sdk, **common}
        list_id = f"H{index:023d}"
        entries = [(f"G{index:021d}{position:02d}", configuration, {**values, **per_configuration.get(configuration, {})})
                   for position, configuration in enumerate(configuration_names)]
        configuration_list = named_configurations(list_id, entries, default)
        if xcconfig:
            configuration_list = configuration_list.replace("\t\t\tbuildSettings = {", f"\t\t\tbaseConfigurationReference = {xcconfig};\n\t\t\tbuildSettings = {{")
        targets.add(name, product_type, {}, sdk=sdk, configuration_list=configuration_list, list_ids=[list_id])
    entries = ([(name, project_settings or {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}) for name in configuration_names], default)
    return targets.project(files, project_configurations=entries, group_children="\t\t\t\tA00000000000000000000001 /* Name.xcconfig */,\n")



def product_names_empty():
    # ish's `MakeXcodeAutoCompleteWork`, a tool with no PRODUCT_NAME at any level: its name
    # would be empty. Product types whose name is only the product name, and others, with
    # PRODUCT_NAME unset or empty, in a list whose only configuration is not called Debug.
    targets = Targets()
    variants = [
        ("UnsetTool", "com.apple.product-type.tool", {}), ("EmptyTool", "com.apple.product-type.tool", {"PRODUCT_NAME": '""'}),
        ("PrefixTool", "com.apple.product-type.tool", {"EXECUTABLE_PREFIX": "pre"}),
        ("UnsetStatic", "com.apple.product-type.library.static", {}), ("UnsetDynamic", "com.apple.product-type.library.dynamic", {}),
        ("UnsetFramework", "com.apple.product-type.framework", {}), ("UnsetBundle", "com.apple.product-type.bundle", {}),
        ("UnsetApp", APPLICATION, {}), ("EmptyApp", APPLICATION, {"PRODUCT_NAME": '""'}),
        ("UnsetToolPath", "com.apple.product-type.tool", {}), ("UnsetToolNamed", "com.apple.product-type.tool", {}),
    ]
    for name, product_type, settings in variants:
        index = len(targets.ids) + 1
        sdk = "macosx" if "tool" in product_type else "iphoneos"
        values = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}", "SDKROOT": sdk, **settings}
        list_id = f"H{index:023d}"
        configuration_list = named_configurations(list_id, [(f"G{index:021d}00", "Debug-Other", values)], "Debug-Other")
        targets.add(name, product_type, {}, sdk=sdk, configuration_list=configuration_list, list_ids=[list_id])
    files = targets.project(project_configurations=([("Debug-Other", {"SDKROOT": "iphoneos"})], "Debug-Other"))
    # UnsetToolPath's product reference names another file than the target, UnsetToolNamed's
    # productName another product.
    files["P.xcodeproj/project.pbxproj"] = files["P.xcodeproj/project.pbxproj"].replace('path = "UnsetToolPath";', "path = OtherPath;").replace(
        'productName = "UnsetToolNamed";', "productName = OtherProduct;")
    return files


WHOLEMODULE_TARGETS = [
    ("Plain", {"SWIFT_OPTIMIZATION_LEVEL": '"-Owholemodule"'}, None),
    ("WithMode", {"SWIFT_OPTIMIZATION_LEVEL": '"-Owholemodule"', "SWIFT_COMPILATION_MODE": "singlefile"}, None),
    ("Conditional", {pbx_string("SWIFT_OPTIMIZATION_LEVEL[sdk=iphoneos*]"): '"-Owholemodule"'}, None),
    ("Xcconfig", {}, "A00000000000000000000001 /* Optimization.xcconfig */"),
    ("OtherFlags", {"OTHER_SWIFT_FLAGS": '"-Owholemodule"'}, None),
    ("OtherFlagsList", {"OTHER_SWIFT_FLAGS": '(\n\t\t\t\t\t"-DNOMAC",\n\t\t\t\t\t"-Owholemodule",\n\t\t\t\t)'}, None),
    ("Onone", {"SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}, None),
    ("Unset", {}, None),
]


def swift_wholemodule(object_version=77, attributes=""):
    # delta's projects set SWIFT_OPTIMIZATION_LEVEL = -Owholemodule, the value Xcode 9 wrote
    # before SWIFT_COMPILATION_MODE. One target per way to write it, and the project's Release
    # configuration sets it too, for the PIF and -showBuildSettings; the project saved at
    # `object_version` with `attributes` (LastUpgradeCheck).
    targets = Targets()
    files = {"Optimization.xcconfig": "SWIFT_OPTIMIZATION_LEVEL = -Owholemodule\n"}
    targets.objects += '\t\tA00000000000000000000001 /* Optimization.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Optimization.xcconfig; sourceTree = "<group>"; };\n'
    for name, settings, xcconfig in WHOLEMODULE_TARGETS:
        index = len(targets.ids) + 1
        values = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}", "PRODUCT_NAME": '"$(TARGET_NAME)"',
                  "SDKROOT": "iphoneos", **settings}
        list_id = f"H{index:023d}"
        configuration_list = named_configurations(list_id, [(f"G{index:021d}{position:02d}", configuration, values)
                                                            for position, configuration in enumerate(("Debug", "Release"))], "Release")
        if xcconfig:
            configuration_list = configuration_list.replace("\t\t\tbuildSettings = {", f"\t\t\tbaseConfigurationReference = {xcconfig};\n\t\t\tbuildSettings = {{")
        targets.add(name, APPLICATION, {}, configuration_list=configuration_list, list_ids=[list_id])
    project = [("Debug", {"SDKROOT": "iphoneos"}), ("Release", {"SDKROOT": "iphoneos", "SWIFT_OPTIMIZATION_LEVEL": '"-Owholemodule"'})]
    files = targets.project(files, project_configurations=(project, "Release"), attributes=attributes,
                            group_children="\t\t\t\tA00000000000000000000001 /* Optimization.xcconfig */,\n")
    files["P.xcodeproj/project.pbxproj"] = files["P.xcodeproj/project.pbxproj"].replace("objectVersion = 77;", f"objectVersion = {object_version};")
    return files


def observe_swift_wholemodule(run, names=None):
    for name, _, _ in WHOLEMODULE_TARGETS:
        if names is None or name in names:
            for configuration in ("Debug", "Release"):
                run(f"{name}-{configuration}", "-showBuildSettings", "-target", name, "-configuration", configuration)


MIG_FILES = [  # path, file type, phase, ATTRIBUTES
    ("None.defs", "sourcecode.mig", "Sources", None), ("Client.defs", "sourcecode.mig", "Sources", "Client"),
    ("Server.defs", "sourcecode.mig", "Sources", "Server"),
    ("Both.defs", "sourcecode.mig", "Sources", "Client, Server"),
    ("BothReversed.defs", "sourcecode.mig", "Sources", "Server, Client"),
    ("Public.defs", "sourcecode.mig", "Sources", "Public"),
    ("ServerPublic.defs", "sourcecode.mig", "Sources", "Server, Public"),
    ("Lowercase.defs", "sourcecode.mig", "Sources", "server"),
    ("Resource.defs", "sourcecode.mig", "Resources", "Server"),
    ("Server.c", "sourcecode.c.c", "Sources", "Server"),
]


def mig_codegen():
    # ish's `mach_exc.defs` build file says ATTRIBUTES = (Server, ); Xcode's PIF gives it
    # `migCodegenFiles`. One build file per attribute combination, in Sources and Resources.
    targets = Targets()
    target, _ = targets.add("App", APPLICATION, {})
    files, children, members = {}, "", {"Sources": [], "Resources": []}
    for index, (path, file_type, phase, settings) in enumerate(MIG_FILES, 1):
        reference, identifier = f"A{index:023d}", f"Z{index:023d}"
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{identifier} = {{isa = PBXBuildFile; fileRef = {reference};{build_file_settings(settings)} }};\n")
        files[path] = "subsystem nomac 100;\n" if path.endswith(".defs") else "int nomac;\n"
        children += f"\t\t\t\t{reference},\n"
        members[phase].append(identifier)
    for index, (phase, isa) in enumerate({"Sources": "PBXSourcesBuildPhase", "Resources": "PBXResourcesBuildPhase"}.items(), 1):
        phase_id = f"W{index:023d}"
        listed = "".join(f"\t\t\t\t{member},\n" for member in members[phase])
        targets.objects += (f"\t\t{phase_id} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
                            f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
        targets.phases[target].append(phase_id)
    return targets.project(files, group_children=children)


def dependency_proxies():
    # session's targets depend on `SessionUtil` through a proxy into their own project whose
    # remote ID no target has. App's dependencies, in order: Kit as Xcode writes them, proxies
    # into the project without `target` (to no target, to Lib), a `target` naming no object,
    # and unresolved proxies without remoteInfo, one of them with the dependency's `name`, then a
    # proxy to no target whose remoteInfo names Lib.
    targets = Targets()
    app, _ = targets.add("App", APPLICATION, {})
    kit, _ = targets.add("Kit", "com.apple.product-type.framework", {})
    lib, _ = targets.add("Lib", "com.apple.product-type.framework", {})
    targets.depend(app, kit, "Kit")
    entries = [("Gone", "C99999999999999999999991", "Gone", None, ""), ("ByProxy", lib, "Lib", None, ""),
               ("GoneTarget", "C99999999999999999999992", "GoneTarget", "C99999999999999999999992", ""),
               ("GoneNoInfo", "C99999999999999999999993", None, None, ""), ("GoneNamed", "C99999999999999999999994", None, None, "name = Named; "),
               ("StaleLib", "C99999999999999999999995", "Lib", None, "")]
    for _, remote, info, target, extra in entries:
        proxy, dependency = targets.next_id("X"), targets.next_id("T")
        remote_info = f" remoteInfo = {pbx_string(info)};" if info else ""
        target_key = f" target = {target};" if target else ""
        targets.objects += (f"\t\t{proxy} = {{isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; "
                            f"remoteGlobalIDString = {remote};{remote_info} }};\n"
                            f"\t\t{dependency} = {{isa = PBXTargetDependency; {extra}{target_key.strip()} targetProxy = {proxy}; }};\n")
        targets.dependencies[app].append(dependency)
    return targets.project()


PRODUCT_SDKS = [("iphoneos", {}), ("macosx", {}), ("watchos", {}), ("appletvos", {}), ("xros", {}), ("auto", {}), (None, {})]
# The product types that keep their reference's name on some SDKs (`product-types-sdks`), under
# simulator SDKs, versioned SDK names and `auto` with SUPPORTED_PLATFORMS.
RESTRICTED_SDKS = [("watchsimulator", {}), ("appletvsimulator", {}), ("iphonesimulator", {}), ("xrsimulator", {}),
                   ("watchos26.0", {}), ("macosx27.0", {}), ("auto", {"SUPPORTED_PLATFORMS": pbx_string("watchos watchsimulator")}),
                   ("auto", {"SUPPORTED_PLATFORMS": pbx_string("appletvos appletvsimulator")}), ("auto", {"SUPPORTED_PLATFORMS": "iphoneos"}),
                   ("", {}), (None, {"SUPPORTED_PLATFORMS": "macosx"})]


def product_types_sdks(kinds=None, sdks=PRODUCT_SDKS):
    # A watch app on the iOS SDK keeps its product reference's own name in the PIF, where other
    # products take PRODUCT_NAME and their type's extension (`product-names`). Each product type
    # under each SDK (None: no SDKROOT); target names are not ASCII, PRODUCT_NAME is.
    targets = Targets()
    kinds = kinds or list(PRODUCT_FILES) + ["objfile", "nomac-unknown"]
    for index, kind in enumerate(kinds, 1):
        for position, (sdk, extra) in enumerate(sdks):
            name = f"\u00dc{index:02d}{position:02d}"
            product_type = kind if kind.startswith("org.") else f"com.apple.product-type.{kind}"
            targets.add(name, product_type if kind in PRODUCT_FILES else APPLICATION, {"PRODUCT_NAME": f"N{index:02d}{position:02d}", **extra},
                        sdk=sdk or "")
            target, _, _, values, *rest = targets.pending[-1]
            if sdk is None:
                values.pop("SDKROOT")
            elif not sdk:
                values["SDKROOT"] = '""'
            targets.pending[-1] = (target, name, product_type, values, *rest)
    return targets.project()



# Product types of Swift Build's specifications that `product-types-sdks` does not cover.
OTHER_PRODUCT_TYPES = ["app-extension.intents-service", "application.java", "bundle.external-test", "bundle.ocunit-test",
                       "in-app-purchase-content", "kernel-extension.iokit", "library.java.archive", "pluginkit-plugin",
                       "spotlight-importer", "tool.host-build", "tool.java", "tool.swiftpm-test-runner", "tv-broadcast-extension",
                       "org.swift.product-type.common.object", "org.swift.product-type.library.object", "org.swift.product-type.library.static"]


def remove_project_sdk(directory):
    """Drops SDKROOT from the project's configurations, so that no level sets it."""
    path = directory / "P.xcodeproj" / "project.pbxproj"
    path.write_text(path.read_text().replace("\t\t\t\tSDKROOT = iphoneos;\n\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET", "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET"))



def xcconfig_conditions():
    # A setting nomac reads itself assigned with and without an SDK condition in one xcconfig, in
    # both orders: Xcode's own reading takes the condition whatever the order for CODE_SIGN_STYLE
    # (`provisioning-conditions`), where Swift Build takes the last assignment.
    targets = Targets()
    variants = {
        "NameCondThenPlain": "PRODUCT_NAME[sdk=iphoneos*] = Cond\nPRODUCT_NAME = Plain\n",
        "NamePlainThenCond": "PRODUCT_NAME = Plain\nPRODUCT_NAME[sdk=iphoneos*] = Cond\n",
        "GenerateCondThenPlain": "GENERATE_INFOPLIST_FILE[sdk=iphoneos*] = YES\nGENERATE_INFOPLIST_FILE = NO\n",
        "GeneratePlainThenCond": "GENERATE_INFOPLIST_FILE = NO\nGENERATE_INFOPLIST_FILE[sdk=iphoneos*] = YES\n",
    }
    files, children = {}, ""
    for index, (name, text) in enumerate(variants.items(), 1):
        reference = f"A{index:023d}"
        files[f"{name}.xcconfig"] = text
        targets.objects += f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {name}.xcconfig; sourceTree = "<group>"; }};\n'
        children += f"\t\t\t\t{reference},\n"
        values = {"SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        if name.startswith("Generate"):
            values["PRODUCT_NAME"] = pbx_string("$(TARGET_NAME)")
        list_id = f"H{index:023d}"
        configuration_list = configurations(list_id, f"G{index:023d}", f"J{index:023d}", values, base=reference)
        targets.add(name, APPLICATION, {}, configuration_list=configuration_list, list_ids=[list_id])
    return targets.project(files, group_children=children)

def class_prefix(prefix='"XY"'):
    # The fuzzer's targets carry the project's CLASSPREFIX as `classPrefix`. A native, an
    # aggregate and a legacy target, under a project whose CLASSPREFIX is `prefix` (none: unset).
    targets = Targets()
    targets.add("App", APPLICATION, {})
    targets.add("Kit", "com.apple.product-type.framework", {})
    targets.objects += configurations("F000000000000000000000AL", "F000000000000000000000AD", "F000000000000000000000AR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'})
    targets.objects += pbx_object("C00000000000000000000091", "PBXAggregateTarget", {
        "buildConfigurationList": "F000000000000000000000AL", "buildPhases": "(\n\t\t\t)", "dependencies": "(\n\t\t\t)", "name": "Agg", "productName": "Agg"})
    targets.objects += configurations("F000000000000000000000LL", "F000000000000000000000LD", "F000000000000000000000LR", {"PRODUCT_NAME": '"$(TARGET_NAME)"'})
    targets.objects += pbx_object("C00000000000000000000092", "PBXLegacyTarget", {
        "buildArgumentsString": pbx_string("$(ACTION)"), "buildConfigurationList": "F000000000000000000000LL", "buildPhases": "(\n\t\t\t)",
        "buildToolPath": "/usr/bin/make", "dependencies": "(\n\t\t\t)", "name": "Legacy", "passBuildSettingsInEnvironment": "1", "productName": "Legacy"})
    targets.ids += ["C00000000000000000000091", "C00000000000000000000092"]
    return targets.project(attributes=f"\t\t\t\tCLASSPREFIX = {prefix};\n" if prefix is not None else "")


def synchronized_project(folders, target_specs, files, project_settings=None, bases=None, extra_objects="", extra_children=""):
    """A project of synchronized folders: `folders` is [(object ID, path, [(set ID, target name,
    entries)], extra folder entries)] (the last item optional) and `target_specs` [(name,
    product type, [phase isa], [folder object ID], settings)]. Targets are named in exception
    sets by name; `bases` names the xcconfig file reference of a target's configurations.
    Folders whose entries say `nested` are left out of the main group (`extra_children` lists
    the groups that hold them)."""
    targets = Targets()
    ids = {}
    for name, product_type, phases, listed, settings in target_specs:
        index = len(targets.ids) + 1
        base = (bases or {}).get(name)
        configuration_list = None
        if base:
            values = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}", **settings}
            configuration_list = configurations(f"H{index:023d}", f"G{index:023d}", f"J{index:023d}", values, base=base)
        target, _ = targets.add(name, product_type, settings, configuration_list=configuration_list,
                                list_ids=[f"H{index:023d}"] if base else None)
        ids[name] = target
        for phase_index, isa in enumerate(phases):
            phase_id = f"W{int(target[1:]):020d}{phase_index:03d}"
            targets.objects += pbx_object(phase_id, isa, {"buildActionMask": "2147483647", "files": "(\n\t\t\t)", "runOnlyForDeploymentPostprocessing": "0"})
            targets.phases[target].append(phase_id)
        targets.synchronized = getattr(targets, "synchronized", {})
        targets.synchronized[target] = listed
    children = ""
    for folder_id, path, sets, *rest in folders:
        entries = dict(rest[0]) if rest else {}
        nested = entries.pop("nested", False)
        exceptions = ""
        for set_id, target_name, values in sets:
            targets.objects += pbx_object(set_id, "PBXFileSystemSynchronizedBuildFileExceptionSet", {**values, "target": ids[target_name]})
            exceptions += f"\t\t\t\t{set_id},\n"
        exception_entry = {"exceptions": f"(\n{exceptions}\t\t\t)"} if exceptions else {}
        targets.objects += pbx_object(folder_id, "PBXFileSystemSynchronizedRootGroup",
                                      {**exception_entry, "path": pbx_string(path), "sourceTree": '"<group>"', **entries})
        if not nested:
            children += f"\t\t\t\t{folder_id},\n"
    targets.objects += extra_objects
    project_configurations = None
    if project_settings:
        project_configurations = ([(name, {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", **project_settings})
                                   for name in ["Debug", "Release"]], "Release")
    return targets.project(files, project_configurations=project_configurations, group_children=children + extra_children)

SOURCES, HEADERS, FRAMEWORKS, RESOURCES = "PBXSourcesBuildPhase", "PBXHeadersBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"



def language_synchronized():
    # The fuzzer's synchronized targets report Swift when an exception set removes their only
    # Swift file, also one that is not on disk, and nothing when they have no Sources phase.
    folders = [
        ("S00000000000000000000001", "Excluded", [("X00000000000000000000001", "Excluded", {"membershipExceptions": pbx_list(["a.swift", "b.swift"])})]),
        ("S00000000000000000000002", "NoSources", []),
        ("S00000000000000000000003", "HeadersOnly", []),
        ("S00000000000000000000004", "Unlisted", [("X00000000000000000000004", "Unlisted", {"membershipExceptions": pbx_list(["c.m"])})]),
        ("S00000000000000000000005", "Missing", [("X00000000000000000000005", "Missing", {"membershipExceptions": pbx_list(["gone.swift"])})]),
        ("S00000000000000000000006", "FrameworksOnly", []),
        ("S00000000000000000000007", "Mixed", [("X00000000000000000000007", "Mixed", {"membershipExceptions": pbx_list(["x.swift", "y.swift"])})]),
        ("S00000000000000000000008", "OtherTarget", [("X00000000000000000000008", "Mixed", {"membershipExceptions": pbx_list(["z.swift"])})]),
    ]
    specs = [
        ("Excluded", APPLICATION, [SOURCES, RESOURCES], ["S00000000000000000000001"], {}),
        ("NoSources", APPLICATION, [RESOURCES], ["S00000000000000000000002"], {}),
        ("HeadersOnly", "com.apple.product-type.framework", [HEADERS, RESOURCES], ["S00000000000000000000003"], {}),
        ("Unlisted", APPLICATION, [SOURCES], [], {}),
        ("Missing", APPLICATION, [SOURCES], ["S00000000000000000000005"], {}),
        ("FrameworksOnly", APPLICATION, [FRAMEWORKS], ["S00000000000000000000006"], {}),
        ("Mixed", APPLICATION, [SOURCES, RESOURCES], ["S00000000000000000000007"], {}),
        ("NoPhases", APPLICATION, [], ["S00000000000000000000002"], {}),
    ]
    files = {
        "Excluded/a.swift": "let a = 1\n", "Excluded/b.swift": "let b = 1\n", "Excluded/c.m": "int c;\n", "Excluded/d.json": "{}\n",
        "NoSources/a.swift": "let a = 1\n", "NoSources/b.js": "var b;\n",
        "HeadersOnly/a.h": "int a;\n", "HeadersOnly/b.m": "int b;\n", "HeadersOnly/c.m": "int c;\n",
        "Unlisted/a.swift": "let a = 1\n", "Unlisted/b.swift": "let b = 1\n", "Unlisted/c.m": "int c;\n",
        "Missing/a.json": "{}\n",
        "FrameworksOnly/a.swift": "let a = 1\n",
        "Mixed/x.swift": "let x = 1\n", "Mixed/y.swift": "let y = 1\n", "Mixed/m.m": "int m;\n", "Mixed/sub/n.m": "int n;\n",
        "OtherTarget/z.swift": "let z = 1\n", "OtherTarget/w.swift": "let w = 1\n",
    }
    return synchronized_project(folders, specs, files)


def language_fallback():
    # language-synchronized: a Swift file an exception set removes does not count when another
    # member has a language, but the fuzzer's targets whose members have none report Swift for
    # such a file. Each target lists its own folder.
    def excluded(*names):
        return lambda target: [(f"X{target}", target, {"membershipExceptions": pbx_list(list(names))})]
    cases = [
        ("AllExcluded", [SOURCES], excluded("a.swift", "b.m", "c.m"), {"a.swift": "", "b.m": "", "c.m": ""}),
        ("ResourcesOnly", [RESOURCES], excluded("a.swift"), {"a.swift": ""}),
        ("HeaderExcluded", [HEADERS, SOURCES], excluded("a.h"), {"a.h": ""}),
        ("MemberWithoutLanguage", [SOURCES, RESOURCES], excluded("x.swift"), {"x.swift": "", "d.json": "{}"}),
        ("ScriptTie", [SOURCES, RESOURCES], excluded("a.swift", "b.js"), {"a.swift": "", "b.js": ""}),
        ("Nested", [SOURCES], excluded("sub/a.swift"), {"sub/a.swift": ""}),
        ("FrameworksOnly", [FRAMEWORKS], excluded("a.swift"), {"a.swift": ""}),
        ("TwoSourcesPhases", [RESOURCES, SOURCES, SOURCES], excluded("a.m"), {"a.m": ""}),
        ("NothingExcluded", [SOURCES], lambda target: [], {"d.json": "{}"}),
        ("HeaderMemberSwiftExcluded", [HEADERS, SOURCES], excluded("a.swift", "b.swift"), {"a.swift": "", "b.swift": "", "h.h": ""}),
        ("AssemblyMemberSwiftExcluded", [SOURCES], excluded("b.swift", "c.swift"), {"a.s": "", "b.swift": "", "c.swift": ""}),
    ]
    folders, specs, files = [], [], {}
    for index, (name, phases, sets, contents) in enumerate(cases, 1):
        folder = f"S{index:023d}"
        folders.append((folder, name, [(f"X{index:023d}", target, entries) for _, target, entries in sets(name)]))
        specs.append((name, APPLICATION, phases, [folder], {}))
        files.update({f"{name}/{path}": text + "\n" for path, text in contents.items()})
    specs.append(("NoFolders", APPLICATION, [SOURCES], [], {}))
    return synchronized_project(folders, specs, files)


def language_fallback_missing():
    # The fuzzer's seed 70136: a target that excludes a.swift, gone.swift (not on disk) and b.m
    # reports Objective-C, where language-synchronized has gone.swift deciding on its own.
    # Each target lists its own folder and excludes every file named, on disk or not.
    cases = [
        ("OneOfEachAndGone", ["a.swift", "b.m"], ["gone.swift"]),
        ("TwoGoneOverOne", ["b.m"], ["gone1.swift", "gone2.swift"]),
        ("ThreeGoneOverOne", ["b.m"], ["gone1.swift", "gone2.swift", "gone3.swift"]),
        ("GoneTiesDisk", ["a.swift"], ["gone.m"]),
        ("GoneOverDiskNoLanguage", ["a.json"], ["gone.swift"]),
        ("GoneOnlyTie", [], ["gone.swift", "gone.m"]),
        ("GoneOnlyCount", [], ["gone1.swift", "gone2.swift", "gone.m"]),
        ("GoneOnlyReverse", [], ["gone1.m", "gone2.m", "gone.swift"]),
        ("DiskWithFolder", ["a.swift", "b.m", "Feature/c.html"], ["gone.swift", "Feature"]),
        ("GoneInSubfolder", ["b.m"], ["sub/gone1.swift", "sub/gone2.swift"]),
        ("GoneInMissingSubfolder", ["b.m", "sub/a.json"], ["none/gone1.swift", "none/gone2.swift"]),
        ("DiskOverGoneAssembly", ["a.swift"], ["gone1.s", "gone2.s"]),
        ("DiskCountSwift", ["a.swift", "b.swift", "c.swift", "d.m"], []),
        ("DiskCountC", ["a.swift", "b.swift", "c.swift", "d.c"], []),
        ("DiskCountObjC", ["a.m", "b.m", "c.m", "d.c"], []),
        ("DiskCountJS", ["a.swift", "b.swift", "c.js"], []),
        ("DiskCountHeader", ["a.swift", "b.swift", "c.swift", "d.h"], []),
        ("DiskCountCppHeader", ["a.m", "b.m", "c.hpp"], []),
        ("DiskCountMetal", ["a.swift", "b.swift", "c.metal"], []),
    ]
    folders, specs, files = [], [], {}
    for index, (name, disk, gone) in enumerate(cases, 1):
        folder = f"S{index:023d}"
        named = [path for path in disk if not path.startswith("Feature/") and not path.endswith(".json")] + gone
        folders.append((folder, name, [(f"X{index:023d}", name, {"membershipExceptions": pbx_list(named)})]))
        specs.append((name, APPLICATION, [SOURCES], [folder], {}))
        files.update({f"{name}/{path}": "\n" for path in disk})
    return synchronized_project(folders, specs, files)


def pif_key_order():
    # The fuzzer's seeds with PROVISIONING_PROFILE[sdk=iphoneos*] beside PROVISIONING_PROFILE_SPECIFIER:
    # `_` comes before `[` in the PIF. One target's settings name every ASCII punctuation mark,
    # both cases, digit runs with and without leading zeros, and non-ASCII letters.
    punctuation = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$"
    keys = [f"K{mark}z" for mark in punctuation] + ["K0z", "K9z", "KAz", "KBz", "Kaz", "Kbz", "KZz", "Kzz"]
    keys += ["a1", "a01", "A1", "a2", "a10", "9b", "9B", "09b", "0_0", "0_00", "00_0"]
    keys += ["KEz", "Kez", "KÉz", "KFz", "Knz", "Kñz", "Koz", "KUz", "KÜz", "Kαz", "K日z"]
    keys += ["PROVISIONING_PROFILE[sdk=iphoneos*]", "PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE", "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"]
    targets = Targets()
    targets.add("Keys", APPLICATION, {pbx_string(key): pbx_string("x") for key in keys})
    return targets.project({})


def workspace_locations(values, shared=False, symroot=False, workspace=False):
    # The fuzzer's seeds with BuildLocationStyle = UseTargetSettings in the per-user
    # WorkspaceSettings.xcsettings: BUILD_DIR moves into the project. One app; `values` are the
    # file's keys, in the shared or the current user's copy of the opened container.
    targets = Targets()
    targets.add("App", APPLICATION, {"SYMROOT": "Custom"} if symroot else {})
    files = targets.project({})
    container = "W.xcworkspace" if workspace else "P.xcodeproj/project.xcworkspace"
    if workspace:
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj"])
    folder = "xcshareddata" if shared else f"xcuserdata/{getpass.getuser()}.xcuserdatad"
    entries = "".join(f"\t<key>{key}</key>\n\t<string>{value}</string>\n" for key, value in values.items())
    files[f"{container}/{folder}/WorkspaceSettings.xcsettings"] = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        f'<plist version="1.0">\n<dict>\n{entries}</dict>\n</plist>\n')
    return files


def observe_workspace_locations(run):
    run("target", "-showBuildSettings", "-target", "App")
    run("scheme", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS")
    run("scheme-derived", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS", "-derivedDataPath", str(run.container.parent / "Given"))


WORKSPACE_LOCATION_CASES = {
    "target-settings": {"BuildLocationStyle": "UseTargetSettings"},
    "app-preferences": {"BuildLocationStyle": "UseAppPreferences"},
    "custom-derived": {"BuildLocationStyle": "CustomLocation", "CustomBuildLocationType": "RelativeToDerivedData",
                       "CustomBuildProductsPath": "Out/Products", "CustomBuildIntermediatesPath": "Out/Intermediates"},
    "custom-workspace": {"BuildLocationStyle": "CustomLocation", "CustomBuildLocationType": "RelativeToWorkspace",
                         "CustomBuildProductsPath": "Out/Products", "CustomBuildIntermediatesPath": "Out/Intermediates"},
    "custom-absolute": {"BuildLocationStyle": "CustomLocation", "CustomBuildLocationType": "Absolute",
                        "CustomBuildProductsPath": "/tmp/nomac-out/Products", "CustomBuildIntermediatesPath": "/tmp/nomac-out/Intermediates"},
    "derived-relative": {"DerivedDataLocationStyle": "WorkspaceRelativePath", "DerivedDataCustomLocation": "DD"},
    "derived-absolute": {"DerivedDataLocationStyle": "AbsolutePath", "DerivedDataCustomLocation": "/tmp/nomac-dd"},
    "derived-default": {"DerivedDataLocationStyle": "Default"},
    "custom-no-paths": {"BuildLocationStyle": "CustomLocation", "CustomBuildLocationType": "RelativeToWorkspace"},
    "custom-no-type": {"BuildLocationStyle": "CustomLocation", "CustomBuildProductsPath": "Out/Products", "CustomBuildIntermediatesPath": "Out/Intermediates"},
    "custom-products-only": {"BuildLocationStyle": "CustomLocation", "CustomBuildLocationType": "RelativeToWorkspace", "CustomBuildProductsPath": "Out/Products"},
    "derived-no-location": {"DerivedDataLocationStyle": "WorkspaceRelativePath"},
    "derived-and-custom": {"DerivedDataLocationStyle": "WorkspaceRelativePath", "DerivedDataCustomLocation": "DD", "BuildLocationStyle": "CustomLocation",
                           "CustomBuildLocationType": "RelativeToDerivedData", "CustomBuildProductsPath": "Out/Products", "CustomBuildIntermediatesPath": "Out/Intermediates"},
    "derived-and-target-settings": {"DerivedDataLocationStyle": "WorkspaceRelativePath", "DerivedDataCustomLocation": "DD", "BuildLocationStyle": "UseTargetSettings"},
    "unknown-style": {"BuildLocationStyle": "Mystery", "DerivedDataLocationStyle": "Mystery"},
}


def keyed(scheme_text):
    return scheme_text.replace('version = "1.7"', 'wasCreatedForAppExtension = "YES"\n   version = "1.7"')


def scheme_extension_key():
    # The fuzzer's seed 400029: a shared scheme with wasCreatedForAppExtension = YES for a watch
    # app, and -list shows that name twice. Each kind of target gets one shared scheme of its name
    # with the key, one without, and one with the key under another name.
    targets = Targets()
    container = "container:P.xcodeproj"
    files = {}
    kinds = [("App", APPLICATION, "iphoneos", "app"), ("Fw", "com.apple.product-type.framework", "iphoneos", "framework"),
             ("Ext", APPEX, "iphoneos", "appex"), ("WatchOnly", APPLICATION, "watchos", "app"),
             ("Watch2", "com.apple.product-type.application.watchapp2", "watchos", "app"),
             ("WatchExt", "com.apple.product-type.watchkit2-extension", "watchos", "appex"),
             ("Mac", APPLICATION, "macosx", "app"), ("Tv", APPLICATION, "appletvos", "app"), ("Vision", APPLICATION, "xros", "app"),
             ("Clip", "com.apple.product-type.application.on-demand-install-capable", "iphoneos", "app"),
             ("Container", "com.apple.product-type.application.watchapp2-container", "iphoneos", "app"),
             ("Legacy1", "com.apple.product-type.application.watchapp", "watchos", "app"),
             ("Messages", "com.apple.product-type.application.messages", "iphoneos", "app"),
             ("Tool", "com.apple.product-type.tool", "macosx", "tool"), ("Lib", "com.apple.product-type.library.static", "iphoneos", "a"),
             ("Bundle", "com.apple.product-type.bundle", "iphoneos", "bundle"), ("ExKit", "com.apple.product-type.extensionkit-extension", "iphoneos", "appex")]
    for name, product_type, sdk, suffix in kinds:
        for variant, scheme_name, flagged in [("Keyed", f"{name}Keyed", True), ("Plain", f"{name}Plain", False), ("Other", f"{name}Other", True)]:
            target_name = scheme_name if variant != "Other" else f"{name}Other"
            target, _ = targets.add(target_name, product_type, {}, sdk=sdk)
            shared_name = scheme_name if variant != "Other" else f"{name} Elsewhere"
            buildable = (target, f"{target_name}.{suffix}", target_name, container)
            text = scheme_file(build=[(*buildable, True)], launch=("product", buildable) if suffix == "app" else None)
            if flagged:
                text = keyed(text)
            files[f"P.xcodeproj/xcshareddata/xcschemes/{shared_name}.xcscheme"] = text
    # The shapes Xcode's templates write: an extension's scheme builds it and its app and launches
    # the app, shared or per-user, and an app's scheme with the key and no launch.
    extension, _ = targets.add("Pair Ext", APPEX, {})
    host, _ = targets.add("PairHost", APPLICATION, {})
    pair = [(extension, "Pair Ext.appex", "Pair Ext", container, True), (host, "PairHost.app", "PairHost", container, True)]
    files["P.xcodeproj/xcshareddata/xcschemes/Pair Ext.xcscheme"] = keyed(scheme_file(build=pair, launch=("product", pair[1][:4])))
    user_app, _ = targets.add("UserKeyed", APPLICATION, {})
    user_buildable = (user_app, "UserKeyed.app", "UserKeyed", container)
    files[f"{user_schemes_folder('P.xcodeproj')}/UserKeyed.xcscheme"] = keyed(scheme_file(build=[(*user_buildable, True)], launch=("product", user_buildable)))
    quiet, _ = targets.add("NoLaunch", APPLICATION, {})
    files["P.xcodeproj/xcshareddata/xcschemes/NoLaunch.xcscheme"] = keyed(scheme_file(build=[(quiet, "NoLaunch.app", "NoLaunch", container, True)]))
    profiled, _ = targets.add("ProfileKeyed", APPLICATION, {})
    files["P.xcodeproj/xcshareddata/xcschemes/ProfileKeyed.xcscheme"] = keyed(scheme_file(
        build=[(profiled, "ProfileKeyed.app", "ProfileKeyed", container, True)], profile=("product", (profiled, "ProfileKeyed.app", "ProfileKeyed", container))))
    both, _ = targets.add("BothKeyed", APPLICATION, {})
    both_buildable = (both, "BothKeyed.app", "BothKeyed", container)
    files["P.xcodeproj/xcshareddata/xcschemes/BothKeyed.xcscheme"] = keyed(scheme_file(
        build=[(*both_buildable, True)], launch=("product", both_buildable), profile=("product", both_buildable)))
    launched_no, _ = targets.add("KeyNoLaunched", APPLICATION, {})
    launched_buildable = (launched_no, "KeyNoLaunched.app", "KeyNoLaunched", container)
    files["P.xcodeproj/xcshareddata/xcschemes/KeyNoLaunched.xcscheme"] = scheme_file(build=[(*launched_buildable, True)], launch=("product", launched_buildable)).replace(
        'version = "1.7"', 'wasCreatedForAppExtension = "NO"\n   version = "1.7"')
    remote, _ = targets.add("RemoteKeyed", APPLICATION, {})
    remote_buildable = (remote, "RemoteKeyed.app", "RemoteKeyed", container)
    files["P.xcodeproj/xcshareddata/xcschemes/RemoteKeyed.xcscheme"] = keyed(scheme_file(build=[(*remote_buildable, True)], launch=("remote", remote_buildable)))
    no_value, _ = targets.add("KeyNo", APPLICATION, {})
    files["P.xcodeproj/xcshareddata/xcschemes/KeyNo.xcscheme"] = scheme_file(build=[(no_value, "KeyNo.app", "KeyNo", container, True)]).replace(
        'version = "1.7"', 'wasCreatedForAppExtension = "NO"\n   version = "1.7"')
    return targets.project(files)


def observe_scheme_extension_key(run):
    run("list", "-list", "-json")


def info_plist_conditions():
    # The fuzzer's targets that set only `INFOPLIST_FILE[sdk=iphoneos*]` take the identifier of
    # that plist, and watch container stubs with no Info.plist settings report
    # $(PRODUCT_BUNDLE_IDENTIFIER). Each plist's identifier names its folder; only the targets
    # that say so set GENERATE_INFOPLIST_FILE.
    targets = Targets()
    variants = [
        ("DeviceOnly", APPLICATION, {pbx_string("INFOPLIST_FILE[sdk=iphoneos*]"): "Device/Info.plist"}),
        ("BaseAndDevice", APPLICATION, {"INFOPLIST_FILE": "Base/Info.plist", pbx_string("INFOPLIST_FILE[sdk=iphoneos*]"): "Device/Info.plist"}),
        ("SimulatorOnly", APPLICATION, {pbx_string("INFOPLIST_FILE[sdk=iphonesimulator*]"): "Simulator/Info.plist"}),
        ("BaseAndSimulator", APPLICATION, {"INFOPLIST_FILE": "Base/Info.plist", pbx_string("INFOPLIST_FILE[sdk=iphonesimulator*]"): "Simulator/Info.plist"}),
        ("MacOnly", APPLICATION, {pbx_string("INFOPLIST_FILE[sdk=macosx*]"): "Mac/Info.plist", "SDKROOT": "macosx"}),
        ("ArchOnly", APPLICATION, {pbx_string("INFOPLIST_FILE[arch=arm64]"): "Arch/Info.plist"}),
        ("BaseAndArch", APPLICATION, {"INFOPLIST_FILE": "Base/Info.plist", pbx_string("INFOPLIST_FILE[arch=x86_64]"): "Arch/Info.plist"}),
        ("ConfigOnly", APPLICATION, {pbx_string("INFOPLIST_FILE[config=Release]"): "Config/Info.plist"}),
        ("GenerateMacro", APPLICATION, {"GENERATE_INFOPLIST_FILE": pbx_string("$(NOMAC_GENERATE)"), "NOMAC_GENERATE": "YES"}),
        ("GenerateConditional", APPLICATION, {pbx_string("GENERATE_INFOPLIST_FILE[sdk=iphoneos*]"): "YES"}),
        ("GenerateLowercase", APPLICATION, {"GENERATE_INFOPLIST_FILE": "yes"}),
        ("GenerateNo", APPLICATION, {"GENERATE_INFOPLIST_FILE": "NO"}),
    ] + [(f"Generate-{value}", APPLICATION, {"GENERATE_INFOPLIST_FILE": pbx_string(value)})
         for value in ["Yes", "true", "TRUE", "1", "7", "Y", "t", "on", "0", "nope", "", " YES", "+1", "-0", "007", "\tYES", "00", "+YES", "0Y", "0t", "\nYES", "-1"]] + [(f"Kind{index:02d}", f"com.apple.product-type.{kind}", {}) for index, kind in enumerate(PRODUCT_FILES, 1)]
    for name, product_type, settings in variants:
        values = dict(settings)
        targets.add(name, product_type, values, sdk=values.pop("SDKROOT", "iphoneos"))
    targets.pending = [(target, name, kind, {key: value for key, value in values.items() if key != "GENERATE_INFOPLIST_FILE" or key in dict(variants_settings)},
                        reference, configuration_list, list_ids)
                       for (target, name, kind, values, reference, configuration_list, list_ids), (_, _, variants_settings)
                       in zip(targets.pending, variants)]
    files = {f"{folder}/Info.plist": info_plist(None).replace("$(PRODUCT_BUNDLE_IDENTIFIER)", f"org.nomac.from-plist.{folder.lower()}")
             for folder in ["Device", "Base", "Simulator", "Mac", "Arch", "Config"]}
    return targets.project(files)


def synchronized_search_paths(project_settings=None):
    # The fuzzer's targets that link a static library or a framework from a synchronized folder
    # get LIBRARY_SEARCH_PATHS or FRAMEWORK_SEARCH_PATHS = "$(inherited) $(PROJECT_DIR)/<folder>".
    folders = [
        ("S00000000000000000000001", "Libs", [("X00000000000000000000003", "Excluded", {"membershipExceptions": pbx_list(["libA.a", "Sub/libB.a"])}),
                                              ("X00000000000000000000004", "Added", {"membershipExceptions": pbx_list(["Sub/libB.a"])})]),
        ("S00000000000000000000002", "My Libs", []),
        ("S00000000000000000000003", "Kinds", []),
        ("S00000000000000000000004", "Nested/Deep", []),
        ("S00000000000000000000005", "R&D (it's) \u00dcn\u00ef", []),
        ("S00000000000000000000006", "XCFrameworks", []),
        ("S00000000000000000000007", "Frameworks", []),
        ("S00000000000000000000008", "Stubs", []),
    ]
    specs = [
        ("Linked", APPLICATION, [FRAMEWORKS], ["S00000000000000000000001"], {}),
        ("NoFrameworksPhase", APPLICATION, [RESOURCES], ["S00000000000000000000001"], {}),
        ("Excluded", APPLICATION, [FRAMEWORKS], ["S00000000000000000000001"], {}),
        ("Added", APPLICATION, [FRAMEWORKS], [], {}),
        ("Spaces", APPLICATION, [FRAMEWORKS], ["S00000000000000000000002"], {}),
        ("OwnSetting", APPLICATION, [FRAMEWORKS], ["S00000000000000000000001"],
         {"LIBRARY_SEARCH_PATHS": pbx_string("/custom/lib"), "FRAMEWORK_SEARCH_PATHS": pbx_list(["$(inherited)", "/custom/frameworks"])}),
        ("Kinds", APPLICATION, [FRAMEWORKS], ["S00000000000000000000003"], {}),
        ("TwoFolders", APPLICATION, [FRAMEWORKS], ["S00000000000000000000002", "S00000000000000000000001"], {}),
        ("Nested", APPLICATION, [FRAMEWORKS], ["S00000000000000000000004"], {}),
        ("Resources", APPLICATION, [RESOURCES, FRAMEWORKS], ["S00000000000000000000004"], {}),
        ("Odd", APPLICATION, [FRAMEWORKS], ["S00000000000000000000005"], {}),
        ("Xcconfig", APPLICATION, [FRAMEWORKS], ["S00000000000000000000004"], {}),
        ("Empty", APPLICATION, [FRAMEWORKS], ["S00000000000000000000004"], {"LIBRARY_SEARCH_PATHS": '""'}),
        ("XCFrameworkOnly", APPLICATION, [FRAMEWORKS], ["S00000000000000000000006"], {}),
        ("FrameworkOnly", APPLICATION, [FRAMEWORKS], ["S00000000000000000000007"], {}),
        ("StubsOnly", APPLICATION, [FRAMEWORKS], ["S00000000000000000000008"], {}),
        ("OwnSettingWithPath", APPLICATION, [FRAMEWORKS], ["S00000000000000000000001"],
         {"LIBRARY_SEARCH_PATHS": pbx_string("$(inherited) $(PROJECT_DIR)/Libs"), "FRAMEWORK_SEARCH_PATHS": pbx_string('"$(PROJECT_DIR)/Libs"')}),
    ]
    files = {
        "Libs/libA.a": "!<arch>\n", "Libs/Sub/libB.a": "!<arch>\n", "Libs/Sub/Deeper/libC.a": "!<arch>\n", "Libs/Fw.framework/Info.plist": "x\n",
        "My Libs/libS.a": "!<arch>\n", "My Libs/Space Kit.framework/Info.plist": "x\n",
        "Kinds/libD.dylib": "x\n", "Kinds/libE.tbd": "--- !tapi-tbd\n", "Kinds/X.xcframework/Info.plist": "x\n", "Kinds/Y.framework/Info.plist": "x\n",
        "Nested/Deep/libN.a": "!<arch>\n", "Nested/Deep/Inner/I.framework/Info.plist": "x\n",
        "R&D (it's) \u00dcn\u00ef/libO.a": "!<arch>\n", "R&D (it's) \u00dcn\u00ef/a \"b\"/O.framework/Info.plist": "x\n",
        "Search.xcconfig": "LIBRARY_SEARCH_PATHS = /from/xcconfig\n",
        "XCFrameworks/X.xcframework/Info.plist": "x\n", "XCFrameworks/Sub/Y.xcframework/Info.plist": "x\n",
        "Frameworks/F.framework/Info.plist": "x\n", "Frameworks/S.framework/Info.plist": "x\n",
        "Stubs/libT.tbd": "--- !tapi-tbd\n", "Stubs/Sub/libD.dylib": "x\n",
    }
    xcconfig = "A00000000000000000000001 /* Search.xcconfig */"
    reference = f'\t\t{xcconfig} = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Search.xcconfig; sourceTree = "<group>"; }};\n'
    return synchronized_project(folders, specs, files, project_settings, bases={"Xcconfig": xcconfig}, extra_objects=reference,
                                extra_children=f"\t\t\t\t{xcconfig},\n")


def synchronized_search_paths_folders():
    # Where a folder is: inside a group with a path, relative to the project directory
    # (SOURCE_ROOT) inside such a group, and at an absolute path outside the project directory
    # (written by place_outside_folder). The project is in App/.
    folders = [
        ("S00000000000000000000001", "Libs", [], {"nested": True}),
        ("S00000000000000000000002", "Rooted", [], {"nested": True, "sourceTree": "SOURCE_ROOT"}),
        ("S00000000000000000000003", "@OUTSIDE@", [], {"sourceTree": '"<absolute>"'}),
        ("S00000000000000000000004", "@INSIDE@", [], {"sourceTree": '"<absolute>"'}),
        ("S00000000000000000000005", "../Beside", [], {}),
    ]
    specs = [
        ("InGroup", APPLICATION, [FRAMEWORKS], ["S00000000000000000000001"], {}),
        ("SourceRoot", APPLICATION, [FRAMEWORKS], ["S00000000000000000000002"], {}),
        ("Absolute", APPLICATION, [FRAMEWORKS], ["S00000000000000000000003"], {}),
        ("AbsoluteInside", APPLICATION, [FRAMEWORKS], ["S00000000000000000000004"], {}),
        ("Beside", APPLICATION, [FRAMEWORKS], ["S00000000000000000000005"], {}),
    ]
    group = pbx_object("G00000000000000000000001", "PBXGroup", {"children": "(\n\t\t\t\tS00000000000000000000001,\n\t\t\t\tS00000000000000000000002,\n\t\t\t)",
                                                               "path": "Vendor", "sourceTree": '"<group>"'})
    files = {"Vendor/Libs/libA.a": "!<arch>\n", "Rooted/libR.a": "!<arch>\n", "Rooted/R.framework/Info.plist": "x\n", "Inside/libI.a": "!<arch>\n"}
    text = synchronized_project(folders, specs, files, extra_objects=group, extra_children="\t\t\t\tG00000000000000000000001,\n")
    return {f"App/{path}": contents for path, contents in text.items()} | {"Elsewhere/libO.a": "!<arch>\n", "Beside/libB.a": "!<arch>\n"}


def place_outside_folder(directory):
    """Names the absolute path of `Elsewhere` in synchronized-search-paths-folders' project."""
    path = directory / "App" / "P.xcodeproj" / "project.pbxproj"
    path.write_text(path.read_text().replace("@OUTSIDE@", str(directory / "Elsewhere")).replace("@INSIDE@", str(directory / "App" / "Inside")))


def scheme_coverage():
    # A shared scheme that only builds its app leaves the app an autocreated scheme of the same name
    # (test-bundles: Shared, listed twice), unless the app has no product reference (schemes:
    # App) or the scheme also launches it. Each scheme here covers its targets in one way.
    targets = Targets()
    container = "container:P.xcodeproj"
    files = {}

    def add(name, product_type=APPLICATION):
        target, _ = targets.add(name, product_type, {})
        extension = PRODUCT_FILES[product_type.removeprefix("com.apple.product-type.")][1].format(name)
        return (target, extension, name, container)

    def entry(buildable, running=True):
        return (*buildable, running)

    def scheme(name, **arguments):
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(**arguments)

    app = add("App01")
    scheme("S01-Build", build=[entry(app)])
    app = add("App02")
    scheme("S02-BuildLaunch", build=[entry(app)], launch=("product", app))
    app = add("App03")
    scheme("S03-LaunchOnly", launch=("product", app))
    app = add("App04")
    scheme("S04-BuildRemote", build=[entry(app)], launch=("remote", app))
    app = add("App05")
    scheme("S05-BuildProfile", build=[entry(app)], profile=("product", app))
    first, second = add("App06"), add("App07")
    scheme("S06-BuildTwoLaunchSecond", build=[entry(first), entry(second)], launch=("product", second))
    app = add("App08")
    scheme("S07-BuildTesting", build=[entry(app, running=False)])
    app = add("App09")
    scheme("S08-BuildPath", build=[entry(app)], launch=("path", None))
    extension = add("Ext01", APPEX)
    scheme("S09-ExtBuild", build=[entry(extension)])
    extension, host = add("Ext02", APPEX), add("Host02")
    targets.depend(host[0], extension[0], "Ext02")
    scheme("S10-ExtHostLaunchAsk", build=[entry(extension), entry(host)], launch=("product", host), profile=("product", host), ask_for_app=True)
    extension, host = add("Ext03", APPEX), add("Host03")
    targets.depend(host[0], extension[0], "Ext03")
    scheme("S11-ExtHostLaunch", build=[entry(extension), entry(host)], launch=("product", host))
    extension, host = add("Ext04", APPEX), add("Host04")
    targets.depend(host[0], extension[0], "Ext04")
    scheme("S12-HostExtLaunch", build=[entry(host), entry(extension)], launch=("product", host))
    framework = add("Fw01", "com.apple.product-type.framework")
    scheme("S13-FwBuild", build=[entry(framework)])
    framework = add("Fw02", "com.apple.product-type.framework")
    scheme("S14-FwBuildTesting", build=[entry(framework, running=False)])
    tests = add("Tests01", UNIT_TEST)
    scheme("S15-TestsBuild", build=[entry(tests, running=False)])
    framework, app = add("Fw03", "com.apple.product-type.framework"), add("App10")
    scheme("S16-FwAppLaunchApp", build=[entry(framework), entry(app)], launch=("product", app))
    built, launched = add("App11"), add("App12")
    scheme("S17-BuildOneLaunchOther", build=[entry(built)], launch=("product", launched))
    app = add("App13")
    scheme("S18-ProfileOnly", profile=("product", app))
    app = add("App14")
    scheme("S19-RemoteOnly", launch=("remote", app))
    app = add("App15")
    scheme("S20-BuildTestingLaunch", build=[entry(app, running=False)], launch=("product", app))
    built, launched = add("Fw04", "com.apple.product-type.framework"), add("App16")
    scheme("S21-FwLaunchOther", build=[entry(built)], launch=("product", launched))
    app, framework = add("App17"), add("Fw05", "com.apple.product-type.framework")
    scheme("S22-TestingFirstLaunchIt", build=[entry(app, running=False), entry(framework)], launch=("product", app))
    return targets.project(files)


STATIC_LIBRARY = "com.apple.product-type.library.static"

# moonlight's project references moonlight-common/moonlight-common.xcodeproj, whose targets get
# schemes. Each project: (ID prefix, targets, referenced projects relative to its folder); a target
# is (name, product type, SDK, the targets it depends on, the products it links), each of the last
# two a (referenced project, target name). P references Sub before Alpha, which sorts first; Sub
# references Deep through `..`; both P and Sub have a `Twin`.
REFERENCE_PROJECTS = {
    "P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib"), ("Alpha/A.xcodeproj", "AlphaLib")],
                           [("Sub/Sub.xcodeproj", "Lib")]),
                          ("Twin", STATIC_LIBRARY, "iphoneos", [], [])],
                    ["Sub/Sub.xcodeproj", "Alpha/A.xcodeproj"]),
    "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [("../Deep/Deep.xcodeproj", "DeepLib")], []),
                                ("TVLib", STATIC_LIBRARY, "appletvos", [], []),
                                ("SubApp", APPLICATION, "iphoneos", [], []),
                                ("Covered", STATIC_LIBRARY, "iphoneos", [], []),
                                ("Twin", STATIC_LIBRARY, "iphoneos", [], [])],
                          ["../Deep/Deep.xcodeproj"]),
    "Alpha/A.xcodeproj": ("C", [("AlphaLib", STATIC_LIBRARY, "iphoneos", [], [])], []),
    "Deep/Deep.xcodeproj": ("D", [("DeepLib", STATIC_LIBRARY, "iphoneos", [], [])], []),
}


def reference_id(prefix, kind, index):
    return f"{prefix}{kind}{index:022d}"


def referencing_project(path, projects):
    """The project file of `projects[path]`: for each project it references, a file reference, a
    Products group of reference proxies and the container item proxies of its dependencies."""
    prefix, target_list, references = projects[path]
    folder = Path(path).parent
    objects, children, references_text, count = "", "", "", 0

    def next_id(kind):
        nonlocal count
        count += 1
        return reference_id(prefix, kind, count)

    def referenced(reference):
        return projects[os.path.normpath(folder / reference)]

    file_ids, proxies = {}, {}
    for reference in references:
        file_id, group_id = next_id("R"), next_id("G")
        file_ids[reference] = file_id
        other_prefix, other_targets, _ = referenced(reference)
        proxy_ids = ""
        for index, (name, product_type, *_) in enumerate(other_targets):
            proxy, container_proxy = next_id("Y"), next_id("X")
            file_type, pattern = PRODUCT_FILES[product_type.removeprefix("com.apple.product-type.")]
            objects += f"""		{proxy} = {{
			isa = PBXReferenceProxy;
			fileType = {pbx_string(file_type)};
			path = {pbx_string(pattern.format(name))};
			remoteRef = {container_proxy};
			sourceTree = BUILT_PRODUCTS_DIR;
		}};
		{container_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {file_id}; proxyType = 2; remoteGlobalIDString = {reference_id(other_prefix, "P", index)}; remoteInfo = {pbx_string(name)}; }};
"""
            proxy_ids += f"\t\t\t\t{proxy},\n"
            proxies[(reference, name)] = proxy
        objects += f"""		{file_id} = {{isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; name = {pbx_string(Path(reference).name)}; path = {pbx_string(reference)}; sourceTree = "<group>"; }};
		{group_id} = {{
			isa = PBXGroup;
			children = (
{proxy_ids}			);
			name = Products;
			sourceTree = "<group>";
		}};
"""
        children += f"\t\t\t\t{file_id},\n"
        references_text += f"\t\t\t\t{{\n\t\t\t\t\tProductGroup = {group_id};\n\t\t\t\t\tProjectRef = {file_id};\n\t\t\t\t}},\n"
    target_ids, products = [], ""
    for index, (name, product_type, sdk, depends, links) in enumerate(target_list):
        target_id, product = reference_id(prefix, "T", index), reference_id(prefix, "P", index)
        target_ids.append(target_id)
        file_type, pattern = PRODUCT_FILES[product_type.removeprefix("com.apple.product-type.")]
        products += (f"\t\t{product} = {{isa = PBXFileReference; explicitFileType = {pbx_string(file_type)}; includeInIndex = 0; "
                     f"path = {pbx_string(pattern.format(name))}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
        children += f"\t\t\t\t{product},\n"
        dependency_ids = ""
        for reference, other in depends:
            other_prefix, other_targets, _ = referenced(reference)
            other_index = [target[0] for target in other_targets].index(other)
            container_proxy, dependency = next_id("X"), next_id("D")
            objects += f"""		{container_proxy} = {{isa = PBXContainerItemProxy; containerPortal = {file_ids[reference]}; proxyType = 1; remoteGlobalIDString = {reference_id(other_prefix, "T", other_index)}; remoteInfo = {pbx_string(other)}; }};
		{dependency} = {{isa = PBXTargetDependency; name = {pbx_string(other)}; targetProxy = {container_proxy}; }};
"""
            dependency_ids += f"\t\t\t\t{dependency},\n"
        build_files = ""
        for reference, other in links:
            build_file = next_id("B")
            objects += f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {proxies[(reference, other)]}; }};\n"
            build_files += f"\t\t\t\t{build_file},\n"
        phase = next_id("F")
        objects += f"""		{phase} = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{build_files}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
        settings = {"SDKROOT": sdk, "PRODUCT_NAME": '"$(TARGET_NAME)"'}
        if product_type == APPLICATION:
            settings.update(GENERATE_INFOPLIST_FILE="YES", PRODUCT_BUNDLE_IDENTIFIER=f"org.nomac.experiment.{prefix}{index}")
        extra = f"\t\t\tdependencies = (\n{dependency_ids}\t\t\t);\n" if dependency_ids else ""
        objects += app_target(target_id, name, [phase], [next_id("L"), next_id("C"), next_id("C")], settings, extra=extra,
                              product_type=product_type, product_reference=product)
    main_group = reference_id(prefix, "M", 0)
    objects += products + f"""		{main_group} = {{
			isa = PBXGroup;
			children = (
{children}			);
			sourceTree = "<group>";
		}};
"""
    project_references = f"\t\t\tprojectReferences = (\n{references_text}\t\t\t);\n" if references_text else ""
    return project(reference_id(prefix, "J", 0), main_group, target_ids, objects, project_references=project_references)


def project_references(workspace=None):
    files = {f"{path}/project.pbxproj": referencing_project(path, REFERENCE_PROJECTS) for path in REFERENCE_PROJECTS}
    sub_targets = [target[0] for target in REFERENCE_PROJECTS["Sub/Sub.xcodeproj"][1]]
    sub_app, covered = (reference_id("B", "T", sub_targets.index(name)) for name in ("SubApp", "Covered"))
    files["Sub/Sub.xcodeproj/xcshareddata/xcschemes/SubShared.xcscheme"] = scheme_file(
        build=[(sub_app, "SubApp.app", "SubApp", "container:Sub.xcodeproj", True)],
        launch=("product", (sub_app, "SubApp.app", "SubApp", "container:Sub.xcodeproj")))
    files["P.xcodeproj/xcshareddata/xcschemes/PShared.xcscheme"] = scheme_file(
        build=[(covered, "libCovered.a", "Covered", "container:Sub/Sub.xcodeproj", True)])
    if workspace:
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(workspace)
    return files


def project_references_missing():
    # A referenced project that is not on disk (a submodule not checked out), before one that is.
    projects = {"P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib"), ("Gone/Gone.xcodeproj", "GoneLib")],
                                       [("Gone/Gone.xcodeproj", "GoneLib")])],
                                ["Gone/Gone.xcodeproj", "Sub/Sub.xcodeproj"]),
                "Gone/Gone.xcodeproj": ("E", [("GoneLib", STATIC_LIBRARY, "iphoneos", [], [])], []),
                "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], [])], [])}
    return {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects if path != "Gone/Gone.xcodeproj"}


def project_references_packages():
    # moonlight's referenced project uses the OpenSSL package, which its main project uses too.
    # Here only the referenced project uses a package: a local one, whose product Lib links.
    projects = {"P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib")], [])], ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], [])], [])}
    files = {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects}
    files.update(package_files("Sub/Kit", "Kit", ['.library(name: "Kit", targets: ["Kit"])'], {"Kit": ("library", [])}))
    text = files["Sub/Sub.xcodeproj/project.pbxproj"]
    text = text.replace("\tobjects = {\n", "\tobjects = {\n\t\tBK0000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Kit; };\n"
                        "\t\tBK0000000000000000000002 = {isa = XCSwiftPackageProductDependency; package = BK0000000000000000000001; productName = Kit; };\n", 1)
    text = text.replace("\t\t\tpreferredProjectObjectVersion", "\t\t\tpackageReferences = (\n\t\t\t\tBK0000000000000000000001,\n\t\t\t);\n"
                        "\t\t\tpreferredProjectObjectVersion", 1)
    files["Sub/Sub.xcodeproj/project.pbxproj"] = text.replace('\t\t\tname = "Lib";\n', "\t\t\tname = \"Lib\";\n\t\t\tpackageProductDependencies = (\n"
                                                              "\t\t\t\tBK0000000000000000000002,\n\t\t\t);\n", 1)
    return files


def project_references_stale():
    # A target deleted from a referenced project that is on disk (Gone), which the referencing
    # project still depends on and links, next to one that is still there (Lib).
    projects = {"P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib"), ("Sub/Sub.xcodeproj", "Gone")],
                                       [("Sub/Sub.xcodeproj", "Lib"), ("Sub/Sub.xcodeproj", "Gone")])],
                                ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], []), ("Gone", STATIC_LIBRARY, "iphoneos", [], [])], [])}
    files = {"P.xcodeproj/project.pbxproj": referencing_project("P.xcodeproj", projects)}
    projects["Sub/Sub.xcodeproj"] = ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], [])], [])
    files["Sub/Sub.xcodeproj/project.pbxproj"] = referencing_project("Sub/Sub.xcodeproj", projects)
    return files


def project_references_renamed():
    # delta's Harmony links CwlPreconditionTesting.framework through a proxy whose remote ID the
    # referenced project no longer has, though a target of the proxy's remoteInfo is there. Sub is
    # written again with other object IDs: every remote ID of P's proxies is stale, every name kept.
    projects = {"P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib")], [("Sub/Sub.xcodeproj", "Lib")])],
                                ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], [])], [])}
    files = {"P.xcodeproj/project.pbxproj": referencing_project("P.xcodeproj", projects)}
    projects["Sub/Sub.xcodeproj"] = ("C", [("Lib", STATIC_LIBRARY, "iphoneos", [], [])], [])
    files["Sub/Sub.xcodeproj/project.pbxproj"] = referencing_project("Sub/Sub.xcodeproj", projects)
    return files


def project_references_bundles():
    # A referenced project's targets whose autocreated schemes depend on their evaluated settings:
    # a unit test bundle that depends on nothing, and an app extension.
    projects = {"P.xcodeproj": ("A", [("App", APPLICATION, "iphoneos", [("Sub/Sub.xcodeproj", "Lib")], [])], ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [("Lib", STATIC_LIBRARY, "iphoneos", [], []), ("SubTests", UNIT_TEST, "iphoneos", [], []),
                                            ("SubExtension", "com.apple.product-type.app-extension", "iphoneos", [], [])], [])}
    return {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects}


def workspace_twins():
    # Two projects copied from one template have the same object IDs; each app links its own
    # project's framework, whose product reference has the same ID in both.
    files = {"W.xcworkspace/contents.xcworkspacedata": workspace_contents(["One/P.xcodeproj", "Two/P.xcodeproj"])}
    framework = "com.apple.product-type.framework"
    for folder in ["One", "Two"]:
        objects = """		B00000000000000000000001 = {isa = PBXBuildFile; fileRef = P00000000000000000000002; };
		F00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				P00000000000000000000001,
				P00000000000000000000002,
			);
			sourceTree = "<group>";
		};
		F00000000000000000000004 = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				B00000000000000000000001,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
        objects += product_file("P00000000000000000000001", f"{folder}App", APPLICATION) + product_file("P00000000000000000000002", f"{folder}Fw", framework)
        objects += app_target("C00000000000000000000001", f"{folder}App", ["F00000000000000000000004"],
                              ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                              product_reference="P00000000000000000000001")
        objects += app_target("C00000000000000000000002", f"{folder}Fw", [], ["F000000000000000000000UL", "F000000000000000000000UD", "F000000000000000000000UR"],
                              APP_SETTINGS, product_type=framework, product_reference="P00000000000000000000002")
        files[f"{folder}/P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002",
                                                                 ["C00000000000000000000001", "C00000000000000000000002"], objects)
    return files


def project_reference_names(workspace=False):
    # project-references: P's and Sub's targets are both named Twin, and -list shows Twin once.
    # Here each name is shared by two projects: the root and one before it in path order (One),
    # the root and one after it (Two), two others (Three). Q references Z before A; the
    # workspace lists Z, Q, A and no project references another.
    def library(name):
        return name, STATIC_LIBRARY, "iphoneos", [], []

    projects = {"Q.xcodeproj": ("A", [library("One"), library("Two")], [] if workspace else ["Z/Z.xcodeproj", "A/A.xcodeproj"]),
                "A/A.xcodeproj": ("B", [library("One"), library("Three")], []),
                "Z/Z.xcodeproj": ("C", [library("Two"), library("Three")], [])}
    files = {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects}
    if workspace:
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["Z/Z.xcodeproj", "Q.xcodeproj", "A/A.xcodeproj"])
    return files


def observe_project_reference_names(run):
    run("list", "-list", "-json")
    for name in ["One", "Two", "Three"]:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")


def observe_project_references(run, key="project"):
    run("list-text", "-list")
    observe_every_scheme(run, key=key)
    run("scheme-TVLib-tvos", "-showBuildSettings", "-scheme", "TVLib", "-destination", "generic/platform=tvOS")
    if key == "project":
        run("settings-default", "-showBuildSettings")
        run("settings-target-Lib", "-showBuildSettings", "-target", "Lib")
        run("settings-alltargets", "-showBuildSettings", "-alltargets")


# intents-codegen: mastodon's Intents.intentdefinition build files (one with `ATTRIBUTES = (codegen, )`)
# and nextcloud's Intent.intentdefinition variant group carry `intentsCodegenVisibility: "public"`
# in the PIF. Each build file here differs from the others in its reference's type, its phase,
# its settings or, for variant groups, its children.
INTENT_DEFINITION = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>INIntentDefinitionModelVersion</key>
	<string>1.2</string>
	<key>INIntents</key>
	<array/>
</dict>
</plist>
"""
# A build file's settings: None (no settings), the ATTRIBUTES list, or (COMPILER_FLAGS, ATTRIBUTES or None).
INTENT_SETTINGS = [
    None, "codegen", "no_codegen", "public", "private", "project", "Public", "codegen, no_codegen", "no_codegen, codegen", "Weak", "",
    "codegen, Weak", "Weak, codegen", "no_codegen, Weak", "Foo", "CodeSignOnCopy", "Codegen", "NO_CODEGEN", "public_codegen",
    "project_codegen", "private_codegen", "codegen, project_codegen", "project_codegen, codegen", "project_codegen, private_codegen",
    "private_codegen, project_codegen", "private_codegen, no_codegen", "no_codegen, private_codegen", "project_codegen, no_codegen",
    "codegen, private_codegen", "codegen, codegen", "public, codegen", "codegen, public", "no_codegen, no_codegen", "Public, no_codegen",
    "Foo, codegen", "codegen, Foo", "CodeSignOnCopy, codegen", "RemoveHeadersOnCopy, codegen", "Private, codegen", "Project, codegen",
    "Required, codegen", "Optional, codegen", "weak, codegen", "Required", "Foo, Bar", "Foo, no_codegen", "Private", "RemoveHeadersOnCopy",
    "codegen, CodeSignOnCopy", "public_codegen, codegen", "codegen, public_codegen", "Project", "Project, no_codegen", "Private, no_codegen",
    "Weak, private_codegen", "Foo, private_codegen", "CodeSignOnCopy, RemoveHeadersOnCopy, codegen", "Public, Weak", "Public, Private",
    ("-DNOMAC", None), ("-DNOMAC", "codegen"), ("-DNOMAC", "Weak"),
]
MODEL_SETTINGS = [
    None, "no_codegen", "codegen", "Weak", "public", "codegen, Weak", "", "project_codegen", "private_codegen", "codegen, no_codegen",
    "codegen, project_codegen", "Foo", "Foo, codegen", "CodeSignOnCopy, no_codegen", "Public", "Private, codegen", "Project, codegen",
    "CodeSignOnCopy, codegen", "RemoveHeadersOnCopy", "Weak, no_codegen", ("-DNOMAC", None),
]
# (path, lastKnownFileType, phase, settings)
CODEGEN_FILES = ([(f"I{index:02d}.intentdefinition", "file.intentdefinition", "Sources", value) for index, value in enumerate(INTENT_SETTINGS, 1)]
                 + [(f"M{index:02d}.mlmodel", "file.mlmodel", "Sources", value) for index, value in enumerate(MODEL_SETTINGS, 1)] + [
    ("R01.intentdefinition", "file.intentdefinition", "Resources", None), ("R02.intentdefinition", "file.intentdefinition", "Resources", "no_codegen"),
    ("R03.intentdefinition", "file.intentdefinition", "CopyFiles", None), ("R04.mlmodel", "file.mlmodel", "Resources", None),
    ("R05.mlmodel", "file.mlmodel", "CopyFiles", None), ("R06.intentdefinition", "file.intentdefinition", "Resources", "codegen"),
    ("T01.intentdefinition", "text", "Sources", None), ("T02.txt", "file.intentdefinition", "Sources", None),
    ("T03.intentdefinition", "text.xml", "Sources", "codegen"), ("Missing.intentdefinition", "file.intentdefinition", "Sources", None),
    ("P01.mlpackage", "folder.mlpackage", "Sources", None), ("P02.mlpackage", "folder.mlpackage", "Sources", "no_codegen"),
    ("P03.mlpackage", "folder.mlpackage", "Sources", "codegen, Weak"), ("C01.mlmodelc", "wrapper.mlmodelc", "Sources", None),
    ("S01.swift", "sourcecode.swift", "Sources", None), ("S02.swift", "sourcecode.swift", "Sources", "codegen"),
    ("S03.swift", "sourcecode.swift", "Sources", "no_codegen"), ("S04.strings", "text.plist.strings", "Resources", "codegen"),
])
# Variant groups in the Sources phase: (name, [(child name or None, child path, child type)], settings).
CODEGEN_VARIANTS = [
    ("V01.intentdefinition", [("Base", "Base.lproj/V01.intentdefinition", "file.intentdefinition")], None),
    ("V02.intentdefinition", [("Base", "Base.lproj/V02.intentdefinition", "file.intentdefinition")], "no_codegen"),
    ("V03.intentdefinition", [("Base", "Base.lproj/V03.intentdefinition", "text")], None),
    ("V04.txt", [("Base", "Base.lproj/V04.txt", "file.intentdefinition")], None),
    ("V05.intentdefinition", [("Base", "Base.lproj/V05.intentdefinition", "file.intentdefinition"), ("en", "en.lproj/V05.strings", "text.plist.strings")], None),
    ("V06.intentdefinition", [("en", "en.lproj/V06.strings", "text.plist.strings"), ("Base", "Base.lproj/V06.intentdefinition", "file.intentdefinition")], None),
    ("V07.intentdefinition", [("Base", "Base.lproj/V07.txt", "text"), ("en", "en.lproj/V07.intentdefinition", "file.intentdefinition")], None),
    ("V08.intentdefinition", [("en", "en.lproj/V08.mlmodel", "file.mlmodel"), ("Base", "Base.lproj/V08.intentdefinition", "file.intentdefinition")], None),
    ("V09.intentdefinition", [], None),
    ("V10.intentdefinition", [("fr", "fr.lproj/V10.strings", "text.plist.strings"), ("en", "en.lproj/V10.intentdefinition", "file.intentdefinition")], None),
    ("V11.intentdefinition", [("en", "en.lproj/V11.strings", "text.plist.strings"), ("fr", "fr.lproj/V11.intentdefinition", "file.intentdefinition")], None),
    ("V12.intentdefinition", [("fr", "fr.lproj/V12.intentdefinition", "file.intentdefinition"), ("de", "de.lproj/V12.strings", "text.plist.strings")], None),
    ("V13.intentdefinition", [("de", "de.lproj/V13.strings", "text.plist.strings"), ("fr", "fr.lproj/V13.intentdefinition", "file.intentdefinition")], None),
    ("V14.intentdefinition", [("en", "en.lproj/V14.txt", "text"), ("Base", "Base.lproj/V14.intentdefinition", "file.intentdefinition")], None),
    ("V15.intentdefinition", [("Base", "Base.lproj/V15.strings", "text.plist.strings"), ("en", "en.lproj/V15.intentdefinition", "file.intentdefinition")], None),
    ("V16.intentdefinition", [("de", "de.lproj/V16.intentdefinition", "file.intentdefinition"), ("fr", "fr.lproj/V16.mlmodel", "file.mlmodel")], None),
    ("V17.intentdefinition", [("de", "de.lproj/V17.mlmodel", "file.mlmodel"), ("fr", "fr.lproj/V17.intentdefinition", "file.intentdefinition")], None),
    ("Named.strings", [("Base", "Base.lproj/Named.intentdefinition", "file.intentdefinition")], None),
    ("NoExtension", [("Base", "Base.lproj/NoExtension.intentdefinition", "file.intentdefinition")], None),
    ("V20.intentdefinition", [("en", "en.lproj/V20.strings", "text.plist.strings"), ("de", "de.lproj/V20.intentdefinition", "file.intentdefinition")], None),
    ("V21.intentdefinition", [("Base", "Base.lproj/V21.strings", "text.plist.strings"), ("de", "de.lproj/V21.intentdefinition", "file.intentdefinition"),
                              ("en", "en.lproj/V21.strings", "text.plist.strings")], None),
    ("V22.intentdefinition", [("de", "de.lproj/V22.intentdefinition", "file.intentdefinition")], None),
    ("V23.intentdefinition", [("Base", "Base.lproj/V23.mlmodel", "file.mlmodel"), ("en", "en.lproj/V23.intentdefinition", "file.intentdefinition")], None),
    ("V24.intentdefinition", [("en", "en.lproj/V24.intentdefinition", "file.intentdefinition"), ("Base", "Base.lproj/V24.strings", "text.plist.strings")], None),
    ("V25.intentdefinition", [("Base", "fr.lproj/V25.intentdefinition", "file.intentdefinition")], None),
    ("V26.intentdefinition", [(None, "Base.lproj/V26.intentdefinition", "file.intentdefinition")], None),
    ("V27.intentdefinition", [("Base", "Base.lproj/V27.intentdefinition", "file.intentdefinition")], "codegen, Weak"),
    ("V28.intentdefinition", [("Base", "Base.lproj/V28.intentdefinition", "file.intentdefinition")], "private_codegen"),
    ("V29.intentdefinition", [("Base", "Base.lproj/V29.intentdefinition", "file.intentdefinition")], "CodeSignOnCopy, codegen"),
]


def build_file_settings(value):
    """The `settings` of a build file: None, an ATTRIBUTES list, or (COMPILER_FLAGS, ATTRIBUTES or None)."""
    if value is None:
        return ""
    flags, attributes = value if isinstance(value, tuple) else (None, value)
    text = f"COMPILER_FLAGS = {pbx_string(flags)}; " if flags else ""
    if attributes is not None:
        text += f"ATTRIBUTES = ({attributes + ', ' if attributes else ''}); "
    return f" settings = {{{text}}};"


def intents_codegen(region="en"):
    targets = Targets()
    target, _ = targets.add("App", APPLICATION, {})
    files, children = {}, ""
    members = {"Sources": [], "Resources": [], "CopyFiles": []}
    for index, (path, file_type, phase, settings) in enumerate(CODEGEN_FILES, 1):
        reference, identifier = f"A{index:023d}", f"Z{index:023d}"
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; "
                            f"path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{identifier} = {{isa = PBXBuildFile; fileRef = {reference};{build_file_settings(settings)} }};\n")
        if path.endswith((".mlpackage", ".mlmodelc")):
            files[f"{path}/Manifest.json"] = "{}\n"
        elif not path.startswith("Missing"):
            files[path] = INTENT_DEFINITION
        children += f"\t\t\t\t{reference},\n"
        members[phase].append(identifier)
    for index, (name, variants, settings) in enumerate(CODEGEN_VARIANTS, 1):
        group, identifier = f"G{index:023d}", f"Y{index:023d}"
        child_ids = ""
        for number, (child_name, path, file_type) in enumerate(variants, 1):
            child = f"H{index:021d}{number:02d}"
            named = f"name = {child_name}; " if child_name else ""
            targets.objects += (f"\t\t{child} = {{isa = PBXFileReference; lastKnownFileType = {file_type}; {named}"
                                f"path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n")
            child_ids += f"{child}, "
            files[path] = INTENT_DEFINITION
        targets.objects += (f"\t\t{group} = {{isa = PBXVariantGroup; children = ({child_ids}); name = {pbx_string(name)}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{identifier} = {{isa = PBXBuildFile; fileRef = {group};{build_file_settings(settings)} }};\n")
        children += f"\t\t\t\t{group},\n"
        members["Sources"].append(identifier)
    phases = {"Sources": "PBXSourcesBuildPhase", "Resources": "PBXResourcesBuildPhase", "CopyFiles": "PBXCopyFilesBuildPhase"}
    for index, (phase, isa) in enumerate(phases.items(), 1):
        phase_id = f"W{index:023d}"
        listed = "".join(f"\t\t\t\t{member},\n" for member in members[phase])
        extra = "\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 7;\n" if phase == "CopyFiles" else ""
        targets.objects += (f"\t\t{phase_id} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n{extra}"
                            f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
        targets.phases[target].append(phase_id)
    result = targets.project(files, group_children=children)
    if region != "en":
        name = "P.xcodeproj/project.pbxproj"
        result[name] = result[name].replace("developmentRegion = en;", f"developmentRegion = {region};").replace(
            "\t\t\t\ten,\n\t\t\t\tBase,\n", f"\t\t\t\t{region},\n\t\t\t\ten,\n\t\t\t\tBase,\n")
    return result


def codegen_file_types():
    # mastodon: intent definitions get `intentsCodegenVisibility: "public"` without attributes,
    # Core ML models "project". One build file per file type, without settings, in a Sources phase.
    targets = Targets()
    target, _ = targets.add("App", APPLICATION, {})
    children, listed = "", ""
    for index, file_type in enumerate(ENCODED_FILE_TYPES + ["folder.mlmodelc", "wrapper.mlmodelc", "file.mlmodelc", "folder.rcproject",
                                                               "file.realitycomposerpro", "file.skybox"], 1):
        reference, build_file = f"A{index:023d}", f"B{index:023d}"
        targets.objects += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = {pbx_string(file_type)}; "
                            f"path = {pbx_string(f'file{index:03d}')}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
        children += f"\t\t\t\t{reference},\n"
        listed += f"\t\t\t\t{build_file},\n"
    targets.objects += (f"\t\tF00000000000000000000004 = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
                        f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    targets.phases[target].append("F00000000000000000000004")
    return targets.project(group_children=children)


# codegen-members: the same files as members of a synchronized folder, with the exception set's
# attributesByRelativePath, publicHeaders, privateHeaders and additionalCompilerFlagsByRelativePath.
CODEGEN_MEMBERS = {"A": None, "B": "no_codegen", "C": "codegen", "E": "private_codegen", "F": "Weak, codegen", "G": "CodeSignOnCopy",
                   "H": "CodeSignOnCopy, codegen", "J": "Foo", "K": "", "L": "Public, codegen"}


def codegen_members():
    files = {"Src/a.swift": "let a = 1\n", "Src/M.mlmodel": "x\n", "Src/N.mlmodel": "x\n", "Src/Q.mlmodel": "x\n",
             "Src/P.mlpackage/Manifest.json": "{}\n", "Src/Base.lproj/D.intentdefinition": INTENT_DEFINITION,
             "Src/en.lproj/D.strings": '"a" = "b";\n',
             **{f"Src/{stem}.intentdefinition": INTENT_DEFINITION for stem in [*CODEGEN_MEMBERS, "PublicHeader", "PrivateHeader", "Flags"]}}
    attributes = {**{f"{stem}.intentdefinition": value for stem, value in CODEGEN_MEMBERS.items() if value is not None},
                  "N.mlmodel": "codegen", "Q.mlmodel": "project_codegen"}
    by_path = "".join(f"\t\t\t\t{pbx_string(path)} = ({value + ', ' if value else ''});\n" for path, value in attributes.items())
    objects = f"""		S00000000000000000000001 /* Src */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				S00000000000000000000002,
			);
			path = Src;
			sourceTree = "<group>";
		}};
		S00000000000000000000002 = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			additionalCompilerFlagsByRelativePath = {{
				"Flags.intentdefinition" = "-DNOMAC";
			}};
			attributesByRelativePath = {{
{by_path}			}};
			membershipExceptions = (
			);
			privateHeaders = (
				PrivateHeader.intentdefinition,
			);
			publicHeaders = (
				PublicHeader.intentdefinition,
			);
			target = C00000000000000000000001;
		}};
		F00000000000000000000004 /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		F00000000000000000000005 /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
{product_file("F00000000000000000000001", "App", APPLICATION)}		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
				S00000000000000000000001 /* Src */,
				F00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
""" + app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */", "F00000000000000000000005 /* Resources */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra="\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tS00000000000000000000001 /* Src */,\n\t\t\t);\n",
                 product_reference="F00000000000000000000001")
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects), **files}


# variant-regions: Xcode names a variant group child's region after the `.lproj` folder of its
# path, not its `name` (intents-codegen: `name = Base; path = fr.lproj/…` is "fr"). Each child here
# differs in its name and the folders of its path.
VARIANT_REGION_CHILDREN = [
    ("Base", "fr.lproj/R01.strings"), (None, "Base.lproj/R02.strings"), ("de", "R03.strings"), (None, "R04.strings"),
    ("de", "sub/fr.lproj/R05.strings"), ("English", "English.lproj/R06.strings"), ("fr", "FR.lproj/R07.strings"),
    ("fr", "fr.lproj/sub/R08.strings"), ("de", "fr.lproj/de.lproj/R09.strings"), ("it", "es.lproj.txt/R10.strings"),
    ("Base", "nl.LPROJ/R11.strings"), ("pt", "pt-BR.lproj/R12.strings"),
]


def variant_regions():
    targets = Targets()
    target, _ = targets.add("App", APPLICATION, {})
    files, children, listed = {}, "", ""
    for index, (name, path) in enumerate(VARIANT_REGION_CHILDREN, 1):
        child, group, build_file = f"H{index:023d}", f"G{index:023d}", f"Y{index:023d}"
        named = f"name = {pbx_string(name)}; " if name else ""
        stem = path.rsplit("/", 1)[-1]
        targets.objects += (f"\t\t{child} = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; {named}"
                            f"path = {pbx_string(path)}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{group} = {{isa = PBXVariantGroup; children = ({child}, ); name = {pbx_string(stem)}; sourceTree = \"<group>\"; }};\n"
                            f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {group}; }};\n")
        files[path] = STRINGS_FILE
        children += f"\t\t\t\t{group},\n"
        listed += f"\t\t\t\t{build_file},\n"
    targets.objects += (f"\t\tW00000000000000000000001 = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
                        f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    targets.phases[target].append("W00000000000000000000001")
    return targets.project(files, group_children=children)


STRINGS_FILE = '"key" = "value";\n'

# synchronized-headers: in codegen-members, intent definitions that publicHeaders or privateHeaders
# name get no headerVisibility, and one whose attributes say Public does. Headers and other
# members here are named in those lists or carry those attributes, in a target with a Headers phase.
SYNCHRONIZED_HEADERS = {"PublicList.h": "public", "PrivateList.h": "private", "Plain.h": None, "PublicList.swift": "public",
                        "PublicList.m": "public", "PrivateList.c": "private", "PublicList.hpp": "public", "PublicAttribute.h": None,
                        "PublicAttribute.swift": None, "PrivateAttribute.m": None, "PublicList.strings": "public", "PublicAttribute.strings": None,
                        "PrivateAttribute.json": None, "PublicList.a": "public", "PublicAttribute.a": None}
SYNCHRONIZED_HEADER_ATTRIBUTES = {"PublicAttribute.h": "Public", "PublicAttribute.swift": "Public", "PrivateAttribute.m": "Private",
                                  "PublicAttribute.strings": "Public", "PrivateAttribute.json": "Private", "PublicAttribute.a": "Public"}


def synchronized_headers():
    files = {f"Src/{name}": "\n" for name in SYNCHRONIZED_HEADERS}
    lists = {visibility: "".join(f"\t\t\t\t{name},\n" for name, value in SYNCHRONIZED_HEADERS.items() if value == visibility)
             for visibility in ["public", "private"]}
    by_path = "".join(f"\t\t\t\t{pbx_string(path)} = ({value}, );\n" for path, value in SYNCHRONIZED_HEADER_ATTRIBUTES.items())
    objects = f"""		S00000000000000000000001 /* Src */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				S00000000000000000000002,
			);
			path = Src;
			sourceTree = "<group>";
		}};
		S00000000000000000000002 = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			attributesByRelativePath = {{
{by_path}			}};
			membershipExceptions = (
			);
			privateHeaders = (
{lists["private"]}			);
			publicHeaders = (
{lists["public"]}			);
			target = C00000000000000000000001;
		}};
		F00000000000000000000003 /* Headers */ = {{isa = PBXHeadersBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		F00000000000000000000004 /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		F00000000000000000000005 /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		F00000000000000000000007 /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
{product_file("F00000000000000000000001", "Kit", "com.apple.product-type.framework")}		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
				S00000000000000000000001 /* Src */,
				F00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
""" + app_target("C00000000000000000000001", "Kit", ["F00000000000000000000003 /* Headers */", "F00000000000000000000004 /* Sources */",
                                                     "F00000000000000000000005 /* Resources */", "F00000000000000000000007 /* Frameworks */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra="\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tS00000000000000000000001 /* Src */,\n\t\t\t);\n",
                 product_type="com.apple.product-type.framework", product_reference="F00000000000000000000001")
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects), **files}

# The differential fuzzer saw synchronized `.modulemap` files in no phase where nomac put them in
# Sources. One member of each extension, for the phase each type joins, in a target with a
# Headers, Sources, Resources and Frameworks phase, and (-2) in one with Sources and Resources.
SYNCHRONIZED_PHASE_EXTENSIONS = [
    "swift", "m", "mm", "c", "cpp", "cc", "cxx", "h", "hpp", "hh", "pch", "modulemap", "exp", "defs", "mig", "s", "asm", "nasm", "ll",
    "metal", "java", "js", "ts", "l", "lm", "y", "ym", "iig", "d", "f", "f77", "f90", "glsl", "cl", "proto", "r", "ada", "adb", "pas",
    "dylan", "nqc", "clp", "applescript", "mk", "i", "ii", "mi", "tbd", "apinotes", "md", "xcconfig", "entitlements", "plist", "strings",
    "stringsdict", "json", "xcstrings", "sh", "py", "rb", "pl", "metallib", "intentdefinition", "mlmodel", "storyboard", "xib", "a",
    "dylib", "o", "txt", "html", "css", "png", "rcproject", "usdz", "xcprivacy", "swiftinterface", "inl", "def", "lproj-less",
    "gpx", "geojson", "sks", "scn", "rtf", "pdf", "ttf", "wav", "mov", "zip", "xcfilelist", "xcappextensionpoints", "exports", "tcc"]
SYNCHRONIZED_PHASE_FOLDERS = ["xcassets", "docc", "framework", "xcframework", "bundle", "mlpackage", "rkassets", "scnassets", "playground",
                              "xcdatamodeld", "icon", "appex"]


def synchronized_phases(headers=True):
    files = {f"Src/t_{extension}.{extension}": "x\n" for extension in SYNCHRONIZED_PHASE_EXTENSIONS}
    files.update({f"Src/f_{extension}.{extension}/inner": "x\n" for extension in SYNCHRONIZED_PHASE_FOLDERS})
    files["Src/Makefile"] = "all:\n"
    phases = ([("F00000000000000000000003", "Headers", "PBXHeadersBuildPhase")] if headers else []) + [
        ("F00000000000000000000004", "Sources", "PBXSourcesBuildPhase"), ("F00000000000000000000005", "Resources", "PBXResourcesBuildPhase")] + (
        [("F00000000000000000000007", "Frameworks", "PBXFrameworksBuildPhase")] if headers else [])
    objects = '\t\tS00000000000000000000001 /* Src */ = {isa = PBXFileSystemSynchronizedRootGroup; path = Src; sourceTree = "<group>"; };\n'
    for identifier, name, isa in phases:
        objects += f"\t\t{identifier} /* {name} */ = {{isa = {isa}; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};\n"
    objects += f"""{product_file("F00000000000000000000001", "Kit", "com.apple.product-type.framework")}		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
				S00000000000000000000001 /* Src */,
				F00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
""" + app_target("C00000000000000000000001", "Kit", [f"{identifier} /* {name} */" for identifier, name, _ in phases],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra="\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tS00000000000000000000001 /* Src */,\n\t\t\t);\n",
                 product_type="com.apple.product-type.framework", product_reference="F00000000000000000000001")
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects), **files}


def spec_extensions():
    """Every extension a `FileType` specification of the Xcode in DEVELOPER_DIR names."""
    contents = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")).parent
    found = set()
    listing = subprocess.run(["find", str(contents / "SharedFrameworks" / "SwiftBuild.framework"), "-name", "*.xcspec"], capture_output=True, text=True).stdout
    for path in listing.splitlines():
        converted = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", path], capture_output=True)
        if converted.returncode:
            continue
        items = plistlib.loads(converted.stdout)
        for item in items if isinstance(items, list) else [items]:
            if item.get("Type") == "FileType":
                found.update(extension for extension in item.get("Extensions", []) if extension.isalnum())
    return sorted(found)


def synchronized_phases_all():
    # The fuzzer's `.vsh` member, typed sourcecode.glsl, is in no phase of its target, where
    # synchronized-phases' 113 extensions had no such case. One file of every extension the
    # specifications name, in a framework with Headers, Sources, Resources and Frameworks phases.
    specifications = spec_extensions()
    return {**synchronized_phases(), **{f"Src/t_{extension}.{extension}": "x\n" for extension in specifications
                                         if extension not in SYNCHRONIZED_PHASE_EXTENSIONS and extension not in SYNCHRONIZED_PHASE_FOLDERS}}


def provisioning_fallback(project_entries, project_default, variants, xcconfigs=None, project_base=None):
    # mastodon: CODE_SIGN_STYLE is Automatic in each target's Debug, Manual in the project's
    # Release (the default configuration), and set nowhere for Profile and Release Snapshot, whose
    # provisioningStyle is 1; each target's Release names a profile for iphoneos* only. Each target
    # here differs in which of its configurations set CODE_SIGN_STYLE or a provisioning profile,
    # its ProvisioningStyle attribute, its configuration list's default and its base xcconfig.
    # `xcconfigs` replaces PROVISIONING_XCCONFIGS; `project_base` is (index of a project
    # configuration, the xcconfig it is based on).
    xcconfigs = xcconfigs or PROVISIONING_XCCONFIGS
    targets = Targets()
    files = {name: text for name, text in xcconfigs.values()}
    for reference, (name, _) in xcconfigs.items():
        targets.objects += f'\t\t{reference} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {name}; sourceTree = "<group>"; }};\n'
    for name, attribute, styles, default, xcconfig in variants:
        index = len(targets.ids) + 1
        values = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        list_id = f"H{index:023d}"
        entries = []
        for position, configuration in enumerate(["Debug", "Release", "Profile"]):
            extra = styles.get(configuration, {})
            extra = extra if isinstance(extra, dict) else {"CODE_SIGN_STYLE": extra}
            entries.append((f"G{index:021d}{position:02d}", configuration, {**values, **extra}))
        configuration_list = named_configurations(list_id, entries, default)
        if xcconfig is not None:
            position, reference = xcconfig
            head, tail = configuration_list.split(f"\t\tG{index:021d}{position:02d} /* ", 1)
            tail = tail.replace("isa = XCBuildConfiguration;\n", f"isa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {reference};\n", 1)
            configuration_list = f"{head}\t\tG{index:021d}{position:02d} /* {tail}"
        target, _ = targets.add(name, APPLICATION, {}, configuration_list=configuration_list, list_ids=[list_id])
        if attribute:
            targets.attribute(target, f"\t\t\t\t\t\tProvisioningStyle = {attribute};\n")
    base = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}
    entries = ([(configuration, {**base, **settings}) for configuration, settings in project_entries], project_default)
    group = "".join(f"\t\t\t\t{reference} /* {name} */,\n" for reference, (name, _) in xcconfigs.items())
    result = targets.project(files, project_configurations=entries, group_children=group)
    if project_base is not None:
        position, reference = project_base
        name = "P.xcodeproj/project.pbxproj"
        old = f"\t\tF0000000000000000000PC{position:02d} /* {project_entries[position][0]} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
        result[name] = result[name].replace(old, old + f"\t\t\tbaseConfigurationReference = {reference};\n", 1)
    return result


PROVISIONING_XCCONFIGS = {"A00000000000000000000001": ("Manual.xcconfig", "CODE_SIGN_STYLE = Manual\n"),
                          "A00000000000000000000002": ("Specifier.xcconfig", "PROVISIONING_PROFILE_SPECIFIER = Some Profile\n"),
                          "A00000000000000000000003": ("SpecifierIphoneos.xcconfig", "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = Some Profile\n"),
                          "A00000000000000000000004": ("StyleIphoneos.xcconfig", "CODE_SIGN_STYLE[sdk=iphoneos*] = Manual\n")}
# (target name, ProvisioningStyle attribute, {configuration: CODE_SIGN_STYLE or settings}, the
# target list's default configuration, (index of a configuration, the xcconfig it is based on) or None)
STYLE_FALLBACKS = [
    ("ReleaseManual", None, {"Release": "Manual"}, "Release", None),
    ("DebugManual", None, {"Debug": "Manual"}, "Release", None),
    ("ProfileManual", None, {"Profile": "Manual"}, "Release", None),
    ("DebugAutomaticReleaseManual", None, {"Debug": "Automatic", "Release": "Manual"}, "Release", None),
    ("AttrManualReleaseAutomatic", "Manual", {"Release": "Automatic"}, "Release", None),
    ("AttrAutomaticReleaseManual", "Automatic", {"Release": "Manual"}, "Release", None),
    ("AttrManualReleaseEmpty", "Manual", {"Release": '""'}, "Release", None),
    ("DefaultDebugDebugManual", None, {"Debug": "Manual"}, "Debug", None),
    ("DefaultProfileReleaseManual", None, {"Release": "Manual"}, "Profile", None),
    ("ReleaseMacro", None, {"Release": {"CODE_SIGN_STYLE": pbx_string("$(NOMAC_STYLE)"), "NOMAC_STYLE": "Manual"}}, "Release", None),
    ("ReleaseXcconfig", None, {}, "Release", (1, "A00000000000000000000001")),
    ("ReleaseLowercase", None, {"Release": "manual"}, "Release", None),
    ("ReleaseIphoneos", None, {"Release": {'"CODE_SIGN_STYLE[sdk=iphoneos*]"': "Manual"}}, "Release", None),
    ("ReleaseMacosx", None, {"Release": {'"CODE_SIGN_STYLE[sdk=macosx*]"': "Manual"}}, "Release", None),
    ("ReleaseXcconfigIphoneos", None, {}, "Release", (1, "A00000000000000000000004")),
]
# Project-level CODE_SIGN_STYLE = Manual in Release only.
PROJECT_STYLE_FALLBACKS = [
    ("Nothing", None, {}, "Release", None),
    ("DebugAutomatic", None, {"Debug": "Automatic"}, "Release", None),
    ("DefaultDebug", None, {}, "Debug", None),
    ("DefaultProfile", None, {}, "Profile", None),
    ("AttrAutomatic", "Automatic", {}, "Release", None),
    ("ReleaseAutomatic", None, {"Release": "Automatic"}, "Release", None),
]
IPHONEOS_SPECIFIER = '"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"'
PROFILE = {"PROVISIONING_PROFILE_SPECIFIER": pbx_string("Some Profile")}
# Provisioning profiles, with CODE_SIGN_STYLE set nowhere unless named.
PROFILE_FALLBACKS = [
    ("SpecifierRelease", None, {"Release": PROFILE}, "Release", None),
    ("SpecifierReleaseIphoneos", None, {"Release": {IPHONEOS_SPECIFIER: pbx_string("Some Profile")}}, "Release", None),
    ("SpecifierReleaseIphoneosBesideEmpty", None, {"Release": {"PROVISIONING_PROFILE_SPECIFIER": '""', IPHONEOS_SPECIFIER: pbx_string("Some Profile")}},
     "Release", None),
    ("SpecifierReleaseMacosx", None, {"Release": {'"PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]"': pbx_string("Some Profile")}}, "Release", None),
    ("SpecifierDebug", None, {"Debug": PROFILE}, "Release", None),
    ("SpecifierProfile", None, {"Profile": PROFILE}, "Release", None),
    ("SpecifierEmpty", None, {name: {"PROVISIONING_PROFILE_SPECIFIER": '""'} for name in ["Debug", "Release", "Profile"]}, "Release", None),
    ("SpecifierReleaseDebugAutomatic", None, {"Debug": "Automatic", "Release": PROFILE}, "Release", None),
    ("SpecifierReleaseAutomatic", None, {"Release": {**PROFILE, "CODE_SIGN_STYLE": "Automatic"}}, "Release", None),
    ("SpecifierReleaseAttrAutomatic", "Automatic", {"Release": PROFILE}, "Release", None),
    ("SpecifierReleaseDefaultDebug", None, {"Release": PROFILE}, "Debug", None),
    ("SpecifierMacro", None, {"Release": {"PROVISIONING_PROFILE_SPECIFIER": pbx_string("$(NOMAC_PROFILE)"), "NOMAC_PROFILE": "Some"}}, "Release", None),
    ("SpecifierMacroEmpty", None, {"Release": {"PROVISIONING_PROFILE_SPECIFIER": pbx_string("$(NOMAC_PROFILE)")}}, "Release", None),
    ("SpecifierXcconfig", None, {}, "Release", (1, "A00000000000000000000002")),
    ("SpecifierXcconfigIphoneos", None, {}, "Release", (1, "A00000000000000000000003")),
    ("LegacyProfile", None, {"Release": {"PROVISIONING_PROFILE": pbx_string("01234567-89ab-cdef-0123-456789abcdef")}}, "Release", None),
    ("LegacyProfileIphoneos", None, {"Release": {'"PROVISIONING_PROFILE[sdk=iphoneos*]"': pbx_string("01234567-89ab-cdef-0123-456789abcdef")}},
     "Release", None),
    ("IdentityDistribution", None, {"Release": {"CODE_SIGN_IDENTITY": pbx_string("iPhone Distribution")}}, "Release", None),
    ("TeamOnly", None, {"Release": {"DEVELOPMENT_TEAM": "ABCDE12345"}}, "Release", None),
    ("SpecifierStyleEmpty", None, {"Release": {**PROFILE, "CODE_SIGN_STYLE": '""'}}, "Release", None),
    ("SpecifierStyleLowercase", None, {"Release": {**PROFILE, "CODE_SIGN_STYLE": "manual"}}, "Release", None),
    ("SpecifierStyleBogus", None, {"Release": {**PROFILE, "CODE_SIGN_STYLE": "Bogus"}}, "Release", None),
    ("SpecifierStyleMacroEmpty", None, {"Release": {**PROFILE, "CODE_SIGN_STYLE": pbx_string("$(NOMAC_UNDEFINED)")}}, "Release", None),
    ("SpecifierStyleIphoneosAutomatic", None, {"Release": {**PROFILE, '"CODE_SIGN_STYLE[sdk=iphoneos*]"': "Automatic"}}, "Release", None),
    ("SpecifierWhitespace", None, {"Release": {"PROVISIONING_PROFILE_SPECIFIER": pbx_string(" ")}}, "Release", None),
    ("SpecifierAttrManualDebugAutomatic", "Manual", {"Debug": "Automatic", "Release": PROFILE}, "Release", None),
]
PROJECT_RELEASE_MANUAL = [("Debug", {}), ("Release", {"CODE_SIGN_STYLE": "Manual"}), ("Profile", {})]

# provisioning-conditions: home-assistant's project Release is based on an xcconfig that
# includes one setting CODE_SIGN_STYLE[sdk=iphoneos*] through a macro, then sets
# CODE_SIGN_STYLE = Manual; -showBuildSettings gives Manual, the PIF's provisioningStyle 0. Each
# target's Release here pits a conditional style against an unconditional one in another way.
CONDITION_XCCONFIGS = {
    "A00000000000000000000001": ("IncludeThenPlain.xcconfig", '#include "Inner.xcconfig"\nCODE_SIGN_STYLE = Manual\n'),
    "A00000000000000000000002": ("Inner.xcconfig", "CODE_SIGN_STYLE = Automatic\nCODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\n"),
    "A00000000000000000000003": ("ConditionThenPlain.xcconfig", "CODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\nCODE_SIGN_STYLE = Manual\n"),
    "A00000000000000000000004": ("PlainThenCondition.xcconfig", "CODE_SIGN_STYLE = Manual\nCODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\n"),
    "A00000000000000000000005": ("ManualConditionThenPlain.xcconfig", "CODE_SIGN_STYLE[sdk=iphoneos*] = Manual\nCODE_SIGN_STYLE = Automatic\n"),
    "A00000000000000000000006": ("MacroDefault.xcconfig", '#include "MacroInner.xcconfig"\nCODE_SIGN_STYLE = Manual\n'),
    "A00000000000000000000007": ("MacroInner.xcconfig", "NOMAC_STYLE_DEFAULT = Automatic\nCODE_SIGN_STYLE = $(NOMAC_STYLE_DEFAULT)\n"
                                 "CODE_SIGN_STYLE[sdk=iphoneos*] = $(NOMAC_STYLE_$(TARGET_NAME:c99extidentifier):default=$NOMAC_STYLE_DEFAULT)\n"),
    "A00000000000000000000008": ("ConditionOnly.xcconfig", "CODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\n"),
    "A00000000000000000000009": ("MacosxConditionThenPlain.xcconfig", "CODE_SIGN_STYLE[sdk=macosx*] = Automatic\nCODE_SIGN_STYLE = Manual\n"),
}
CONDITION_FALLBACKS = [
    ("IncludeThenPlain", None, {}, "Release", (1, "A00000000000000000000001")),
    ("ConditionThenPlain", None, {}, "Release", (1, "A00000000000000000000003")),
    ("PlainThenCondition", None, {}, "Release", (1, "A00000000000000000000004")),
    ("ManualConditionThenPlain", None, {}, "Release", (1, "A00000000000000000000005")),
    ("MacroDefault", None, {}, "Release", (1, "A00000000000000000000006")),
    ("MacosxConditionThenPlain", None, {}, "Release", (1, "A00000000000000000000009")),
    ("TargetBoth", None, {"Release": {'"CODE_SIGN_STYLE[sdk=iphoneos*]"': "Automatic", "CODE_SIGN_STYLE": "Manual"}}, "Release", None),
    ("TargetPlainXcconfigCondition", None, {"Release": "Manual"}, "Release", (1, "A00000000000000000000008")),
    ("TargetConditionXcconfigPlain", None, {"Release": {'"CODE_SIGN_STYLE[sdk=iphoneos*]"': "Automatic"}}, "Release", (1, "A00000000000000000000001")),
    ("Nothing", None, {}, "Release", None),
]
THREE_CONFIGURATIONS = [("Debug", {}), ("Release", {}), ("Profile", {})]
OTHER_USER = "nomac-other-user"
FRAMEWORK = "com.apple.product-type.framework"


def user_schemes_folder(container, user=None):
    """The per-user scheme folder of a project or workspace, the current user's by default."""
    return f"{container}/xcuserdata/{user or getpass.getuser()}.xcuserdatad/xcschemes"


def scheme_management(states, suppressed=()):
    """An xcschememanagement.plist: `states` maps a scheme's key (its file name, followed by
    `_^#shared#^_` for a shared scheme) to its `isShown` and `orderHint`; `suppressed` holds
    (target identifier, `primary`) pairs for SuppressBuildableAutocreation."""
    values = {"SchemeUserState": states}
    if suppressed:
        values["SuppressBuildableAutocreation"] = {target: {"primary": primary} for target, primary in suppressed}
    return plistlib.dumps(values).decode()


class SchemeTargets(Targets):
    """Targets of one project with helpers that write schemes building or launching them."""

    def __init__(self, project_name="P"):
        super().__init__()
        self.container = f"container:{project_name}.xcodeproj"
        self.files = {}

    def buildable(self, name, product_type=FRAMEWORK, settings=None, sdk="iphoneos"):
        target, _ = self.add(name, product_type, settings or {}, sdk=sdk)
        if product_type in (AGGREGATE, LEGACY):
            return (target, name, name, self.container)
        return (target, PRODUCT_FILES[product_type.removeprefix("com.apple.product-type.")][1].format(name), name, self.container)

    def depends(self, target, on):
        """Makes the buildable `target` depend on the buildable `on`."""
        self.depend(target[0], on[0], on[2])

    def scheme(self, folder, name, build=(), launch=None, profile=None, testables=(), running=True):
        self.files[f"{folder}/{name}.xcscheme"] = scheme_file(build=[(*entry, running) for entry in build], testables=testables,
                                                             launch=launch and (launch if launch[0] in ("product", "remote") else ("product", launch)),
                                                             profile=profile and ("product", profile))


def user_schemes():
    # The fuzzer's projects have schemes in xcuserdata/<user>.xcuserdatad/xcschemes, which -list
    # shows and -scheme builds. Each target here is covered, or not, by one scheme of one kind in
    # one place; the current user's xcschememanagement.plist hides schemes, gives order hints and
    # suppresses the autocreation of targets, another user's suppresses one target too.
    targets = SchemeTargets()
    shared, mine, other = "P.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("P.xcodeproj"), user_schemes_folder("P.xcodeproj", OTHER_USER)
    app = targets.buildable("AppMine", APPLICATION)
    targets.scheme(mine, "MineLaunch", [app], app)
    targets.scheme(mine, "MineBuild", [targets.buildable("FwMine")])
    app = targets.buildable("AppOther", APPLICATION)
    targets.scheme(other, "OtherLaunch", [app], app)
    targets.scheme(other, "OtherBuild", [targets.buildable("FwOther")])
    targets.scheme(shared, "Dup", [targets.buildable("FwDup")])
    targets.scheme(mine, "Dup", [targets.buildable("LibDup", STATIC_LIBRARY)])
    targets.buildable("FwNamed")
    targets.scheme(mine, "FwNamed", [targets.buildable("LibNamed", STATIC_LIBRARY)])
    targets.scheme(mine, "Hidden", [targets.buildable("FwHidden")])
    targets.scheme(shared, "SharedHidden", [targets.buildable("LibSharedHidden", STATIC_LIBRARY)])
    targets.buildable("FwAutoHidden")
    suppressed, kept, suppressed_app, other_suppressed = (targets.buildable("FwSuppressed"), targets.buildable("FwSuppressedNo"),
                                                          targets.buildable("AppSuppressed", APPLICATION), targets.buildable("FwOtherSuppressed"))
    app = targets.buildable("AppWsUser", APPLICATION)
    targets.scheme(user_schemes_folder("P.xcodeproj/project.xcworkspace"), "WsUser", [app], app)
    targets.scheme("P.xcodeproj/project.xcworkspace/xcshareddata/xcschemes", "WsShared", [targets.buildable("FwWsShared")])
    targets.scheme(mine, "MineTests", testables=[targets.buildable("TestsMine", UNIT_TEST)])
    targets.scheme(mine, "MineBuildApp", [targets.buildable("AppBuildOnly", APPLICATION)])
    targets.scheme(mine, "Hinted", [targets.buildable("FwHinted")])
    targets.files[f"{mine}/xcschememanagement.plist"] = scheme_management({
        "Hidden.xcscheme": {"isShown": False, "orderHint": 0},
        "SharedHidden.xcscheme_^#shared#^_": {"isShown": False, "orderHint": 1},
        "FwAutoHidden.xcscheme": {"isShown": False, "orderHint": 2},
        "MineLaunch.xcscheme": {"isShown": True, "orderHint": 3},
        "Ghost.xcscheme": {"orderHint": 4},
        "Hinted.xcscheme": {"orderHint": 5},
        "Dup.xcscheme_^#shared#^_": {"orderHint": 6},
        "Dup.xcscheme": {"orderHint": 7},
    }, [(suppressed[0], True), (kept[0], False), (suppressed_app[0], True)])
    targets.files[f"{other}/xcschememanagement.plist"] = scheme_management({"OtherBuild.xcscheme": {"isShown": False}}, [(other_suppressed[0], True)])
    return targets.project(targets.files)


def observe_schemes_and(names, key="project"):
    """Lists the schemes, as text, as JSON and as another user, then shows the settings of every
    listed scheme and of `names`."""
    def observe(run):
        run("list-text", "-list")
        run("list-other-user", "-list", "-json", env={"USER": OTHER_USER, "LOGNAME": OTHER_USER})
        listing = run("list", "-list", "-json")
        try:
            listed = json.loads(listing.stdout)[key]["schemes"]
        except (ValueError, KeyError):
            listed = []
        for name in dict.fromkeys(listed + names):
            run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
    return observe


def user_schemes_packages():
    # Per-user schemes of a root package (named Kit, in the folder Kit Folder), a project's per-user
    # scheme building a package product, and a package scheme with a project scheme's name.
    targets = SchemeTargets()
    targets.objects += '\t\tA00000000000000000000005 /* Kit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = "Kit Folder"; sourceTree = "<group>"; };\n'
    targets.scheme("P.xcodeproj/xcshareddata/xcschemes", "Clash", [targets.buildable("FwClash")])

    def package(name):
        return name, name, name, "container:Kit Folder"

    targets.scheme(user_schemes_folder("P.xcodeproj"), "MineKitMore", [package("KitMore")])
    products = [f'.library(name: "{name}", targets: ["{name}"])' for name in ("Kit", "KitExtras", "KitMore")]
    targets.files.update(package_files("Kit Folder", "Kit", products, {name: ("library", []) for name in ("Kit", "KitExtras", "KitMore")},
                                       {"Clash": scheme_file(build=[("Kit", "Kit", "Kit", "container:", True)])}))
    targets.files[f"{user_schemes_folder('Kit Folder/.swiftpm/xcode')}/KitUser.xcscheme"] = scheme_file(build=[("KitExtras", "KitExtras", "KitExtras", "container:", True)])
    return targets.project(targets.files, group_children="\t\t\t\tA00000000000000000000005 /* Kit */,\n")


def user_schemes_workspace():
    # Schemes of one name in several places of a workspace (the fuzzer's `Fuzz (Sample project)`
    # and `Fuzz (Fuzz Workspace)`), and the workspace's own per-user schemes.
    p, q = SchemeTargets("P"), SchemeTargets("Q")
    workspace_shared, workspace_mine = "W.xcworkspace/xcshareddata/xcschemes", user_schemes_folder("W.xcworkspace")
    p_shared, p_mine = "P.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("P.xcodeproj")
    q_shared, q_mine = "Q.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("Q.xcodeproj")
    p.scheme(workspace_shared, "Same", [p.buildable("FwA")])
    p.scheme(p_shared, "Same", [p.buildable("FwB")])
    q.scheme(q_shared, "Same", [q.buildable("FwC")])
    p.scheme(p_shared, "Pair", [p.buildable("FwP")])
    q.scheme(q_shared, "Pair", [q.buildable("FwQ")])
    q.scheme(q_shared, "Pair (P project)", [q.buildable("FwFake")])
    p.scheme(p_mine, "UserPair", [p.buildable("LibU", STATIC_LIBRARY)])
    q.scheme(q_shared, "UserPair", [q.buildable("LibQ", STATIC_LIBRARY)])
    p.scheme(p_shared, "Inner", [p.buildable("FwInner1")])
    p.scheme(p_mine, "Inner", [p.buildable("FwInner2")])
    app = p.buildable("AppW", APPLICATION)
    p.scheme(workspace_mine, "WUser", [app], app)
    p.scheme(user_schemes_folder("W.xcworkspace", OTHER_USER), "WOther", [p.buildable("FwWOther")])
    p.buildable("Twin")
    q.scheme(q_shared, "Twin", [q.buildable("LibTwin", STATIC_LIBRARY)])
    p.buildable("Solo")
    p.scheme(workspace_shared, "Solo", [q.buildable("LibSolo", STATIC_LIBRARY)])
    q.scheme(q_mine, "QUser", [q.buildable("FwQU")])
    p.scheme(workspace_mine, "Mixed", [p.buildable("FwMixedW")])
    p.scheme(p_shared, "Mixed", [p.buildable("FwMixedP")])
    p.scheme(p_mine, "BothUser", [p.buildable("FwBothP")])
    q.scheme(q_mine, "BothUser", [q.buildable("FwBothQ")])
    files = {**p.project(p.files), **q.project(q.files, path="Q.xcodeproj")}
    files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj", "Q.xcodeproj"])
    return files


USER_SCHEMES_WORKSPACE_NAMES = ["Same", "Pair", "UserPair", "Inner", "Twin", "Solo", "Mixed", "BothUser", "WOther"]


# BACKLOG B-065: a shared and a per-user scheme of one name in one project. Names in both
# orders around the project's targets; `kinds`: the shared scheme builds a static library,
# the per-user one a framework; `hints`: an xcschememanagement.plist giving the shared scheme
# the lower order hint, or with `reverse` the per-user one, or with `shared-only` and `user-only`
# a hint to that scheme only; `workspace`: opened through a
# workspace listing the project.
SCHEME_PAIR_NAMES = ["Dup", "Inner", "Aaa", "Zed"]
SCHEME_PAIR_MANY_NAMES = ["A", "B", "C", "Z", "Ab", "Ba", "Zz", "App", "Kit", "Lib", "Core", "Main", "Tests", "Widget", "Zed2", "Yak",
                          "Xray", "Mmm", "Nnn", "Ooo", "Pp", "Qq", "Rr", "Ss", "Tt", "Uu", "Vv", "Ww", "Dup2", "Dupe", "Duq", "Zec", "Zee",
                          "Zea", "Zeb", "Zf", "Ze", "Zedd", "Zed Scheme", "zed"]


def scheme_pairs(kinds=False, hints=None, workspace=False, names=SCHEME_PAIR_NAMES):
    targets = SchemeTargets()
    shared, mine = "P.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("P.xcodeproj")
    states = {}
    for index, name in enumerate(names):
        target = name.replace(" ", "")
        targets.scheme(shared, name, [targets.buildable(f"{target}Shared", STATIC_LIBRARY if kinds else FRAMEWORK)])
        targets.scheme(mine, name, [targets.buildable(f"{target}User")])
        low, high = (f"{name}.xcscheme", f"{name}.xcscheme_^#shared#^_") if hints in ("reverse", "user-only") else (f"{name}.xcscheme_^#shared#^_", f"{name}.xcscheme")
        states[low] = {"orderHint": 2 * index}
        if hints in ("shared", "reverse"):
            states[high] = {"orderHint": 2 * index + 1}
    if hints:
        targets.files[f"{mine}/xcschememanagement.plist"] = scheme_management(states)
    files = targets.project(targets.files)
    if workspace:
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj"])
    return files


def user_schemes_references():
    # The same names in a project and the project it references: shared, per-user, and a per-user
    # scheme of the referenced project launching its app.
    def library(name):
        return name, STATIC_LIBRARY, "iphoneos", [], []

    projects = {"P.xcodeproj": ("A", [library("PLib1"), library("PLib2")], ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [library("SubLib1"), library("SubLib2"), ("SubApp", APPLICATION, "iphoneos", [], [])], [])}
    files = {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects}

    def scheme(folder, name, prefix, index, target, product, container, launch=False):
        buildable = (reference_id(prefix, "T", index), product, target, container)
        files[f"{folder}/{name}.xcscheme"] = scheme_file(build=[(*buildable, True)], launch=("product", buildable) if launch else None)

    scheme("P.xcodeproj/xcshareddata/xcschemes", "Both", "A", 0, "PLib1", "libPLib1.a", "container:P.xcodeproj")
    scheme("Sub/Sub.xcodeproj/xcshareddata/xcschemes", "Both", "B", 0, "SubLib1", "libSubLib1.a", "container:Sub.xcodeproj")
    scheme(user_schemes_folder("P.xcodeproj"), "UBoth", "A", 1, "PLib2", "libPLib2.a", "container:P.xcodeproj")
    scheme(user_schemes_folder("Sub/Sub.xcodeproj"), "UBoth", "B", 1, "SubLib2", "libSubLib2.a", "container:Sub.xcodeproj")
    scheme(user_schemes_folder("Sub/Sub.xcodeproj"), "SubUser", "B", 2, "SubApp", "SubApp.app", "container:Sub.xcodeproj", launch=True)
    return files


def own_test_schemes():
    # test-bundles: DependentTests, which depends on App, gets no scheme of its own, and App's
    # autocreated scheme does not test it. The fuzzer's UnitTests, which depends on an App that a
    # shared scheme launches, gets one. Each bundle here relates to its own target in one way
    # (a dependency, a test host, a TestTargetID), and that target is covered by no scheme, by a
    # shared scheme or by a per-user scheme, none of which tests the bundle.
    targets = SchemeTargets()
    shared, mine = "P.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("P.xcodeproj")
    cases = ([(FRAMEWORK, UNIT_TEST, relation) for relation in ("dep", "id", "dep-id")]
             + [(APPLICATION, UNIT_TEST, relation) for relation in ("dep", "dep-host", "host", "id", "dep-id", "dep-host-id")]
             + [(APPLICATION, UI_TEST, relation) for relation in ("dep", "dep-id")])
    index = 0
    for product_type, bundle_type, relation in cases:
        for cover in ("auto", "shared", "user"):
            index += 1
            name = f"{'Fw' if product_type == FRAMEWORK else 'App'}{index:02d}"
            tested = targets.buildable(name, product_type)
            host = {"TEST_HOST": pbx_string(f"$(BUILT_PRODUCTS_DIR)/{name}.app/{name}"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}
            bundle = targets.buildable(f"{name}{'UI' if bundle_type == UI_TEST else ''}Tests", bundle_type, host if "host" in relation else {})
            if relation.startswith("dep"):
                targets.depend(bundle[0], tested[0], name)
            if relation.endswith("id"):
                targets.attribute(bundle[0], f"\t\t\t\t\t\tTestTargetID = {tested[0]};\n")
            if cover != "auto":
                targets.scheme(shared if cover == "shared" else mine, f"Cover{index:02d}", [tested],
                               tested if product_type == APPLICATION else None)
    # A bundle depending on two frameworks, one autocreated and one a shared scheme builds; and
    # on two frameworks shared schemes build.
    for index, covers in [(40, ("auto", "shared")), (41, ("shared", "shared"))]:
        bundle = targets.buildable(f"Two{index}Tests", UNIT_TEST)
        for letter, cover in zip("AB", covers):
            tested = targets.buildable(f"Fw{index}{letter}")
            targets.depend(bundle[0], tested[0], tested[2])
            if cover == "shared":
                targets.scheme(shared, f"Cover{index}{letter}", [tested])
    return targets.project(targets.files)


def own_test_schemes_hosts():
    # own-test-schemes: a bundle that depends on a target with an autocreated scheme, or whose
    # TEST_HOST is that target's executable, gets no scheme of its own. Here the target gets no
    # scheme (a messages app, a suppressed one), or TEST_HOST names something else: no app, the
    # app's bundle rather than its executable, an app a shared scheme launches while the bundle
    # depends on a covered framework. One bundle is suppressed itself, one depends on an
    # aggregate target.
    targets = SchemeTargets()
    shared, mine = "P.xcodeproj/xcshareddata/xcschemes", user_schemes_folder("P.xcodeproj")

    def host(path):
        return {"TEST_HOST": pbx_string(path), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}

    def executable(name):
        return f"$(BUILT_PRODUCTS_DIR)/{name}.app/{name}"

    targets.buildable("H1Tests", UNIT_TEST, host(executable("Nowhere")))
    targets.buildable("Messages3", "com.apple.product-type.application.messages")
    targets.buildable("H3Tests", UNIT_TEST, host(executable("Messages3")))
    suppressed_app = targets.buildable("App4", APPLICATION)
    targets.buildable("H4Tests", UNIT_TEST, host(executable("App4")))
    targets.buildable("App7", APPLICATION)
    targets.buildable("H7Tests", UNIT_TEST, host("$(BUILT_PRODUCTS_DIR)/App7.app"))
    app, framework = targets.buildable("App8", APPLICATION), targets.buildable("Fw8")
    targets.scheme(shared, "Cover8", [app, framework], app)
    targets.depends(targets.buildable("H8Tests", UNIT_TEST, host(executable("App8"))), framework)
    targets.buildable("App9", APPLICATION)
    bundle, framework = targets.buildable("H9Tests", UNIT_TEST, host(executable("App9"))), targets.buildable("Fw9")
    targets.scheme(shared, "Cover9", [framework])
    targets.depends(bundle, framework)
    targets.depends(targets.buildable("D1Tests", UNIT_TEST), targets.buildable("Messages11", "com.apple.product-type.application.messages"))
    targets.depends(targets.buildable("D2Tests", UNIT_TEST), targets.buildable("Agg12", AGGREGATE))
    suppressed_framework = targets.buildable("Fw13")
    targets.depends(targets.buildable("D3Tests", UNIT_TEST), suppressed_framework)
    suppressed_bundle = targets.buildable("S1Tests", UNIT_TEST)
    targets.files[f"{mine}/xcschememanagement.plist"] = scheme_management(
        {}, [(suppressed_app[0], True), (suppressed_framework[0], True), (suppressed_bundle[0], True)])
    return targets.project(targets.files)



def own_test_schemes_more():
    # The fuzzer's Tests, a skipped testable of a shared scheme, gets no scheme of its own; its
    # Tests of a workspace with three Fuzz targets, which depends on the one with an autocreated
    # scheme, gets one. P: bundles only skipped testables of a shared scheme name, one alone and
    # one depending on a covered framework; bundles of apps whose SDKROOT is auto. P and Q: bundles
    # depending on targets with a name another project's target has, covered or not, or that a
    # shared scheme has; R, in a folder named Ñ: a hosted bundle and a framework's bundle.
    p, q = SchemeTargets("P"), SchemeTargets("Q")
    shared = "P.xcodeproj/xcshareddata/xcschemes"
    alone = p.buildable("SkipTests", UNIT_TEST)
    covered = p.buildable("FwS")
    p.scheme(shared, "CoverFwS", [covered])
    dependent = p.buildable("SkipDepTests", UNIT_TEST)
    p.depends(dependent, covered)
    p.files[f"{shared}/SkipScheme.xcscheme"] = scheme_file(testables=[alone, dependent], skipped=True)
    auto = {"SUPPORTED_PLATFORMS": pbx_string("iphoneos iphonesimulator macosx")}
    for index, hosted in [(1, True), (3, False)]:
        host = p.buildable(f"HostAuto{index}", APPLICATION, auto, sdk="auto")
        settings = {"TEST_HOST": pbx_string(f"$(BUILT_PRODUCTS_DIR)/HostAuto{index}.app/HostAuto{index}"),
                    "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")} if hosted else {}
        p.depends(p.buildable(f"C{index}Tests", UNIT_TEST, settings), host)
    p.scheme(shared, "CoverTwin", [p.buildable("Twin")])
    p.buildable("Twin2")
    p.scheme(shared, "Named", [p.buildable("FwN")])
    for name in ["Twin", "Twin2", "Solo", "Named"]:
        q.depends(q.buildable(f"{name}Tests", UNIT_TEST), q.buildable(name))
    # The fuzzer's third project is in a folder with a non-ASCII name.
    r = SchemeTargets("R")
    hosted = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/HostR.app/HostR"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}
    r.depends(r.buildable("HostRTests", UNIT_TEST, hosted), r.buildable("HostR", APPLICATION))
    r.depends(r.buildable("FwRTests", UNIT_TEST), r.buildable("FwR"))
    # The fuzzer's three apps named Fuzz: P's launched by a shared scheme named Fuzz, Q's only
    # profiled, R's with a bundle; then the same with a framework instead of R's app (Lib), and
    # with P's app only (Solo2).
    for name, kind in [("Fuzz", APPLICATION), ("Lib", FRAMEWORK)]:
        app = p.buildable(name, APPLICATION)
        p.scheme(shared, name, [app], app)
        app = q.buildable(name, APPLICATION)
        q.scheme("Q.xcodeproj/xcshareddata/xcschemes", f"{name} Profile", profile=app)
        r.depends(r.buildable(f"{name}Tests", UNIT_TEST), r.buildable(name, kind))
    app = p.buildable("Solo2", APPLICATION)
    p.scheme(shared, "Solo2", [app], app)
    r.depends(r.buildable("Solo2Tests", UNIT_TEST), r.buildable("Solo2", APPLICATION))
    # A bundle depending on an autocreated framework whose TEST_HOST is a covered app's executable,
    # nothing, a covered app of another project, or an app of another project with the name of
    # the app it depends on, whose SDKROOT is auto.
    def hosted_by(name):
        return {"TEST_HOST": pbx_string(f"$(BUILT_PRODUCTS_DIR)/{name}.app/{name}"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}

    for index, host in [(1, "A1"), (3, "Nowhere")]:
        app = p.buildable(f"A{index}", APPLICATION)
        p.scheme(shared, f"CoverA{index}", [app], app)
        p.depends(p.buildable(f"B{index}Tests", UNIT_TEST, hosted_by(host)), p.buildable(f"F{index}"))
    app = p.buildable("A4", APPLICATION)
    p.scheme(shared, "CoverA4", [app], app)
    q.depends(q.buildable("B4Tests", UNIT_TEST, hosted_by("A4")), q.buildable("F4"))
    app = p.buildable("Same", APPLICATION)
    p.scheme(shared, "CoverSame", [app], app)
    q.depends(q.buildable("SameTests", UNIT_TEST, hosted_by("Same")), q.buildable("Same", APPLICATION, auto, sdk="auto"))
    # The covered app of a project whose configurations are AppStore and Production, the default
    # AppStore (the fuzzer's first project), named by the TEST_HOST of a bundle that depends on an
    # autocreated framework.
    other = SchemeTargets("S")
    configurations = ["AppStore", "Production"]
    index = len(other.ids) + 1
    list_id = f"H{index:023d}"
    values = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.x5"}
    app, _ = other.add("X5", APPLICATION, {}, list_ids=[list_id], configuration_list=named_configurations(
        list_id, [(f"G{index:021d}{position:02d}", name, values) for position, name in enumerate(configurations)], "AppStore"))
    buildable = (app, "X5.app", "X5", other.container)
    other.scheme("S.xcodeproj/xcshareddata/xcschemes", "CoverX5", [buildable], buildable)
    q.depends(q.buildable("B5Tests", UNIT_TEST, hosted_by("X5")), q.buildable("F5"))
    project_configurations = ([(name, {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}) for name in configurations], "AppStore")
    files = {**p.project(p.files), **q.project(q.files, path="Q.xcodeproj"), **r.project(r.files, path="Ñ/R.xcodeproj"),
             **other.project(other.files, path="S.xcodeproj", project_configurations=project_configurations)}
    files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj", "Q.xcodeproj", "Ñ/R.xcodeproj", "S.xcodeproj"])
    return files

# Names whose order in -list tells how xcodebuild sorts: numbers, diacritics, case, punctuation,
# other scripts, ligatures and full-width letters. Shared schemes; targets get the names a
# case-insensitive file system cannot hold next to them.
SCHEME_ORDER_NAMES = ["Item2", "item10", "Émile", "Eve", "ezra", "Ünï Kit", "Unit", "über", "Vendor", "_under", "-dash", "a b", "a-b",
                      "a.b", "a_b", "a+b", "ab", "Zed", "日本", "Ωmega", "Яблоко", "ﬁle", "Ｆull", "file2", "9lives", "10lives",
                      "🙂 smile", " Leading", "Œuvre", "Ab1", "ab2", "Ab10", "x(1)", "x 1", "x1", "x01"]
SCHEME_ORDER_TARGETS = ["zed", "Oeuvre", "strasse", "straße", "UNIT", "über2", "Uber", "Ü", "U", "u"]


def scheme_order():
    targets = SchemeTargets()
    framework = targets.buildable("FwOrder")
    for name in SCHEME_ORDER_NAMES:
        targets.scheme("P.xcodeproj/xcshareddata/xcschemes", name, [framework])
    for name in SCHEME_ORDER_TARGETS:
        targets.buildable(name, STATIC_LIBRARY)
    return targets.project(targets.files)


def scheme_destinations():
    # The fuzzer's Lint scheme builds only an aggregate target and works with an iOS
    # destination; its App-Dev scheme builds an iOS bundle and launches a macOS tool, and fails.
    # The project sets no SDKROOT; each scheme builds, launches or profiles one combination.
    targets = SchemeTargets()
    shared = "P.xcodeproj/xcshareddata/xcschemes"
    for name, kind, sdk in [("Agg", AGGREGATE, None), ("AggIOS", AGGREGATE, "iphoneos"), ("AggMac", AGGREGATE, "macosx"),
                            ("Legacy", LEGACY, None), ("LegacyMac", LEGACY, "macosx"), ("NoSDKFw", FRAMEWORK, None)]:
        targets.scheme(shared, f"{name}Only", [targets.buildable(name, kind, sdk=sdk)])
    aggregate, framework = targets.buildable("AggDeps", AGGREGATE, sdk=None), targets.buildable("MacFwDep", FRAMEWORK, sdk="macosx")
    targets.depend(aggregate[0], framework[0], framework[2])
    targets.scheme(shared, "AggDepsOnly", [aggregate])
    targets.scheme(shared, "AggTesting", [targets.buildable("AggT", AGGREGATE, sdk=None)], running=False)

    def tool(name):
        return targets.buildable(name, "com.apple.product-type.tool", sdk="macosx")

    def bundle(name):
        return targets.buildable(name, "com.apple.product-type.bundle")

    first, second = tool("Tool1"), bundle("Bundle1")
    targets.scheme(shared, "LaunchTool", [first, second], first)
    targets.scheme(shared, "BuildToolBundle", [tool("Tool2"), bundle("Bundle2")])
    first, second = tool("Tool3"), bundle("Bundle3")
    targets.scheme(shared, "LaunchBundle", [first, second], second)
    first, second = tool("Tool4"), targets.buildable("App4", APPLICATION)
    targets.scheme(shared, "LaunchIOSApp", [first, second], second)
    first, second = targets.buildable("MacApp5", APPLICATION, sdk="macosx"), targets.buildable("Fw5")
    targets.scheme(shared, "LaunchMacApp", [first, second], first)
    first, second = tool("Tool6"), bundle("Bundle6")
    targets.scheme(shared, "ProfileTool", [first, second], profile=first)
    first, second = tool("Tool7"), bundle("Bundle7")
    targets.scheme(shared, "RemoteTool", [first, second], ("remote", first))
    targets.scheme(shared, "AggAndMac", [targets.buildable("Agg8", AGGREGATE, sdk=None), targets.buildable("MacFw8", FRAMEWORK, sdk="macosx")])
    first, second = targets.buildable("Agg9", AGGREGATE, sdk=None), tool("Tool9")
    targets.scheme(shared, "AggLaunchTool", [first, second], second)
    first = tool("Tool10")
    targets.scheme(shared, "LaunchToolAlone", [first], first)
    first, second = bundle("Bundle11"), tool("Tool11")
    targets.scheme(shared, "BundleFirstLaunchTool", [first, second], second)
    # The fuzzer's Lint depends on an iOS extension. Targets that depend on targets of another
    # platform, directly or through an aggregate; AggAuto15 has only its autocreated scheme.
    aggregate = targets.buildable("Agg12", AGGREGATE, sdk=None)
    targets.depends(aggregate, targets.buildable("Fw12"))
    targets.scheme(shared, "AggDepIOS", [aggregate])
    first = targets.buildable("MacFw13", FRAMEWORK, sdk="macosx")
    targets.depends(first, targets.buildable("Fw13"))
    targets.scheme(shared, "MacFwDepIOS", [first])
    first = targets.buildable("MacApp14", APPLICATION, sdk="macosx")
    targets.depends(first, targets.buildable("Fw14"))
    targets.scheme(shared, "LaunchMacAppDepIOS", [first], first)
    targets.depends(targets.buildable("AggAuto15", AGGREGATE, sdk=None), targets.buildable("Fw15"))
    first, second = targets.buildable("Agg16", AGGREGATE, sdk=None), targets.buildable("Agg16b", AGGREGATE, sdk=None)
    targets.depends(first, second)
    targets.depends(second, targets.buildable("Fw16"))
    targets.scheme(shared, "AggDeep", [first])
    first = targets.buildable("Fw17")
    targets.depends(first, targets.buildable("MacFw17", FRAMEWORK, sdk="macosx"))
    targets.scheme(shared, "IOSFwDepMac", [first])
    # autocreate-hosts' WatchWidget, whose autocreated scheme also builds an iOS app, fails with
    # an iOS destination. Autocreated schemes of an iOS extension a macOS app depends on, and of
    # a macOS extension an iOS app depends on.
    targets.depends(targets.buildable("MacHost18", APPLICATION, sdk="macosx"), targets.buildable("ExtIOS18", APPEX))
    targets.depends(targets.buildable("Host19", APPLICATION), targets.buildable("ExtMac19", APPEX, sdk="macosx"))
    return targets.project(targets.files, project_settings={"IPHONEOS_DEPLOYMENT_TARGET": "18.0"})


def observe_scheme_destinations(run):
    listing = run("list", "-list", "-json")
    try:
        names = json.loads(listing.stdout)["project"]["schemes"]
    except (ValueError, KeyError):
        names = []
    for name in names:
        run(f"scheme-{name}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
        run(f"scheme-{name}-json", "-showBuildSettings", "-json", "-scheme", name, "-destination", "generic/platform=iOS")
        run(f"scheme-{name}-macos", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=macOS")


def same_name_destinations():
    # The fuzzer's Stickers: -json exits 0 where the same invocation without it exits 64. The
    # project and the project it references each have a Twin, one for iOS, one for macOS.
    projects = {"P.xcodeproj": ("A", [("Twin", STATIC_LIBRARY, "iphoneos", [], [])], ["Sub/Sub.xcodeproj"]),
                "Sub/Sub.xcodeproj": ("B", [("Twin", STATIC_LIBRARY, "macosx", [], [])], [])}
    return {f"{path}/project.pbxproj": referencing_project(path, projects) for path in projects}


def observe_same_name_destinations(run):
    for index in range(6):
        run(f"scheme-Twin-{index}", "-showBuildSettings", "-scheme", "Twin", "-destination", "generic/platform=iOS")
        run(f"scheme-Twin-json-{index}", "-showBuildSettings", "-json", "-scheme", "Twin", "-destination", "generic/platform=iOS")


def test_plan_entries():
    # wikipedia's WikipediaUITests scheme builds its app and, for testing only, a test plan (a
    # TestPlanReference in a BuildActionEntry). Each scheme here builds a plan in another way; each
    # plan names a test bundle of its own that would otherwise get a scheme of its own
    # (test-bundles), for whether a plan in a build action counts as building its bundles.
    targets = Targets()
    container = "container:P.xcodeproj"
    app, _ = targets.add("App", APPLICATION, {})
    hosted, _ = targets.add("AppTests", UNIT_TEST, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")})
    targets.depend(hosted, app, "App")
    app_buildable = (app, "App.app", "App", container)
    files = {}

    def plan(path, bundles, coverage=None):
        options = {} if coverage is None else {"codeCoverage": coverage}
        files[path] = json.dumps({"configurations": [{"id": "A11977F5-134B-4CB5-B798-B2F3F30138CD", "name": "Configuration 1", "options": {}}],
                                  "defaultOptions": options,
                                  "testTargets": [{"target": {"containerPath": container, "identifier": bundle, "name": name}} for bundle, name in bundles],
                                  "version": 1}, indent=2) + "\n"
        return f"container:{path}"

    def loose(index, coverage=None, folder=False):
        name = f"Loose{index:02d}"
        bundle, _ = targets.add(name, UNIT_TEST, {})
        return plan(f"{'Plans/' if folder else ''}P{index:02d}.xctestplan", [(bundle, name)], coverage)

    def scheme(name, **arguments):
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(version="2.1", **arguments)

    launch = ("product", app_buildable)
    scheme("S01-AppPlanTesting", build=[(*app_buildable, True), (loose(1), False)], launch=launch)
    scheme("S02-AppPlanRunning", build=[(*app_buildable, True), (loose(2), True)], launch=launch)
    scheme("S03-PlanRunning", build=[(loose(3), True)])
    scheme("S04-PlanTesting", build=[(loose(4), False)])
    scheme("S05-PlanFirst", build=[(loose(5), True), (*app_buildable, True)], launch=launch)
    scheme("S06-MissingPlan", build=[(*app_buildable, True), ("container:Missing.xctestplan", True)], launch=launch)
    tested = loose(7)
    scheme("S07-PlanAlsoTested", build=[(*app_buildable, True), (tested, False)], plans=[(tested, True)], launch=launch)
    scheme("S08-PlanCoverage", build=[(*app_buildable, True), (loose(8, coverage=True), True)], launch=launch)
    scheme("S09-PlanHostedTests", build=[(plan("P09.xctestplan", [(hosted, "AppTests")]), True)])
    scheme("S10-PlanInFolder", build=[(*app_buildable, True), (loose(10, folder=True), True)], launch=launch)
    # A plan naming two bundles against project order, a bundle both an entry and a plan build,
    # and a bundle no scheme names.
    first, _ = targets.add("Loose11", UNIT_TEST, {})
    second, _ = targets.add("Loose12", UNIT_TEST, {})
    scheme("S11-PlanTwoBundles", build=[(*app_buildable, True), (plan("P11.xctestplan", [(second, "Loose12"), (first, "Loose11")]), True)], launch=launch)
    both, _ = targets.add("Loose13", UNIT_TEST, {})
    scheme("S12-EntryAndPlan", build=[(both, "Loose13.xctest", "Loose13", container, True), (plan("P13.xctestplan", [(both, "Loose13")]), True)])
    targets.add("Loose14", UNIT_TEST, {})
    # The same bundle built for testing only by one entry and for running by the other.
    bundle, _ = targets.add("Loose15", UNIT_TEST, {})
    scheme("S13-EntryTestingPlanRunning", build=[(bundle, "Loose15.xctest", "Loose15", container, False), (plan("P15.xctestplan", [(bundle, "Loose15")]), True)])
    bundle, _ = targets.add("Loose16", UNIT_TEST, {})
    scheme("S14-PlanTestingEntryRunning", build=[(plan("P16.xctestplan", [(bundle, "Loose16")]), False), (*app_buildable, True),
                                                 (bundle, "Loose16.xctest", "Loose16", container, True)], launch=launch)
    bundle, _ = targets.add("Loose17", UNIT_TEST, {})
    scheme("S15-PlanRunningEntryRunning", build=[(plan("P17.xctestplan", [(bundle, "Loose17")]), True), (*app_buildable, True),
                                                 (bundle, "Loose17.xctest", "Loose17", container, True)], launch=launch)
    bundle, _ = targets.add("Loose18", UNIT_TEST, {})
    scheme("S16-EntryTwice", build=[(bundle, "Loose18.xctest", "Loose18", container, True), (*app_buildable, True),
                                    (bundle, "Loose18.xctest", "Loose18", container, True)], launch=launch)
    return targets.project(files)


def copy_files():
    # wikipedia's localization and languages tools copy a man page with dstSubfolderSpec 0 and an
    # absolute dstPath. A tool and an app here each have one copy-files phase per
    # dstSubfolderSpec value (0 to 17, none), without a dstPath, with an empty one, with a
    # relative one and with an absolute one, in that order. copy-files-18: a value above 17.
    return copy_files_project([*range(18), None])


def copy_files_project(specs):
    targets = Targets()
    for name, product_type, sdk in [("Tool", "com.apple.product-type.tool", "macosx"), ("App", APPLICATION, "iphoneos")]:
        target, _ = targets.add(name, product_type, {}, sdk=sdk)
        for spec in specs:
            for path in (None, "", "sub/dir", "/usr/share/man/man1/"):
                phase = targets.next_id("B")
                keys = (f"dstPath = {pbx_string(path)}; " if path is not None else "") + (f"dstSubfolderSpec = {spec}; " if spec is not None else "")
                targets.objects += f"\t\t{phase} = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; {keys}files = (); runOnlyForDeploymentPostprocessing = 0; }};\n"
                targets.phases[target].append(phase)
    return targets.project()


def unicode_names(form):
    """A project whose names and paths are non-ASCII, written in `form` (NFC or NFD) in the
    project file and the scheme files, with some files on disk and some references in the other
    form (`odd` below)."""
    a = lambda text: unicodedata.normalize(form, text)
    odd = lambda text: unicodedata.normalize("NFD" if form == "NFC" else "NFC", text)
    q = lambda text: pbx_string(a(text))
    container = a("Café.xcodeproj")
    files = {
        # Group Ångström: a reference whose file on disk has the same form, one with the other
        # form, one without a type, one missing.
        f"{a('Ångström')}/{a('Zürich.swift')}": "let zurich = 1\n",
        f"{a('Ångström')}/{odd('Über.swift')}": "let uber = 1\n",
        f"{a('Ångström')}/{a('Ñandú.txt')}": "text\n",
        "Named.swift": "let named = 1\n",
        "Plain.swift": "let plain = 1\n",
        f"{a('en.lproj')}/{a('Lôcalizable.strings')}": '"a" = "b";\n',
        f"{a('fr.lproj')}/{a('Lôcalizable.strings')}": '"a" = "c";\n',
        a("Cönfig.xcconfig"): a("INFOPLIST_KEY_NSHumanReadableCopyright = Çopyright\n"),
        odd("Ödd.xcconfig"): "FROM_ODD_XCCONFIG = 1\n",
        # Synchronized folder Sÿnc: members on disk in both forms, exceptions and explicit file
        # types keyed in both forms; Sÿnc2 is on disk in the other form than the project file's.
        f"{a('Sÿnc')}/{a('Émoji.swift')}": "let emoji = 1\n",
        f"{a('Sÿnc')}/{odd('Ëxtra.swift')}": "let extra = 1\n",
        f"{a('Sÿnc')}/{a('Ïgnored.swift')}": "let ignored = 1\n",
        f"{a('Sÿnc')}/{a('Ïgnored2.swift')}": "let ignored2 = 1\n",
        f"{a('Sÿnc')}/{odd('Ïgnored3.swift')}": "let ignored3 = 1\n",
        f"{a('Sÿnc')}/{a('Ñote.dat')}": "let note = 1\n",
        f"{a('Sÿnc')}/{a('Ôther.dat')}": "let other = 1\n",
        f"{a('Sÿnc')}/{odd('Ûnder.dat')}": "let under = 1\n",
        f"{a('Sÿnc')}/{a('Sübdir')}/{odd('Ïnner.swift')}": "let inner = 1\n",
        f"{a('Sÿnc')}/{odd('Sübdir2')}/{a('Ïnner2.swift')}": "let inner2 = 1\n",
        f"{odd('Sÿnc2')}/{a('Twö.swift')}": "let two = 1\n",
        f"{a('Sÿnc')}/{a('Földer')}/{a('Ïn.txt')}": "in\n",
        f"{a('Sÿnc')}/{a('Földer2')}/{a('Ïn.txt')}": "in\n",
        f"{a('Hëaders')}/{a('Püblic.h')}": "int a;\n",
        f"{a('Hëaders')}/{a('Püblic2.h')}": "int b;\n",
        f"{a('Hëaders')}/{a('Lïb.a')}": "",
        f"{a('Hëaders')}/{a('Lïb2.a')}": "",
        f"{a('Sÿnc')}/{a('Ànchored.xcconfig')}": "ANCHORED_ONE = 1\n",
        f"{a('Sÿnc')}/{a('Ànchored2.xcconfig')}": "ANCHORED_TWO = 2\n",
    }
    exceptions = ", ".join(pbx_string(name) for name in [a("Ïgnored.swift"), odd("Ïgnored2.swift"), a("Ïgnored3.swift"), a("Sübdir/Ïnner.swift"),
                                                         a("Ghöst.swift")])
    folders = ", ".join(pbx_string(name) for name in [a("Földer"), odd("Földer2")])
    flags = "".join(f"{pbx_string(key)} = {pbx_string(value)}; " for key, value in [(a("Émoji.swift"), "-DONE"), (odd("Ëxtra.swift"), "-DTWO")])
    explicit = "".join(f"\t\t\t\t{pbx_string(key)} = sourcecode.swift;\n" for key in [a("Ñote.dat"), odd("Ôther.dat"), a("Ûnder.dat")])
    objects = f"""		U00000000000000000000001 = {{
			isa = PBXGroup;
			children = (
				U00000000000000000000002,
				U00000000000000000000003,
				U00000000000000000000004,
				U00000000000000000000005,
				U00000000000000000000006,
				U00000000000000000000007,
				U00000000000000000000008,
				U00000000000000000000009,
				U0000000000000000000000A,
				U00000000000000000000072,
			);
			sourceTree = "<group>";
		}};
		U0000000000000000000000A = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = (U000000000000000000000A1, ); path = {q('Hëaders')}; sourceTree = "<group>"; }};
		U000000000000000000000A1 = {{isa = PBXFileSystemSynchronizedBuildFileExceptionSet; attributesByRelativePath = {{ {pbx_string(a("Lïb.a"))} = (Weak, ); {pbx_string(odd("Lïb2.a"))} = (Weak, ); }}; privateHeaders = ({pbx_string(a("Püblic.h"))}, ); publicHeaders = ({pbx_string(odd("Püblic2.h"))}, ); target = U00000000000000000000040; }};
		U000000000000000000000A2 = {{isa = PBXHeadersBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		U000000000000000000000A3 = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		U00000000000000000000002 = {{isa = PBXGroup; children = (U00000000000000000000021, U00000000000000000000022, U00000000000000000000023, U00000000000000000000024, ); path = {q('Ångström')}; sourceTree = "<group>"; }};
		U00000000000000000000021 = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q('Zürich.swift')}; sourceTree = "<group>"; }};
		U00000000000000000000022 = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q('Über.swift')}; sourceTree = "<group>"; }};
		U00000000000000000000023 = {{isa = PBXFileReference; path = {q('Ñandú.txt')}; sourceTree = "<group>"; }};
		U00000000000000000000024 = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q('Mïssing.swift')}; sourceTree = "<group>"; }};
		U00000000000000000000003 = {{isa = PBXGroup; children = (U00000000000000000000031, ); name = {q('Ünïcödé')}; sourceTree = "<group>"; }};
		U00000000000000000000031 = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Plain.swift; sourceTree = "<group>"; }};
		U00000000000000000000004 = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {q('Café Name')}; path = Named.swift; sourceTree = "<group>"; }};
		U00000000000000000000005 = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				U00000000000000000000051,
			);
			explicitFileTypes = {{
{explicit}			}};
			explicitFolders = ({folders}, );
			path = {q('Sÿnc')};
			sourceTree = "<group>";
		}};
		U00000000000000000000051 = {{isa = PBXFileSystemSynchronizedBuildFileExceptionSet; additionalCompilerFlagsByRelativePath = {{ {flags}}}; membershipExceptions = ({exceptions}, ); target = U00000000000000000000010; }};
		U00000000000000000000006 = {{isa = PBXVariantGroup; children = (U00000000000000000000061, U00000000000000000000062, ); name = {q('Lôcalizable.strings')}; sourceTree = "<group>"; }};
		U00000000000000000000061 = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = {q('en.lproj/Lôcalizable.strings')}; sourceTree = "<group>"; }};
		U00000000000000000000062 = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = fr; path = {q('fr.lproj/Lôcalizable.strings')}; sourceTree = "<group>"; }};
		U00000000000000000000007 = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {q('Cönfig.xcconfig')}; sourceTree = "<group>"; }};
		U00000000000000000000072 = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {q('Ödd.xcconfig')}; sourceTree = "<group>"; }};
		U00000000000000000000008 = {{isa = PBXFileSystemSynchronizedRootGroup; path = {q('Sÿnc2')}; sourceTree = "<group>"; }};
		U00000000000000000000009 = {{isa = PBXGroup; children = (U00000000000000000000011, U00000000000000000000041, U00000000000000000000071, ); name = Products; sourceTree = "<group>"; }};
		U00000000000000000000011 = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {q('Ünï App.app')}; sourceTree = BUILT_PRODUCTS_DIR; }};
		U00000000000000000000041 = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = {q('Kït.framework')}; sourceTree = BUILT_PRODUCTS_DIR; }};
		U00000000000000000000071 = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {q('Ötro.app')}; sourceTree = BUILT_PRODUCTS_DIR; }};
		U00000000000000000000101 = {{isa = PBXBuildFile; fileRef = U00000000000000000000021; }};
		U00000000000000000000102 = {{isa = PBXBuildFile; fileRef = U00000000000000000000022; }};
		U00000000000000000000103 = {{isa = PBXBuildFile; fileRef = U00000000000000000000024; }};
		U00000000000000000000104 = {{isa = PBXBuildFile; fileRef = U00000000000000000000004; }};
		U00000000000000000000105 = {{isa = PBXBuildFile; fileRef = U00000000000000000000031; }};
		U00000000000000000000106 = {{isa = PBXBuildFile; fileRef = U00000000000000000000006; }};
		U00000000000000000000107 = {{isa = PBXBuildFile; fileRef = U00000000000000000000023; }};
		U00000000000000000000111 = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (U00000000000000000000101, U00000000000000000000102, U00000000000000000000103, U00000000000000000000104, U00000000000000000000105, ); runOnlyForDeploymentPostprocessing = 0; }};
		U00000000000000000000112 = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (U00000000000000000000106, U00000000000000000000107, ); runOnlyForDeploymentPostprocessing = 0; }};
		U00000000000000000000113 = {{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = ({q('$(SRCROOT)/Ångström/Zürich.swift')}, ); name = {q('Rün Script')}; outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = {q('echo Café')}; }};
		U00000000000000000000114 = {{isa = PBXBuildRule; compilerSpec = com.apple.compilers.proxy.script; filePatterns = {q('*.ünï')}; fileType = pattern.proxy; inputFiles = (); isEditable = 1; name = {q('Rüle')}; outputFiles = ({q('$(DERIVED_FILE_DIR)/Öut.swift')}, ); script = {q('echo Rüle')}; }};
		U00000000000000000000115 = {{isa = PBXTargetDependency; target = U00000000000000000000040; targetProxy = U00000000000000000000116; }};
		U00000000000000000000116 = {{isa = PBXContainerItemProxy; containerPortal = U00000000000000000000099; proxyType = 1; remoteGlobalIDString = U00000000000000000000040; remoteInfo = {q('Kït')}; }};
"""
    settings = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.unicode",
                "INFOPLIST_KEY_CFBundleDisplayName": q("Café"), "SWIFT_ACTIVE_COMPILATION_CONDITIONS": q("ÇA"),
                "HEADER_SEARCH_PATHS": q("$(SRCROOT)/Ångström")}
    names = [("Debug", "Debug"), ("Release", "Release"), (a("Bêta"), "Beta")]

    def configuration_list(prefix, values, base=None):
        entries = [(f"{prefix}{suffix}", pbx_string(name), values) for name, suffix in names]
        text = named_configurations(f"{prefix}List", entries, "Release")
        if base:
            text = text.replace(f"\t\t{prefix}Debug /* \"Debug\" */ = {{\n\t\t\tisa = XCBuildConfiguration;\n",
                                f"\t\t{prefix}Debug /* \"Debug\" */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {base};\n")
        return text

    objects += app_target("U00000000000000000000010", a("Ünï App"), ["U00000000000000000000111", "U00000000000000000000112", "U00000000000000000000113"],
                          ["UAPP00000000000000000List"], {}, product_reference="U00000000000000000000011",
                          configuration_list=configuration_list("UAPP00000000000000000", settings, base="U00000000000000000000007"),
                          extra=("\t\t\tbuildRules = (\n\t\t\t\tU00000000000000000000114,\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\tU00000000000000000000115,\n\t\t\t);\n"
                                 "\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tU00000000000000000000005,\n\t\t\t\tU00000000000000000000008,\n\t\t\t);\n"))
    objects += app_target("U00000000000000000000040", a("Kït"), ["U000000000000000000000A2", "U000000000000000000000A3"], ["UKIT00000000000000000List"], {},
                          product_type="com.apple.product-type.framework", product_reference="U00000000000000000000041",
                          extra="\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tU0000000000000000000000A,\n\t\t\t);\n",
                          configuration_list=configuration_list("UKIT00000000000000000", {"PRODUCT_NAME": '"$(TARGET_NAME)"', "GENERATE_INFOPLIST_FILE": "YES"},
                                                                base="U00000000000000000000072"))
    # Ötro's Debug and Release take an xcconfig of Sÿnc by a path relative to the folder, in the
    # project file's form and in the other form.
    otro = configuration_list("UOTR00000000000000000", {**settings, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.otro"})
    for suffix, path in [("Debug", a("Ànchored.xcconfig")), ("Release", odd("Ànchored2.xcconfig"))]:
        otro = otro.replace(f"\t\tUOTR00000000000000000{suffix} /* \"{suffix}\" */ = {{\n\t\t\tisa = XCBuildConfiguration;\n",
                            f"\t\tUOTR00000000000000000{suffix} /* \"{suffix}\" */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
                            f"\t\t\tbaseConfigurationReferenceAnchor = U00000000000000000000005;\n"
                            f"\t\t\tbaseConfigurationReferenceRelativePath = {pbx_string(path)};\n")
    objects += app_target("U00000000000000000000070", a("Ötro"), [], ["UOTR00000000000000000List"], {}, product_reference="U00000000000000000000071",
                          configuration_list=otro)
    text = project("U00000000000000000000099", "U00000000000000000000001",
                   ["U00000000000000000000010", "U00000000000000000000040", "U00000000000000000000070"], objects,
                   project_configurations=([("Debug", {"SDKROOT": "iphoneos"}), ("Release", {"SDKROOT": "iphoneos"}), (pbx_string(a("Bêta")), {"SDKROOT": "iphoneos"})], "Release"))
    files[f"{container}/project.pbxproj"] = text
    # Schémé launches Ünï App through a container written in the other form; Àutre (a file name
    # in the other form) builds Kït through one in the project file's form.
    schemes = f"{container}/xcshareddata/xcschemes"
    files[f"{schemes}/{a('Schémé')}.xcscheme"] = scheme_file(
        build=[("U00000000000000000000010", a("Ünï App.app"), a("Ünï App"), "container:" + odd("Café.xcodeproj"), True)],
        launch=("product", ("U00000000000000000000010", a("Ünï App.app"), a("Ünï App"), "container:" + odd("Café.xcodeproj"))))
    files[f"{schemes}/{odd('Àutre')}.xcscheme"] = scheme_file(
        build=[("U00000000000000000000040", a("Kït.framework"), a("Kït"), "container:" + container, True)])
    return files


def observe_unicode_names(form):
    a = lambda text: unicodedata.normalize(form, text)
    odd = lambda text: unicodedata.normalize("NFD" if form == "NFC" else "NFC", text)

    def observe(run):
        run("list-text", "-list")
        run("list", "-list", "-json")
        for label, name in [("Scheme", a("Schémé")), ("Scheme-odd", odd("Schémé")), ("Scheme-lowercase", a("schémé")), ("Autre", odd("Àutre")),
                            ("Autre-odd", a("Àutre")), ("Otro", a("Ötro")), ("Otro-odd", odd("Ötro"))]:
            run(f"scheme-{label}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")
        run("scheme-Scheme-json", "-showBuildSettings", "-json", "-scheme", a("Schémé"), "-destination", "generic/platform=iOS")
        run("target-App", "-showBuildSettings", "-target", a("Ünï App"), "-configuration", a("Bêta"))
        run("target-App-odd", "-showBuildSettings", "-target", odd("Ünï App"), "-configuration", odd("Bêta"))
        run("target-App-configuration-odd", "-showBuildSettings", "-target", a("Ünï App"), "-configuration", odd("Bêta"))
        run("scheme-Scheme-configuration-odd", "-showBuildSettings", "-scheme", a("Schémé"), "-configuration", odd("Bêta"),
            "-destination", "generic/platform=iOS")
        run("alltargets", "-showBuildSettings", "-alltargets")
        run("target-Kit-Debug", "-showBuildSettings", "-target", a("Kït"), "-configuration", "Debug")
        run("target-Otro-Debug", "-showBuildSettings", "-target", a("Ötro"), "-configuration", "Debug")
        run("target-Otro-Release", "-showBuildSettings", "-target", a("Ötro"), "-configuration", "Release")
        other = run.container.parent / odd("Café.xcodeproj")
        run.output.mkdir(parents=True, exist_ok=True)
        run("dumpPIF-odd", "-dumpPIF", str(run.output / "odd.pif"), container=other)
        run("list-odd", "-list", "-json", container=other)
    return observe


# Synchronized folders whose one non-ASCII member sits at the top level or in subfolders, each
# name on disk in NFC or NFD, for which spelling the position of a folder's block in a phase
# hashes (docs/formats/pif.md "Order in a phase"). Thirty own build files make each position
# an informative remainder.
UNICODE_ORDER_FOLDERS = [
    ("NFC", None, None, "Ünï.swift"), ("NFD", None, None, "Ünï.swift"),
    ("NFC", "Sub", "NFC", "Ünï.swift"), ("NFD", "Sub", "NFD", "Ünï.swift"),
    ("NFC", "Dïr", "NFC", "Ünï.swift"), ("NFD", "Dïr", "NFC", "Ünï.swift"),
    ("NFC", "Dïr", "NFD", "Ünï.swift"), ("NFD", "Dïr", "NFD", "Ünï.swift"),
    ("NFC", "Ελληνικά", "NFC", "Ångström.swift"), ("NFD", "Ελληνικά", "NFD", "Ångström.swift"),
    ("NFC", "Ελληνικά", "NFD", "Ångström.swift"), ("NFD", "Ελληνικά", "NFC", "Ångström.swift"),
    ("NFC", "Dïr/Sëcond", "NFC", "Ünï.swift"), ("NFD", "Dïr/Sëcond", "NFD", "Ünï.swift"),
    ("NFC", "Sub/Deeper", "NFC", "Ünï.swift"), ("NFD", "Sub/Deeper", "NFC", "Ünï.swift"),
]


def unicode_order(ascii_names=False):
    """Each folder Fnn holds `a.swift`, `b.swift` and one non-ASCII file: the file's name on
    disk is in the first form, in subfolder `folder` (on disk in the third form) when given.
    With `ascii_names`, the same names without their diacritics, as a control."""
    files, roots, root_ids = {}, "", []
    for index, (file_form, folder, folder_form, name) in enumerate(UNICODE_ORDER_FOLDERS, 1):
        if ascii_names:
            name, folder = (unicodedata.normalize("NFD", text).encode("ascii", "ignore").decode() if text else text for text in (name, folder))
        root = f"F{index:02d}"
        files[f"{root}/a.swift"] = "let a = 1\n"
        files[f"{root}/b.swift"] = "let b = 1\n"
        inner = unicodedata.normalize(file_form, name)
        path = f"{root}/{unicodedata.normalize(folder_form, folder)}/{inner}" if folder else f"{root}/{inner}"
        files[path] = "let c = 1\n"
        root_id = f"S{index:023d}"
        root_ids.append(root_id)
        roots += f'\t\t{root_id} = {{isa = PBXFileSystemSynchronizedRootGroup; path = {root}; sourceTree = "<group>"; }};\n'
    own = [f"Own{index:02d}.swift" for index in range(1, 31)]
    objects = roots
    for index, name in enumerate(own, 1):
        files[name] = "let own = 1\n"
        objects += f'\t\tA{index:023d} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n'
        objects += f"\t\tB{index:023d} = {{isa = PBXBuildFile; fileRef = A{index:023d}; }};\n"
    children = "".join(f"\t\t\t\t{root_id},\n" for root_id in root_ids) + "".join(f"\t\t\t\tA{index:023d},\n" for index in range(1, 31))
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}				P00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000004 = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({"".join(f"B{index:023d}, " for index in range(1, 31))}); runOnlyForDeploymentPostprocessing = 0; }};
""" + product_file("P00000000000000000000001", "App", APPLICATION) + app_target(
        "C00000000000000000000001", "App", ["F00000000000000000000004"], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"],
        APP_SETTINGS, product_reference="P00000000000000000000001",
        extra="\t\t\tfileSystemSynchronizedGroups = (\n" + "".join(f"\t\t\t\t{root_id},\n" for root_id in root_ids) + "\t\t\t);\n")
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects)
    return files


def unicode_project_dir(form):
    """A project whose `projectDirPath` is a non-ASCII folder written in `form`, on disk in the
    other form, for the spelling of the PIF's `projectDirectory`."""
    other = "NFD" if form == "NFC" else "NFC"
    text = simple_project("App", extra_objects=product_file("P00000000000000000000001", "App", APPLICATION),
                          extra_target="\t\t\tproductReference = P00000000000000000000001;\n", group_children="\t\t\t\tP00000000000000000000001,\n")
    files = {"P.xcodeproj/project.pbxproj": text.replace('projectDirPath = "";', f"projectDirPath = {pbx_string(unicodedata.normalize(form, 'Rööt'))};"),
             f"{unicodedata.normalize(other, 'Rööt')}/App.swift": "let app = 1\n"}
    return files


# Shared scheme names whose order in `-list` tells a comparison of decomposed names from a
# localized one: accented and unaccented letters, letters without a decomposition (Ø, ß, Æ),
# canonical singletons (the Ohm and Angstrom signs), a compatibility ligature, and names written
# decomposed on disk. A Mac's default volume compares names without case and normalization, so
# no two names here are equal that way.
LIST_ORDER_NAMES = [
    "Àa", "Ab", "Aa", "Éa", "Eb", unicodedata.normalize("NFD", "Éc"), "Øa", "Ob", "Ünï Kit", "Vendor", "Ue", "ßa", "ss", "Æb", "AEa",
    "日本", "Zz", "\ufb01x", "\u2126mega", "Ωb", "\u212bx", "Åy", "a\u0301",
]


def list_order():
    files = {"P.xcodeproj/project.pbxproj": simple_project("App"), "App.swift": "let app = 1\n"}
    for name in LIST_ORDER_NAMES:
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(
            build=[("C00000000000000000000001", "App.app", "App", "container:P.xcodeproj", True)])
    return files


# Names of projects and workspaces, for the DerivedData folder name xcodebuild derives from them.
DERIVED_DATA_NAMES = [
    "Plain", "App 2", "Two  Spaces", " Leading", "Trailing ", "Tab\tName", "A+B", "A&B", "Dot.Name", "Dash-Name", "Under_Score",
    "Paren(Name)", "Quote'Name", 'Double"Name', "Comma,Name", "Semi;Name", "At@Name", "Hash#Name", "Percent%Name", "Bang!Name",
    "Tilde~Name", "Equals=Name", "Bracket[Name]", "Brace{Name}", "Dollar$Name", "Colon:Name", "Pipe|Name", "Caret^Name",
    "Grave`Name", "Angle<Name>", "Question?Name", "Star*Name", "Back\\Name", "No\u00a0Break", "Em\u2003Space", "Ideo\u3000Space",
    "Line\u2028Sep", unicodedata.normalize("NFC", "Ünï Kit"), unicodedata.normalize("NFD", "Ünï Kit2"), "日本", "Émoji\U0001f642", "-Dash",
    ".Dot", "New\nLine", "Return\rName", "VTab\vName", "Feed\fName", "Space \t Tab", "Under_ Space", "Next\u0085Line", "Unit\x1fSep",
    "Bell\x07Name", "Esc\x1bName", "Del\x7fName", "Ogham\u1680Space",
]


def derived_data_names():
    files = {}
    for index, name in enumerate(DERIVED_DATA_NAMES):
        files[f"N{index:02d}/{name}.xcodeproj/project.pbxproj"] = simple_project("App")
        files[f"N{index:02d}/App.swift"] = "let app = 1\n"
    for index, name in enumerate(["All Projects", unicodedata.normalize("NFC", "Wörk Späce"), unicodedata.normalize("NFD", "Wörk Späce2")]):
        files[f"W{index:02d}/P.xcodeproj/project.pbxproj"] = simple_project("App")
        files[f"W{index:02d}/App.swift"] = "let app = 1\n"
        files[f"W{index:02d}/{name}.xcworkspace/contents.xcworkspacedata"] = (
            '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "group:P.xcodeproj">\n   </FileRef>\n</Workspace>\n')
    return files


def observe_derived_data_names(run):
    root = run.container.parent.parent
    for index, name in enumerate(DERIVED_DATA_NAMES):
        run(f"project-{index:02d}", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS",
            container=root / f"N{index:02d}" / f"{name}.xcodeproj")
    for index, name in enumerate(["All Projects", unicodedata.normalize("NFC", "Wörk Späce"), unicodedata.normalize("NFD", "Wörk Späce2")]):
        run(f"workspace-{index:02d}", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS",
            container=root / f"W{index:02d}" / f"{name}.xcworkspace", flag="-workspace")


def derived_data_packages():
    # A remote package is checked out in the project's DerivedData folder (netnewswire); here
    # the project's name has a space and a non-ASCII letter.
    files = macros()
    files[unicodedata.normalize("NFC", "Päck Àpp.xcodeproj/project.pbxproj")] = files.pop("P.xcodeproj/project.pbxproj")
    return files
PINS_REMOTE = "file://@EXPERIMENT@/Remote"


def pins_remote_manifest(new_product):
    products = '.library(name: "RemoteKit", targets: ["RemoteKit"])' + (', .library(name: "RemoteNew", targets: ["RemoteNew"])' if new_product else "")
    targets = '.target(name: "RemoteKit")' + (', .target(name: "RemoteNew")' if new_product else "")
    return f'// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: "Remote",\n    products: [{products}],\n    targets: [{targets}]\n)\n'


def pins_root_package(name):
    """A package whose library uses Remote's RemoteKit, from 1.0.0."""
    return {
        f"{name}/Package.swift": (
            "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n"
            f'    name: "{name}",\n    platforms: [.iOS(.v17)],\n'
            f'    products: [.library(name: "{name}Kit", targets: ["{name}Kit"])],\n'
            f'    dependencies: [.package(url: "{PINS_REMOTE}", from: "1.0.0")],\n'
            f'    targets: [.target(name: "{name}Kit", dependencies: [.product(name: "RemoteKit", package: "Remote")])]\n)\n'),
        f"{name}/Sources/{name}Kit/{name}Kit.swift": f"public let {name.lower()}Kit = 1\n",
    }


def package_pins(packages, remote_reference=False):
    # pocket-casts' project commits no Package.resolved (B-018): its remote packages are those of
    # the root package folder Modules, whose own Package.resolved pins sentry-cocoa 9.8.0 where
    # 9.10.0 is out. `packages` holds (folder, the version its Package.resolved pins or None,
    # kind): a root package folder in the group tree, or a local package reference. With
    # `remote_reference` the project also references Remote itself, up to the next major version
    # from 1.0.0. Remote is tagged 1.0.0, 1.1.0 (adding RemoteNew) and 1.2.0 (publish_pins).
    files = {"Remote/Package.swift": pins_remote_manifest(False), "Remote/Sources/RemoteKit/RemoteKit.swift": "public let remoteKit = 1\n"}
    objects, children, dependencies, references = "", "", [], []
    for index, (name, _, kind) in enumerate(packages, 1):
        files.update(pins_root_package(name))
        if kind == "root":
            objects += f'\t\tA{index:023d} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; path = {name}; sourceTree = "<group>"; }};\n'
            objects += f"\t\tE{index:023d} = {{isa = XCSwiftPackageProductDependency; productName = {name}Kit; }};\n"
            children += f"\t\t\t\tA{index:023d} /* {name} */,\n"
        else:
            objects += f"\t\tD{index:023d} = {{isa = XCLocalSwiftPackageReference; relativePath = {name}; }};\n"
            objects += f"\t\tE{index:023d} = {{isa = XCSwiftPackageProductDependency; package = D{index:023d}; productName = {name}Kit; }};\n"
            references.append(f"D{index:023d}")
        dependencies.append(f"E{index:023d}")
    if remote_reference:
        objects += f"""\t\tD00000000000000000000099 /* XCRemoteSwiftPackageReference "Remote" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "{PINS_REMOTE}";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 1.0.0;
\t\t\t}};
\t\t}};
\t\tE00000000000000000000099 = {{isa = XCSwiftPackageProductDependency; package = D00000000000000000000099; productName = RemoteKit; }};
"""
        dependencies.append("E00000000000000000000099")
        references.append("D00000000000000000000099")
    objects += f"""\t\tF00000000000000000000002 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children}\t\t\t\tP00000000000000000000001,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
""" + product_file("P00000000000000000000001", "App", APPLICATION) \
        + app_target("C00000000000000000000001", "App", [], ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                     extra="\t\t\tpackageProductDependencies = (\n" + "".join(f"\t\t\t\t{d},\n" for d in dependencies) + "\t\t\t);\n",
                     product_reference="P00000000000000000000001")
    package_references = "\t\t\tpackageReferences = (\n" + "".join(f"\t\t\t\t{r},\n" for r in references) + "\t\t\t);\n" if references else ""
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects,
                                                   package_references=package_references)
    return files


def publish_pins(packages, workspace=None):
    """Tags Remote 1.0.0, 1.1.0 (adding RemoteNew) and 1.2.0; after each tag, resolves the
    packages pinned to it with this Xcode's `swift package resolve`, and when `workspace` names it,
    writes the project's workspace a Package.resolved pinning it (from a package that depends on
    Remote alone). Records every Package.resolved as prepared in `pins-prepared.json`."""
    def prepare(directory):
        for path in [directory / "P.xcodeproj" / "project.pbxproj", *directory.glob("*/Package.swift")]:
            path.write_text(path.read_text().replace("@EXPERIMENT@", str(directory)))
        remote = directory / "Remote"
        git = ["git", "-c", "user.name=nomac", "-c", "user.email=nomac@example.invalid", "-c", "init.defaultBranch=main"]

        def resolve(folder):
            subprocess.run(["xcrun", "swift", "package", "resolve"], cwd=folder, check=True, capture_output=True)
            shutil.rmtree(folder / ".build", ignore_errors=True)

        def tag(version):
            for arguments in (["add", "."], ["commit", "-q", "-m", version], ["tag", version]):
                subprocess.run(git + arguments, cwd=remote, check=True)
            for name, pinned, _ in packages:
                if pinned == version:
                    resolve(directory / name)
            if workspace == version:
                for path, text in pins_root_package("Pins").items():
                    (directory / path).parent.mkdir(parents=True, exist_ok=True)
                    (directory / path).write_text(text.replace("@EXPERIMENT@", str(directory)))
                resolve(directory / "Pins")
                swiftpm = directory / "P.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm"
                swiftpm.mkdir(parents=True)
                shutil.move(directory / "Pins" / "Package.resolved", swiftpm / "Package.resolved")
                shutil.rmtree(directory / "Pins")

        subprocess.run(git + ["init", "-q"], cwd=remote, check=True)
        tag("1.0.0")
        (remote / "Package.swift").write_text(pins_remote_manifest(True))
        (remote / "Sources" / "RemoteNew").mkdir(parents=True)
        (remote / "Sources" / "RemoteNew" / "RemoteNew.swift").write_text("public let remoteNew = 1\n")
        tag("1.1.0")
        (remote / "Sources" / "RemoteNew" / "RemoteNew.swift").write_text("public let remoteNew = 2\n")
        tag("1.2.0")
        prepared = {str(path.relative_to(directory)): path.read_text() for path in sorted(directory.glob("**/Package.resolved"))}
        (directory / "pins-prepared.json").write_text(json.dumps(prepared, indent=1) + "\n")
    return prepare


def observe_package_pins(run):
    """After -dumpPIF and -list resolved the packages: the version of Remote checked out
    (DerivedData's workspace-state.json), whether the PIF has RemoteNew, the project's files, and
    every Package.resolved with those that differ from the prepared ones."""
    run("list", "-list", "-json")
    directory = run.container.parent
    pif = (run.output.parent / f"{run.output.name}.pif").read_text()
    checkouts = {}
    found = re.search(r'"(/[^"]*?/SourcePackages)/checkouts/', pif)
    if found:
        state = json.loads((Path(found.group(1)) / "workspace-state.json").read_text())
        checkouts = {entry["packageRef"]["identity"]: entry["state"].get("checkoutState") for entry in state["object"]["dependencies"]}
    resolved = {str(path.relative_to(directory)): path.read_text() for path in sorted(directory.glob("**/Package.resolved"))}
    prepared = json.loads((directory / "pins-prepared.json").read_text())
    observation = {
        "checkouts": checkouts,
        "remoteNewInPIF": '"RemoteNew"' in pif,
        "projectFiles": sorted(str(path.relative_to(directory)) for path in (directory / "P.xcodeproj").rglob("*") if path.is_file()),
        "resolved": resolved,
        "written": sorted(path for path in resolved if prepared.get(path) != resolved[path]),
    }
    run.output.mkdir(parents=True, exist_ok=True)
    (run.output / "observation.json").write_text(json.dumps(observation, indent=1, sort_keys=True) + "\n")


def product_target_dependencies():
    # firefox's RustMozillaAppServices depends on the package product Glean through a
    # PBXTargetDependency with a productRef, which its PIF lists first among its dependencies.
    # Each target here names a product of Deps/Local that way, alone, next to target
    # dependencies, linked by the same XCSwiftPackageProductDependency, with a platform filter or
    # also in packageProductDependencies.
    files = {"Deps/Local/Package.swift": ('// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: "Local",\n'
                                          '    platforms: [.iOS(.v17)],\n'
                                          '    products: [.library(name: "LocalKit", targets: ["LocalKit"]), .library(name: "OtherKit", targets: ["OtherKit"])],\n'
                                          '    targets: [.target(name: "LocalKit"), .target(name: "OtherKit")]\n)\n'),
             "Deps/Local/Sources/LocalKit/LocalKit.swift": "public let localKit = 1\n", "Deps/Local/Sources/OtherKit/OtherKit.swift": "public let otherKit = 1\n"}
    objects = "\t\tD00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Local; };\n"
    # name: ([(dependency kind, value, extra keys)], [(phase product, shared with dependency index)], packageProductDependencies)
    targets = {
        "OnlyDependency": ([("product", "LocalKit", "")], [], []),
        "TargetThenProduct": ([("target", 1, ""), ("product", "LocalKit", "")], ["OtherKit"], []),
        "ProductThenTarget": ([("product", "LocalKit", ""), ("target", 1, "")], [], []),
        "SameObjectLinked": ([("product", "LocalKit", "")], [0], []),
        "Filtered": ([("product", "LocalKit", "platformFilters = (ios, ); ")], [], []),
        "AlsoListed": ([("product", "LocalKit", "")], [], [0]),
        "TwoProducts": ([("product", "OtherKit", ""), ("product", "LocalKit", "")], ["LocalKit"], []),
    }
    ids, products = [], ""
    for index, (name, (dependencies, linked, listed)) in enumerate(targets.items(), 1):
        target = f"C{index:023d}"
        ids.append(target)
        dependency_ids, product_ids = [], []
        for position, (kind, value, keys) in enumerate(dependencies):
            dependency = f"T{index:021d}{position:02d}"
            dependency_ids.append(dependency)
            if kind == "target":
                proxy = f"X{index:021d}{position:02d}"
                objects += (f"\t\t{proxy} = {{isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; "
                            f"remoteGlobalIDString = C{value:023d}; remoteInfo = OnlyDependency; }};\n"
                            f"\t\t{dependency} = {{isa = PBXTargetDependency; {keys}target = C{value:023d}; targetProxy = {proxy}; }};\n")
                product_ids.append(None)
            else:
                product = f"E{index:021d}{position:02d}"
                objects += (f"\t\t{product} = {{isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = {value}; }};\n"
                            f"\t\t{dependency} = {{isa = PBXTargetDependency; {keys}productRef = {product}; }};\n")
                product_ids.append(product)
        build_files = []
        for position, item in enumerate(linked):
            if isinstance(item, int):
                product = product_ids[item]
            else:
                product = f"E{index:019d}L{position:03d}"
                objects += f"\t\t{product} = {{isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = {item}; }};\n"
            build_file = f"B{index:021d}{position:02d}"
            objects += f"\t\t{build_file} = {{isa = PBXBuildFile; productRef = {product}; }};\n"
            build_files.append(build_file)
        phase = f"F{index:021d}FW"
        objects += f"\t\t{phase} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({''.join(f + ', ' for f in build_files)}); runOnlyForDeploymentPostprocessing = 0; }};\n"
        extra = "\t\t\tdependencies = (\n" + "".join(f"\t\t\t\t{d},\n" for d in dependency_ids) + "\t\t\t);\n"
        if listed:
            extra += "\t\t\tpackageProductDependencies = (\n" + "".join(f"\t\t\t\t{product_ids[i]},\n" for i in listed) + "\t\t\t);\n"
        products += f"\t\t\t\tP{index:023d},\n"
        objects += product_file(f"P{index:023d}", name, APPLICATION) + app_target(
            target, name, [phase], [f"F{index:021d}TL", f"F{index:021d}TD", f"F{index:021d}TR"],
            {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.app{index}"}, extra=extra, product_reference=f"P{index:023d}")
    objects += f"""\t\tF00000000000000000000002 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{products}\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
"""
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ids, objects, package_references=references)
    return files


PRODUCT_DUPLICATE_PHASES = {"fw": "PBXFrameworksBuildPhase", "embed": 'PBXCopyFilesBuildPhase; dstPath = ""; dstSubfolderSpec = 10',
                            "resources": "PBXResourcesBuildPhase", "sources": "PBXSourcesBuildPhase"}
# name: ([(dependency kind, product object or target, platform filter)], [(phase, [product object or (object, filter)])],
# packageProductDependencies). Objects L1 to L3 name LocalKit, O1 OtherKit, N1 LocalKit without a package.
PRODUCT_DUPLICATE_TARGETS = {
    "FwEmbed": ([], [("fw", ["L1"]), ("embed", ["L2"])], []),
    "FwEmbedListed": ([], [("fw", ["L1"]), ("embed", ["L2"])], ["L1", "L2"]),
    "FwEmbedListedSecond": ([], [("fw", ["L1"]), ("embed", ["L2"])], ["L2"]),
    "EmbedFw": ([], [("embed", ["L2"]), ("fw", ["L1"])], []),
    "FwEmbedSame": ([], [("fw", ["L1"]), ("embed", ["L1"])], []),
    "FwTwo": ([], [("fw", ["L1", "L2"])], []),
    "FwTwoListed": ([], [("fw", ["L1", "L2"])], ["L1", "L2"]),
    "FwOtherBetween": ([], [("fw", ["L1", "O1", "L2"])], []),
    "FwSameTwice": ([], [("fw", ["L1", "L1"])], []),
    "TwoFw": ([], [("fw", ["L1"]), ("fw", ["L2"])], []),
    "TwoFwOther": ([], [("fw", ["L1"]), ("fw", ["O1"])], []),
    "SecondFwOnly": ([], [("fw", []), ("fw", ["L1"])], []),
    "ListedSecondFw": ([], [("fw", ["O1"]), ("fw", ["L1"])], ["L1", "O1"]),
    "SourcesFw": ([], [("sources", ["O1"]), ("fw", ["L1"])], []),
    "SourcesOnly": ([], [("sources", ["L1"])], []),
    "EmbedTwo": ([], [("fw", []), ("embed", ["L1", "L2"])], []),
    "EmbedTwoPhases": ([], [("fw", []), ("embed", ["L1"]), ("embed", ["L2"])], []),
    "FwEmbedThree": ([], [("fw", ["L1", "L2"]), ("embed", ["L3"])], []),
    "FwResources": ([], [("fw", ["L1"]), ("resources", ["L2"])], []),
    "UnlinkedTwo": ([], [("fw", [])], ["L1", "L2"]),
    "UnlinkedLinked": ([], [("fw", ["L2"])], ["L1", "L2"]),
    "UnlinkedEmbed": ([], [("fw", []), ("embed", ["L2"])], ["L1"]),
    "NoPackage": ([], [("fw", ["L1"]), ("embed", ["N1"])], []),
    "FilteredFirst": ([], [("fw", [("L1", "ios")]), ("embed", ["L2"])], []),
    "FilteredSecond": ([], [("fw", ["L1"]), ("embed", [("L2", "ios")])], []),
    "FilteredTwice": ([], [("fw", [("L1", "ios"), ("L2", "macos"), "L3"])], []),
    "DependencyLinked": ([("product", "L1", None)], [("fw", ["L2"])], []),
    "DependencyEmbedded": ([("product", "L1", None)], [("fw", []), ("embed", ["L2"])], []),
    "DependencyTwice": ([("product", "L1", None), ("product", "L2", None)], [("fw", [])], []),
    "DependencySameTwice": ([("product", "L1", None), ("product", "L1", None)], [("fw", [])], []),
    "TargetTwice": ([("target", "Fw", None), ("target", "Fw", None)], [("fw", [])], []),
    "TargetTwiceFiltered": ([("target", "Fw", "ios"), ("target", "Fw", None)], [("fw", [])], []),
    "TargetProductTarget": ([("target", "Fw", None), ("product", "L1", None), ("target", "Fw", None)], [("fw", ["L2"])], []),
}


def product_duplicates():
    # home-assistant's WatchApp links PromiseKitDynamic through one XCSwiftPackageProductDependency
    # and embeds it through another, and its PIF lists the product once; swiftfin's app links
    # StatefulMacros through eleven, all in its Frameworks phase and packageProductDependencies,
    # and lists it eleven times. Each target here names a product of Deps/Local through several
    # objects, phases or target dependencies, or a target through several dependencies.
    files = {"Deps/Local/Package.swift": ('// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: "Local",\n'
                                          '    platforms: [.iOS(.v17)],\n'
                                          '    products: [.library(name: "LocalKit", targets: ["LocalKit"]), .library(name: "OtherKit", targets: ["OtherKit"])],\n'
                                          '    targets: [.target(name: "LocalKit"), .target(name: "OtherKit")]\n)\n'),
             "Deps/Local/Sources/LocalKit/LocalKit.swift": "public let localKit = 1\n", "Deps/Local/Sources/OtherKit/OtherKit.swift": "public let otherKit = 1\n"}
    objects = "\t\tD00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Local; };\n"
    products = {"L": "LocalKit", "O": "OtherKit", "N": "LocalKit"}
    framework = "C00000000000000000000000"
    objects += ("\t\tF0000000000000000000FWPH = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };\n"
                + product_file("P00000000000000000000000", "Fw", FRAMEWORK)
                + app_target(framework, "Fw", ["F0000000000000000000FWPH"], ["F0000000000000000000FWTL", "F0000000000000000000FWTD", "F0000000000000000000FWTR"],
                             {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.fw"}, product_type=FRAMEWORK,
                             product_reference="P00000000000000000000000"))
    ids, references = [framework], "\t\t\t\tP00000000000000000000000,\n"

    def filters(platform):
        return f"platformFilters = ({platform}, ); " if platform else ""

    for index, (name, (dependencies, phases, listed)) in enumerate(PRODUCT_DUPLICATE_TARGETS.items(), 1):
        target = f"C{index:023d}"
        ids.append(target)
        named = {item if isinstance(item, str) else item[0] for _, items in phases for item in items}
        named |= {value for kind, value, _ in dependencies if kind == "product"} | set(listed)
        object_ids = {}
        for object_name in sorted(named):
            object_ids[object_name] = f"E{index:019d}{object_name}00"
            package = "" if object_name.startswith("N") else " package = D00000000000000000000001;"
            objects += f"\t\t{object_ids[object_name]} = {{isa = XCSwiftPackageProductDependency;{package} productName = {products[object_name[0]]}; }};\n"
        dependency_ids = []
        for position, (kind, value, platform) in enumerate(dependencies):
            dependency = f"T{index:021d}{position:02d}"
            dependency_ids.append(dependency)
            if kind == "target":
                proxy = f"X{index:021d}{position:02d}"
                objects += (f"\t\t{proxy} = {{isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; "
                            f"remoteGlobalIDString = {framework}; remoteInfo = {value}; }};\n"
                            f"\t\t{dependency} = {{isa = PBXTargetDependency; {filters(platform)}target = {framework}; targetProxy = {proxy}; }};\n")
            else:
                objects += f"\t\t{dependency} = {{isa = PBXTargetDependency; {filters(platform)}productRef = {object_ids[value]}; }};\n"
        phase_ids = []
        for phase_index, (phase, items) in enumerate(phases):
            build_files = []
            for position, item in enumerate(items):
                object_name, platform = (item, None) if isinstance(item, str) else item
                build_file = f"B{index:019d}{phase_index}{position:03d}"
                objects += f"\t\t{build_file} = {{isa = PBXBuildFile; {filters(platform)}productRef = {object_ids[object_name]}; }};\n"
                build_files.append(build_file)
            phase_ids.append(f"F{index:020d}PH{phase_index}")
            objects += (f"\t\t{phase_ids[-1]} = {{isa = {PRODUCT_DUPLICATE_PHASES[phase]}; buildActionMask = 2147483647; "
                        f"files = ({''.join(f + ', ' for f in build_files)}); runOnlyForDeploymentPostprocessing = 0; }};\n")
        extra = ""
        if dependency_ids:
            extra += "\t\t\tdependencies = (\n" + "".join(f"\t\t\t\t{d},\n" for d in dependency_ids) + "\t\t\t);\n"
        if listed:
            extra += "\t\t\tpackageProductDependencies = (\n" + "".join(f"\t\t\t\t{object_ids[o]},\n" for o in listed) + "\t\t\t);\n"
        references += f"\t\t\t\tP{index:023d},\n"
        objects += product_file(f"P{index:023d}", name, APPLICATION) + app_target(
            target, name, phase_ids, [f"F{index:021d}TL", f"F{index:021d}TD", f"F{index:021d}TR"],
            {**APP_SETTINGS, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.app{index}"}, extra=extra, product_reference=f"P{index:023d}")
    objects += f"""\t\tF00000000000000000000002 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{references}\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
"""
    package_references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = project("F00000000000000000000006", "F00000000000000000000002", ids, objects,
                                                   package_references=package_references)
    return files


def synchronized_missing():
    # home-assistant's Sources/Shared/Iconic is a synchronized folder no target lists and that is
    # not on disk; Xcode's PIF has a group without children for it. Gone is such a folder; App
    # lists Listed, which is not on disk either and whose exception set names a top-level and a
    # nested file, File, a path that is a file, Empty, an empty folder, and Present.
    files = {"File.swift": "let file = 1\n", "Present/a.swift": "let a = 1\n"}
    folders = [("S00000000000000000000001", "Gone", False), ("S00000000000000000000002", "Listed", True),
               ("S00000000000000000000003", "File.swift", True), ("S00000000000000000000004", "Empty", True),
               ("S00000000000000000000005", "Present", True)]
    objects = """		S00000000000000000000012 = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
				Sub/Deep.swift,
			);
			target = C00000000000000000000001;
		};
"""
    for identifier, path, _ in folders:
        exceptions = "exceptions = (S00000000000000000000012, ); " if path == "Listed" else ""
        objects += f'\t\t{identifier} /* {path} */ = {{isa = PBXFileSystemSynchronizedRootGroup; {exceptions}path = {pbx_string(path)}; sourceTree = "<group>"; }};\n'
    listed = "".join(f"\t\t\t\t{identifier},\n" for identifier, _, is_listed in folders if is_listed)
    objects += f"""		F00000000000000000000004 /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		F00000000000000000000005 /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
{product_file("F00000000000000000000001", "App", APPLICATION)}		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{"".join(f"				{identifier},{chr(10)}" for identifier, _, _ in folders)}				F00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
""" + app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */", "F00000000000000000000005 /* Resources */"],
                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], APP_SETTINGS,
                 extra=f"\t\t\tfileSystemSynchronizedGroups = (\n{listed}\t\t\t);\n", product_reference="F00000000000000000000001")
    return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001"], objects), **files}


def blueprint_names():
    # home-assistant's WatchApp schemes test bundles through BuildableReferences without a
    # BlueprintName. Each scheme here leaves the name out, or names another target, in some of its
    # references.
    targets = Targets()
    container = "container:P.xcodeproj"
    app, _ = targets.add("App", APPLICATION, {})
    kit, _ = targets.add("Kit", "com.apple.product-type.framework", {})
    tests, _ = targets.add("AppTests", UNIT_TEST, {})
    files = {}

    def scheme(name, **arguments):
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(**arguments)

    scheme("TestablesUnnamed", build=[(app, "App.app", "App", container, True)], testables=[(tests, "AppTests.xctest", None, container)],
           launch=("product", (app, "App.app", "App", container)))
    scheme("AllUnnamed", build=[(app, "App.app", None, container, True), (kit, "Kit.framework", None, container, True)],
           testables=[(tests, "AppTests.xctest", None, container)], launch=("product", (app, "App.app", None, container)))
    scheme("KitUnnamed", build=[(kit, "Kit.framework", None, container, True)])
    scheme("WrongNames", build=[(kit, "Kit.framework", "App", container, True)], testables=[(tests, "AppTests.xctest", "Kit", container)],
           launch=("product", (app, "App.app", "AppTests", container)))
    return targets.project(files)


AUTO_SDK = {"SDKROOT": "auto", "SUPPORTED_PLATFORMS": pbx_string("iphoneos iphonesimulator macosx")}


def autocreate_testables():
    # The differential fuzzer: an app's autocreated scheme tests no bundle a shared scheme builds
    # or tests; an extension's tests the bundles of the app it builds; a bundle whose SDKROOT is
    # auto, with a TEST_HOST under its own products folder, is its app's. One group per app.
    targets = Targets()
    container = "container:P.xcodeproj"
    files = {}
    test_host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}

    def scheme(name, **arguments):
        files[f"P.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme"] = scheme_file(**arguments)

    def bundle(name, app, app_name, kind=UI_TEST, settings=None, target_id=True):
        values = {key: value.replace("{0}", app_name) for key, value in (settings or {}).items()}
        identifier, _ = targets.add(name, kind, values)
        if target_id:
            targets.attribute(identifier, f"\t\t\t\t\t\tTestTargetID = {app};\n")
        targets.depend(identifier, app, app_name)
        return identifier

    def app(name, settings=None, sdk="iphoneos"):
        return targets.add(name, APPLICATION, settings or {}, sdk=sdk)[0]

    def testable(identifier, name):
        return (identifier, f"{name}.xctest", name, container)

    # A bundle a shared scheme tests, builds or skips, and a control no scheme covers.
    for index, how in enumerate(["tests", "builds", "skips", "none", "tests-unit", "tests-one"], 1):
        name = f"App{index:02d}"
        host = app(name)
        kind, settings = (UNIT_TEST, test_host) if how == "tests-unit" else (UI_TEST, None)
        first = bundle(f"{name}Tests", host, name, kind, settings)
        if how == "tests-one":
            bundle(f"{name}MoreTests", host, name)
        if how in ("tests", "tests-unit", "tests-one"):
            scheme(f"S{index:02d}", testables=[testable(first, f"{name}Tests")])
        elif how == "builds":
            scheme(f"S{index:02d}", build=[(first, f"{name}Tests.xctest", f"{name}Tests", container, False)])
        elif how == "skips":
            scheme(f"S{index:02d}", testables=[testable(first, f"{name}Tests")], skipped=True)
    # Extensions whose autocreated scheme builds an app with test bundles.
    for index, (extension_type, how) in enumerate([
        (APPEX, "ui"), (APPEX, "unit"), (APPEX, "none"), (APPEX, "host-launched"), (APPEX, "via-framework"),
        ("com.apple.product-type.app-extension.messages-sticker-pack", "ui"), (APPEX, "bundle-covered"), (APPEX, "two-hosts"),
        ("com.apple.product-type.extensionkit-extension", "ui"),
    ], 7):
        name = f"Ext{index:02d}"
        extension, _ = targets.add(name, extension_type, {})
        host_name = f"Host{index:02d}"
        host = app(host_name)
        if how == "via-framework":
            middle, _ = targets.add(f"Mid{index:02d}", "com.apple.product-type.framework", {})
            targets.depend(middle, extension, name)
            targets.depend(host, middle, f"Mid{index:02d}")
        else:
            targets.depend(host, extension, name)
        if how == "unit":
            bundle(f"{host_name}Tests", host, host_name, UNIT_TEST, test_host)
        elif how != "none":
            tests = bundle(f"{host_name}Tests", host, host_name)
            if how == "bundle-covered":
                scheme(f"S{index:02d}", testables=[testable(tests, f"{host_name}Tests")])
        if how == "host-launched":
            scheme(f"S{index:02d}", build=[(host, f"{host_name}.app", host_name, container, True)],
                   launch=("product", (host, f"{host_name}.app", host_name, container)))
        if how == "two-hosts":
            other = app(f"Other{index:02d}")
            targets.depend(other, extension, name)
            bundle(f"Other{index:02d}Tests", other, f"Other{index:02d}")
    # Bundles and apps whose SDKROOT is auto.
    for index, (app_settings, bundle_settings, kind, covered) in enumerate([
        ({}, {**AUTO_SDK, **test_host}, UNIT_TEST, False),
        ({}, {**AUTO_SDK, **test_host}, UNIT_TEST, True),
        (AUTO_SDK, test_host, UNIT_TEST, False),
        ({}, AUTO_SDK, UI_TEST, False),
        (AUTO_SDK, {}, UI_TEST, False),
        ({}, {**AUTO_SDK, "TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/{0}.app/{0}")}, UNIT_TEST, True),
    ], 16):
        name = f"Auto{index:02d}"
        host = app(name, app_settings)
        bundle(f"{name}Tests", host, name, kind, bundle_settings)
        if covered:
            scheme(f"S{index:02d}", build=[(host, f"{name}.app", name, container, True)], launch=("product", (host, f"{name}.app", name, container)))
    # A unit test bundle of a macOS app whose TEST_HOST names it under the bundle's iOS products folder.
    mac = app("Mac22", sdk="macosx")
    bundle("Mac22Tests", mac, "Mac22", UNIT_TEST, {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/Mac22.app/Contents/MacOS/Mac22"),
                                                   "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")})
    # An extension's scheme and the bundle of the framework between it and its app.
    extension, _ = targets.add("Ext23", APPEX, {})
    middle, _ = targets.add("Mid23", "com.apple.product-type.framework", {})
    host = app("Host23")
    targets.depend(middle, extension, "Ext23")
    targets.depend(host, middle, "Mid23")
    bundle("Mid23Tests", middle, "Mid23")
    # A bundle only a shared scheme's test plan names.
    host = app("App24")
    tests = bundle("App24Tests", host, "App24")
    files["Plan24.xctestplan"] = json.dumps({
        "configurations": [{"id": "A11977F5-134B-4CB5-B798-B2F3F30138CD", "name": "Configuration 1", "options": {}}], "defaultOptions": {},
        "testTargets": [{"target": {"containerPath": container, "identifier": tests, "name": "App24Tests"}}], "version": 1}, indent=2) + "\n"
    scheme("S24", plans=[("container:Plan24.xctestplan", True)])
    return targets.project(files)


def observe_autocreate_testables(run):
    observe_test_hosts(run)
    for action in [(), ("test",)]:
        run(f"scheme-Mac22-macosx{'-test' if action else ''}", "-showBuildSettings", "-scheme", "Mac22", "-destination", "generic/platform=macOS", *action)


def provisioning_auto():
    # The differential fuzzer: an app whose SDKROOT is auto, for iOS and macOS, with a team and no
    # style has provisioningStyle 0, where `-showBuildSettings -target` evaluates no identity.
    # The supported platforms, the team and the identity, each way, for apps and other types.
    targets = Targets()
    identity, team = "CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM"
    platforms = {"Both": "iphoneos iphonesimulator macosx", "Mac": "macosx", "MacFirst": "macosx iphoneos iphonesimulator",
                 "IOS": "iphoneos iphonesimulator", "None": None}
    for label, supported in platforms.items():
        for suffix, settings in [("", {}), ("Team", {team: "ABCDE12345"}), ("Dash", {identity: pbx_string("-")}),
                                 ("Developer", {identity: pbx_string("Apple Development")}),
                                 ("MacDash", {pbx_string(identity + "[sdk=macosx*]"): pbx_string("-")}),
                                 ("Catalyst", {"SUPPORTS_MACCATALYST": "YES", team: "ABCDE12345"})]:
            values = {**settings, "SUPPORTED_PLATFORMS": pbx_string(supported) if supported else None}
            targets.add(f"App{label}{suffix}", APPLICATION, values, sdk="auto")
    for product_type in ["framework", "tool", "bundle.unit-test", "app-extension"]:
        name = product_type.replace(".", "-").title().replace("-", "")
        targets.add(f"{name}Both", f"com.apple.product-type.{product_type}", {"SUPPORTED_PLATFORMS": pbx_string(platforms["Both"])}, sdk="auto")
        targets.add(f"{name}Mac", f"com.apple.product-type.{product_type}", {"SUPPORTED_PLATFORMS": pbx_string("macosx")}, sdk="auto")
    return targets.project()


SYNCHRONIZED_EXCEPTION_FILES = ["a.swift", "b.swift", "c.swift", "d.m", "e.png", "f.json", "g.h", "h.a", "i.xcconfig", "en.lproj/L.strings",
                                "fr.lproj/L.strings", "Sub/j.swift", "Sub/k.png"]


class SynchronizedTargets:
    """Targets that take members from one synchronized folder `Src`, with the exception sets
    (PBXFileSystemSynchronizedBuildFileExceptionSet, -GroupBuildPhaseMembershipExceptionSet)
    each one adds."""

    PHASES = {"sources": "PBXSourcesBuildPhase", "resources": "PBXResourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase",
              "headers": "PBXHeadersBuildPhase", "copy": "PBXCopyFilesBuildPhase"}

    def __init__(self):
        self.objects, self.targets, self.sets, self.count = "", [], [], 0

    def identifier(self, prefix):
        self.count += 1
        return f"{prefix}{self.count:023d}"

    @staticmethod
    def entries(mapping):
        return "".join(f"\t\t\t\t{pbx_string(path)} = ({', '.join(values)}, );\n" for path, values in mapping.items())

    @staticmethod
    def paths(items):
        return "".join(f"\t\t\t\t{pbx_string(path)},\n" for path in items)

    def build_file_set(self, target, membership=(), filters=None, attributes=None, flags=None):
        set_id = self.identifier("S")
        text = f"\t\t{set_id} = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
        if flags:
            text += "\t\t\tadditionalCompilerFlagsByRelativePath = {\n" + "".join(
                f"\t\t\t\t{pbx_string(path)} = {pbx_string(value)};\n" for path, value in flags.items()) + "\t\t\t};\n"
        if attributes:
            text += f"\t\t\tattributesByRelativePath = {{\n{self.entries(attributes)}\t\t\t}};\n"
        if membership:
            text += f"\t\t\tmembershipExceptions = (\n{self.paths(membership)}\t\t\t);\n"
        if filters:
            text += f"\t\t\tplatformFiltersByRelativePath = {{\n{self.entries(filters)}\t\t\t}};\n"
        self.sets.append(set_id)
        self.objects += text + f"\t\t\ttarget = {target};\n\t\t}};\n"

    def phase_set(self, phase, membership, attributes=None):
        set_id = self.identifier("S")
        text = f"\t\t{set_id} = {{\n\t\t\tisa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet;\n"
        if attributes:
            text += f"\t\t\tattributesByRelativePath = {{\n{self.entries(attributes)}\t\t\t}};\n"
        self.sets.append(set_id)
        self.objects += text + f"\t\t\tbuildPhase = {phase};\n\t\t\tmembershipExceptions = (\n{self.paths(membership)}\t\t\t);\n\t\t}};\n"

    def target(self, name, listed, phases, product_type=APPLICATION):
        """Adds a target with `phases` (kind, extra keys); returns its ID and its phases' IDs."""
        target_id, reference = self.identifier("C"), self.identifier("P")
        phase_ids = []
        for kind, extra in phases:
            phase_id = self.identifier("B")
            self.objects += (f"\t\t{phase_id} = {{isa = {self.PHASES[kind]}; buildActionMask = 2147483647; {extra}files = (); "
                             "runOnlyForDeploymentPostprocessing = 0; };\n")
            phase_ids.append(phase_id)
        groups = "\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tS00000000000000000000000,\n\t\t\t);\n" if listed else ""
        index = len(self.targets) + 1
        settings = {**APP_SETTINGS, "SDKROOT": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.experiment.target{index}"}
        self.objects += product_file(reference, name, product_type) + app_target(
            target_id, name, phase_ids, [f"L{index:023d}", f"D{index:023d}", f"R{index:023d}"], settings, extra=groups,
            product_type=product_type, product_reference=reference)
        self.targets.append((target_id, reference))
        return target_id, phase_ids

    def project(self, files):
        folder = "\t\tS00000000000000000000000 /* Src */ = {\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\texceptions = (\n" \
                 + "".join(f"\t\t\t\t{set_id},\n" for set_id in self.sets) + '\t\t\t);\n\t\t\tpath = Src;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
        children = "".join(f"\t\t\t\t{reference},\n" for _, reference in self.targets)
        objects = self.objects + folder + f"""\t\tF00000000000000000000002 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tS00000000000000000000000 /* Src */,
{children}\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
"""
        return {"P.xcodeproj/project.pbxproj": project("F00000000000000000000006", "F00000000000000000000002", [t for t, _ in self.targets],
                                                       objects, known_regions=("en", "Base", "fr")), **files}


SYNCHRONIZED_STANDARD_PHASES = [("sources", ""), ("frameworks", ""), ("resources", "")]
SYNCHRONIZED_COPY_PHASE = ("copy", 'dstPath = ""; dstSubfolderSpec = 7; name = "Copy Shared"; ')


def synchronized_files(names):
    return {f"Src/{name}": "!<arch>\n" if name.endswith(".a") else "x\n" for name in names}


def synchronized_exceptions():
    # The differential fuzzer: Xcode gives the build file of a synchronized member the platform
    # filters of `platformFiltersByRelativePath`, and adds a member to the phase a
    # PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet names. Each target here takes
    # members from one folder in one way; `Sub` and the missing `gone.swift` test paths.
    sync = SynchronizedTargets()
    standard = SYNCHRONIZED_STANDARD_PHASES
    plugins = ("copy", 'dstPath = ""; dstSubfolderSpec = 13; name = "Copy PlugIns"; ')
    # Platform filters on every kind of member, in a target that lists the folder.
    filters, _ = sync.target("Filters", True, [("headers", "")] + standard, product_type="com.apple.product-type.framework")
    sync.build_file_set(filters, filters={
        "a.swift": ["ios"], "b.swift": ["macos"], "c.swift": ["ios", "maccatalyst"], "d.m": ["maccatalyst"], "e.png": ["ios"], "f.json": ["tvos"],
        "g.h": ["ios"], "h.a": ["macos"], "/Localized/L.strings": ["ios"], "Sub/j.swift": ["watchos"], "Sub": ["ios"], "i.xcconfig": ["ios"],
        "gone.swift": ["ios"], "A.swift": ["ios"]})
    # Filters with membership: an excluded member, a guest's added member, two sets.
    excluded, _ = sync.target("Excluded", True, standard)
    sync.build_file_set(excluded, membership=["a.swift"], filters={"a.swift": ["ios"], "b.swift": ["macos"]})
    guest, _ = sync.target("Guest", False, standard)
    sync.build_file_set(guest, membership=["a.swift", "e.png"], filters={"a.swift": ["ios"], "b.swift": ["macos"]})
    both, _ = sync.target("Both", True, standard)
    sync.build_file_set(both, filters={"a.swift": ["ios"]})
    sync.build_file_set(both, filters={"a.swift": ["macos"], "b.swift": ["ios"]})
    # Phase membership: Resources, two copy-files phases, the Sources phase, with attributes.
    _, phase_ids = sync.target("Phases", True, standard + [SYNCHRONIZED_COPY_PHASE, plugins])
    sync.phase_set(phase_ids[2], ["a.swift", "f.json", "/Localized/L.strings", "Sub/j.swift", "gone.swift"])
    sync.phase_set(phase_ids[3], ["e.png", "b.swift", "Sub"], attributes={"b.swift": ["CodeSignOnCopy"], "e.png": ["RemoveHeadersOnCopy"]})
    sync.phase_set(phase_ids[4], ["c.swift"], attributes={"c.swift": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
    sync.phase_set(phase_ids[0], ["e.png", "a.swift"])
    # A phase set for a target that does not list the folder, and one naming an excluded member.
    _, phase_ids = sync.target("PhaseGuest", False, standard + [SYNCHRONIZED_COPY_PHASE])
    sync.phase_set(phase_ids[3], ["c.swift", "e.png"])
    sync.phase_set(phase_ids[2], ["f.json"])
    phase_excluded, phase_ids = sync.target("PhaseExcluded", True, standard + [SYNCHRONIZED_COPY_PHASE])
    sync.build_file_set(phase_excluded, membership=["c.swift", "e.png"])
    sync.phase_set(phase_ids[3], ["c.swift", "e.png"])
    # A second phase of a kind.
    _, phase_ids = sync.target("SecondPhase", True, standard + [("resources", "")])
    sync.phase_set(phase_ids[3], ["f.json", "a.swift"])
    return sync.project(synchronized_files(SYNCHRONIZED_EXCEPTION_FILES))


def synchronized_exceptions_2():
    # synchronized-exceptions listed `gone.swift`, which a phase set and platform filters name, and
    # `A.swift`, which platform filters name next to `a.swift`. Here each missing path is named by
    # one key of one set, for which of them the folder lists it, and with which filters or flags.
    sync = SynchronizedTargets()
    standard = SYNCHRONIZED_STANDARD_PHASES
    first, _ = sync.target("Keys", True, standard)
    sync.build_file_set(first, filters={"filtered.swift": ["ios"], "B.swift": ["ios"]}, attributes={"attributed.swift": ["Weak"]},
                        flags={"flagged.m": "-DX"})
    _, phase_ids = sync.target("PhaseKeys", True, standard + [SYNCHRONIZED_COPY_PHASE])
    sync.phase_set(phase_ids[3], ["phased.png", "Sub/deep.png"], attributes={"phased.png": ["CodeSignOnCopy"]})
    third, _ = sync.target("Members", True, standard)
    sync.build_file_set(third, membership=["C.swift", "member.swift"], filters={"member.swift": ["macos"]})
    return sync.project(synchronized_files(["a.swift", "b.swift", "c.swift", "e.png", "Sub/j.swift"]))


SYNCHRONIZED_ORDER_ITEMS = ["r1.png", "r2.json", "r3.png", "r4.txt", "r5.png", "r6.json", "r7.png", "r8.txt", "s1.swift", "s2.swift", "s3.swift",
                            "Sub/r9.png", "Sub/s4.swift"]


def synchronized_phase_order():
    # synchronized-exceptions: a phase set's members came before the folder's own in the Sources
    # phase and after them in Resources. Twenty targets with one phase set each, on Resources or
    # Sources, of other members, for where the set's block goes among the folder's.
    sync = SynchronizedTargets()
    chooser = random.Random("nomac-synchronized-phase-order")
    for index in range(1, 21):
        kind = 2 if index % 3 else 0
        listed = index % 7 != 0
        _, phase_ids = sync.target(f"T{index:02d}", listed, SYNCHRONIZED_STANDARD_PHASES)
        members = chooser.sample(SYNCHRONIZED_ORDER_ITEMS, chooser.randint(1, 5))
        sync.phase_set(phase_ids[kind], members)
        if index % 5 == 0:
            sync.phase_set(phase_ids[kind], chooser.sample(SYNCHRONIZED_ORDER_ITEMS, 2))
    return sync.project(synchronized_files(SYNCHRONIZED_ORDER_ITEMS))



def synchronized_phase_order_2():
    # synchronized-exceptions: the block of a phase set naming the variant group L.strings went
    # where hashing its name as `Localized` puts it. Phase sets naming variant groups and files.
    sync = SynchronizedTargets()
    chooser = random.Random("nomac-synchronized-phase-order-2")
    names = ["r1.png", "r2.json", "s1.swift", "/Localized/V1.strings", "/Localized/V2.strings", "/Localized/Sub/V3.strings", "Sub/r3.png"]
    for index in range(1, 16):
        _, phase_ids = sync.target(f"T{index:02d}", index % 4 != 0, SYNCHRONIZED_STANDARD_PHASES)
        members = chooser.sample(names, chooser.randint(1, 4))
        sync.phase_set(phase_ids[0 if index % 5 == 0 else 2], members)
    return sync.project(synchronized_files(["r1.png", "r2.json", "s1.swift", "en.lproj/V1.strings", "fr.lproj/V1.strings", "en.lproj/V2.strings",
                                            "Sub/en.lproj/V3.strings", "Sub/r3.png"]))


def autocreate_ui_targets():
    # autocreate-testables: Mid23Tests, a UI test bundle whose TestTargetID is a framework, is
    # tested by no scheme and gets none of its own. One UI test bundle per product type it names.
    targets = Targets()
    for index, (product_type, sdk) in enumerate([
        ("application", "iphoneos"), ("framework", "iphoneos"), ("app-extension", "iphoneos"), ("library.static", "iphoneos"),
        ("application.on-demand-install-capable", "iphoneos"), ("tool", "macosx"), ("application.watchapp2", "watchos"),
        ("bundle", "iphoneos"), ("app-extension.messages-sticker-pack", "iphoneos"), ("application", "macosx"),
    ], 1):
        name = f"Kind{index:02d}"
        tested, _ = targets.add(name, f"com.apple.product-type.{product_type}", {}, sdk=sdk)
        bundle, _ = targets.add(f"{name}UITests", UI_TEST, {}, sdk=sdk)
        targets.attribute(bundle, f"\t\t\t\t\t\tTestTargetID = {tested};\n")
        targets.depend(bundle, tested, name)
    return targets.project()


def autocreate_auto_hosts():
    # autocreate-testables: Auto18, an app whose SDKROOT is auto, tests the iOS bundle whose
    # TEST_HOST is $(BUILT_PRODUCTS_DIR)/Auto18.app/Auto18, while `-showBuildSettings -target`
    # gives the app no EXECUTABLE_PATH. Such apps, their platforms in either order, and bundles
    # naming an iOS or a macOS executable.
    targets = Targets()
    ios, mac = "$(BUILT_PRODUCTS_DIR)/{0}.app/{0}", "$(BUILT_PRODUCTS_DIR)/{0}.app/Contents/MacOS/{0}"
    for index, (platforms, host) in enumerate([
        ("iphoneos iphonesimulator macosx", ios), ("macosx iphoneos iphonesimulator", ios), ("macosx iphoneos iphonesimulator", mac),
        ("iphoneos iphonesimulator macosx", mac), (None, ios), (None, mac), ("macosx", mac), ("macosx", ios),
    ], 1):
        name = f"A{index:02d}"
        app, _ = targets.add(name, APPLICATION, {"SUPPORTED_PLATFORMS": pbx_string(platforms) if platforms else None}, sdk="auto")
        bundle, _ = targets.add(f"{name}Tests", UNIT_TEST, {"TEST_HOST": pbx_string(host.replace("{0}", name)), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")})
        targets.attribute(bundle, f"\t\t\t\t\t\tTestTargetID = {app};\n")
        targets.depend(bundle, app, name)
    # A TEST_HOST naming another app, none, and no TestTargetID with a matching BUNDLE_LOADER.
    both = "iphoneos iphonesimulator macosx"
    for index, (settings, target_id) in enumerate([
        ({"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/Elsewhere.app/Elsewhere"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}, True),
        ({}, True), ({"TEST_HOST": pbx_string(ios), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}, False),
        ({"TEST_HOST": pbx_string(mac), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}, False),
    ], 9):
        name = f"A{index:02d}"
        app, _ = targets.add(name, APPLICATION, {"SUPPORTED_PLATFORMS": pbx_string(both)}, sdk="auto")
        bundle, _ = targets.add(f"{name}Tests", UNIT_TEST, {key: value.replace("{0}", name) for key, value in settings.items()})
        if target_id:
            targets.attribute(bundle, f"\t\t\t\t\t\tTestTargetID = {app};\n")
        targets.depend(bundle, app, name)
    return targets.project()


def synchronized_missing_order():
    # synchronized-exceptions-2: Sub/deep.png, named by a set but not on disk in the existing
    # folder Sub, came after the other members in Resources, though the group tree lists it in
    # Sub. Missing paths in two subfolders, a nested one and the top level, named by sets in an
    # order unlike the walk's, with members of both phases around them.
    sync = SynchronizedTargets()
    first, _ = sync.target("Missing", True, SYNCHRONIZED_STANDARD_PHASES)
    sync.build_file_set(first, filters={"Sub2/m2.png": ["ios"], "zz.png": ["ios"], "Sub/m1.png": ["ios"], "Sub/Deep/m3.swift": ["ios"],
                                        "Sub/m0.swift": ["ios"], "aa.png": ["ios"]})
    second, _ = sync.target("Guest", False, SYNCHRONIZED_STANDARD_PHASES)
    sync.build_file_set(second, membership=["Sub/m1.png", "Sub2/y.png", "a.png", "Sub/x.png"])
    return sync.project(synchronized_files(["a.png", "b.swift", "Sub/x.png", "Sub/w.swift", "Sub/Deep/d.png", "Sub2/y.png", "Sub2/z.swift"]))


def test_host_clashes(workspace, covered_first):
    # The differential fuzzer: a unit test bundle depending on an autocreated App, whose TEST_HOST
    # names App.app/App, got a scheme of its own when another target, a shared scheme launches,
    # builds App.app too, in another project or the same one. Two apps named App, the covered one
    # first or last, in one project or two of a workspace.
    files = {}
    test_host = {"TEST_HOST": pbx_string("$(BUILT_PRODUCTS_DIR)/App.app/App"), "BUNDLE_LOADER": pbx_string("$(TEST_HOST)")}

    def covered(targets, container):
        app, _ = targets.add("App", APPLICATION, {})
        return app, scheme_file(build=[(app, "App.app", "App", container, True)], launch=("product", (app, "App.app", "App", container)))

    def hosted(targets):
        app, _ = targets.add("App", APPLICATION, {})
        tests, _ = targets.add("AppTests", UNIT_TEST, test_host)
        targets.attribute(tests, f"\t\t\t\t\t\tTestTargetID = {app};\n")
        targets.depend(tests, app, "App")

    if workspace:
        p, q = Targets(), Targets()
        _, text = covered(p, "container:P.xcodeproj")
        hosted(q)
        files.update(p.project(path="P.xcodeproj"))
        files.update(q.project(path="Q.xcodeproj"))
        files["P.xcodeproj/xcshareddata/xcschemes/Covered.xcscheme"] = text
        files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj", "Q.xcodeproj"] if covered_first else ["Q.xcodeproj", "P.xcodeproj"])
        return files
    targets = Targets()
    if covered_first:
        _, text = covered(targets, "container:P.xcodeproj")
        hosted(targets)
    else:
        hosted(targets)
        _, text = covered(targets, "container:P.xcodeproj")
    files.update(targets.project())
    files["P.xcodeproj/xcshareddata/xcschemes/Covered.xcscheme"] = text
    return files


def observe_test_host_clashes(run):
    for attempt in range(1, 4):
        run(f"list-{attempt}", "-list", "-json")

def scheme_name_clashes():
    # The differential fuzzer: `-scheme Fuzz` used a shared Fuzz scheme of another project, renamed
    # in -list, rather than the autocreated Fuzz; `-scheme Kit` the autocreated scheme of a local
    # package's Kit product rather than that of the target Kit. P has the targets Dup and Kit and
    # the package Kit, Q and R a shared scheme Dup each.
    files = package_files("Packages/Kit", "Kit", ['.library(name: "Kit", targets: ["Kit"])'], {"Kit": ("library", [])})
    targets = Targets()
    targets.add("Dup", APPLICATION, {})
    targets.add("Kit", "com.apple.product-type.framework", {})
    files.update(targets.project())
    reference = '\t\tY00000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Kit; };\n'
    text = files["P.xcodeproj/project.pbxproj"]
    text = text.replace("/* Begin PBXProject section */", "/* Begin PBXProject section */\n" + reference, 1) if "/* Begin PBXProject section */" in text \
        else text.replace("\t\tF00000000000000000000006 /* Project object */", reference + "\t\tF00000000000000000000006 /* Project object */", 1)
    files["P.xcodeproj/project.pbxproj"] = text.replace("\t\t\tminimizedProjectReferenceProxies = 1;\n",
                                                        "\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpackageReferences = (\n\t\t\t\tY00000000000000000000001,\n\t\t\t);\n", 1)
    for name in ["Q", "R"]:
        other = Targets()
        app, _ = other.add(f"{name}App", APPLICATION, {})
        container = f"container:{name}.xcodeproj"
        files.update(other.project(path=f"{name}.xcodeproj"))
        files[f"{name}.xcodeproj/xcshareddata/xcschemes/Dup.xcscheme"] = scheme_file(
            build=[(app, f"{name}App.app", f"{name}App", container, True)], launch=("product", (app, f"{name}App.app", f"{name}App", container)))
    files["W.xcworkspace/contents.xcworkspacedata"] = workspace_contents(["P.xcodeproj", "Q.xcodeproj", "R.xcodeproj"])
    return files


def observe_scheme_name_clashes(run):
    run("list", "-list", "-json")
    for attempt in range(1, 5):
        for name in ["Dup", "Kit"]:
            run(f"scheme-{name}-{attempt}", "-showBuildSettings", "-scheme", name, "-destination", "generic/platform=iOS")


# name: (files, container to dump, function that runs further xcodebuild commands)
EXPERIMENTS = {
    "version-group": (version_group, "P.xcodeproj", None),
    "targets": (targets, "P.xcodeproj", lambda run: run("alltargets", "-showBuildSettings", "-alltargets")),
    "settings": (settings, "P.xcodeproj", lambda run: (run("App", "-target", "App", "-configuration", "Debug", "-showBuildSettings"),
                                                       run("alltargets", "-showBuildSettings", "-alltargets"))),
    "workspace": (workspace, "W.xcworkspace", lambda run: (run("list-text", "-list"), run("list", "-list", "-json"),
                                                            run("settings-default", "-showBuildSettings"),
                                                            run("settings-target", "-showBuildSettings", "-target", "App"),
                                                            run("settings-alltargets", "-showBuildSettings", "-alltargets"))),
    "workspace-order": (workspace_order, "W.xcworkspace", None),
    "target-names": (target_names, "P.xcodeproj", observe_target_names),
    "schemes": (schemes, "P.xcodeproj", observe_schemes),
    "autocreate": (autocreate, "P.xcodeproj", lambda run: (run("list", "-list", "-json"), run("scheme-Host", "-showBuildSettings", "-scheme", "Host", "-destination", "generic/platform=iOS"))),
    "extension-points": (extension_points, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "product-types": (product_types, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "autocreate-hosts": (autocreate_hosts, "P.xcodeproj", lambda run: (
        observe_every_scheme(run),
        run("scheme-ToolExtension-macosx", "-showBuildSettings", "-scheme", "ToolExtension", "-destination", "generic/platform=macOS"),
        run("scheme-WatchWidget-watchos", "-showBuildSettings", "-scheme", "WatchWidget", "-destination", "generic/platform=watchOS"),
        [run(f"scheme-Kind{index:02d}-{platform}", "-showBuildSettings", "-scheme", f"Kind{index:02d}", "-destination", f"generic/platform={platform}")
         for index, platform in [(7, "tvOS"), (8, "macOS"), (9, "macOS"), (10, "macOS")]])),
    "autocreate-order": (lambda: configuration_experiment(["Release", "Debug"], "Release"), "P.xcodeproj", observe_configurations),
    "autocreate-names": (lambda: configuration_experiment(["Alpha", "Beta"], "Beta"), "P.xcodeproj", observe_configurations),
    "autocreate-three": (lambda: configuration_experiment(["Alpha", "Beta", "Gamma"], "Beta"), "P.xcodeproj", observe_configurations),
    "test-bundles": (test_bundles, "P.xcodeproj", observe_test_bundles),
    "scheme-coverage": (scheme_coverage, "P.xcodeproj", observe_every_scheme),
    "test-hosts": (test_hosts, "P.xcodeproj", observe_test_hosts),
    "infoplist-macros": (infoplist_macros, "P.xcodeproj", None),
    "file-encodings": (file_encodings, "P.xcodeproj", None),
    "coverage": (coverage, "P.xcodeproj", observe_every_scheme),
    "coverage-autocreated-plan": (coverage_autocreated_plan, "P.xcodeproj", observe_every_scheme),
    "provisioning-style": (provisioning_style, "P.xcodeproj", None),
    "provisioning-style-project": (lambda: provisioning_style("Manual"), "P.xcodeproj", None),
    "provisioning-defaults": (provisioning_defaults, "P.xcodeproj", observe_provisioning_defaults),
    "source-languages": (source_languages, "P.xcodeproj", None),
    "build-rules": (build_rules, "P.xcodeproj", None),
    "build-rule-keys": (build_rule_keys, "P.xcodeproj", None),
    "product-names": (product_names, "P.xcodeproj", None),
    "product-names-configurations": (lambda: product_names(("Alpha", "Beta", "Gamma"), "Beta", {"SDKROOT": "iphoneos", "PRODUCT_NAME": "ProjectLevel"}),
                                     "P.xcodeproj", None),
    "class-prefix": (class_prefix, "P.xcodeproj", None),
    "xcconfig-conditions": (xcconfig_conditions, "P.xcodeproj", None),
    "class-prefix-empty": (lambda: class_prefix('""'), "P.xcodeproj", None),
    "class-prefix-unset": (lambda: class_prefix(None), "P.xcodeproj", None),
    "language-synchronized": (language_synchronized, "P.xcodeproj", None),
    "info-plist-conditions": (info_plist_conditions, "P.xcodeproj", None),
    "product-names-order": (lambda: product_names(("Release", "Debug"), "Release"), "P.xcodeproj", None),
    "product-names-empty": (product_names_empty, "P.xcodeproj", None),
    "swift-wholemodule": (swift_wholemodule, "P.xcodeproj", observe_swift_wholemodule),
    "swift-wholemodule-46": (lambda: swift_wholemodule(46), "P.xcodeproj", lambda run: observe_swift_wholemodule(run, ["Plain", "Xcconfig"])),
    "swift-wholemodule-upgrade-1010": (lambda: swift_wholemodule(77, "LastUpgradeCheck = 1010;"), "P.xcodeproj",
                                       lambda run: observe_swift_wholemodule(run, ["Plain", "Xcconfig"])),
    "swift-wholemodule-46-upgrade-1010": (lambda: swift_wholemodule(46, "LastUpgradeCheck = 1010;"), "P.xcodeproj",
                                          lambda run: observe_swift_wholemodule(run, ["Plain", "Xcconfig"])),
    **{f"swift-wholemodule-{version}": (lambda version=version: swift_wholemodule(version), "P.xcodeproj", None)
       for version in (42, 45, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 60, 63, 70)},
    "product-types-sdks": (product_types_sdks, "P.xcodeproj", None),
    "product-types-restricted": (lambda: product_types_sdks(["application.watchapp2", "watchkit2-extension", "xcode-extension", "tv-app-extension",
                                                             "application.messages", "application"], RESTRICTED_SDKS), "P.xcodeproj", None),
    "synchronized-search-paths": (synchronized_search_paths, "P.xcodeproj", None),
    "synchronized-search-paths-project": (lambda: synchronized_search_paths({"LIBRARY_SEARCH_PATHS": pbx_string("/project/lib")}), "P.xcodeproj", None),
    "synchronized-search-paths-folders": (synchronized_search_paths_folders, "App/P.xcodeproj", None, place_outside_folder),
    "language-fallback": (language_fallback, "P.xcodeproj", None),
    "language-fallback-missing": (language_fallback_missing, "P.xcodeproj", None),
    "pif-key-order": (pif_key_order, "P.xcodeproj", None),
    "scheme-extension-key": (scheme_extension_key, "P.xcodeproj", observe_scheme_extension_key),
    **{f"workspace-locations-{name}": (lambda values=values: workspace_locations(values), "P.xcodeproj", observe_workspace_locations)
       for name, values in WORKSPACE_LOCATION_CASES.items()},
    **{f"workspace-locations-shared-{name}": (lambda values=values: workspace_locations(values, shared=True), "P.xcodeproj", observe_workspace_locations)
       for name, values in WORKSPACE_LOCATION_CASES.items()},
    "workspace-locations-symroot": (lambda: workspace_locations(WORKSPACE_LOCATION_CASES["target-settings"], symroot=True), "P.xcodeproj", observe_workspace_locations),
    "workspace-locations-workspace": (lambda: workspace_locations(WORKSPACE_LOCATION_CASES["target-settings"], workspace=True), "W.xcworkspace", observe_workspace_locations),
    "workspace-locations-workspace-derived": (lambda: workspace_locations(WORKSPACE_LOCATION_CASES["derived-relative"], workspace=True), "W.xcworkspace", observe_workspace_locations),
    "product-types-other": (lambda: product_types_sdks(OTHER_PRODUCT_TYPES, PRODUCT_SDKS[:5]), "P.xcodeproj", None),
    "product-names-no-sdk": (lambda: product_types_sdks(["application.watchapp2", "xcode-extension", "tv-app-extension", "application"], [(None, {})]),
                             "P.xcodeproj", None, remove_project_sdk),
    "local-packages": (local_packages, "P.xcodeproj", lambda run: (run("list", "-list", "-json"), observe_every_scheme(run))),
    "scheme-package-clashes": (scheme_package_clashes, "P.xcodeproj", lambda run: (run("list", "-list", "-json"), run("list-text", "-list"))),
    "root-package-references": (root_package_references, "P.xcodeproj", lambda run: (run("list", "-list", "-json"), [
        run(f"test-{name}", "-scheme", name, "-showBuildSettings", "test") for name in [entry[0] for entry in ROOT_REFERENCES] + ["Alpha", "Beta"]])),
    "macros": (macros, "P.xcodeproj", None, publish_remote),
    "unlinked-products": (unlinked_products, "P.xcodeproj", None),
    "autocreate-contexts": (lambda: autocreate_contexts(), "P.xcodeproj", observe_autocreate_contexts),
    "autocreate-contexts-off": (lambda: autocreate_contexts([(PROJECT_SETTINGS, "<false/>")]), "P.xcodeproj", observe_autocreate_contexts),
    "autocreate-contexts-off-user": (lambda: {**autocreate_contexts([(PROJECT_SETTINGS, "<false/>")]), f"{user_schemes_folder('P.xcodeproj')}/MineFw.xcscheme":
                                              scheme_file(build=[("C00000000000000000000002", "Fw.framework", "Fw", "container:P.xcodeproj", True)])},
                                     "P.xcodeproj", lambda run: (run("list", "-list", "-json"),
                                                                 run("scheme-MineFw", "-showBuildSettings", "-scheme", "MineFw", "-destination", "generic/platform=iOS"))),
    "autocreate-contexts-on": (lambda: autocreate_contexts([(PROJECT_SETTINGS, "<true/>")]), "P.xcodeproj", observe_autocreate_contexts),
    "autocreate-contexts-user-off": (lambda: autocreate_contexts([(user_settings("P.xcodeproj/project.xcworkspace"), "<false/>")]), "P.xcodeproj",
                                     observe_autocreate_contexts),
    "autocreate-contexts-shared-off-user-on": (lambda: autocreate_contexts([(PROJECT_SETTINGS, "<false/>"),
                                                                            (user_settings("P.xcodeproj/project.xcworkspace"), "<true/>")]),
                                               "P.xcodeproj", observe_autocreate_contexts),
    "autocreate-contexts-workspace-off": (lambda: autocreate_contexts([("W.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings", "<false/>")], workspace=True),
                                          "W.xcworkspace", observe_autocreate_contexts),
    "autocreate-contexts-workspace-project-off": (lambda: autocreate_contexts([(PROJECT_SETTINGS, "<false/>")], workspace=True), "W.xcworkspace",
                                                  observe_autocreate_contexts),
    "package-target-kinds": (package_target_kinds, "P.xcodeproj", observe_package_target_kinds),
    "project-references": (project_references, "P.xcodeproj", observe_project_references),
    "project-references-workspace": (lambda: project_references(workspace=["P.xcodeproj"]), "W.xcworkspace",
                                     lambda run: observe_project_references(run, "workspace")),
    "project-references-missing": (project_references_missing, "P.xcodeproj",
                                   lambda run: (run("list", "-list", "-json"),
                                                run("scheme-App", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS"))),
    "project-references-packages": (project_references_packages, "P.xcodeproj", observe_every_scheme),
    "project-references-stale": (project_references_stale, "P.xcodeproj",
                                 lambda run: (run("list", "-list", "-json"),
                                              run("scheme-App", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS"))),
    "project-references-bundles": (project_references_bundles, "P.xcodeproj", observe_every_scheme),
    "project-references-renamed": (project_references_renamed, "P.xcodeproj", None),
    "workspace-twins": (workspace_twins, "W.xcworkspace", None),
    "project-reference-names": (project_reference_names, "Q.xcodeproj", observe_project_reference_names),
    "workspace-names": (lambda: project_reference_names(workspace=True), "W.xcworkspace", observe_project_reference_names),
    "intents-codegen": (intents_codegen, "P.xcodeproj", None),
    "mig-codegen": (mig_codegen, "P.xcodeproj", None),
    "dependency-proxies": (dependency_proxies, "P.xcodeproj", None),
    "root-group-name": (lambda: root_group([("name", "CustomTemplate")]), "P.xcodeproj", None),
    "root-group-path": (lambda: root_group([("path", "Sources")]), "P.xcodeproj", None),
    "root-group-name-path": (lambda: root_group([("name", "CustomTemplate"), ("path", "Sources")]), "P.xcodeproj", None),
    "watch-schemes": (watch_schemes, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "dangling-synchronized": (dangling_synchronized, "P.xcodeproj", None),
    "dangling-synchronized-renamed": (lambda: dangling_synchronized("Q"), "P.xcodeproj", None),
    "dangling-synchronized-ids": (lambda: dangling_synchronized(first_id=501), "P.xcodeproj", None),
    "dangling-synchronized-members": (lambda: dangling_synchronized(member="zz"), "P.xcodeproj", None),
    "dangling-synchronized-lengths": (lambda: dangling_synchronized(cases=DANGLING_LENGTHS), "P.xcodeproj", None),
    "dangling-synchronized-lengths-members": (lambda: dangling_synchronized(member="zz", cases=DANGLING_LENGTHS), "P.xcodeproj", None),
    "dangling-synchronized-pairs": (lambda: dangling_synchronized(cases=DANGLING_PAIRS), "P.xcodeproj", None),
    "watch-schemes-plist": (watch_schemes_plist, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-missing": (lambda: watch_schemes_missing("missing"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-written": (lambda: watch_schemes_missing("written"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-empty": (lambda: watch_schemes_missing("empty"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-garbage": (lambda: watch_schemes_missing("garbage"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-xib": (lambda: watch_schemes_missing("xib"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-type-only": (lambda: watch_schemes_missing("type-only"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-extension-only": (lambda: watch_schemes_missing("extension-only"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-complication": (lambda: watch_schemes_missing("complication"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-variant": (lambda: watch_schemes_missing("variant"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-variant-missing": (lambda: watch_schemes_missing("variant-missing"), "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-referencing": (lambda: watch_schemes_missing("referencing"), "Q.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-referenced": (lambda: watch_schemes_missing("referenced"), "Q.xcodeproj", lambda run: run("list", "-list", "-json")),
    "watch-schemes-workspace": (lambda: watch_schemes_missing("workspace"), "All.xcworkspace", lambda run: run("list", "-list", "-json")),
    "watch-schemes-apns": (watch_schemes_apns, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "intents-codegen-fr": (lambda: intents_codegen("fr"), "P.xcodeproj", None),
    "codegen-file-types": (codegen_file_types, "P.xcodeproj", None),
    "codegen-members": (codegen_members, "P.xcodeproj", None),
    "synchronized-headers": (synchronized_headers, "P.xcodeproj", None),
    "variant-regions": (variant_regions, "P.xcodeproj", None),
    "provisioning-fallback": (lambda: provisioning_fallback(THREE_CONFIGURATIONS, "Release", STYLE_FALLBACKS), "P.xcodeproj", None),
    "provisioning-fallback-project": (lambda: provisioning_fallback(PROJECT_RELEASE_MANUAL, "Release", PROJECT_STYLE_FALLBACKS), "P.xcodeproj", None),
    "provisioning-fallback-project-debug": (lambda: provisioning_fallback(PROJECT_RELEASE_MANUAL, "Debug", PROJECT_STYLE_FALLBACKS), "P.xcodeproj", None),
    "provisioning-profile": (lambda: provisioning_fallback(THREE_CONFIGURATIONS, "Release", PROFILE_FALLBACKS), "P.xcodeproj", None),
    "provisioning-profile-project": (lambda: provisioning_fallback([("Debug", {}), ("Release", PROFILE), ("Profile", {})], "Release",
                                                                   PROJECT_STYLE_FALLBACKS), "P.xcodeproj", None),
    "provisioning-conditions": (lambda: provisioning_fallback(THREE_CONFIGURATIONS, "Release", CONDITION_FALLBACKS, CONDITION_XCCONFIGS),
                                "P.xcodeproj", lambda run: run("alltargets-Release", "-showBuildSettings", "-alltargets", "-configuration", "Release")),
    "provisioning-conditions-project": (lambda: provisioning_fallback(THREE_CONFIGURATIONS, "Release", [("Nothing", None, {}, "Release", None)],
                                                                      CONDITION_XCCONFIGS, project_base=(1, "A00000000000000000000006")),
                                        "P.xcodeproj", lambda run: run("alltargets-Release", "-showBuildSettings", "-alltargets", "-configuration", "Release")),
    "test-plan-entries": (test_plan_entries, "P.xcodeproj", lambda run: (run("list-text", "-list"), observe_every_scheme(run))),
    "copy-files": (copy_files, "P.xcodeproj", None),
    "copy-files-18": (lambda: copy_files_project([18]), "P.xcodeproj", lambda run: (run("list", "-list", "-json"), run("settings", "-showBuildSettings"))),
    "unicode-nfc": (lambda: unicode_names("NFC"), unicodedata.normalize("NFC", "Café.xcodeproj"), observe_unicode_names("NFC")),
    "unicode-nfd": (lambda: unicode_names("NFD"), unicodedata.normalize("NFD", "Café.xcodeproj"), observe_unicode_names("NFD")),
    "unicode-order": (unicode_order, "P.xcodeproj", None),
    "unicode-order-ascii": (lambda: unicode_order(ascii_names=True), "P.xcodeproj", None),
    "unicode-project-dir": (lambda: unicode_project_dir("NFC"), "P.xcodeproj", lambda run: run("target-App", "-showBuildSettings", "-target", "App")),
    "unicode-project-dir-nfd": (lambda: unicode_project_dir("NFD"), "P.xcodeproj", lambda run: run("target-App", "-showBuildSettings", "-target", "App")),
    "unicode-list-order": (list_order, "P.xcodeproj", lambda run: (run("list-text", "-list"), run("list", "-list", "-json"))),
    "derived-data-names": (derived_data_names, "N00/Plain.xcodeproj", observe_derived_data_names),
    "derived-data-packages": (derived_data_packages, unicodedata.normalize("NFC", "Päck Àpp.xcodeproj"),
                              lambda run: run("scheme-App", "-showBuildSettings", "-scheme", "App", "-destination", "generic/platform=iOS"),
                              lambda directory: publish_remote(directory, unicodedata.normalize("NFC", "Päck Àpp.xcodeproj"))),
    "package-pins-root": (lambda: package_pins([("Root", "1.0.0", "root")]), "P.xcodeproj", observe_package_pins, publish_pins([("Root", "1.0.0", "root")])),
    "package-pins-remote": (lambda: package_pins([], remote_reference=True), "P.xcodeproj", observe_package_pins, publish_pins([])),
    "package-pins-both": (lambda: package_pins([("Root", "1.0.0", "root")], remote_reference=True), "P.xcodeproj", observe_package_pins,
                          publish_pins([("Root", "1.0.0", "root")])),
    "package-pins-two-roots": (lambda: package_pins([("Alpha", "1.0.0", "root"), ("Beta", "1.1.0", "root")]), "P.xcodeproj", observe_package_pins,
                               publish_pins([("Alpha", "1.0.0", "root"), ("Beta", "1.1.0", "root")])),
    "package-pins-two-roots-same": (lambda: package_pins([("Alpha", "1.0.0", "root"), ("Beta", "1.0.0", "root")]), "P.xcodeproj", observe_package_pins,
                                    publish_pins([("Alpha", "1.0.0", "root"), ("Beta", "1.0.0", "root")])),
    "package-pins-unpinned": (lambda: package_pins([("Root", None, "root")]), "P.xcodeproj", observe_package_pins, publish_pins([("Root", None, "root")])),
    "package-pins-workspace": (lambda: package_pins([("Root", "1.0.0", "root")]), "P.xcodeproj", observe_package_pins,
                               publish_pins([("Root", "1.0.0", "root")], workspace="1.1.0")),
    "package-pins-local": (lambda: package_pins([("Local", "1.0.0", "local")]), "P.xcodeproj", observe_package_pins, publish_pins([("Local", "1.0.0", "local")])),
    "synchronized-missing": (synchronized_missing, "P.xcodeproj", lambda run: (run("list", "-list", "-json"), run("target-App", "-showBuildSettings", "-target", "App")),
                             lambda directory: (directory / "Empty").mkdir(exist_ok=True)),
    "product-target-dependencies": (product_target_dependencies, "P.xcodeproj", None),
    "product-duplicates": (product_duplicates, "P.xcodeproj", None),
    "blueprint-names": (blueprint_names, "P.xcodeproj", lambda run: (run("list-text", "-list"), observe_every_scheme(run))),
    "user-schemes": (user_schemes, "P.xcodeproj", observe_schemes_and(["Dup", "FwNamed", "Hidden", "SharedHidden", "FwAutoHidden", "OtherLaunch",
                                                                       "OtherBuild", "WsUser", "WsShared"])),
    "user-schemes-packages": (user_schemes_packages, "P.xcodeproj", observe_schemes_and(["Clash", "KitUser"])),
    "user-schemes-workspace": (user_schemes_workspace, "W.xcworkspace", observe_schemes_and(USER_SCHEMES_WORKSPACE_NAMES, "workspace")),
    "user-schemes-references": (user_schemes_references, "P.xcodeproj", observe_schemes_and(["Both", "UBoth"])),
    "scheme-pairs": (scheme_pairs, "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-kinds": (lambda: scheme_pairs(kinds=True), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-hints": (lambda: scheme_pairs(hints="shared"), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-hints-reverse": (lambda: scheme_pairs(hints="reverse"), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-hints-shared-only": (lambda: scheme_pairs(hints="shared-only"), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-hints-user-only": (lambda: scheme_pairs(hints="user-only"), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_NAMES)),
    "scheme-pairs-workspace": (lambda: scheme_pairs(workspace=True), "W.xcworkspace", observe_schemes_and(SCHEME_PAIR_NAMES, "workspace")),
    "scheme-pairs-workspace-hints": (lambda: scheme_pairs(hints="shared", workspace=True), "W.xcworkspace",
                                     observe_schemes_and(SCHEME_PAIR_NAMES, "workspace")),
    "scheme-pairs-many": (lambda: scheme_pairs(names=SCHEME_PAIR_MANY_NAMES), "P.xcodeproj", observe_schemes_and(SCHEME_PAIR_MANY_NAMES)),
    "own-test-schemes": (own_test_schemes, "P.xcodeproj", observe_test_hosts),
    "own-test-schemes-hosts": (own_test_schemes_hosts, "P.xcodeproj", lambda run: run("list", "-list", "-json")),
    "own-test-schemes-more": (own_test_schemes_more, "W.xcworkspace",
                              lambda run: (run("list", "-list", "-json"),
                                           run("scheme-SkipScheme", "-showBuildSettings", "-scheme", "SkipScheme", "-destination", "generic/platform=iOS"))),
    "scheme-order": (scheme_order, "P.xcodeproj", lambda run: (run("list-text", "-list"), run("list", "-list", "-json"))),
    "scheme-destinations": (scheme_destinations, "P.xcodeproj", observe_scheme_destinations),
    "simulator-sdks": (simulator_sdks, "P.xcodeproj", observe_simulator_sdks),
    "symroot-targets": (symroot_targets, "P.xcodeproj", observe_symroot),
    "build-tool-plugin": (build_tool_plugin, "P.xcodeproj", observe_build_tool_plugin),
    "symroot-project-none": (lambda: symroot_project("None"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-custom": (lambda: symroot_project("Custom"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-default": (lambda: symroot_project("Default"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-macro": (lambda: symroot_project("Macro"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-empty": (lambda: symroot_project("Empty"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-maconly": (lambda: symroot_project("MacOnly"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-releaseonly": (lambda: symroot_project("ReleaseOnly"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-debugonly": (lambda: symroot_project("DebugOnly"), "P.xcodeproj", observe_symroot_project),
    "symroot-project-iosonly": (lambda: symroot_project("IOSOnly"), "P.xcodeproj", observe_symroot_project),
    "symroot-references-sub": (lambda: symroot_references("sub"), "Q.xcodeproj", observe_symroot_references),
    "symroot-references-top": (lambda: symroot_references("top"), "Q.xcodeproj", observe_symroot_references),
    "simulator-sdks-project": (lambda: simulator_sdks("iphonesimulator"), "P.xcodeproj", observe_simulator_sdks),
    "simulator-sdk-conditions": (simulator_sdk_conditions, "P.xcodeproj", observe_simulator_sdks),
    "simulator-sdk-conditions-project": (lambda: simulator_sdk_conditions({"SDKROOT": "iphoneos", '"SDKROOT[config=Debug]"': "iphonesimulator"}),
                                         "P.xcodeproj", observe_simulator_sdks),
    "simulator-sdk-conditions-project-reverse": (lambda: simulator_sdk_conditions({"SDKROOT": "iphonesimulator", '"SDKROOT[config=Debug]"': "iphoneos"}),
                                                 "P.xcodeproj", observe_simulator_sdks),
    "same-name-destinations": (same_name_destinations, "P.xcodeproj", observe_same_name_destinations),
    "declared-types": (declared_types, "P.xcodeproj", None),
    "regions-classic": (regions_classic, "P.xcodeproj", None),
    "declared-types-2": (declared_types_2, "P.xcodeproj", None),
    "declared-language": (declared_language, "P.xcodeproj", None),
    "regions-classic-2": (regions_classic_2, "P.xcodeproj", None),
    "regions-classic-3": (lambda: variant_groups_project(REGION_GROUPS_3, ("fr", "de"), "pt"), "P.xcodeproj", None),
    "regions-classic-4": (lambda: variant_groups_project(REGION_GROUPS_3, ()), "P.xcodeproj", None),
    "regions-classic-5": (lambda: variant_groups_project(REGION_GROUPS_3, ("fr", "en")), "P.xcodeproj", None),
    "variant-build-files": (variant_build_files, "P.xcodeproj", None),
    "regions-case": (lambda: variant_groups_project(REGION_CASE_GROUPS, ("en", "Base", "fr")), "P.xcodeproj", None),
    "regions-case-2": (lambda: variant_groups_project({"VA": ("A.strings", [("it", "it.lproj/A.strings")])}, ("en", "fr"), "EN"),
                       "P.xcodeproj", None),
    "regions-case-3": (lambda: variant_groups_project({"VA": ("A.strings", [("it", "it.lproj/A.strings")])}, ("DE", "fr"), "de"),
                       "P.xcodeproj", None),
    "declared-language-2": (declared_language_2, "P.xcodeproj", None),
    "lproj-groups": (lproj_groups, "P.xcodeproj", None),
    "declared-encodings": (declared_encodings, "P.xcodeproj", None),
    "regions-case-4": (lambda: variant_groups_project(REGION_CASE_GROUPS_4, ("en", "Base", "Fr")), "P.xcodeproj", None),
    "regions-case-5": (lambda: variant_groups_project(REGION_CASE_GROUPS_5, ("en", "Base")), "P.xcodeproj", None),
    "regions-case-6": (lambda: variant_groups_project(REGION_CASE_GROUPS_6, ("en", "Base")), "P.xcodeproj", None),
    "language-weights": (language_weights, "P.xcodeproj", None),
    "language-ties": (lambda: language_weights(LANGUAGE_TIE_TYPES, "sourcecode.ada", 1), "P.xcodeproj", None),
    "language-pool": (language_pool, "P.xcodeproj", None),
    "language-bisect": (lambda: language_pool(language_bisect_cases()), "P.xcodeproj", None),
    "language-types": (lambda: language_pool(language_type_cases()), "P.xcodeproj", None),
    "language-pairs": (lambda: language_pool(language_pair_cases()), "P.xcodeproj", None),
    "synchronized-phases": (synchronized_phases, "P.xcodeproj", None),
    "synchronized-phases-2": (lambda: synchronized_phases(headers=False), "P.xcodeproj", None),
    "synchronized-phases-all": (synchronized_phases_all, "P.xcodeproj", None),
    "autocreate-testables": (autocreate_testables, "P.xcodeproj", observe_autocreate_testables),
    "provisioning-auto": (provisioning_auto, "P.xcodeproj", None),
    "synchronized-exceptions": (synchronized_exceptions, "P.xcodeproj", None),
    "synchronized-exceptions-2": (synchronized_exceptions_2, "P.xcodeproj", None),
    "synchronized-phase-order": (synchronized_phase_order, "P.xcodeproj", None),
    "scheme-name-clashes": (scheme_name_clashes, "W.xcworkspace", observe_scheme_name_clashes),
    "synchronized-phase-order-2": (synchronized_phase_order_2, "P.xcodeproj", None),
    "autocreate-ui-targets": (autocreate_ui_targets, "P.xcodeproj", observe_test_hosts),
    "autocreate-auto-hosts": (autocreate_auto_hosts, "P.xcodeproj", observe_every_scheme),
    "synchronized-missing-order": (synchronized_missing_order, "P.xcodeproj", None),
    "test-host-clashes": (lambda: test_host_clashes(True, True), "W.xcworkspace", observe_test_host_clashes),
    "test-host-clashes-reversed": (lambda: test_host_clashes(True, False), "W.xcworkspace", observe_test_host_clashes),
    "test-host-clashes-project": (lambda: test_host_clashes(False, True), "P.xcodeproj", observe_test_host_clashes),
    "test-host-clashes-project-reversed": (lambda: test_host_clashes(False, False), "P.xcodeproj", observe_test_host_clashes),
    "autocreate-debug-both": (lambda: configuration_experiment(["Release", "Debug-Dev", "Debug"], "Release"), "P.xcodeproj",
                              observe_configurations),
    "autocreate-debug-upper": (lambda: configuration_experiment(["Release", "DEBUG", "Debugger"], "Release"), "P.xcodeproj",
                               observe_configurations),
    "autocreate-debug-dev": (lambda: configuration_experiment(["Adhoc", "Debug-Dev", "Production"], "Adhoc"), "P.xcodeproj",
                             observe_configurations),
    "autocreate-debug-lower": (lambda: configuration_experiment(["Release", "debug"], "Release"), "P.xcodeproj", observe_configurations),
    "autocreate-debug-suffix": (lambda: configuration_experiment(["Release", "MyDebug", "Debugging"], "Release"), "P.xcodeproj",
                                observe_configurations),
}
EXPERIMENTS.update({
    f"scheme-pairs-single-{name.replace(' ', '-').lower()}-{index}": (lambda name=name: scheme_pairs(names=[name]), "P.xcodeproj", observe_schemes_and([name]))
    for index, name in enumerate(SCHEME_PAIR_NAMES + SCHEME_PAIR_MANY_NAMES)
})
EXPERIMENTS.update({
    f"scheme-pairs-count-{count}": (lambda count=count: scheme_pairs(names=SCHEME_PAIR_MANY_NAMES[:count]), "P.xcodeproj",
                                    observe_schemes_and(SCHEME_PAIR_MANY_NAMES[:count]))
    for count in (8, 12, 16, 20, 24, 32)
})


def write_all(directory):
    """Writes every experiment's files under `directory/<name>`; returns {name: container path}."""
    containers = {}
    for name, (files, container, _, *prepare) in EXPERIMENTS.items():
        for path, text in files().items():
            target = Path(directory) / name / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        for step in prepare:
            step(Path(directory).resolve() / name)
        containers[name] = Path(directory) / name / container
    return containers


def folder_hash(path):
    """DerivedData's folder hash (Sources/NomacInspect/DerivedData.swift folderHash)."""
    digest = hashlib.md5(path.encode()).digest()

    def base26(chunk):
        value, letters = int.from_bytes(chunk, "big"), []
        for _ in range(14):
            letters.append(chr(97 + value % 26))
            value //= 26
        return "".join(reversed(letters))
    return base26(digest[:8]) + base26(digest[8:])


def remove_derived_data(directory):
    """Removes the DerivedData folders of the projects and workspaces under `directory`, which
    xcodebuild creates for them (named by a hash of the container's path in either form)."""
    root = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
    containers = [str(path) for pattern in ("*.xcodeproj", "*.xcworkspace") for path in directory.rglob(pattern)]
    hashes = {folder_hash(unicodedata.normalize(form, path)) for path in containers for form in ("NFC", "NFD")}
    for entry in root.iterdir() if root.exists() else []:
        if entry.is_dir() and entry.name.rsplit("-", 1)[-1] in hashes:
            shutil.rmtree(entry, ignore_errors=True)


def main():
    output = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or list(EXPERIMENTS)
    if not sys.argv[2:] and output.exists():
        shutil.rmtree(output)
    for name in selected:
        shutil.rmtree(output / name, ignore_errors=True)
    work = output / "work"
    shutil.rmtree(work, ignore_errors=True)
    containers = write_all(work)
    for name in selected:
        _, _, observe, *_ = EXPERIMENTS[name]
        container = containers[name]
        flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
        result = subprocess.run(["xcodebuild", flag, str(container), "-dumpPIF", str(output / f"{name}.pif")],
                                cwd=container.parent, capture_output=True, text=True)
        (output / f"{name}.dumpPIF.log").write_text(result.stdout[-4000:] + result.stderr[-4000:])
        print(f"{name}: dumpPIF exit {result.returncode}")

        def run(label, *arguments, name=name, container=container, flag=None, env=None):
            flag = flag or ("-workspace" if Path(container).suffix == ".xcworkspace" else "-project")
            argv = ["xcodebuild", flag, str(container), *arguments]
            completed = subprocess.run(argv, cwd=container.parent, capture_output=True, text=True, env={**os.environ, **env} if env else None)
            stem = output / name / re.sub(r"[^A-Za-z0-9_.-]", "_", label)
            stem.parent.mkdir(parents=True, exist_ok=True)
            Path(f"{stem}.stdout").write_text(completed.stdout)
            Path(f"{stem}.stderr").write_text(completed.stderr[-8000:])
            Path(f"{stem}.json").write_text(json.dumps({"argv": argv, "exitStatus": completed.returncode}, indent=2) + "\n")
            print(f"{name}: {label} exit {completed.returncode}")
            return completed

        run.container, run.output = container, output / name
        if observe:
            observe(run)
        remove_derived_data(work / name)
    shutil.rmtree(work)


if __name__ == "__main__":
    main()

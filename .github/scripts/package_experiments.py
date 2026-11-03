#!/usr/bin/env python3
"""Observe how Xcode evaluates package manifests and builds package projects in the PIF.

Runs on a macOS machine with Xcode installed (the `package-experiments` workflow). Everything
it builds is written here from scratch:

- conditions: one manifest whose product names record how compilation conditions (`os`,
  `arch`, `canImport`, ...) evaluate when Xcode's toolchain runs a manifest on this Mac,
  read back with `swift package dump-package`.
- deployment: a project with local packages that declare different iOS versions, or one
  version of another platform, with and without test targets; its PIF shows the deployment
  targets Xcode derives for the other platforms and for test products.
- order: the same project copied to two directories; the PIFs show whether the order of
  package projects in the workspace depends on the checkout path.

observations.json records the results. No Xcode output other than these PIFs and the
manifest dump is kept.

Usage: package_experiments.py <output-dir>
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

MODULES = [
    "AppKit", "Android", "Bionic", "CRT", "Combine", "CompilerPluginSupport", "CoreFoundation",
    "CryptoKit", "Darwin", "Dispatch", "Foundation", "FoundationEssentials",
    "FoundationInternationalization", "FoundationNetworking", "FoundationXML", "Glibc", "Musl",
    "Network", "ObjectiveC", "Observation", "PackageDescription", "RegexBuilder", "Security",
    "Swift", "SwiftUI", "Synchronization", "System", "Testing", "UIKit", "WASILibc", "WinSDK",
    "XCTest", "_Concurrency", "_StringProcessing", "os", "ucrt",
    "Compression", "Accelerate", "AVFoundation", "CommonCrypto", "CoreGraphics", "CoreImage", "CoreText", "Metal",
    "OSLog", "QuartzCore", "SystemConfiguration", "WatchKit", "zlib",
    # firebase-ios-sdk (nextcloud) adds its Gemini targets under canImport(FoundationModels).
    "FoundationModels", "ActivityKit", "AppIntents", "CoreLocation", "CoreML", "CoreServices", "Darwin.C", "ImageIO",
    "MobileCoreServices", "NaturalLanguage", "SQLite3", "StoreKit", "SwiftData", "UniformTypeIdentifiers",
    "UserNotifications", "Vision", "WebKit", "WidgetKit",
]

CONDITIONS = (
    [f"os({name})" for name in ["macOS", "OSX", "iOS", "tvOS", "watchOS", "visionOS", "Linux", "Windows", "Android", "FreeBSD", "WASI"]]
    + [f"arch({name})" for name in ["arm64", "x86_64", "arm64e", "arm", "i386", "wasm32"]]
    + [f"canImport({name})" for name in MODULES]
    + [f"targetEnvironment({name})" for name in ["simulator", "macCatalyst"]]
    + ["_endian(little)", "_endian(big)", "_pointerBitWidth(_64)", "_pointerBitWidth(_32)",
       "_runtime(_ObjC)", "_runtime(_Native)", "_hasAtomicBitWidth(_64)", "_hasAtomicBitWidth(_128)",
       "compiler(>=6.4)", "compiler(>=6.5)", "swift(>=6.0)", "DEBUG"]
)


def conditions_manifest():
    lines = ["// swift-tools-version: 6.0", "import PackageDescription", "", "var observed: [String] = []"]
    for index, condition in enumerate(CONDITIONS):
        lines += [f"#if {condition}", f'observed.append("{index}=1")', "#else", f'observed.append("{index}=0")', "#endif"]
    lines += [
        "",
        "let package = Package(",
        '    name: "Conditions",',
        '    products: observed.map { .library(name: "c" + $0, targets: ["Conditions"]) },',
        '    targets: [.target(name: "Conditions")]',
        ")",
    ]
    return "\n".join(lines) + "\n"


def observe_conditions(work):
    package = work / "conditions"
    (package / "Sources" / "Conditions").mkdir(parents=True)
    (package / "Package.swift").write_text(conditions_manifest())
    (package / "Sources" / "Conditions" / "Conditions.swift").write_text("public let conditions = 1\n")
    dump = subprocess.run(["xcrun", "swift", "package", "dump-package"], cwd=package, check=True, capture_output=True, text=True)
    products = [product["name"] for product in json.loads(dump.stdout)["products"]]
    values = dict(name[1:].split("=") for name in products)
    return {condition: values[str(index)] == "1" for index, condition in enumerate(CONDITIONS)}


# Local packages referenced with XCLocalSwiftPackageReference ("reference": Xcode treats
# them as dependencies) or as folders in the project's file tree ("folder": root packages,
# whose test targets become test products).
# name: (platforms expression, has test target, how the project references it)
PACKAGES = {
    "Ios12": (".iOS(.v12)", True, "reference"),
    "Ios16": (".iOS(.v16)", True, "reference"),
    "Ios174": ('.iOS("17.4")', True, "reference"),
    "Ios182": ('.iOS("18.2")', True, "reference"),
    "Ios26": ('.iOS("26.0")', True, "reference"),
    "Undeclared": (None, True, "reference"),
    "MacOnly": (".macOS(.v13)", True, "reference"),
    "IosAndWatch": ('.iOS(.v17), .watchOS(.v11)', False, "reference"),
    **{f"Ios{version.replace('.', '_')}": (f'.iOS("{version}")', False, "reference") for version in (
        [f"15.{minor}" for minor in range(9)] + [f"16.{minor}" for minor in range(8)]
        + [f"17.{minor}" for minor in range(8)] + [f"18.{minor}" for minor in range(8)]
        + [f"26.{minor}" for minor in range(8)] + [f"27.{minor}" for minor in range(5)]
        + ["17.4.1", "18.2.1", "26.0.1", "26.1.1"]
    ) if version not in ["17.4", "18.2"]},
    "RootIos12": (".iOS(.v12)", True, "folder"),
    "RootIos18": (".iOS(.v18)", True, "folder"),
    "RootMac": (".macOS(.v10_13)", True, "folder"),
    "RootTv": (".tvOS(.v12)", True, "folder"),
    "RootWatch": (".watchOS(.v4)", True, "folder"),
    "RootVision": (".visionOS(.v1)", True, "folder"),
    # Test-product floors where a platform's testing binaries disagree across slices (kickstarter:
    # Library declares watchOS 5 and its Library-Tests product gets watchOS 10.0; Xcode 27.0's
    # watchOS XCTest and Testing are arm64 26.0, arm64e 26.0, arm64_32 10.0).
    "RootWatch5": (".watchOS(.v5)", True, "folder"),
    "RootWatch9": (".watchOS(.v9)", True, "folder"),
    "RootWatch10_5": ('.watchOS("10.5")', True, "folder"),
    "RootWatch11": (".watchOS(.v11)", True, "folder"),
    "RootVision1_1": ('.visionOS("1.1")', True, "folder"),
    "RootTv15": (".tvOS(.v15)", True, "folder"),
    "RootIos15": (".iOS(.v15)", True, "folder"),
    "RootCatalyst13": (".macCatalyst(.v13)", True, "folder"),
    "RootMac12": (".macOS(.v12)", True, "folder"),
    "DepWatch5": (".watchOS(.v5)", True, "reference"),
}


def package_manifest(name, platforms, tests):
    targets = [f'.target(name: "{name}")']
    if tests:
        targets.append(f'.testTarget(name: "{name}Tests", dependencies: ["{name}"])')
    platform_line = f"    platforms: [{platforms}],\n" if platforms else ""
    return (
        "// swift-tools-version: 6.0\n"
        "import PackageDescription\n\n"
        "let package = Package(\n"
        f'    name: "{name}",\n'
        f"{platform_line}"
        f'    products: [.library(name: "{name}", targets: ["{name}"])],\n'
        f"    targets: [{', '.join(targets)}]\n"
        ")\n"
    )


def object_id(prefix, index):
    return f"{prefix}{index:023d}"


def project_file(names):
    folders = [n for n in names if PACKAGES[n][2] == "folder"]
    references = "".join(f"\t\t{object_id('D', i)} /* {n} */ = {{isa = XCLocalSwiftPackageReference; relativePath = Packages/{n}; }};\n" for i, n in enumerate(names, 1) if n not in folders)
    folder_files = "".join(f"\t\t{object_id('A', i)} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; name = {n}; path = Packages/{n}; sourceTree = \"<group>\"; }};\n" for i, n in enumerate(names, 1) if n in folders)
    folder_list = "".join(f"\t\t\t\t{object_id('A', i)} /* {n} */,\n" for i, n in enumerate(names, 1) if n in folders)
    products = "".join(f"\t\t{object_id('E', i)} /* {n} */ = {{isa = XCSwiftPackageProductDependency; productName = {n}; }};\n" for i, n in enumerate(names, 1))
    build_files = "".join(f"\t\t{object_id('9', i)} /* {n} in Frameworks */ = {{isa = PBXBuildFile; productRef = {object_id('E', i)} /* {n} */; }};\n" for i, n in enumerate(names, 1))
    framework_files = "".join(f"\t\t\t\t{object_id('9', i)} /* {n} in Frameworks */,\n" for i, n in enumerate(names, 1))
    reference_list = "".join(f"\t\t\t\t{object_id('D', i)} /* {n} */,\n" for i, n in enumerate(names, 1) if n not in folders)
    product_list = "".join(f"\t\t\t\t{object_id('E', i)} /* {n} */,\n" for i, n in enumerate(names, 1))
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
{build_files}/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{folder_files}		F00000000000000000000001 /* T.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = T.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		F00000000000000000000009 /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{framework_files}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{folder_list}				F00000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000003 /* Products */ = {{
			isa = PBXGroup;
			children = (
				F00000000000000000000001 /* T.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		C00000000000000000000001 /* T */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = F00000000000000000000010 /* Build configuration list for PBXNativeTarget "T" */;
			buildPhases = (
				F00000000000000000000004 /* Sources */,
				F00000000000000000000009 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = T;
			packageProductDependencies = (
{product_list}			);
			productName = T;
			productReference = F00000000000000000000001 /* T.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		F00000000000000000000006 /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
			}};
			buildConfigurationList = F00000000000000000000011 /* Build configuration list for PBXProject "P" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = F00000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
{reference_list}			);
			preferredProjectObjectVersion = 77;
			productRefGroup = F00000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				C00000000000000000000001 /* T */,
			);
		}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		F00000000000000000000007 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				SDKROOT = iphoneos;
			}};
			name = Debug;
		}};
		F00000000000000000000008 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				SDKROOT = iphoneos;
			}};
			name = Release;
		}};
		F00000000000000000000012 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = org.nomac.experiment;
				PRODUCT_NAME = "$(TARGET_NAME)";
			}};
			name = Debug;
		}};
		F00000000000000000000013 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = org.nomac.experiment;
				PRODUCT_NAME = "$(TARGET_NAME)";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		F00000000000000000000010 /* Build configuration list for PBXNativeTarget "T" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				F00000000000000000000012 /* Debug */,
				F00000000000000000000013 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		F00000000000000000000011 /* Build configuration list for PBXProject "P" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				F00000000000000000000007 /* Debug */,
				F00000000000000000000008 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
{references}/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
{products}/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = F00000000000000000000006 /* Project object */;
}}
"""


def write_project(directory):
    for name, (platforms, tests, _) in PACKAGES.items():
        package = directory / "Packages" / name
        (package / "Sources" / name).mkdir(parents=True)
        (package / "Package.swift").write_text(package_manifest(name, platforms, tests))
        (package / "Sources" / name / f"{name}.swift").write_text(f"public let {name.lower()} = 1\n")
        if tests:
            (package / "Tests" / f"{name}Tests").mkdir(parents=True)
            (package / "Tests" / f"{name}Tests" / f"{name}Tests.swift").write_text(f"import Testing\n@testable import {name}\n\n@Test func value() {{ #expect({name.lower()} == 1) }}\n")
    xcodeproj = directory / "P.xcodeproj"
    xcodeproj.mkdir(parents=True)
    (xcodeproj / "project.pbxproj").write_text(project_file(list(PACKAGES)))


def dump_pif(directory, output):
    pif = output.resolve()
    subprocess.run(
        ["xcodebuild", "-project", "P.xcodeproj", "-dumpPIF", str(pif)],
        cwd=directory, check=True, stdout=subprocess.DEVNULL,
    )
    return json.loads(pif.read_text())


def summarize(objects):
    by_signature = {o.get("signature"): o for o in objects}
    workspace = next(o["contents"] for o in objects if o["type"] == "workspace")
    projects = [by_signature[s]["contents"] for s in workspace["projects"]]
    packages = {}
    for project in projects:
        if project.get("projectIsPackage") != "true":
            continue
        entry = {"project": {}, "targets": {}}
        for config in project["buildConfigurations"]:
            settings = config["buildSettings"]
            entry["project"][config["name"]] = {k: v for k, v in settings.items() if k.endswith("DEPLOYMENT_TARGET")}
            entry["tags"] = settings.get("BUILD_SERVER_PROTOCOL_TARGET_TAGS")
        for signature in project["targets"]:
            target = by_signature[signature]["contents"]
            for config in target.get("buildConfigurations", []):
                settings = {k: v for k, v in config["buildSettings"].items() if k.endswith("DEPLOYMENT_TARGET")}
                if settings:
                    entry["targets"].setdefault(target["guid"], {})[config["name"]] = settings
        packages[project["guid"]] = entry
    return {
        "order": [p["guid"] for p in projects],
        "paths": [p.get("path") for p in projects],
        "packages": packages,
    }


def main():
    output = Path(sys.argv[1])
    if output.exists():
        shutil.rmtree(output)
    work = output / "work"
    work.mkdir(parents=True)
    observations = {"conditions": observe_conditions(work)}
    for location in ["first", "second-location"]:
        directory = work / location
        write_project(directory)
        observations[location] = summarize(dump_pif(directory, output / f"{location}.pif"))
    shutil.rmtree(work)
    (output / "observations.json").write_text(json.dumps(observations, indent=1, sort_keys=True) + "\n")
    print(json.dumps(observations["conditions"], indent=1))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""What Xcode 27.0 does with a file reference a build phase names and no group holds, as Expo config plugins write
them for the targets they add (the sweep's bluesky: `{isa = PBXFileReference; explicitFileType = undefined; path =
"Share-with-Bluesky/ShareViewController.swift"; sourceTree = "<group>"; }`). Each case is one self-written application
project that differs from `in-group` in one input. It records from `xcodebuild -dumpPIF` where the reference is and what
it says, and from an unsigned build for iphoneos whether the file was compiled or copied.

No Xcode output other than the PIFs of these self-written projects is kept.

Usage: orphan_reference_experiments.py <output-dir> [experiment ...]
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

REFERENCE = '{{isa = PBXFileReference; {extra}lastKnownFileType = {kind}; path = "{path}"; sourceTree = {tree}; }}'
# case: the reference's path, source tree and extra keys, whether a group holds it, the build phase, and the file's folder.
CASES = {
    "in-group": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=True),
    "orphan": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False),
    "orphan-explicit-undefined": dict(path="Sub/extra.swift", tree='"<group>"', extra="explicitFileType = undefined; includeInIndex = 0; ", grouped=False),
    "in-group-explicit-undefined": dict(path="Sub/extra.swift", tree='"<group>"', extra="explicitFileType = undefined; includeInIndex = 0; ", grouped=True),
    "orphan-source-root": dict(path="Sub/extra.swift", tree="SOURCE_ROOT", extra="", grouped=False),
    "orphan-project-folder": dict(path="extra.swift", tree='"<group>"', extra="", grouped=False, on_disk="extra.swift"),
    "orphan-resource": dict(path="Sub/extra.txt", tree='"<group>"', extra="", grouped=False, phase="resources", kind="text", on_disk="Sub/extra.txt"),
    "orphan-missing-file": dict(path="Sub/absent.swift", tree='"<group>"', extra="", grouped=False, on_disk="Sub/other.swift"),
    # Several orphans: the order of the group's children against the phases' order, the object IDs and the names.
    "two": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, second="A5", order="B3, B5"),
    "two-phase-reversed": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, second="A5", order="B5, B3"),
    "two-ids-swapped": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, second="A0", order="B3, B5"),
    "two-in-two-phases": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, second="A5", order="B3", resources="B5", second_kind="text", second_path="Sub/second.txt"),
    # What else recovers: what refers to the orphan, and a project of another name.
    "orphan-unused": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, order="", phase="none"),
    "orphan-product": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=True, product_orphan=True),
    "orphan-xcconfig": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=True, xcconfig_orphan=True),
    "orphan-other-project": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, project="Other"),
    "orphan-source-and-xcconfig": dict(path="Sub/extra.swift", tree='"<group>"', extra="", grouped=False, xcconfig_orphan=True),
}
PROJECT = """// !$*UTF8*$!
{{
archiveVersion = 1; classes = {{}}; objectVersion = 77;
objects = {{
A1 /* main */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; }};
A2 /* product */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = T.app; sourceTree = BUILT_PRODUCTS_DIR; }};
A3 /* extra */ = {reference};
A4 /* info */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
{second_objects}{xcconfig_objects}B1 = {{isa = PBXBuildFile; fileRef = A1; }};
B3 = {{isa = PBXBuildFile; fileRef = A3; }};
C1 = {{isa = PBXGroup; children = (A1, A4, {member} C2); sourceTree = "<group>"; }};
C2 = {{isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>"; }};
D1 = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (B1, {source_file}); runOnlyForDeploymentPostprocessing = 0; }};
D2 = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({resource_file}); runOnlyForDeploymentPostprocessing = 0; }};
E1 = {{isa = PBXNativeTarget; buildConfigurationList = F1; buildPhases = (D1, D2); buildRules = (); dependencies = (); name = T; productName = T; productReference = A2; productType = "com.apple.product-type.application"; }};
E2 = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700; }}; buildConfigurationList = F2; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en); mainGroup = C1; productRefGroup = C2; projectDirPath = ""; projectRoot = ""; targets = (E1); }};
F1 = {{isa = XCConfigurationList; buildConfigurations = (G1); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
F2 = {{isa = XCConfigurationList; buildConfigurations = (G2); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
G1 = {{isa = XCBuildConfiguration; {base_configuration}buildSettings = {{INFOPLIST_FILE = Info.plist; PRODUCT_BUNDLE_IDENTIFIER = dev.nomac.orphan; PRODUCT_NAME = T; SWIFT_VERSION = 5.0; }}; name = Release; }};
G2 = {{isa = XCBuildConfiguration; buildSettings = {{SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 15.0; }}; name = Release; }};
}};
rootObject = E2;
}}
"""
INFO = """<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>T</string>
<key>CFBundleIdentifier</key><string>dev.nomac.orphan</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
"""


def write_project(folder, case):
    phase = case.get("phase", "sources")
    on_disk = case.get("on_disk", case["path"])
    name = case.get("project", "T")
    second = case.get("second")
    second_path = case.get("second_path", "Sub/second.swift")
    second_objects = ""
    if second:
        second_objects = (f'{second} /* second */ = ' + REFERENCE.format(extra="", kind=case.get("second_kind", "sourcecode.swift"), path=second_path, tree='"<group>"').replace("{{", "{").replace("}}", "}") + ";\n"
                          + f"B5 = {{isa = PBXBuildFile; fileRef = {second}; }};\n")
    xcconfig_objects = ""
    if case.get("xcconfig_orphan"):
        xcconfig_objects = 'A6 /* config */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = base.xcconfig; sourceTree = "<group>"; };\n'
        (folder / "base.xcconfig").parent.mkdir(parents=True, exist_ok=True)
        (folder / "base.xcconfig").write_text("OTHER_SWIFT_FLAGS = -DORPHANCONFIG\n")
    (folder / f"{name}.xcodeproj").mkdir(parents=True)
    (folder / f"{name}.xcodeproj/project.pbxproj").write_text(PROJECT.format(
        reference=REFERENCE.format(extra=case["extra"], kind=case.get("kind", "sourcecode.swift"), path=case["path"], tree=case["tree"]),
        member="A3," if case["grouped"] else "", second_objects=second_objects, xcconfig_objects=xcconfig_objects,
        product="" if case.get("product_orphan") else "A2",
        base_configuration="baseConfigurationReference = A6; " if case.get("xcconfig_orphan") else "",
        source_file=case["order"] if "order" in case else ("B3" if phase == "sources" else ""),
        resource_file=case.get("resources", "B3" if phase == "resources" else "")))
    if second:
        (folder / second_path).parent.mkdir(parents=True, exist_ok=True)
        (folder / second_path).write_text("let second = 1\n" if second_path.endswith(".swift") else "text\n")
    (folder / "main.swift").write_text("print(1)\n")
    (folder / "Info.plist").write_text(INFO)
    target = folder / on_disk
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("let extra = 1\n" if on_disk.endswith(".swift") else "text\n")


def references(node, found, trail=""):
    if isinstance(node, dict):
        if node.get("type") == "file":
            found.append({"group": trail, "guid": node.get("guid"), "path": node.get("path"), "sourceTree": node.get("sourceTree"),
                          "fileType": node.get("fileType")})
        for child in node.get("children", []):
            references(child, found, f"{trail}/{node.get('name') or node.get('path') or ''}")


def observe(folder, tool):
    dumped = folder / "pif.json"
    project = next(folder.glob("*.xcodeproj")).name
    subprocess.run([*tool, "-project", project, "-dumpPIF", str(dumped)], cwd=folder, capture_output=True)
    observed = {}
    if dumped.exists():
        for entry in json.loads(dumped.read_text()):
            contents = entry.get("contents", {})
            if entry.get("type") == "project":
                found = []
                references(contents.get("groupTree"), found)
                observed["references"] = found
                observed["projectGUID"] = contents.get("guid")
                observed["recovered"] = [child["guid"].removeprefix(contents.get("guid", "")) for child in contents["groupTree"].get("children", [])
                                         if child.get("name") == "Recovered References"]
            if entry.get("type") == "target" and contents.get("name") == "T":
                observed["buildFiles"] = [{"phase": phase.get("type"), "fileReference": item.get("fileReference") or item.get("guid")}
                                          for phase in contents.get("buildPhases", []) for item in phase.get("buildFiles", [])]
    proc = subprocess.run([*tool, "-project", project, "-target", "T", "-configuration", "Release", "-sdk", "iphoneos",
                           "CODE_SIGNING_ALLOWED=NO", f"SYMROOT={folder}/build", f"OBJROOT={folder}/obj"], cwd=folder, capture_output=True, text=True)
    text = proc.stdout + proc.stderr
    observed["exit"] = proc.returncode
    observed["errors"] = sorted({line.strip()[:220] for line in text.splitlines() if "error:" in line and "note:" not in line})[:5]
    observed["compiled"] = sorted({word.rsplit("/", 1)[-1] for line in text.splitlines() if "swift-frontend" in line or line.startswith("SwiftCompile")
                                   for word in line.split() if word.endswith(".swift") and "extra" in word or word.endswith("/absent.swift")})
    observed["inProduct"] = sorted(p.name for p in (folder / "build/Release-iphoneos/T.app").glob("*")) if (folder / "build/Release-iphoneos/T.app").is_dir() else []
    return observed


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve()
    tool = sys.argv[3:] if sys.argv[2:3] == ["--tool"] else ["xcodebuild"]
    names = [name for name in (sys.argv[2:] if tool == ["xcodebuild"] else []) if name != "--tool"] or list(CASES)
    results = {}
    for name in names:
        folder = out / name
        shutil.rmtree(folder, ignore_errors=True)
        write_project(folder, CASES[name])
        results[name] = observe(folder, tool)
        shutil.rmtree(folder / "build", ignore_errors=True)
        shutil.rmtree(folder / "obj", ignore_errors=True)
    (out / "observations.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

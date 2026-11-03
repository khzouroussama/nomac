#!/usr/bin/env python3
"""What each corpus app's Linux build needs from tools nomac does not have yet.

For every app with a build entry in corpus/corpus.json, the targets its build scheme builds
(the blocks of the reference's `-showBuildSettings -scheme` capture) and the package targets
they depend on (the reference PIF), and in their build phases: storyboards (the launch screen
apart), xibs, the kinds of sets in asset catalogs, Core Data models, other compiled resource
types, and the closed Apple macros their Swift files use (macro_experiments.py's kinds).

Usage: linux_readiness.py <references-dir> <corpus-checkouts-dir> [--json <file>]

The references are capture_reference.py's (their PIF and settings); the checkouts are the
corpus apps at the paths the references recorded. Files outside the checkouts (package
checkouts not on this machine) are counted as unknown.
"""

import collections
import json
import os
import plistlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macro_experiments as macros  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
# The folder extensions of asset catalog entries (a folder with another dot in its name is not one).
ASSET_SETS = {"appiconset", "imageset", "colorset", "dataset", "symbolset", "launchimage", "spriteatlas", "sticker",
              "stickerpack", "stickersiconset", "stickersequence", "complicationset", "solidimagestack", "solidimagestacklayer",
              "imagestack", "imagestacklayer", "brandassets", "textureset", "cubetextureset", "mipmapset", "arresourcegroup",
              "arobject", "iconset", "appicon", "gcdashboardimage", "gcleaderboard", "gcleaderboardset"}
COMPILED = {
    "sourcecode.metal": "metal", "file.mlmodel": "coreml", "file.mlpackage": "coreml", "file.intentdefinition": "intents",
    "text.json.xcstrings": "xcstrings", "wrapper.scnassets": "scenekit", "file.scn": "scenekit", "file.sks": "spritekit",
    "folder.iconcomposer.icon": "icon-composer", "file.rcproject": "reality", "folder.skatlas": "sprite-atlas",
    "wrapper.xcdatamodeld": "coredata", "wrapper.xcdatamodel": "coredata", "wrapper.xcmappingmodel": "coredata",
}


def settings_blocks(path):
    """The blocks of an xcodebuild -showBuildSettings text capture: target name → settings."""
    blocks, current = {}, None
    for line in open(path, errors="replace"):
        match = re.match(r"Build settings for action \w+ and target (.+):$", line.rstrip("\n"))
        if match:
            current = blocks.setdefault(match.group(1).strip('"'), {})
        elif current is not None and line.startswith("    ") and " =" in line:
            key, _, value = line.strip().partition(" =")
            current[key] = value.strip()
    return blocks


def file_paths(project):
    """GUID → absolute path of every file reference in a PIF project's group tree."""
    paths = {}
    root = project["projectDirectory"]

    def walk(node, parent):
        tree, path = node.get("sourceTree", "<group>"), node.get("path", "")
        if tree == "<group>":
            base = os.path.join(parent, path) if parent is not None else None
        elif tree == "SOURCE_ROOT":
            base = os.path.join(root, path)
        elif tree == "<absolute>":
            base = path
        else:
            base = None
        if node["type"] in ("file", "folder"):
            paths[node["guid"]] = (base, node.get("fileType", ""))
        elif node["type"] == "variantGroup":
            for child in node.get("children", []):
                walk(child, parent)
            paths[node["guid"]] = (None, "variantGroup:" + ",".join(c["guid"] for c in node.get("children", [])))
        for child in node.get("children", []) if node["type"] == "group" else []:
            walk(child, base)
    walk(project["groupTree"], root)
    return paths


def survey(reference, app):
    build = app["build"]
    scheme = build["scheme"].replace(" ", "_")
    capture = reference / "settings" / f"scheme-{scheme}-{build.get('configuration', 'Release')}-iphoneos.txt"
    if not capture.exists():
        # Without a capture in the build's configuration, the scheme's in another one.
        captures = sorted((reference / "settings").glob(f"scheme-{scheme}-*-iphoneos.txt"))
        capture = captures[0] if captures else capture
    blocks = settings_blocks(capture) if capture.exists() else {}
    document = json.load(open(reference / "pif" / "workspace.pif"))
    projects = [o["contents"] for o in document if o["type"] == "project"]
    targets = {o["contents"]["guid"]: o["contents"] for o in document if o["type"] == "target"}
    guid_of_signature = {o["signature"]: o["contents"]["guid"] for o in document if o["type"] == "target"}
    paths = {}
    project_of = {}
    for project in projects:
        paths.update(file_paths(project))
        for signature in project["targets"]:
            project_of[guid_of_signature.get(signature)] = project
    # The scheme's targets, then everything they depend on: targets, package products, package targets.
    pending = [guid for guid, target in targets.items() if target["name"] in blocks
               and blocks[target["name"]].get("PROJECT_FILE_PATH", "").removesuffix("/project.pbxproj") == project_of.get(guid, {}).get("path")]
    graph = []
    while pending:
        guid = pending.pop()
        if guid in graph or guid not in targets:
            continue
        graph.append(guid)
        target = targets[guid]
        pending += [dependency["guid"] for dependency in target.get("dependencies", [])]
        for phase in target.get("buildPhases", []):
            pending += [b["targetReference"] for b in phase.get("buildFiles", []) if "targetReference" in b]
    result = collections.Counter()
    details = collections.defaultdict(set)
    swift_files = set()
    for guid in graph:
        target = targets[guid]
        kind = target.get("productTypeIdentifier", target.get("type", ""))
        if kind not in ("com.apple.product-type.application", "com.apple.product-type.framework", "packageProduct", ""):
            details["product types"].add(kind.removeprefix("com.apple.product-type."))
        references = [b["fileReference"] for phase in target.get("buildPhases", []) for b in phase.get("buildFiles", []) if "fileReference" in b]
        while references:
            reference_guid = references.pop()
            path, file_type = paths.get(reference_guid, (None, ""))
            if file_type.startswith("variantGroup:"):
                references += file_type.split(":", 1)[1].split(",")
                continue
            name = os.path.basename(path or "")
            if file_type == "file.storyboard":
                launch = re.search(r"launch", name, re.I) is not None
                result["launch storyboards" if launch else "storyboards"] += 1
            elif file_type == "file.xib":
                result["xibs"] += 1
            elif file_type == "folder.assetcatalog":
                if path and os.path.isdir(path):
                    for directory, subdirectories, _ in os.walk(path):
                        for sub in subdirectories:
                            if "." in sub and sub.rsplit(".", 1)[1] in ASSET_SETS:
                                details["asset sets"].add(sub.rsplit(".", 1)[1])
                else:
                    result["asset catalogs not on this machine"] += 1
            elif file_type in COMPILED:
                result[COMPILED[file_type]] += 1
            elif file_type == "sourcecode.swift" and path:
                swift_files.add(path)
    for path in swift_files:
        if os.path.isfile(path):
            found = macros.kinds_used(open(path, errors="replace").read())
            for kind in found:
                details["closed macros"].add(kind)
    # How the app gives its launch screen: a generated or written UILaunchScreen, or a storyboard.
    app_block = next((b for b in blocks.values() if b.get("WRAPPER_EXTENSION") == "app"), {})
    launch = "unknown"
    if app_block.get("INFOPLIST_KEY_UILaunchScreen_Generation") == "YES":
        launch = "UILaunchScreen (generated)"
    elif app_block.get("INFOPLIST_KEY_UILaunchStoryboardName"):
        launch = "storyboard " + app_block["INFOPLIST_KEY_UILaunchStoryboardName"]
    elif app_block.get("INFOPLIST_FILE"):
        plist = Path(app_block.get("SRCROOT", "")) / app_block["INFOPLIST_FILE"]
        if plist.is_file():
            try:
                values = plistlib.load(open(plist, "rb"))
                launch = "UILaunchScreen" if "UILaunchScreen" in values else ("storyboard " + values["UILaunchStoryboardName"]) if "UILaunchStoryboardName" in values else "none"
            except Exception:
                launch = "Info.plist with build-time variables"
    return {"app": app["id"], "targets": len(graph), "counts": dict(result), "launch": launch,
            **{key: sorted(value) for key, value in details.items()}}


def main():
    references, checkouts = Path(sys.argv[1]), Path(sys.argv[2])
    manifest = json.load(open(REPO_ROOT / "corpus" / "corpus.json"))
    rows = [survey(references / app["id"], app) for app in manifest["apps"] if app.get("build") and (references / app["id"] / "pif").is_dir()]
    for row in rows:
        print(json.dumps(row))
    if "--json" in sys.argv:
        json.dump(rows, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=2)


if __name__ == "__main__":
    main()

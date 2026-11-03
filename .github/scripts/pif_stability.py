#!/usr/bin/env python3
"""Measure how stable Xcode's PIF is for one corpus app.

Runs on a macOS machine with Xcode installed (the `pif-stability` workflow). The app is
cloned at its pinned commit, then `xcodebuild -dumpPIF` runs several times: twice at the
same path with Xcode's DerivedData for the app removed in between, once more without
removing it, and once on a copy of the checkout at a different path.

Each pair of dumps is compared on what nomac has to reproduce for synchronized folders
(docs/formats/pif.md, open questions):

  - whether the files are byte-identical;
  - whether every group-tree node keeps its GUID (nodes matched by path);
  - whether every build file keeps its GUID (matched by target, phase and file path);
  - whether every build phase lists its files in the same order.

The PIFs and summary.json are written to the output directory. Only output derived from the
corpus's own open-source apps is produced (docs/adr/0004-reference-artifacts.md).

Usage: pif_stability.py <app-id> <output-dir> [--work <dir>]
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "corpus" / "scripts"))
from capture_reference import clone, container_args, load_app, log, prepare, reference_environment, run


def dump(app, src, env, path):
    proc = run(["xcodebuild", "-dumpPIF", str(path)] + container_args(app, src), cwd=src, env=env)
    if proc.returncode != 0:
        log(proc.stderr.decode(errors="replace")[-2000:])
    return proc.returncode


def remove_derived_data(app, env):
    root = Path(env["HOME"]) / "Library/Developer/Xcode/DerivedData"
    stem = Path(app["container"]).stem
    for entry in root.glob(f"{stem}-*"):
        shutil.rmtree(entry, ignore_errors=True)


def describe(path, source_root):
    """Maps a PIF to path-keyed GUIDs and build-phase orders, relative to its checkout."""
    objects = json.loads(Path(path).read_text())
    nodes, phases, build_files = {}, {}, {}
    file_paths = {}

    def walk(node, prefix, project):
        for child in node.get("children", []) or []:
            relative = prefix + "/" + (child.get("path") or "") + "#" + child.get("name", "")
            nodes[(project, relative)] = child["guid"]
            file_paths[child["guid"]] = relative
            walk(child, prefix + "/" + (child.get("path") or ""), project)

    for obj in objects:
        if obj["type"] == "project":
            contents = obj["contents"]
            project = contents.get("path", "").replace(source_root, "<SOURCE_ROOT>")
            walk(contents["groupTree"], "", project)
    for obj in objects:
        if obj["type"] != "target":
            continue
        target = obj["contents"]
        for index, phase in enumerate(target.get("buildPhases", [])):
            key = f"{target['name']}#{index}#{phase['type']}"
            order = []
            for build_file in phase.get("buildFiles", []):
                reference = build_file.get("fileReference") or build_file.get("targetReference") or ""
                label = file_paths.get(reference, reference)
                order.append(label)
                build_files[(key, label)] = build_file["guid"]
            phases[key] = order
    return nodes, phases, build_files


def compare(a, b, a_root, b_root):
    nodes_a, phases_a, files_a = describe(a, a_root)
    nodes_b, phases_b, files_b = describe(b, b_root)
    changed_nodes = sorted(k[1] for k in nodes_a if k in nodes_b and nodes_a[k] != nodes_b[k])
    changed_files = sorted(f"{k[0]} {k[1]}" for k in files_a if k in files_b and files_a[k] != files_b[k])
    reordered = sorted(k for k in phases_a if k in phases_b and phases_a[k] != phases_b[k]
                       and sorted(phases_a[k]) == sorted(phases_b[k]))
    different_sets = sorted(k for k in phases_a if k in phases_b and sorted(phases_a[k]) != sorted(phases_b[k]))
    return {
        "identicalBytes": Path(a).read_bytes() == Path(b).read_bytes(),
        "nodes": len(nodes_a), "nodesWithNewGUID": len(changed_nodes), "nodeExamples": changed_nodes[:5],
        "buildFiles": len(files_a), "buildFilesWithNewGUID": len(changed_files), "buildFileExamples": changed_files[:5],
        "phases": len(phases_a), "phasesReordered": reordered,
        "phaseOrders": {k: [phases_a[k], phases_b[k]] for k in reordered[:3]},
        "phasesWithDifferentMembers": different_sets,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app_id")
    parser.add_argument("output")
    parser.add_argument("--work", default="/tmp/nomac-stability")
    args = parser.parse_args()

    _, app = load_app(args.app_id)
    out = Path(args.output).resolve() / app["id"]
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    src = clone(app, work)
    prepare(app, src, out / "prepare")
    developer_dir = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
    env = reference_environment(developer_dir)

    remove_derived_data(app, env)
    status = {"first": dump(app, src, env, out / "first.pif")}
    remove_derived_data(app, env)
    status["fresh"] = dump(app, src, env, out / "fresh.pif")
    status["warm"] = dump(app, src, env, out / "warm.pif")
    moved = work / (app["id"] + "-moved")
    if moved.exists():
        shutil.rmtree(moved)
    shutil.copytree(src, moved, symlinks=True)
    status["moved"] = dump(app, moved, env, out / "moved.pif")

    summary = {"app": app["id"], "commit": app["commit"], "exitStatus": status, "comparisons": {}}
    if all(code == 0 for code in status.values()):
        for name, (a, b, a_root, b_root) in {
            "first-fresh": ("first.pif", "fresh.pif", str(src), str(src)),
            "fresh-warm": ("fresh.pif", "warm.pif", str(src), str(src)),
            "first-moved": ("first.pif", "moved.pif", str(src), str(moved)),
        }.items():
            summary["comparisons"][name] = compare(out / a, out / b, a_root, b_root)
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

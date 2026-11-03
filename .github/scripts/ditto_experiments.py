#!/usr/bin/env python3
"""What `ditto <source> <destination>` does when it copies, on macOS and with nomac's ditto.

CocoaPods' "Copy generated compatibility header" phases call `ditto "<file>" "<file>"` twice per
Swift pod (expo-default: 48 calls), and Linux has no ditto. Each case builds a source tree in a
fresh folder, runs the copy, and records the destination tree: every entry's kind, mode,
modification time relative to its source's, contents and link target, and ditto's status and
output.

Usage:
  ditto_experiments.py <output.json> [ditto ...]     default: /usr/bin/ditto
  ditto_experiments.py compare <reference.json> <other.json>
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE_TIME = 1_700_000_000


def tree(spec, root):
    """Writes `spec` ({relative path: contents, or ("link", target), or ("dir",)}) under root."""
    for relative, value in spec.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if value == ("dir",):
            path.mkdir(exist_ok=True)
        elif isinstance(value, tuple):
            os.symlink(value[1], path)
        else:
            path.write_text(value)
            os.chmod(path, 0o640 if relative.endswith(".h") else 0o755 if relative.endswith(".sh") else 0o644)
    for path in sorted(root.rglob("*"), reverse=True):
        os.utime(path, (SOURCE_TIME, SOURCE_TIME), follow_symlinks=False)


CASES = {
    # (source tree, the source and destination arguments relative to the case folder, a tree
    # already at the destination)
    "file-to-new-path-in-new-folders": ({"src/A-Swift.h": "header\n"}, ["src/A-Swift.h", "out/x/y/A-Swift.h"], {}),
    "file-to-existing-file": ({"src/a.modulemap": "module A {}\n"}, ["src/a.modulemap", "out/a.modulemap"], {"out/a.modulemap": "old, longer contents\n"}),
    "file-to-existing-folder": ({"src/a.h": "a\n"}, ["src/a.h", "out"], {"out/keep.txt": "keep\n"}),
    "executable-file": ({"src/run.sh": "#!/bin/sh\n"}, ["src/run.sh", "out/run.sh"], {}),
    "folder-to-new-path": ({"src/d/a.h": "a\n", "src/d/sub/b.txt": "b\n", "src/d/link": ("link", "a.h"), "src/d/empty": ("dir",)},
                           ["src/d", "out/new"], {}),
    "folder-to-existing-folder": ({"src/d/a.h": "new a\n", "src/d/c.txt": "c\n"}, ["src/d", "out/d"],
                                  {"out/d/a.h": "old a\n", "out/d/b.txt": "b\n"}),
    "link-source": ({"src/real.h": "r\n", "src/alias.h": ("link", "real.h")}, ["src/alias.h", "out/alias.h"], {}),
}


def snapshot(root):
    entries = {}
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        info = os.lstat(path)
        if path.is_symlink():
            entries[relative] = {"kind": "link", "target": os.readlink(path)}
        elif path.is_dir():
            entries[relative] = {"kind": "dir", "mode": oct(info.st_mode & 0o7777)}
        else:
            entries[relative] = {"kind": "file", "mode": oct(info.st_mode & 0o7777), "contents": path.read_text(),
                                 "sourceTime": int(info.st_mtime) == SOURCE_TIME}
    return entries


def run(ditto):
    results = {}
    for name, (source, arguments, existing) in CASES.items():
        with tempfile.TemporaryDirectory() as folder:
            case = Path(folder)
            tree(source, case)
            if existing:
                tree(existing, case)
                for path in (case / "out").rglob("*"):
                    os.utime(path, (SOURCE_TIME + 100, SOURCE_TIME + 100), follow_symlinks=False)
            proc = subprocess.run(ditto + arguments, cwd=case, capture_output=True, text=True, env={"PATH": "/usr/bin:/bin"})
            out = case / "out"
            results[name] = {"status": proc.returncode, "stdout": proc.stdout, "stderr": bool(proc.stderr),
                             "out": snapshot(out) if out.exists() else None}
    return results


def main():
    if sys.argv[1] == "compare":
        reference, other = (json.load(open(path)) for path in sys.argv[2:4])
        same = [name for name in reference["results"] if reference["results"][name] == other["results"].get(name)]
        print(f"{other['ditto']}: {len(same)}/{len(reference['results'])} like {reference['ditto']}")
        for name in reference["results"]:
            if name not in same:
                print(f"    {name}: {json.dumps(reference['results'][name])}\n    {' ' * len(name)}  {json.dumps(other['results'].get(name))}")
        return
    ditto = sys.argv[2:] or ["/usr/bin/ditto"]
    Path(sys.argv[1]).write_text(json.dumps({"ditto": " ".join(ditto), "results": run(ditto)}, indent=2) + "\n")


if __name__ == "__main__":
    main()

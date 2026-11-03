#!/usr/bin/env python3
"""Static libraries from another `libtool` than Xcode's, against Xcode 27.0's.

Xcode's `libtool` (`cctools_ld-27037.1`) is not open source, and Linux has none, so every static
library target (every CocoaPods pod by default) fails there. This replays the `Libtool` tasks of a
build log (`libtool -static -arch_only <arch> -D -syslibroot <sdk> -L<dir> -filelist <list>
-dependency_info <file> -o <archive>`) with another libtool, on the same objects, and compares each
archive with the one Xcode's libtool wrote, byte for byte, and the dependency info.

Usage:
  libtool_experiments.py commands <build.log> <commands.json>     the Libtool tasks of a build log
  libtool_experiments.py run <commands.json> <libtool> <out-dir>  replay them, compare, write summary.json
"""

import json
import shlex
import subprocess
import sys
from pathlib import Path


def commands(log_path):
    found = []
    for block in Path(log_path).read_text(errors="replace").split("\n\n"):
        if not block.startswith("Libtool "):
            continue
        line = next((line.strip() for line in block.splitlines() if "/libtool " in line), None)
        if line:
            argv = shlex.split(line)
            found.append({"archive": argv[argv.index("-o") + 1], "argv": argv})
    return found


def replay(entries, libtool, out):
    out.mkdir(parents=True, exist_ok=True)
    summary = {"libtool": libtool, "identical": 0, "different": [], "failed": [], "dependencyInfo": {"identical": 0, "different": 0}}
    for entry in entries:
        argv = list(entry["argv"])
        argv[0] = libtool
        name = Path(entry["archive"]).name
        argv[argv.index("-o") + 1] = str(out / name)
        reference_info = argv[argv.index("-dependency_info") + 1] if "-dependency_info" in argv else None
        if reference_info:
            argv[argv.index("-dependency_info") + 1] = str(out / (name + ".dependency_info"))
        proc = subprocess.run(argv, capture_output=True, text=True)
        if proc.returncode != 0:
            summary["failed"].append({"archive": name, "status": proc.returncode, "stderr": proc.stderr[-400:]})
            continue
        if (out / name).read_bytes() == Path(entry["archive"]).read_bytes():
            summary["identical"] += 1
        else:
            summary["different"].append(name)
        if reference_info and Path(reference_info).exists():
            same = (out / (name + ".dependency_info")).read_bytes() == Path(reference_info).read_bytes()
            summary["dependencyInfo"]["identical" if same else "different"] += 1
    return summary


def main():
    if sys.argv[1] == "commands":
        Path(sys.argv[3]).write_text(json.dumps(commands(sys.argv[2]), indent=2) + "\n")
    elif sys.argv[1] == "run":
        out = Path(sys.argv[4])
        summary = replay(json.loads(Path(sys.argv[2]).read_text()), sys.argv[3], out)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{summary['identical']} identical, {len(summary['different'])} different, {len(summary['failed'])} failed; "
              f"dependency info {summary['dependencyInfo']}")


if __name__ == "__main__":
    main()

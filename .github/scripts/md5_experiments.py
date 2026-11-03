#!/usr/bin/env python3
"""Another md5 against macOS's BSD `md5` (`/sbin/md5`), on the forms build scripts use.

Bugsnag's React Native instructions name a source map after the build folder with
`$(md5 -qs "$CONFIGURATION_BUILD_DIR")`; the RN sweep's Linux images have no `md5` (bluewallet,
rocketchat), and the scripts then write `$TMPDIR/-main.jsbundle.map`. This records what macOS's
`md5` prints and returns for strings, files, standard input and its errors.

Usage:
  md5_experiments.py capture <out>            Mac: record /sbin/md5's
  md5_experiments.py run <out> <command ...>  run the cases with <command>, compare; writes <out>/results.json
Each case runs in <out>/inputs with a.txt on standard input.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

CASES = [
    ["-qs", "/work/dd/app/Build/Products/Release-iphoneos"],
    ["-s", "abc"],
    ["-qs", ""],
    ["-r", "-s", "abc"],
    ["-s", "abc", "-s", "def"],
    ["-s", "abc", "a.txt"],
    ["a.txt"],
    ["-q", "a.txt"],
    ["-r", "a.txt"],
    ["-rq", "a.txt"],
    ["a.txt", "empty", "binary"],
    ["missing"],
    ["-q", "missing", "a.txt"],
    ["folder"],
    ["--", "-q"],
    [],
    ["-q"],
    ["-r"],
    ["-n", "a.txt"],
    ["-s"],
]


def run_cases(command, inputs):
    found = {}
    for arguments in CASES:
        with open(inputs / "a.txt", "rb") as stdin:
            proc = subprocess.run(command + arguments, stdin=stdin, capture_output=True, cwd=inputs)
        name = os.path.basename(command[-1]) if command[-1] == "/sbin/md5" else "md5"
        stderr = proc.stderr.decode().replace(name + ":", "md5:")
        found[" ".join(arguments) or "(stdin)"] = {"status": proc.returncode, "stdout": proc.stdout.decode(), "stderr": stderr}
    return found


def main():
    out = Path(sys.argv[2]).resolve()
    inputs = out / "inputs"
    if sys.argv[1] == "capture":
        inputs.mkdir(parents=True, exist_ok=True)
        (inputs / "a.txt").write_text("hello\n")
        (inputs / "empty").write_bytes(b"")
        (inputs / "binary").write_bytes(bytes(range(256)) * 300)
        (inputs / "folder").mkdir(exist_ok=True)
        (out / "macos.json").write_text(json.dumps(run_cases(["/sbin/md5"], inputs), indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = run_cases(sys.argv[3:], inputs)
    same = [case for case in expected if found.get(case) == expected[case]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(expected)} cases like macOS's md5")
    for case in expected:
        if case not in same:
            print(f"    {case}: {expected[case]} vs {found.get(case)}")


if __name__ == "__main__":
    main()

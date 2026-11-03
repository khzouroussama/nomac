#!/usr/bin/env python3
"""What Xcode's xcrun prints, finds and passes to the tools it runs, as script phases call it.

The corpus's script phases run `xcrun --sdk macosx swift <script> <arguments>` (swiftfin) and
`xcrun -sdk macosx swift <script> ...` (netnewswire); the cases below also cover the queries such
scripts make. Each runs with a fixed environment (PATH, HOME and DEVELOPER_DIR, and SDKROOT where
named), and records the exit status, standard output and standard error; the `env` cases record the
variables xcrun adds or changes for the tool.

Usage: xcrun_experiments.py <output-dir>     on a Mac; DEVELOPER_DIR selects the Xcode
"""

import json
import os
import subprocess
import sys
from pathlib import Path

SCRIPT = """import Foundation
print(CommandLine.arguments.dropFirst().joined(separator: " "))
print("SDKROOT=" + (ProcessInfo.processInfo.environment["SDKROOT"] ?? "(unset)"))
"""


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    (out / "script.swift").write_text(SCRIPT)
    developer = os.environ["DEVELOPER_DIR"]
    base = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "DEVELOPER_DIR": developer}
    iphoneos = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], env=base, capture_output=True, text=True).stdout.strip()
    cases = {
        "find-swift": ([], ["--find", "swift"]),
        "f-swift": ([], ["-f", "swift"]),
        "find-swift-iphoneos": ([], ["--sdk", "iphoneos", "--find", "swift"]),
        "find-clang-iphoneos": ([], ["--sdk", "iphoneos", "--find", "clang"]),
        "find-ld": ([], ["--find", "ld"]),
        "find-actool": ([], ["--find", "actool"]),
        "find-xcodebuild": ([], ["--find", "xcodebuild"]),
        "find-missing": ([], ["--find", "nomac-no-such-tool"]),
        "sdk-path": ([], ["--show-sdk-path"]),
        "sdk-path-iphoneos": ([], ["--sdk", "iphoneos", "--show-sdk-path"]),
        "sdk-path-single-dash": ([], ["-sdk", "iphoneos", "--show-sdk-path"]),
        "sdk-path-versioned": ([], ["--sdk", "iphoneos27.0", "--show-sdk-path"]),
        "sdk-path-from-sdkroot": ([("SDKROOT", iphoneos)], ["--show-sdk-path"]),
        "sdk-path-from-sdkroot-name": ([("SDKROOT", "iphoneos")], ["--show-sdk-path"]),
        "sdk-version-iphoneos": ([], ["--sdk", "iphoneos", "--show-sdk-version"]),
        "sdk-build-version-iphoneos": ([], ["--sdk", "iphoneos", "--show-sdk-build-version"]),
        "sdk-platform-path-iphoneos": ([], ["--sdk", "iphoneos", "--show-sdk-platform-path"]),
        "sdk-platform-version-iphoneos": ([], ["--sdk", "iphoneos", "--show-sdk-platform-version"]),
        "sdk-missing": ([], ["--sdk", "nomacos", "--show-sdk-path"]),
        "unknown-option": ([], ["--nomac-unknown"]),
        "env": ([], ["env"]),
        "env-macosx": ([], ["--sdk", "macosx", "env"]),
        "env-macosx-over-sdkroot": ([("SDKROOT", iphoneos)], ["--sdk", "macosx", "env"]),
        "env-over-sdkroot": ([("SDKROOT", iphoneos)], ["env"]),
        "run-script": ([("SDKROOT", iphoneos)], ["--sdk", "macosx", "swift", str(out / "script.swift"), "a", "b c"]),
        "run-script-single-dash": ([("SDKROOT", iphoneos)], ["-sdk", "macosx", "swift", str(out / "script.swift"), "--xcode", "x"]),
    }
    record = {}
    for name, (extra, arguments) in cases.items():
        environment = dict(base, **dict(extra))
        proc = subprocess.run(["xcrun"] + arguments, env=environment, capture_output=True, text=True, cwd=out)
        stdout = proc.stdout
        if name.startswith("env"):
            lines = [line for line in stdout.splitlines() if "=" in line]
            seen = dict(line.split("=", 1) for line in lines)
            stdout = {key: value for key, value in sorted(seen.items()) if environment.get(key) != value}
        record[name] = {"arguments": arguments, "environment": dict(extra), "exit": proc.returncode, "stdout": stdout, "stderr": proc.stderr}
    (out / "xcrun.json").write_text(json.dumps(record, indent=1) + "\n")
    for name, value in record.items():
        print(f"{name}: exit {value['exit']} stdout {json.dumps(value['stdout'])[:300]} stderr {value['stderr'].strip()[:200]!r}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]).resolve())

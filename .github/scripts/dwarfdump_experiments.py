#!/usr/bin/env python3
"""Another `dwarfdump --uuid` against macOS's (`/usr/bin/dwarfdump`, Xcode's), on the files build
scripts ask it about.

expo-modules-autolinking's `resolve-dsym-sourcemaps.js` names each `DBGSourcePathRemapping` plist it
writes into a prebuilt framework's dSYM (`Contents/Resources/<UUID>.plist`, Debug builds) after the
UUIDs `dwarfdump --uuid <dSYM>` prints; the Linux toolchain has no dwarfdump, and the script then
skips them (expo-default's Debug archive). This builds Mach-O files and dSYMs with Xcode's tools and
records what macOS's `dwarfdump --uuid` prints and returns for them and for files it refuses.

Usage:
  dwarfdump_experiments.py inputs <out>              Mac: build the inputs, run /usr/bin/dwarfdump
  dwarfdump_experiments.py run <out> <command ...>   run the cases with <command>, compare; writes <out>/results.json
Each case runs in <out>/inputs; a case's absolute paths are written relative to <out>.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

SOURCE = "int counter = 2;\nint visible(int x) { return x + counter; }\n"


def build(inputs):
    sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    sim = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    (inputs / "c.c").write_text(SOURCE)
    run = lambda argv: subprocess.run(argv, cwd=inputs, check=True, capture_output=True)
    run(["xcrun", "clang", "-target", "arm64-apple-ios15.1", "-isysroot", sdk, "-g", "-dynamiclib", "c.c", "-o", "dylib"])
    run(["xcrun", "clang", "-target", "x86_64-apple-ios15.1-simulator", "-isysroot", sim, "-g", "-dynamiclib", "c.c", "-o", "dylib-x86_64"])
    run(["xcrun", "lipo", "-create", "dylib", "dylib-x86_64", "-output", "universal-dylib"])
    run(["xcrun", "clang", "-target", "arm64-apple-ios15.1", "-isysroot", sdk, "-c", "c.c", "-o", "object.o"])
    run(["xcrun", "libtool", "-static", "object.o", "-o", "static.a"])
    run(["xcrun", "dsymutil", "dylib", "-o", "dylib.dSYM"])
    run(["xcrun", "dsymutil", "universal-dylib", "-o", "universal.dSYM"])
    (inputs / "text.txt").write_text("hello\n")
    (inputs / "empty").write_bytes(b"")
    os.mkdir(inputs / "folder")
    (inputs / "c.c").unlink()
    (inputs / "dylib-x86_64").unlink()


def cases(inputs):
    return [["--uuid", name] for name in sorted(p.name for p in inputs.iterdir())] + [
        ["--uuid", "missing"],
        ["--uuid", str(inputs / "dylib.dSYM")],
        ["--uuid", "dylib", "universal.dSYM"],
        ["-uuid", "dylib"],
    ]


def run_cases(command, out):
    inputs = out / "inputs"
    found = {}
    for arguments in cases(inputs):
        proc = subprocess.run(command + arguments, capture_output=True, text=True, cwd=inputs)
        normal = lambda text: text.replace(str(out), "<out>")
        found[normal(" ".join(arguments))] = {"status": proc.returncode, "stdout": normal(proc.stdout), "stderr": normal(proc.stderr)}
    return found


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "inputs":
        (out / "inputs").mkdir(parents=True, exist_ok=True)
        build(out / "inputs")
        (out / "macos.json").write_text(json.dumps(run_cases(["/usr/bin/dwarfdump"], out), indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = run_cases(sys.argv[3:], out)
    same = [case for case in expected if found.get(case) == expected[case]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(expected)} cases like macOS's dwarfdump --uuid")
    for case in expected:
        if case not in same:
            print(f"    {case}: {expected[case]} vs {found.get(case)}")


if __name__ == "__main__":
    main()

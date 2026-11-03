#!/usr/bin/env python3
"""Another `file` against macOS's, on the files build scripts ask it about.

CocoaPods' frameworks script asks `file` about each framework binary it embeds (`*"dynamically
linked shared library"*`: strip its architectures) and each dSYM (`*"Mach-O "*"dSYM companion"*`:
strip and copy it); the RN sweep's Linux images have no `file` (246 calls in 11 apps), and the
script then skips both silently. This builds Mach-O files of each kind with Xcode's tools and
records what macOS's `file` prints for them and for a few other files.

Usage:
  file_experiments.py inputs <out>              Mac: build the inputs, run /usr/bin/file
  file_experiments.py run <out> <command ...>   run the cases with <command>, compare; writes <out>/results.json
Each case runs in <out>/inputs: each file alone, a missing file, `-b`, and several files at once.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SOURCE = "int counter = 2;\nint visible(int x) { return x + counter; }\n"
MAIN = "int main(void) { return 0; }\n"


def build(inputs):
    sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    sim = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    (inputs / "c.c").write_text(SOURCE)
    (inputs / "main.c").write_text(MAIN)
    device = ["xcrun", "--sdk", "iphoneos", "clang", "-target", "arm64-apple-ios15.1", "-isysroot", sdk]
    simulator = ["xcrun", "--sdk", "iphonesimulator", "clang", "-target", "x86_64-apple-ios15.1-simulator", "-isysroot", sim]
    run = lambda argv: subprocess.run(argv, cwd=inputs, check=True)
    run(device + ["-g", "-dynamiclib", "c.c", "-install_name", "@rpath/Lib.framework/Lib", "-o", "dylib"])
    run(simulator + ["-dynamiclib", "c.c", "-o", "dylib-x86_64"])
    run(["xcrun", "lipo", "-create", "dylib", "dylib-x86_64", "-output", "universal-dylib"])
    run(device + ["main.c", "-o", "executable"])
    run(device + ["-bundle", "c.c", "-o", "bundle"])
    run(device + ["-c", "c.c", "-o", "object.o"])
    run(["xcrun", "libtool", "-static", "object.o", "-o", "static.a"])
    run(["ar", "rcS", "plain.a", "object.o"])
    run(device[:-4] + ["-target", "arm64e-apple-ios15.1", "-isysroot", sdk, "-dynamiclib", "c.c", "-o", "dylib-arm64e"])
    watch = subprocess.run(["xcrun", "--sdk", "watchos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    run(["xcrun", "--sdk", "watchos", "clang", "-target", "arm64_32-apple-watchos9.0", "-isysroot", watch, "-dynamiclib", "c.c", "-o", "dylib-arm64_32"])
    run(["xcrun", "dsymutil", "dylib", "-o", "dylib.dSYM"])
    shutil.copy(inputs / "dylib.dSYM/Contents/Resources/DWARF/dylib", inputs / "dsym-companion")
    shutil.rmtree(inputs / "dylib.dSYM")
    (inputs / "text.txt").write_text("hello\n")
    (inputs / "script.sh").write_text("#!/bin/sh\necho hi\n")
    (inputs / "empty").write_bytes(b"")
    os.mkdir(inputs / "folder")
    os.symlink("dylib", inputs / "link")
    (inputs / "c.c").unlink()
    (inputs / "main.c").unlink()


def cases(inputs):
    return [[path.name] for path in sorted(inputs.iterdir())] + [
        ["missing"],
        ["-b", "universal-dylib", "dylib"],
        ["universal-dylib", "empty", "object.o", "missing"],
    ]


def run_cases(command, inputs):
    found = {}
    for arguments in cases(inputs):
        proc = subprocess.run(command + arguments, capture_output=True, text=True, cwd=inputs)
        found[" ".join(arguments)] = {"status": proc.returncode, "stdout": proc.stdout}
    return found


def main():
    out = Path(sys.argv[2]).resolve()
    inputs = out / "inputs"
    if sys.argv[1] == "inputs":
        inputs.mkdir(parents=True, exist_ok=True)
        build(inputs)
        (out / "macos.json").write_text(json.dumps(run_cases(["/usr/bin/file"], inputs), indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = run_cases(sys.argv[3:], inputs)
    same = [name for name in expected if found.get(name) == expected[name]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(expected)} cases described like macOS's file")
    for name in expected:
        if name not in same:
            print(f"    {name}: {expected[name]['stdout'].strip()!r} vs {found.get(name, {}).get('stdout', '').strip()!r}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Another Mach-O `strip` against Xcode 27.0's, on self-written binaries Xcode's tools link.

Swift Build's Strip task runs `strip -D <style> [-T] <binary>` (`STRIP_DETERMINISTIC_MODE`,
`STRIP_STYLE`, `STRIP_SWIFT_SYMBOLS`: SWBUniversalPlatform's StripSymbols.xcspec and
SWBApplePlatform's StripSymbolsDarwin.xcspec). The swift.org toolchain has no Mach-O strip, so
on Linux Swift Build ran GNU strip (expo-default's nested build of ExpoModulesJSI, B-186).

Usage:
  strip_experiments.py inputs <out>        Mac: build the inputs with Xcode's tools (DEVELOPER_DIR)
                                           and strip copies with Xcode's strip
  strip_experiments.py run <out> <strip>   strip copies of the inputs with <strip>, its directory
                                           first on PATH as in Swift Build's tasks, and compare
                                           each with Xcode's; writes <out>/<strip name>.json

The inputs include the C dylib signed ad hoc: Xcode's strip never signs, and leaves a signature
it invalidates in place with a warning.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CASES = {
    "debugging": ["-D", "-S"],
    "debugging-swift": ["-D", "-S", "-T"],
    "non-global": ["-D", "-x"],
    "non-global-swift": ["-D", "-x", "-T"],
    "all": ["-D"],
}

SOURCES = {
    "c.c": "static int hidden(int x) { return x * 3; }\nint counter = 2;\nint visible(int x) { return hidden(x) + counter; }\n",
    "s.swift": "public final class Box { public var value = 1; public init() {} }\n"
               "func helper(_ x: Int) -> Int { x &* 7 }\nprivate func secret() -> Int { 5 }\n"
               "public func api(_ x: Int) -> Int { helper(x) &+ secret() &+ Box().value }\n",
    "main.swift": "struct Point { var x = 1, y = 2 }\nfunc sum(_ p: Point) -> Int { p.x + p.y }\nprint(sum(Point()))\n",
    # An executable that exports more than its header: global functions and data, an Objective-C
    # class, and C++ weak definitions (a template's static, its guard variable), as rn-bare's does.
    "exports.mm": "#import <Foundation/Foundation.h>\n@interface Exported : NSObject\n@end\n@implementation Exported\n@end\n"
                  "int exportedCounter = 3;\nint exportedFunction(int x) { return x + exportedCounter; }\n"
                  "template <typename T> struct Holder { static T &shared() { static T value{}; return value; } };\n"
                  "int main(int argc, char **argv) { Holder<int>::shared() += argc; return exportedFunction(Holder<int>::shared())"
                  " + (int)[[Exported new] hash]; }\n",
}


def inputs(out):
    source = out / "src"
    source.mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (source / name).write_text(text)
    binaries = out / "inputs"
    binaries.mkdir(exist_ok=True)
    target = ["-target", "arm64-apple-ios15.1"]
    sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    builds = {
        "libc.dylib": ["xcrun", "--sdk", "iphoneos", "clang"] + target + ["-isysroot", sdk, "-g", "-O1", "-dynamiclib", str(source / "c.c"), "-o"],
        "libs.dylib": ["xcrun", "swiftc"] + target + ["-sdk", sdk, "-g", "-O", "-emit-library", "-module-name", "S", str(source / "s.swift"), "-o"],
        "app": ["xcrun", "swiftc"] + target + ["-sdk", sdk, "-g", "-O", "-module-name", "App", str(source / "main.swift"), "-o"],
        "exports": ["xcrun", "--sdk", "iphoneos", "clang++"] + target + ["-isysroot", sdk, "-g", "-Os", "-fobjc-arc", "-framework", "Foundation",
                                                                        str(source / "exports.mm"), "-o"],
    }
    for name, command in builds.items():
        subprocess.run(command + [str(binaries / name)], cwd=out, check=True)
    # Signed ad hoc, as a binary strip sees after an earlier signature.
    shutil.copy(binaries / "libc.dylib", binaries / "libc-signed.dylib")
    subprocess.run(["xcrun", "codesign", "--sign", "-", "--force", str(binaries / "libc-signed.dylib")], check=True)
    for case, flags in CASES.items():
        for binary in sorted(path for path in binaries.iterdir() if path.is_file()):
            stripped = out / "xcode" / case / binary.name
            stripped.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(binary, stripped)
            # Xcode's strip refuses "all" on the Swift dylib; run() then expects the same refusal.
            if subprocess.run(["xcrun", "strip"] + flags + [str(stripped)]).returncode != 0:
                stripped.unlink()


def run(out, strip):
    results = {"strip": strip, "identical": 0, "different": [], "failed": []}
    work = out / "work"
    # Swift Build's tasks find the toolchain's tools first on PATH, nomac's codesign among them.
    environment = {**os.environ, "PATH": str(Path(strip).parent) + os.pathsep + os.environ.get("PATH", "")}
    for case, flags in CASES.items():
        for binary in sorted(path for path in (out / "inputs").iterdir() if path.is_file()):
            stripped = work / case / binary.name
            stripped.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(binary, stripped)
            proc = subprocess.run([strip] + flags + [str(stripped)], capture_output=True, text=True, env=environment)
            if proc.returncode != 0:
                results["failed"].append(f"{case}/{binary.name}: {proc.stderr.strip()[:200]}")
            elif stripped.read_bytes() == (out / "xcode" / case / binary.name).read_bytes():
                results["identical"] += 1
            else:
                results["different"].append(f"{case}/{binary.name}")
    (out / f"{Path(strip).name}.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"{results['identical']} identical, {len(results['different'])} different, {len(results['failed'])} failed")
    for line in results["different"][:10] + results["failed"][:5]:
        print("    " + line)


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "inputs":
        inputs(out)
    else:
        run(out, sys.argv[3])


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Another `lipo` against Xcode 27.0's, on self-written binaries Xcode's tools build.

Scripts that build phases run call `lipo` from the toolchain's `usr/bin`, which Xcode puts first
on their PATH: CocoaPods' frameworks script reads each embedded framework's architectures with
`lipo -info` and removes the ones the build does not ask for with `lipo -remove` (rn-bare's
`[CP] Embed Pods Frameworks` in an archive build: "lipo: command not found" on Linux). Swift
Build itself makes universal binaries with `lipo -create`.

Usage:
  lipo_experiments.py inputs <out>        Mac: build a dylib for arm64 and x86_64 with Xcode's
                                          tools (DEVELOPER_DIR), and run Xcode's lipo on them
  lipo_experiments.py run <out> <lipo>    run the same cases with <lipo>, compare the standard
                                          output, the exit status and any file written with
                                          Xcode's; writes <out>/<lipo name>.json

Each case runs in <out>/inputs (the paths lipo prints are relative).
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

CASES = {
    "info-thin": ["-info", "arm64.dylib"],
    "info-fat": ["-info", "fat.dylib"],
    "archs-thin": ["-archs", "arm64.dylib"],
    "archs-fat": ["-archs", "fat.dylib"],
    "verify-arch-present": ["fat.dylib", "-verify_arch", "arm64"],
    "verify-arch-missing": ["arm64.dylib", "-verify_arch", "x86_64"],
    "remove": ["fat.dylib", "-remove", "x86_64", "-output", "{output}"],
    "thin": ["fat.dylib", "-thin", "arm64", "-output", "{output}"],
    "extract": ["fat.dylib", "-extract", "arm64", "-output", "{output}"],
    "create": ["-create", "arm64.dylib", "x86_64.dylib", "-output", "{output}"],
}

SOURCE = "static int hidden(int x) { return x * 3; }\nint counter = 2;\nint visible(int x) { return hidden(x) + counter; }\n"


def run_case(lipo, flags, inputs, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    command = [lipo] + [str(output) if flag == "{output}" else flag for flag in flags]
    proc = subprocess.run(command, cwd=inputs, capture_output=True)
    return {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"),
            "output": output.read_bytes().hex() if output.exists() else None}


def inputs(out):
    binaries = out / "inputs"
    binaries.mkdir(parents=True, exist_ok=True)
    (out / "c.c").write_text(SOURCE)
    for arch, sdk_name, target in [("arm64", "iphoneos", "arm64-apple-ios15.1"), ("x86_64", "iphonesimulator", "x86_64-apple-ios15.1-simulator")]:
        sdk = subprocess.run(["xcrun", "--sdk", sdk_name, "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(["xcrun", "--sdk", sdk_name, "clang", "-target", target, "-isysroot", sdk, "-O1", "-dynamiclib",
                        "-install_name", "@rpath/lib.dylib", str(out / "c.c"), "-o", str(binaries / f"{arch}.dylib")], check=True)
    lipo = subprocess.run(["xcrun", "--find", "lipo"], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run([lipo, "-create", "arm64.dylib", "x86_64.dylib", "-output", "fat.dylib"], cwd=binaries, check=True)
    expected = {case: run_case(lipo, flags, binaries, out / "xcode" / case) for case, flags in CASES.items()}
    (out / "xcode.json").write_text(json.dumps(expected, indent=2) + "\n")
    shutil.rmtree(out / "xcode")


def run(out, lipo):
    expected = json.loads((out / "xcode.json").read_text())
    results = {"lipo": lipo, "identical": [], "different": {}}
    for case, flags in CASES.items():
        found = run_case(lipo, flags, out / "inputs", out / "work" / case)
        differences = [key for key in ("status", "stdout", "output") if found[key] != expected[case][key]]
        if differences:
            results["different"][case] = {key: {"xcode": expected[case][key], "other": found[key]} for key in differences}
        else:
            results["identical"].append(case)
    shutil.rmtree(out / "work", ignore_errors=True)
    (out / f"{Path(lipo).name}.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"{len(results['identical'])} of {len(CASES)} cases like Xcode's lipo")
    for case, details in results["different"].items():
        print(f"    {case}: " + "; ".join(f"{key} {str(value['xcode'])[:60]!r} vs {str(value['other'])[:60]!r}" for key, value in details.items()))


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "inputs":
        inputs(out)
    else:
        run(out, sys.argv[3])


if __name__ == "__main__":
    main()

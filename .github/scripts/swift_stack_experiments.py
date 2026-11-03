#!/usr/bin/env python3
"""Stack checks of Swift compiles: when Xcode 27.0's swift-driver passes -stack-check to the
frontend, what it changes in the LLVM IR, and the objects it gives (ADR 0106).

The driver cases record, for each target and option, whether the driver's frontend job has
-stack-check and -disable-clang-spi. The IR cases compile self-written Swift with and without the
frontend's -stack-check and list the defined functions with and without the attribute
`"probe-stack"="__chkstk_darwin"`. The object cases compile the same sources through the driver,
which calls ___chkstk_darwin before frames of 4096 bytes or more and before dynamic allocations
where it checks the stack; the frames' buffers go to an external function, so that -O keeps them.

Usage:
  swift_stack_experiments.py xcode <out>                Mac: Xcode's swiftc (DEVELOPER_DIR); writes
                                                       <out>/xcode.json and <out>/xcode/*.o
  swift_stack_experiments.py run <out> <developer-dir>  the developer directory's swift-frontend; writes
                                                       <out>/run.json and prints the differences
  swift_stack_experiments.py driver <out> <swiftc>      Mac: another swift-driver build's jobs, with
                                                       Xcode's swift-frontend, against <out>/xcode.json
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

DRIVER_CASES = [
    ("arm64-apple-ios12.0", []),
    ("arm64-apple-ios12.4", []),
    ("arm64-apple-ios12.99", []),
    ("arm64-apple-ios13.0", []),
    ("arm64-apple-ios15.1", []),
    ("arm64e-apple-ios13.0", []),
    ("arm64-apple-tvos12.0", []),
    ("arm64-apple-tvos13.0", []),
    ("arm64_32-apple-watchos5.0", []),
    ("arm64_32-apple-watchos6.0", []),
    ("arm64_32-apple-watchos7.0", []),
    ("arm64_32-apple-watchos8.0", []),
    ("arm64_32-apple-watchos10.0", []),
    ("arm64_32-apple-watchos26.0", []),
    ("arm64-apple-watchos4.0", []),
    ("arm64-apple-watchos5.0", []),
    ("arm64-apple-watchos5.99", []),
    ("arm64-apple-watchos6.0", []),
    ("arm64-apple-watchos7.0", []),
    ("arm64-apple-watchos10.0", []),
    ("arm64e-apple-watchos7.0", []),
    ("arm64-apple-tvos13.0-simulator", []),
    ("arm64-apple-watchos10.0-simulator", []),
    ("arm64-apple-xros1.0", []),
    ("x86_64-apple-tvos13.0-simulator", []),
    ("arm64-apple-tvos26.0-simulator", []),
    ("x86_64-apple-watchos10.0-simulator", []),
    ("arm64-apple-watchos26.0-simulator", []),
    ("arm64-apple-ios26.0-simulator", []),
    ("x86_64-apple-macos10.14", []),
    ("x86_64-apple-macos10.14.6", []),
    ("arm64-apple-macos10.15", []),
    ("arm64e-apple-macos11.0", []),
    ("x86_64-apple-macos10.15", []),
    ("arm64-apple-macos14.0", []),
    ("arm64-apple-ios15.1-macabi", []),
    ("x86_64-apple-ios13.1-macabi", []),
    ("arm64-apple-macos14.0", ["-target-variant", "arm64-apple-ios12.0-macabi"]),
    ("x86_64-apple-macos10.14", ["-target-variant", "x86_64-apple-ios13.1-macabi"]),
    ("arm64-apple-driverkit19.0", []),
    ("x86_64-apple-driverkit19.0", []),
    ("arm64-apple-firmware1.0", []),
    ("arm64e-apple-firmware", []),
    ("arm64-apple-none-macho", []),
    ("x86_64-unknown-linux-gnu", []),
    ("arm64-apple-ios15.1-simulator", []),
    ("x86_64-apple-ios15.1-simulator", []),
    ("arm64-apple-xros1.0-simulator", []),
    ("arm64-apple-ios15.1", ["-Onone"]),
    ("arm64-apple-ios15.1", ["-Osize"]),
    ("arm64-apple-ios15.1", ["-Onone", "-g"]),
    ("arm64-apple-ios15.1", ["-wmo"]),
    ("arm64-apple-ios15.1", ["-enable-library-evolution"]),
    ("arm64-apple-ios15.1", ["-emit-module", "-emit-module-path", "Frames.swiftmodule"]),
    ("arm64-apple-ios15.1", ["-explicit-module-build"]),
    ("arm64-apple-ios15.1", ["-wmo", "-enable-experimental-feature", "Embedded"]),
    ("arm64-apple-ios15.1", ["-sanitize=address"]),
    ("arm64-apple-ios15.1", ["-sanitize=undefined"]),
    ("arm64-apple-macos14.0", ["-sanitize=thread"]),
    ("arm64-apple-ios15.1", ["-sanitize=address", "-stack-check"]),
    ("arm64-apple-ios12.0", ["-stack-check"]),
    ("arm64-apple-ios15.1-simulator", ["-stack-check"]),
    ("x86_64-unknown-linux-gnu", ["-stack-check"]),
    ("arm64-apple-ios15.1", ["-no-stack-check"]),
    ("arm64-apple-ios15.1", ["-no-stack-check", "-stack-check"]),
    ("arm64-apple-ios15.1", ["-stack-check", "-no-stack-check"]),
]

SDKS = {"ios": "iphoneos", "ios-simulator": "iphonesimulator", "tvos": "appletvos", "tvos-simulator": "appletvsimulator", "watchos": "watchos",
        "watchos-simulator": "watchsimulator", "xros": "xros", "xros-simulator": "xrsimulator", "macos": "macosx", "ios-macabi": "macosx",
        "driverkit": "driverkit"}

SOURCES = {
    "frames.swift": """@_silgen_name("nomac_use") func use(_ pointer: UnsafeMutableRawPointer)
public struct Page {
    public var words: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0, 0, 0, 0)
    public init() {}
}
@inline(never) public func small() -> Int {
    var local = (Page(), Page())
    return withUnsafeMutableBytes(of: &local) { use($0.baseAddress!); return $0.count }
}
@inline(never) public func large() -> Int {
    var local = (Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(),
                 Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(),
                 Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(),
                 Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page(), Page())
    return withUnsafeMutableBytes(of: &local) { use($0.baseAddress!); return $0.count }
}
@inline(never) public func dynamic(_ count: Int) -> Int {
    withUnsafeTemporaryAllocation(byteCount: count, alignment: 16) { use($0.baseAddress!); return $0.count }
}
public final class Holder {
    public var pages = [Page]()
    public init() {}
    public func add() { pages.append(Page()) }
}
""",
}
OBJECT_TARGETS = ["arm64-apple-ios15.1", "arm64-apple-ios12.0"]
IR_TARGETS = ["arm64-apple-ios15.1", "arm64-apple-ios12.0"]
OPTIMIZATIONS = ["-O", "-Onone"]
PROBE = '"probe-stack"="__chkstk_darwin"'


def platform_of(target):
    os_part = target.split("-")[2]
    name = re.sub(r"[0-9.]+$", "", os_part)
    suffix = target.split("-")[3] if len(target.split("-")) > 3 else ""
    return name + ("-" + suffix if suffix else "")


def sdk_path(target):
    sdk = SDKS.get(platform_of(target))
    if sdk is None:
        return None
    return subprocess.run(["xcrun", "--sdk", sdk, "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()


def frontend_job(swiftc, source, target, flags, sdk, env=None):
    """The flags of the compile job (`swift-frontend -frontend -c`, after any module build jobs)."""
    command = [swiftc, "-###", "-target", target, "-parse-as-library", "-c", str(source), "-module-name", "Frames"] + (["-sdk", sdk] if sdk else []) + flags
    output = subprocess.run(command, capture_output=True, text=True, cwd=source.parent, env=env)
    job = next((line.split() for line in output.stdout.splitlines() if line.split()[1:3] == ["-frontend", "-c"]), None)
    if job is None:
        return {"error": (output.stderr.strip().splitlines() or [""])[0]}
    return {"stackCheck": "-stack-check" in job, "noStackCheck": "-no-stack-check" in job, "disableClangSPI": job.count("-disable-clang-spi")}


def driver_table(swiftc, source, env=None):
    return {f"{target} {' '.join(flags)}".strip(): frontend_job(swiftc, source, target, flags, sdk_path(target), env)
            for target, flags in DRIVER_CASES}


def ir_functions(text):
    """The functions the module defines and declares, by whether their attributes name the probe."""
    groups = {number for number, body in re.findall(r"^attributes #(\d+) = \{(.*)\}$", text, re.M) if PROBE in body}
    functions = {"definedWithProbe": [], "definedWithoutProbe": [], "declaredWithProbe": []}
    for kind, name, group in re.findall(r'^(define|declare) [^@\n]*@("[^"]+"|[\w$.]+)\([^\n]*\)[^#\n]*#(\d+)', text, re.M):
        if kind == "define":
            functions["definedWithProbe" if group in groups else "definedWithoutProbe"].append(name.strip('"'))
        elif group in groups:
            functions["declaredWithProbe"].append(name.strip('"'))
    return {key: sorted(names) for key, names in functions.items()}


def ir_differences(ours, xcode):
    """The functions both compilers make whose probe differs, and those only one of them makes."""
    if "error" in ours or "error" in xcode:
        return {"ours": ours, "xcode": xcode}
    def defined(functions):
        return set(functions["definedWithProbe"]) | set(functions["definedWithoutProbe"])
    common = defined(ours) & defined(xcode)
    return {"probeDiffers": sorted(name for name in common if (name in ours["definedWithProbe"]) != (name in xcode["definedWithProbe"])),
            "declaredProbeDiffers": sorted(set(ours["declaredWithProbe"]) ^ set(xcode["declaredWithProbe"])),
            "onlyOurs": sorted(defined(ours) - common), "onlyXcode": sorted(defined(xcode) - common)}


def ir_report(frontend, source, sdk):
    report = {}
    for target in IR_TARGETS:
        for optimization in OPTIMIZATIONS:
            for flags in ([], ["-stack-check"], ["-no-stack-check"], ["-no-stack-check", "-stack-check"]):
                command = [frontend, "-frontend", "-c", "-emit-ir", "-target", target, "-sdk", sdk, optimization,
                           "-parse-as-library", str(source), "-module-name", "Frames", "-o", "-"] + flags
                result = subprocess.run(command, capture_output=True, text=True)
                case = f"{target} {optimization} {' '.join(flags)}".strip()
                report[case] = ir_functions(result.stdout) if result.returncode == 0 else {"error": result.stderr.strip().splitlines()[:1]}
    return report


def compile_swift(swiftc, source, target, optimization, output, sdk):
    command = [swiftc, "-target", target, "-sdk", sdk, optimization, "-parse-as-library", "-c", str(source),
               "-module-name", "Frames", "-o", str(output)]
    result = subprocess.run(command, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def probe_calls(objdump, obj):
    text = subprocess.run([objdump, "-d", "-r", "--no-show-raw-insn", str(obj)], capture_output=True, text=True, check=True).stdout
    # The probe is called through its GOT entry (`adrp`, `ldr`, `blr`): one page relocation each.
    return sum(1 for line in text.splitlines() if "___chkstk_darwin" in line and "_PAGE21" in line)


def write_sources(out):
    source = out / "src"
    source.mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (source / name).write_text(text)
    return source


def cases():
    for name in SOURCES:
        for target in OBJECT_TARGETS:
            for optimization in OPTIMIZATIONS:
                yield name, target, optimization, f"{Path(name).stem}.{target}{optimization}"


def xcode(out):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    swiftc, frontend, objdump = str(bin_dir / "swiftc"), str(bin_dir / "swift-frontend"), "/usr/bin/objdump"
    source = write_sources(out)
    driver = driver_table(swiftc, source / "frames.swift")
    ir = ir_report(frontend, source / "frames.swift", sdk_path("arm64-apple-ios15.1"))
    objects = out / "xcode"
    objects.mkdir(exist_ok=True)
    probes = {}
    for name, target, optimization, stem in cases():
        compiled, errors = compile_swift(swiftc, source / name, target, optimization, objects / f"{stem}.o", sdk_path(target))
        if not compiled:
            sys.exit(errors)
        probes[stem] = probe_calls(objdump, objects / f"{stem}.o")
    (out / "xcode.json").write_text(json.dumps({"driver": driver, "ir": ir, "probeCalls": probes}, indent=2) + "\n")
    print(json.dumps({"driver": driver, "ir": ir, "probeCalls": probes}, indent=2))


def run(out, developer):
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    frontend, objdump = str(bin_dir / "swift-frontend"), str(bin_dir / "llvm-objdump")
    source = write_sources(out)
    expected = json.loads((out / "xcode.json").read_text())
    sdk = str(Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
    ir = ir_report(frontend, source / "frames.swift", sdk)
    scratch = out / "scratch"
    scratch.mkdir(exist_ok=True)
    objects = {}
    for name, target, optimization, stem in cases():
        ours, reference = scratch / f"{stem}.o", out / "xcode" / f"{stem}.o"
        # The frontend itself, with -stack-check where Xcode's driver passes it, so that the frontend
        # is measured whichever driver the developer directory has.
        flags = ["-stack-check"] if expected["driver"][target]["stackCheck"] else []
        command = [frontend, "-frontend", "-c", "-target", target, "-sdk", sdk, optimization, "-parse-as-library",
                   str(source / name), "-module-name", "Frames", "-o", str(ours)] + flags
        if subprocess.run(command, capture_output=True).returncode != 0:
            objects[stem] = "does not compile"
            continue
        calls = probe_calls(objdump, ours)
        objects[stem] = {"probeCalls": calls, "xcodeProbeCalls": expected["probeCalls"][stem],
                         "identical": ours.read_bytes() == reference.read_bytes()}
    report = {"ir": {case: ir_differences(ir[case], expected["ir"][case]) for case in ir}, "objects": objects}
    (out / "run.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


def driver(out, swift_driver):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    frontend = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"
    source = write_sources(out)
    expected = json.loads((out / "xcode.json").read_text())["driver"]
    env = dict(os.environ, SWIFT_DRIVER_SWIFT_FRONTEND_EXEC=str(frontend))
    ours = driver_table(swift_driver, source / "frames.swift", env)
    differences = {case: {"ours": ours[case], "xcode": expected.get(case)} for case in ours if ours[case] != expected.get(case)}
    (out / "driver.json").write_text(json.dumps(ours, indent=2) + "\n")
    print(json.dumps({"cases": len(ours), "differences": differences}, indent=2))


if __name__ == "__main__":
    if sys.argv[1:2] == ["xcode"]:
        xcode(Path(sys.argv[2]).resolve())
    elif sys.argv[1:2] == ["driver"]:
        driver(Path(sys.argv[2]).resolve(), sys.argv[3])
    elif sys.argv[1:2] == ["run"]:
        run(Path(sys.argv[2]).resolve(), sys.argv[3])
    else:
        sys.exit(__doc__)

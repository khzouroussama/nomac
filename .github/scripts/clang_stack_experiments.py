#!/usr/bin/env python3
"""Stack checks and the exception tables of stack-protected functions: where clang's driver turns
the checks on and the code both give, Xcode 27.0's against a developer directory's (B-170).

Xcode's driver passes -fstack-check to Apple devices from macOS 10.15, iOS and tvOS 13, watchOS 6,
Mac Catalyst and visionOS; the compiler then calls ___chkstk_darwin before a frame of 4096 bytes of
locals or more and before every dynamic alloca. The driver cases record whether the driver passes
-fstack-check; the object cases compile self-written functions with large frames, dynamic allocas,
shrink-wrapped prologues and values live across the probe, and C++ functions with a personality
whose stack objects the stack protector guards (Xcode's clang gives them a cleanup landing pad for
every call that may unwind), and compare the objects.

Usage:
  clang_stack_experiments.py xcode <out>                Mac: Xcode's clang (DEVELOPER_DIR); writes
                                                       <out>/xcode.json and <out>/xcode/*.o
  clang_stack_experiments.py run <out> <developer-dir>  the developer directory's clang; writes
                                                       <out>/run.json and prints the differences
"""

import json
import os
import subprocess
import sys
from pathlib import Path

DRIVER_CASES = [
    ("arm64-apple-ios12.0", []),
    ("arm64-apple-ios13.0", []),
    ("arm64-apple-ios15.1", []),
    ("arm64e-apple-ios12.0", []),
    ("arm64e-apple-ios13.0", []),
    ("arm64-apple-tvos12.0", []),
    ("arm64-apple-tvos13.0", []),
    ("arm64-apple-watchos5.0", []),
    ("arm64-apple-watchos6.0", []),
    ("arm64_32-apple-watchos10.0", []),
    ("arm64-apple-xros1.0", []),
    ("arm64-apple-macos11", []),
    ("x86_64-apple-macos10.14", []),
    ("x86_64-apple-macos10.15", []),
    ("x86_64-apple-ios13.1-macabi", []),
    ("arm64-apple-driverkit20.0", []),
    ("arm64-apple-ios15.1-simulator", []),
    ("x86_64-apple-ios15.1-simulator", []),
    ("arm64-apple-xros1.0-simulator", []),
    ("arm64-apple-ios15.1", ["-fno-stack-check"]),
    ("arm64-apple-ios15.1", ["-ffreestanding"]),
    ("arm64-apple-ios15.1", ["-mkernel"]),
    ("arm64-apple-ios12.0", ["-fstack-check"]),
    ("arm64-apple-ios15.1-simulator", ["-fstack-check"]),
]

SOURCES = {
    "frames.c": """void use(char *);
void big(void) { char buf[8192]; use(buf); }
void bigger(void) { char buf[70000]; use(buf); }
void small(void) { char buf[256]; use(buf); }
void x4080(void) { char buf[4080]; use(buf); }
void x4096(void) { char buf[4096]; use(buf); }
void huge(void) { char buf[0x123456]; use(buf); }
int leaf(int i) { volatile char buf[8192]; buf[i] = 1; return buf[0]; }
int leafsmall(int i) { volatile char buf[4000]; buf[i] = 1; return buf[0]; }
void al64(void) { char buf[8192] __attribute__((aligned(64))); use(buf); }
void al64s(void) { char buf[4064] __attribute__((aligned(64))); use(buf); }
""",
    "allocas.c": """void use(char *);
void vla(int n) { char buf[n]; use(buf); }
void both(int n) { char big[8192]; char buf[n]; use(big); use(buf); }
void c100(int n) { for (int i = 0; i < n; i++) use(__builtin_alloca(100)); }
void c8192(int n) { for (int i = 0; i < n; i++) use(__builtin_alloca(8192)); }
void al32(int n) { char buf[n] __attribute__((aligned(32))); use(buf); }
void wide(int n) { long buf[n]; use((char *)buf); }
""",
    "shrink.c": """void use(char *);
int sw(int a, int b) { if (a) return b; char buf[8192]; use(buf); return 0; }
int sw2(int a, long *p) { long x = p[0] * 3; if (a > x) return 1; char buf[8192]; buf[a] = 1; use(buf); return (int)x; }
int lsw(int a, int i) { if (a) return 0; volatile char buf[8192]; buf[i] = 1; return buf[0]; }
""",
    "live.c": """long g(int n, long a, long b, long c, long d, long e, long f, long h, double x, double y) {
  volatile char buf[n]; buf[0] = 1;
  return a * b + c * d + e * f + h + (long)(x * y);
}
long m(int n, volatile long *p) {
  long v0 = p[0], v1 = p[1], v2 = p[2], v3 = p[3], v4 = p[4], v5 = p[5], v6 = p[6], v7 = p[7];
  long v8 = p[8], v9 = p[9], v10 = p[10], v11 = p[11], v12 = p[12], v13 = p[13], v14 = p[14], v15 = p[15];
  volatile char buf[n]; buf[0] = 1;
  return v0 * v1 + v2 * v3 + v4 * v5 + v6 * v7 + v8 * v9 + v10 * v11 + v12 * v13 + v14 * v15;
}
""",
}

CLEANUPS = """void use(void *); void g(); void h() noexcept;
struct T { int x; ~T() {} };
struct U { ~U(); };
void f9() { char buf[64]; T t; use(buf); g(); }
void f10() { T t; use(nullptr); g(); }
void f11() { char buf[64]; use(buf); g(); }
void f12() { int arr[16]; T t; use(arr); g(); }
void f13(int n) { char buf[n]; T t; use(buf); g(); }
void f14() { char buf[4]; T t; use(buf); g(); }
void f15() { long v; T t; use(&v); g(); }
void f17() { char buf[64]; use(buf); { U u; g(); } g(); }
void f18() { char buf[64]; T t; use(buf); h(); }
void f19() { char buf[64]; T t; h(); }
[[noreturn]] void die();
[[noreturn]] inline void thrower() { throw 1; }
void f20(int c) { char buf[64]; T t; use(buf); if (c) die(); g(); }
void f22(int c) { char buf[64]; T t; use(buf); if (c) thrower(); g(); }
void f23(int c) { if (c) die(); char buf[64]; T t; use(buf); g(); }
void f24(int c) { if (c) thrower(); char buf[64]; T t; use(buf); g(); }
"""
SOURCES["cleanups.cpp"] = CLEANUPS
SOURCES["cleanups-strong.cpp"] = CLEANUPS
FLAGS = {"cleanups-strong.cpp": ["-fstack-protector-strong"]}

TARGETS = ["arm64-apple-ios15.1", "arm64-apple-ios12.0", "arm64-apple-ios15.1-simulator", "x86_64-apple-macos12",
           "arm64e-apple-ios15.1"]
OPTIMIZATIONS = ["-O0", "-Os"]


def sdk_for(developer, target):
    platform = "iPhoneSimulator" if target.endswith("-simulator") else "iPhoneOS"
    return str(Path(developer) / f"Platforms/{platform}.platform/Developer/SDKs/{platform}.sdk")


def passes_stack_check(clang, source, target, flags):
    command = [clang, "-###", "-target", target, "-c", str(source), "-o", "/dev/null"] + flags
    output = subprocess.run(command, capture_output=True, text=True).stderr
    return '"-fstack-check"' in output


def compile_c(clang, developer, source, target, optimization, output):
    command = [clang, "-target", target, "-isysroot", sdk_for(developer, target), optimization] + \
        FLAGS.get(source.name, []) + ["-c", str(source), "-o", str(output)]
    result = subprocess.run(command, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def code(objdump, obj):
    text = subprocess.run([objdump, "-d", "-s", "-r", "--no-show-raw-insn", str(obj)], capture_output=True, text=True,
                          check=True).stdout
    return [line for line in text.splitlines() if str(obj) not in line]


def cases():
    for name in SOURCES:
        for target in TARGETS:
            for optimization in OPTIMIZATIONS:
                yield name, target, optimization, f"{Path(name).stem}.{target}{optimization}"


def write_sources(out):
    source = out / "src"
    source.mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (source / name).write_text(text)
    return source


def driver_report(clang, source):
    return {f"{target} {' '.join(flags)}".strip(): passes_stack_check(clang, source / "frames.c", target, flags)
            for target, flags in DRIVER_CASES}


def xcode(out):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    clang = str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
    source = write_sources(out)
    (out / "xcode.json").write_text(json.dumps(driver_report(clang, source), indent=2) + "\n")
    objects = out / "xcode"
    objects.mkdir(exist_ok=True)
    for name, target, optimization, stem in cases():
        compiled, errors = compile_c(clang, developer, source / name, target, optimization, objects / f"{stem}.o")
        if not compiled:
            sys.exit(errors)
    print(f"{len(DRIVER_CASES)} driver cases and {len(list(objects.glob('*.o')))} objects in {out}")


def run(out, developer):
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    clang, objdump = str(bin_dir / "clang"), str(bin_dir / "llvm-objdump")
    source = write_sources(out)
    expected = json.loads((out / "xcode.json").read_text())
    driver = driver_report(clang, source)
    differences = [case for case in expected if driver.get(case) != expected[case]]
    for case in differences:
        print(f"driver {case}: Xcode's {'passes' if expected[case] else 'leaves out'} -fstack-check, this clang "
              f"{'passes' if driver[case] else 'leaves it out'}")
    print(f"driver: {len(expected) - len(differences)} of {len(expected)} cases as Xcode's")
    scratch = out / "scratch"
    scratch.mkdir(exist_ok=True)
    objects = {}
    for name, target, optimization, stem in cases():
        ours, reference = scratch / f"{stem}.o", out / "xcode" / f"{stem}.o"
        if not compile_c(clang, developer, source / name, target, optimization, ours)[0]:
            objects[stem] = "does not compile"
        elif ours.read_bytes() == reference.read_bytes():
            objects[stem] = "identical"
        else:
            objects[stem] = "same code, other bytes" if code(objdump, ours) == code(objdump, reference) else "code differs"
        if objects[stem] != "identical":
            print(f"{stem}: {objects[stem]}")
    identical = sum(1 for result in objects.values() if result == "identical")
    print(f"objects: {identical} of {len(objects)} identical to Xcode's")
    (out / "run.json").write_text(json.dumps({"driver": driver, "objects": objects}, indent=2, sort_keys=True) + "\n")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        xcode(Path(sys.argv[2]).resolve())
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        run(Path(sys.argv[2]).resolve(), sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

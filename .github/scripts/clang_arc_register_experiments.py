#!/usr/bin/env python3
"""objc_retain_x<N>, objc_release_x<N>, swift_retain_x<N> and swift_release_x<N>: where Xcode 27.0's
LLVM calls the runtime entry points that take their object in a given register, against a
developer directory's clang, compiling the same IR (B-170).

Self-written IR calls swift_retain and swift_release with objects in several registers (arguments,
loaded values, a call's result, a tail call), with the module flag "Swift DirectReg Version" set to
1, 2 or 0 or missing, and the same calls to objc_retain and objc_release, plain and through
llvm.objc.retain and llvm.objc.release as clang's Objective-C IR has them; Swift's own IR for a
self-written file comes from Xcode's swift-frontend (-emit-ir). Each is compiled for arm64,
arm64_32 and x86_64 Apple targets at -O0 to -Os and the objects compared byte for byte. Xcode's
LLVM calls the Swift entry points for every arm64 target when the flag is not 0, the Objective-C
ones from iOS, tvOS and Mac Catalyst 16, watchOS 9 and visionOS, both where SelectionDAG selects
the instructions (above -O0, and for arm64_32 at -O0 too). An objc_retain lowered from
llvm.objc.retain is no this-return call (its object is not marked returned), so the uses
objc-arc-contract moved to its result take x0; after swift_retain the object stays in its register.

Usage:
  clang_arc_register_experiments.py xcode <out>                Mac: Xcode's clang and swiftc
                                                              (DEVELOPER_DIR); writes <out>/src and
                                                              <out>/xcode
  clang_arc_register_experiments.py run <out> <developer-dir>  the developer directory's clang;
                                                              prints the differences
"""

import os
import subprocess
import sys
from pathlib import Path

CALLS = """target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
declare ptr @swift_retain(ptr returned) #0
declare void @swift_release(ptr) #0
declare void @use2(ptr, ptr)
declare void @use1(ptr)
declare ptr @get()
define void @f1(ptr %a, ptr %b) {
  %r = call ptr @swift_retain(ptr %b)
  call void @use2(ptr %a, ptr %b)
  call void @swift_release(ptr %b)
  ret void }
define void @f2(ptr %a) { call void @use1(ptr %a)
  tail call void @swift_release(ptr %a)
  ret void }
define ptr @f3(ptr %a) {
  %r =
  tail call ptr @swift_retain(ptr %a)
  ret ptr
  %r }
define void @f4(ptr %p) {
  %x = load ptr, ptr %p
  %y = getelementptr i8, ptr %p, i64 8
  %z = load ptr, ptr
  %y
  %r1 = call ptr @swift_retain(ptr %x)
  %r2 = call ptr @swift_retain(ptr %z)
  call void @use2(ptr %x, ptr %z)
  call void @swift_release(ptr %x)
  call void @swift_release(ptr %z)
  ret void }
define void @f5() {
  %o = call ptr @get()
  %r = call ptr @swift_retain(ptr %o)
  call void @use1(ptr %o)
  call void @swift_release(ptr %o)
  call void @swift_release(ptr %o)
  ret void }
attributes #0 = { nounwind }
"""

FLAGS = {
    "flag": '!{i32 1, !"Swift DirectReg Version", i32 1}',
    "flag2": '!{i32 1, !"Swift DirectReg Version", i32 2}',
    "flag0": '!{i32 1, !"Swift DirectReg Version", i32 0}',
    "noflag": None,
}

SWIFT = """public final class Box { public var v = 0; public init() {} }
public struct Pair { public var a: Box; public var b: Box }
@inline(never) public func sink(_ p: Pair) {}
public func make(_ a: Box, _ b: Box) -> Pair { let p = Pair(a: a, b: b); sink(p); return p }
public func capture(_ a: Box) -> () -> Int { return { a.v } }
public var global = Box()
public func swap(_ a: Box) -> Box { let old = global; global = a; return old }
"""

TARGETS = ["arm64-apple-ios17.0", "arm64-apple-ios16.0", "arm64-apple-ios15.0", "arm64-apple-macos14",
           "arm64-apple-watchos10.0", "arm64_32-apple-watchos10.0", "arm64-apple-xros1.0",
           "arm64-apple-ios17.0-simulator", "x86_64-apple-ios17.0-simulator", "arm64-apple-tvos17.0"]
LEVELS = ["-O0", "-O1", "-O2", "-Os"]


def module(name):
    flags = ['!{i32 1, !"Swift Version", i32 7}'] + ([FLAGS[name]] if FLAGS[name] else [])
    names = ", ".join(f"!{index}" for index in range(len(flags)))
    return CALLS + f"!llvm.module.flags = !{{{names}}}\n" + "".join(
        f"!{index} = {flag}\n" for index, flag in enumerate(flags))


def write_sources(out, developer=None):
    source = out / "src"
    source.mkdir(parents=True, exist_ok=True)
    for name in FLAGS:
        (source / f"swift-{name}.ll").write_text(module(name))
    (source / "objc.ll").write_text(module("noflag").replace("swift_retain", "objc_retain")
                                    .replace("swift_release", "objc_release"))
    (source / "objc-intrinsics.ll").write_text(
        module("noflag").replace("declare ptr @swift_retain(ptr returned)", "declare ptr @llvm.objc.retain(ptr)")
        .replace("@swift_retain(", "@llvm.objc.retain(").replace("@swift_release(", "@llvm.objc.release("))
    if developer:
        (source / "box.swift").write_text(SWIFT)
        sdk = Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        subprocess.run(["xcrun", "swiftc", "-target", "arm64-apple-ios17.0", "-sdk", str(sdk), "-O",
                        "-parse-as-library", "-module-name", "M", "-emit-ir", str(source / "box.swift"),
                        "-o", str(source / "box.ll")], check=True)
    return sorted(path.name for path in source.glob("*.ll"))


def compile_all(clang, out, products):
    products.mkdir(parents=True, exist_ok=True)
    for name in sorted(path.name for path in (out / "src").glob("*.ll")):
        targets = TARGETS if name != "box.ll" else ["arm64-apple-ios17.0"]
        for target in targets:
            for level in LEVELS:
                output = products / f"{Path(name).stem}.{target}{level}.o"
                subprocess.run([clang, "-target", target, level, "-Wno-override-module", "-c",
                                str(out / "src" / name), "-o", str(output)], check=True)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        out = Path(sys.argv[2]).resolve()
        developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
        write_sources(out, developer)
        compile_all(str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"), out, out / "xcode")
        print(f"{len(list((out / 'xcode').glob('*.o')))} objects in {out / 'xcode'}")
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        out = Path(sys.argv[2]).resolve()
        clang = str(Path(sys.argv[3]) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
        compile_all(clang, out, out / "run")
        objects = sorted(path.name for path in (out / "xcode").glob("*.o"))
        different = [name for name in objects
                     if (out / "run" / name).read_bytes() != (out / "xcode" / name).read_bytes()]
        for name in different:
            print(f"{name}: differs")
        print(f"{len(objects) - len(different)} of {len(objects)} objects identical to Xcode's")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

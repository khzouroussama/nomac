#!/usr/bin/env python3
"""Objective-C as Xcode 27.0's clang compiles it, against the clang nomac installs (B-170).

Xcode's clang writes `@[…]`, `@{…}` and number literals whose elements are constants as constant
objects (`NSConstantArray`, `NSConstantDictionary`, `NSConstantIntegerNumber`, …) from iOS 14, and
from iOS 13 calls `objc_opt_class`, `objc_opt_self`, `objc_opt_new`, `objc_opt_isKindOfClass` and
`objc_opt_respondsToSelector` for those messages; swift.org 6.4.0's builds the literals at run time
and sends the messages; Xcode's leaves `nonnull`, `dereferenceable` and `align` off `this` for
Apple targets, compiles blocks passed to non-escaping parameters as stack blocks,
and from iOS 16 calls `objc_retain_x<N>` and `objc_release_x<N>` (iOS 17.0 here). This compiles
self-written Objective-C with Xcode's clang and with a developer directory's, at several deployment
targets, arm64 and the x86_64 simulator, -O0 and -Os, and compares symbols, sections, and code and
data, each clang with its defaults: Xcode's calls `objc_msgSend$<selector>` stubs for arm64, as the
patched clang does with the toolchain's `clang.cfg` (.github/clang 0013). The iOS 15.1 literal
objects are also linked into dylibs, for the segments the linkers give the literals' sections
(.github/lld 0009) and the stubs the linkers write (`__objc_stubs`).

Usage:
  clang_objc_experiments.py xcode <out>                Mac: Xcode's clang (DEVELOPER_DIR); writes
                                                       Xcode's objects under <out>/xcode
  clang_objc_experiments.py run <out> <developer-dir>  the developer directory's clang; writes
                                                       <out>/run.json
"""

import json
import os
import subprocess
import sys
from pathlib import Path

TARGETS = ["arm64-apple-ios12.0", "arm64-apple-ios13.0", "arm64-apple-ios14.0", "arm64-apple-ios15.1", "arm64-apple-ios17.0", "x86_64-apple-ios15.1-simulator"]
OPTIMIZATIONS = ["-O0", "-Os"]
# Xcode's driver passes -fno-strict-return and -fno-assume-unique-vtables for Apple targets and
# swift.org's does not (docs/formats/build.md "Clang's driver"); both clangs get them here.
FLAGS = ["-fobjc-arc", "-fno-strict-return", "-fno-assume-unique-vtables"]

SOURCES = {
    "literals.m": """#import <Foundation/Foundation.h>
NSArray *strings(void) { return @[@"a", @"b", @"c"]; }
NSArray *empty(void) { return @[]; }
NSDictionary *emptyDictionary(void) { return @{}; }
NSArray *nested(void) { return @[@[@"x"], @{@"k": @"v"}, @1]; }
NSDictionary *dictionary(void) { return @{@"zeta": @1, @"alpha": @2, @"Mid": @"three"}; }
NSDictionary *unicodeKeys(void) { return @{@"\\u00e9": @1, @"z": @2, @"\\U0001F600": @3, @"\\u00ff": @4}; }
NSNumber *integer(void) { return @42; }
NSNumber *negative(void) { return @-7; }
NSNumber *longLong(void) { return @9223372036854775807LL; }
NSNumber *unsignedNumber(void) { return @4294967295U; }
NSNumber *characterNumber(void) { return @'c'; }
NSNumber *doubleNumber(void) { return @3.25; }
NSNumber *floatNumber(void) { return @1.5f; }
NSNumber *yes(void) { return @YES; }
NSNumber *no(void) { return @NO; }
NSNumber *boxed(void) { return @(6 * 7); }
NSArray *runtimeElement(NSString *s) { return @[@"a", s]; }
NSDictionary *runtimeValue(id v) { return @{@"k": v}; }
NSNumber *runtimeNumber(int x) { return @(x); }
""",
    # Constant literals as file-scope initializers, which clang accepts only where they are constants.
    "filescope.m": """#import <Foundation/Foundation.h>
static NSArray *const fileScope = @[@"f", @2];
static NSDictionary *const fileScopeDictionary = @{@"b": @YES, @"a": @[@1]};
id fileScopes(void) { return @[fileScope, fileScopeDictionary]; }
""",
    # Messages Xcode's clang sends through objc_opt_ entrypoints from iOS 13, and the ones it does not.
    "messages.m": """#import <Foundation/Foundation.h>
Class c1(id o) { return [o class]; }
Class c2(void) { return [NSString class]; }
id s1(id o) { return [o self]; }
id s2(void) { return [NSString self]; }
BOOL k1(id o) { return [o isKindOfClass:[NSString class]]; }
BOOL m1(id o) { return [o isMemberOfClass:[NSString class]]; }
BOOL r1(id o) { return [o respondsToSelector:@selector(description)]; }
id n1(void) { return [NSString new]; }
id a1(void) { return [[NSString alloc] init]; }
BOOL cf(id o) { return [o conformsToProtocol:@protocol(NSCopying)]; }
id cp(id o) { return [o copy]; }
NSUInteger h(id o) { return [o hash]; }
BOOL eq(id a, id b) { return [a isEqual:b]; }
id d(id o) { return [o description]; }
Class sc(id o) { return [o superclass]; }
Class nc(void) { return [(id)nil class]; }
id ns(void) { return [(id)nil self]; }
BOOL nr(void) { return [(id)nil respondsToSelector:@selector(x)]; }
BOOL nk(void) { return [(id)nil isKindOfClass:Nil]; }
id nn(void) { return [(Class)nil new]; }
""",
    # The declarations those calls need: root classes whose methods of the same names return or take
    # other types keep the message.
    "roots.m": """#import <Foundation/Foundation.h>
__attribute__((objc_root_class))
@interface Odd
- (int)class;
- (void)self;
- (int)respondsToSelector:(SEL)s;
- (int)isKindOfClass:(Class)c;
+ (int)new;
@end
int o1(Odd *o) { return [o class]; }
void o2(Odd *o) { [o self]; }
int o3(Odd *o) { return [o respondsToSelector:@selector(x)]; }
int o4(Odd *o) { return [o isKindOfClass:Nil]; }
int o5(void) { return [Odd new]; }
__attribute__((objc_root_class))
@interface Root
+ (instancetype)new;
- (Class)class;
- (instancetype)self;
- (BOOL)respondsToSelector:(SEL)s;
- (BOOL)isKindOfClass:(Class)c;
@end
id r1(Root *o) { return [o class]; }
id r2(Root *o) { return [o self]; }
BOOL r3(Root *o) { return [o respondsToSelector:@selector(x)]; }
BOOL r4(Root *o) { return [o isKindOfClass:Nil]; }
id r5(void) { return [Root new]; }
@interface Sub2 : NSObject @end
@implementation Sub2
+ (id)make { return [self new]; }
+ (id)viaSuper { return [super new]; }
- (Class)superClass { return [super class]; }
@end
@class Root0;
#define ROOT(N, RS, KC, CL, SF, NW) __attribute__((objc_root_class)) @interface N - (RS)respondsToSelector:(SEL)s; - (KC)isKindOfClass:(Class)c; - (CL)class; - (SF)self; + (NW)new; @end
ROOT(BoolRoot, bool, bool, Root0 *, NSString *, id)
ROOT(CharRoot, signed char, signed char, Class, id, Class)
ROOT(UCharRoot, unsigned char, unsigned char, id, instancetype, instancetype)
__attribute__((objc_root_class)) @interface ArgRoot - (BOOL)respondsToSelector:(id)s; - (BOOL)isKindOfClass:(id)c; @end
#define USE(N) BOOL N##_r(N *o) { return [o respondsToSelector:@selector(x)]; } BOOL N##_k(N *o) { return [o isKindOfClass:Nil]; } id N##_c(N *o) { return (id)[o class]; } id N##_s(N *o) { return (id)[o self]; } id N##_n(void) { return (id)[N new]; }
USE(BoolRoot) USE(CharRoot) USE(UCharRoot)
BOOL a_r(ArgRoot *o) { return [o respondsToSelector:nil]; } BOOL a_k(ArgRoot *o) { return [o isKindOfClass:nil]; }
__attribute__((objc_root_class)) @interface InstNew - (id)new; + (id)self; @end
id in1(InstNew *o) { return [o new]; }
id in2(void) { return [InstNew self]; }
""",
    # `this` without nonnull, dereferenceable or align (thisNoNullAttr and thisNoAlignAttr): a null test
    # on it stays.
    "this.mm": """struct S { int a; double d; S(); ~S(); int get() const; virtual int v(); };
S::S() : a(1), d(2) {}
S::~S() {}
int S::get() const { return this ? a : -1; }
int S::v() { return a; }
struct alignas(32) Big { int x; int get() const { return x; } };
int useBig(const Big &b) { return b.get(); }
int call(S &s) { return s.get() + s.v(); }
struct Base1 { virtual int f(); int b1; };
struct Base2 { virtual int g(); int b2; };
struct Multi : Base1, Base2 { int g() override; };
int Multi::g() { return 3; }
""",
    # Blocks passed to non-escaping parameters, which Xcode's clang compiles as stack blocks with
    # helpers, and the __block variables they capture, which keep their byref structure.
    "blocks.m": """#import <Foundation/Foundation.h>
void takesNoEscape(__attribute__((noescape)) void (^b)(void));
void takesEscaping(void (^b)(void));
void viaNoEscape(id x) { takesNoEscape(^{ (void)[x description]; }); }
void viaEscaping(id x) { takesEscaping(^{ (void)[x description]; }); }
void viaFoundation(NSDictionary *d, NSMutableArray *a) { [d enumerateKeysAndObjectsUsingBlock:^(id k, id o, BOOL *s) { [a addObject:k]; }]; }
int byrefNoEscape(void) { __block int x = 0; takesNoEscape(^{ x++; }); return x; }
int byrefEscaping(void) { __block int x = 0; takesEscaping(^{ x++; }); return x; }
id byrefObject(void) { __block id o = nil; takesNoEscape(^{ o = [NSObject new]; }); return o; }
""",
}
NEEDS_CONSTANT_LITERALS = {"filescope.m"}
# Objects also linked into a dylib, for the segments the linker gives the literals' sections. The
# sections are compared sorted: lld orders __got, __objc_selrefs and __objc_imageinfo otherwise than
# Xcode's ld with or without literals (ADR 0102).
LINKED = ["literals.arm64-apple-ios15.1-Os", "filescope.arm64-apple-ios15.1-Os"]


def sdk_for(developer, target):
    platform = "iPhoneSimulator" if target.endswith("-simulator") else "iPhoneOS"
    return str(Path(developer) / f"Platforms/{platform}.platform/Developer/SDKs/{platform}.sdk")


def compile_objc(clang, developer, source, target, optimization, output):
    command = [clang, "-target", target, "-isysroot", sdk_for(developer, target), optimization] + FLAGS
    result = subprocess.run(command + ["-c", str(source), "-o", str(output)], capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def symbols(nm, obj):
    lines = subprocess.run([nm, str(obj)], capture_output=True, text=True, check=True).stdout.splitlines()
    return sorted(" ".join(line.split()[-2:]) for line in lines if line.strip())


def sections(objdump, obj):
    lines = subprocess.run([objdump, "-h", str(obj)], capture_output=True, text=True, check=True).stdout.splitlines()
    return sorted(" ".join(line.split()[1:3]) for line in lines if line.strip()[:1].isdigit())


def segments(objdump, binary):
    text = subprocess.run([objdump, "--macho", "--private-headers", str(binary)], capture_output=True, text=True, check=True).stdout
    names, section = [], None
    for line in text.splitlines():
        fields = line.split()
        if fields[:1] == ["sectname"]:
            section = fields[1]
        elif fields[:1] == ["segname"] and section:
            names.append(f"{fields[1]},{section}")
            section = None
    return names


def link(clang, developer, obj, output):
    command = [clang, "-target", "arm64-apple-ios15.1", "-isysroot", sdk_for(developer, "arm64-apple-ios15.1"), "-dynamiclib",
               "-framework", "Foundation", str(obj), "-o", str(output)]
    subprocess.run(command, capture_output=True, text=True, check=True)


def code(objdump, obj):
    text = subprocess.run([objdump, "-d", "-s", "-r", "--no-show-raw-insn", str(obj)], capture_output=True, text=True, check=True).stdout
    return [line for line in text.splitlines() if str(obj) not in line]


def ios_version(target):
    return int(target.split("-ios")[1].split(".")[0])


def cases():
    for name in SOURCES:
        for target in TARGETS:
            if name in NEEDS_CONSTANT_LITERALS and ios_version(target) < 14:
                continue
            for optimization in OPTIMIZATIONS:
                yield name, target, optimization, f"{Path(name).stem}.{target}{optimization}"


def write_sources(out):
    source = out / "src"
    source.mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (source / name).write_text(text)
    return source


def xcode(out):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    clang = str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
    source = write_sources(out)
    objects = out / "xcode"
    objects.mkdir(exist_ok=True)
    for name, target, optimization, stem in cases():
        compiled, errors = compile_objc(clang, developer, source / name, target, optimization, objects / f"{stem}.o")
        if not compiled:
            sys.exit(errors)
    for stem in LINKED:
        link(clang, developer, objects / f"{stem}.o", objects / f"{stem}.dylib")
    print(f"{len(list(objects.glob('*.o')))} objects and {len(LINKED)} dylibs in {objects}")


def run(out, developer):
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    clang, nm, objdump = str(bin_dir / "clang"), str(bin_dir / "llvm-nm"), str(bin_dir / "llvm-objdump")
    source = write_sources(out)
    scratch = out / "scratch"
    scratch.mkdir(exist_ok=True)
    report = {}
    for name, target, optimization, stem in cases():
        if not (Path(sdk_for(developer, target)) / "System/Library/Frameworks/Foundation.framework/Headers/Foundation.h").is_file():
            print(f"{stem}: skipped, the SDK has no Foundation headers")
            continue
        ours, reference = scratch / f"{stem}.o", out / "xcode" / f"{stem}.o"
        if not compile_objc(clang, developer, source / name, target, optimization, ours)[0]:
            report[stem] = {"compiles": False}
            print(f"{stem}: does not compile")
            continue
        report[stem] = {
            "onlyXcode": sorted(set(symbols(nm, reference)) - set(symbols(nm, ours))),
            "onlyOurs": sorted(set(symbols(nm, ours)) - set(symbols(nm, reference))),
            "sections": sections(objdump, ours) == sections(objdump, reference),
            "code": code(objdump, ours) == code(objdump, reference),
        }
        result = report[stem]
        same = not result["onlyXcode"] and not result["onlyOurs"]
        print(f"{stem}: symbols {'identical' if same else 'differ'}, sections {'identical' if result['sections'] else 'differ'}, "
              f"code and data {'identical' if result['code'] else 'differ'}")
    for stem in LINKED:
        if stem not in report or not report[stem].get("compiles", True):
            continue
        link(clang, developer, scratch / f"{stem}.o", scratch / f"{stem}.dylib")
        ours = sorted(segments(objdump, scratch / f"{stem}.dylib"))
        reference = sorted(segments(objdump, out / "xcode" / f"{stem}.dylib"))
        report[stem]["linkedSections"] = ours == reference
        print(f"{stem}.dylib: sections and their segments {'identical' if ours == reference else 'differ'}"
              + ("" if ours == reference else f" ({sorted(set(reference) - set(ours))} only in Xcode's)"))
    (out / "run.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        xcode(Path(sys.argv[2]).resolve())
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        run(Path(sys.argv[2]).resolve(), sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

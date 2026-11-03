#!/usr/bin/env python3
"""What Xcode 27.0's ld links otherwise than a developer directory's ld64.lld, on the same objects
(lld patches 0014 to 0027): where Objective-C references go, which archive members load and where
they go, linker optimization hints, -alias of a dylib's symbol, the order of the segments'
sections, category merging, with and without +load methods, the merged categories' and method
lists' layout, the GOT's order, literals, class references whose address is taken, and the layout
of __unwind_info.

Xcode's ld puts class, protocol and superclass references in __DATA_CONST from iOS 17.4 and loads
classes through the GOT from iOS 18 (no __objc_classrefs; a class of the image is addressed
directly). For archives it loads the members of the undefined symbols in sorted order, round by
round, so a member with a weak definition can win over one with the strong definition. It applies
no linker optimization hint, and an -alias of a dylib's symbol is a re-export of it. In
__unwind_info only the encodings of more than one entry are common, by descending frequency then
ascending encoding; the index reserves an entry per 511 entries and two more, each second-level page
takes its own size rounded up to 8 bytes, and the sentinel is one byte past the last function.

Usage:
  ld_layout_experiments.py xcode <out>                Mac: compiles and links with Xcode (DEVELOPER_DIR);
                                                     writes <out>/objects, <out>/xcode and <out>/xcode.json
  ld_layout_experiments.py run <out> <developer-dir>  links <out>/objects with the developer directory's
                                                     clang and lld; writes <out>/run.json, prints the
                                                     differences
"""

import hashlib
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

OBJC = """#import <Foundation/Foundation.h>
@protocol P <NSObject> - (void)p; @end
@interface Base : NSObject @end
@implementation Base - (id)init { return [super init]; } @end
@interface Sub : Base <P> @end
@implementation Sub - (id)init { return [super init]; } - (void)p {} @end
int main(void) {
  id a = [NSString new]; id b = [Sub new]; Protocol *pr = @protocol(P);
  return (int)([a hash] + [b hash] + (long)pr);
}
"""

ARCHIVE = {
    "strong.c": "int mm_set(void) { return 1; }\n",
    "weak.c": "__attribute__((weak)) int mm_set(void) { return 2; }\nint kk_other(void) { return 3; }\n",
    "first.c": "int mm_set(void);\nint aa_entry(void) { return mm_set(); }\n",
    "second.c": "int kk_other(void);\nint zz_entry(void) { return kk_other(); }\n",
    "main.c": "int aa_entry(void); int zz_entry(void);\nint main(void) { return aa_entry() + zz_entry(); }\n",
}

HINTS = {
    "hints.c": """extern int ext_var;
static int local_var = 3;
const char *str(void) { return "hello"; }
int load_local(void) { return local_var; }
int load_ext(void) { return ext_var; }
int *addr_ext(void) { return &ext_var; }
int main(void) { return str()[0] + load_local() + load_ext() + *addr_ext(); }
""",
    "ext.c": "int ext_var = 5;\n",
    "helper.c": "int helper(void) { return 1; }\n",
}

ORDER = {
    "first.c": """__attribute__((section("__DATA,__zzz"))) int z1 = 1;
__attribute__((section("__DATA,__aaa"))) int a1 = 2;
int d1 = 3;
int b1;
__attribute__((section("__DATA_CONST,__yyy"))) const int y1 = 4;
const char *const cp = "x";
int *const ptr = &d1;
__attribute__((section("__DATA,__mmm"))) int m1 = 5;
int entry(void) { return 0; }
""",
    "second.c": """__attribute__((section("__DATA,__mmm"))) int m2 = 6;
__attribute__((section("__DATA,__bbb"))) int b2 = 7;
__attribute__((section("__DATA_CONST,__ccc"))) const int c2 = 8;
__thread int t1 = 9;
__thread int t2;
static int big[1000];
int *bigp(void) { return big; }
""",
    "literals.m": """#import <Foundation/Foundation.h>
@interface Lit : NSObject @end
@implementation Lit
+ (id)values { return @[@1, @2.5, @{@"k": @3.0f}]; }
@end
@interface Lit (Cat) @end
@implementation Lit (Cat) + (void)load {} @end
""",
    "profile.c": """__thread int tv = 1;
__thread int tz;
int f(int x) { return x ? tv : tz; }
__attribute__((section("__DATA,__late"))) int late = 1;
int entry(void) { return f(1); }
""",
    "text.cpp": """#include <os/log.h>
extern const int ta, tab[4];
__attribute__((section("__TEXT,__aaa"))) const int ta = 1;
const int tab[4] = {1, 2, 3, 4};
void thrower();
void logged(int x) { os_log(OS_LOG_DEFAULT, "x %d", x); }
int caught() { try { thrower(); } catch (int) { return 1; } return 0; }
void thrower() { throw 1; }
""",
    "init.cpp": """#include <cstdio>
struct S { S() { std::puts("s"); } ~S() { std::puts("~s"); } };
S s;
__attribute__((constructor)) static void ctor() {}
""",
}
CATEGORIES = {
    "category-a.m": "#import <Foundation/Foundation.h>\n@implementation NSObject (A)\n- (void)a {}\n@end\n",
    "category-b.m": "#import <Foundation/Foundation.h>\n@implementation NSObject (B)\n- (void)b {}\n+ (void)cb {}\n@end\n",
    "category-own.m": """#import <Foundation/Foundation.h>
@interface Mine : NSObject @end
@implementation Mine - (void)m {} @end
@interface Mine (C) @end
@implementation Mine (C) - (void)c {} @end
int main(void) { return 0; }
""",
}

METADATA = {
    "category-lists.m": """#import <Foundation/Foundation.h>
@protocol Q - (void)q; @end
@protocol R - (void)r; @end
@interface P5 : NSObject <Q> @property int five; @end
@implementation P5 - (void)q {} @end
@interface P5 (M) @end
@implementation P5 (M) - (void)m {} @end
@interface P6 : NSObject @end
@implementation P6 - (void)six {} @end
@interface P6 (N) <R> @property int en; @end
@implementation P6 (N) - (void)r {} - (int)en { return 1; } - (void)setEn:(int)v {} @end
@interface NSObject (D1) <R> @property int d1; @end
@implementation NSObject (D1) - (void)r {} - (int)d1 { return 1; } - (void)setD1:(int)v {} @end
@interface NSObject (D2) <Q> @property int d2; @end
@implementation NSObject (D2) - (void)q {} - (int)d2 { return 1; } - (void)setD2:(int)v {} @end
int main(void) { return 0; }
""",
    "methlist-1.m": """#import <Foundation/Foundation.h>
@interface Zed : NSObject @end
@implementation Zed - (void)z {} + (void)cz {} @end
@interface Abe : NSObject @end
@implementation Abe - (void)a {} @end
int main(void) { return 0; }
""",
    "methlist-2.m": """#import <Foundation/Foundation.h>
@protocol Aaa - (void)p; @end
@interface Mid : NSObject <Aaa> @end
@implementation Mid - (void)p {} - (void)m {} @end
""",
}
METADATA_LINKS = {"category lists": ["category-lists"], "method lists": ["methlist-1", "methlist-2"],
                  "method lists reversed": ["methlist-2", "methlist-1"]}

LOAD_CATEGORIES = {
    "load-own.m": """#import <Foundation/Foundation.h>
@interface Own : NSObject @end
@implementation Own - (void)m {} @end
@interface Own (L) @end
@implementation Own (L) + (void)load {} - (void)l {} @end
int main(void) { return 0; }
""",
    "load-own2.m": """#import <Foundation/Foundation.h>
@interface Own2 : NSObject @end
@implementation Own2 + (void)load {} - (void)m {} @end
@interface Own2 (L) @end
@implementation Own2 (L) + (void)load {} - (void)l {} @end
""",
    "load-own3.m": """#import <Foundation/Foundation.h>
@interface Own3 : NSObject @end
@implementation Own3 + (void)load {} - (void)m {} @end
@interface Own3 (N) @end
@implementation Own3 (N) - (void)n {} @end
""",
    "load-own4.m": """#import <Foundation/Foundation.h>
@interface Own4 : NSObject @end
@implementation Own4 - (void)m {} @end
@interface Own4 (A) @end
@implementation Own4 (A) + (void)load {} - (void)a {} @end
@interface Own4 (B) @end
@implementation Own4 (B) - (void)b {} @end
""",
    "load-ext.m": """#import <Foundation/Foundation.h>
@implementation NSObject (EL) + (void)load {} - (void)el {} @end
@implementation NSObject (EN) - (void)en {} @end
""",
    "load-ext2.m": """#import <Foundation/Foundation.h>
@implementation NSString (S1) + (void)load {} - (void)s1 {} @end
@implementation NSString (S2) + (void)load {} - (void)s2 {} @end
""",
    "load-ext3.m": """#import <Foundation/Foundation.h>
@implementation NSArray (P1) - (void)p1 {} @end
@implementation NSArray (P2) - (void)p2 {} @end
@implementation NSArray (PL) + (void)load {} - (void)pl {} @end
""",
}
LOAD_LINKS = [["own"], ["own", "own2"], ["own", "ext"], ["own", "ext2"], ["own", "ext3"], ["own", "own3"],
              ["own", "own4"]]



def leaf(name, size):
    return f"int {name}(int x) {{ volatile char b[{size}]; b[x] = 1; return b[0]; }}"


def framed(name, i=1):
    return f"void {name}(int x) {{ g(x); g(x + {i}); }}"


def alternating(n):
    return [line for i in range(n) for line in (f"int a{i}(int x) {{ return x * {i + 3}; }}", framed(f"b{i}", i))]


def sizes(n, rounds):
    return [line for r in range(rounds) for i in range(n) for line in (leaf(f"s{i}_{r}", 16 * (i + 1)),
                                                                       framed(f"t{i}_{r}", i))]


UNWIND = {
    "one": [],
    "alternating 2": alternating(2),
    "alternating 600": alternating(600),
    "alternating 3000": alternating(3000),
    "sizes 50": sizes(50, 1),
    "sizes 200x4": sizes(200, 4),
    "sizes 600": sizes(600, 1),
    "ties": [leaf("p0", 32), framed("q0"), leaf("p1", 32), framed("q1"), leaf("p2", 16), framed("q2"), leaf("p3", 16),
             framed("q3")],
    "folded": [leaf("x0", 48), leaf("x1", 48), leaf("x2", 48), framed("q0"), leaf("y0", 64), framed("q1"),
               leaf("y1", 64), framed("q2")],
    "far": [framed("q0"), leaf("p0", 32), 'void big(void) { __asm__ volatile(".space 0x1000010"); }', framed("q1"),
            leaf("p1", 32)],
}
UNWIND_CALLEE = "void g(int x) { (void)x; }\nvoid h(void) {}\n"
UNWIND_CXX = """extern "C" void h(); struct T { ~T(); }; T::~T() { h(); }
void f1() { T t; h(); } void f2() { T t; h(); h(); } int f3(int x) { return x; }
int f4() { try { h(); } catch (int) { return 1; } return 0; }
int main() { try { f1(); f2(); } catch (...) { return 1; } return f3(2) + f4(); }
"""

GOT = {
    "got.s": """	.section	__TEXT,__const
	.p2align	2
_refs:
	.long	_zloc@GOT - .
	.long	_malloc@GOT - .
	.long	_zglob@GOT - .
	.long	__ZTIi@GOT - .
	.long	_zhid@GOT - .
	.long	__Znwm@GOT - .
	.long	_aloc@GOT - .
	.long	___cxa_end_catch@GOT - .
	.long	_aglob@GOT - .
	.long	__Unwind_Resume@GOT - .
	.long	_ahid@GOT - .
	.long	_free@GOT - .
	.long	_zweak@GOT - .
	.long	_aweak@GOT - .
	.long	_refs@GOT - .
	.section	__DATA,__data
	.p2align	3
_zloc:	.quad 1
_aloc:	.quad 2
	.globl	_zhid
	.private_extern	_zhid
_zhid:	.quad 3
	.globl	_ahid
	.private_extern	_ahid
_ahid:	.quad 4
	.globl	_zweak
	.weak_definition	_zweak
_zweak:	.quad 5
	.globl	_aweak
	.weak_definition	_aweak
_aweak:	.quad 6
	.subsections_via_symbols
""",
    "got-weak.s": """	.section	__TEXT,__const
	.p2align	2
_refs4:
	.long	_hw_b@GOT - .
	.long	_hw_a@GOT - .
	.long	_bb_loc@GOT - .
	.section	__DATA,__data
	.p2align	3
	.globl	_hw_b
	.private_extern	_hw_b
	.weak_definition	_hw_b
_hw_b:	.quad 1
	.globl	_hw_a
	.private_extern	_hw_a
	.weak_definition	_hw_a
_hw_a:	.quad 2
_bb_loc:	.quad 3
	.subsections_via_symbols
""",
    "got-defs.c": "long zglob = 7, aglob = 8;\nint main(void) { return 0; }\n",
}
GOT_LINKS = {
    "got": (["got", "got-weak", "got-defs"], ["-lc++"]),
    "got libSystem first": (["got", "got-defs"], ["-lSystem", "-lc++"]),
}
CLASS_REFERENCES = {"class-references.s": """	.section	__TEXT,__text,regular,pure_instructions
	.globl	_main
	.p2align	2
_main:
	adrp	x8, _ref_ns@PAGE
	add	x8, x8, _ref_ns@PAGEOFF
	adrp	x9, _ref_own@PAGE
	add	x9, x9, _ref_own@PAGEOFF
	adrp	x10, _ref_ns2@PAGE
	ldr	x10, [x10, _ref_ns2@PAGEOFF]
	adrp	x11, _ref_own2@PAGE
	ldr	x11, [x11, _ref_own2@PAGEOFF]
	adrp	x12, _ref_own3@PAGE
	ldr	x12, [x12, _ref_own3@PAGEOFF]
	mov	w0, #0
	ret
	.section	__DATA,__objc_classrefs,regular,no_dead_strip
	.p2align	3
_ref_ns:
	.quad	_OBJC_CLASS_$_NSObject
_ref_own:
	.quad	_OBJC_CLASS_$_Own
_ref_ns2:
	.quad	_OBJC_CLASS_$_NSString
_ref_own2:
	.quad	_OBJC_CLASS_$_Own
_ref_own3:
	.quad	_OBJC_CLASS_$_Own3
	.subsections_via_symbols
""", "class-references-own.m": """#import <Foundation/Foundation.h>
@interface Own : NSObject @end
@implementation Own @end
@interface Own3 : NSObject @end
@implementation Own3 @end
"""}
MEMBER_ORDER = {f"member-{name}.c": text for name, text in {
    "a": """int a(void) { return 1; }
""",
    "b": """int a(void); int b(void) { return a() + 2; }
""",
    "c": """int b(void); int d(void); int c(void) { return b() + d(); }
""",
    "d": """int d(void) { return 4; }
""",
    "main": """int c(void); int main(void) { return c(); }
""",
    "other": """int other(void) { return 5; }
""",
}.items()}
MEMBER_LINKS = {"members": ["main", "lib", "other", "lib2"],
                "members second archive first": ["main", "lib2", "lib", "other"]}
LOAD_COMMANDS = {
    "lc-main.c": """void *z(void); int main(void) { return z() != 0; }
""",
    "lc-use.m": """#include <zlib.h>
#include <sqlite3.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
void *z(void) { (void)zlibVersion(); (void)sqlite3_libversion(); [UIView new]; return (__bridge void *)[AVPlayer new]; }
""",
    "lc-autolink.s": """	.linker_option "-framework", "Zzz"
	.linker_option "-lz"
	.linker_option "-framework", "UIKit"
	.linker_option "-framework", "AAA"
	.linker_option "-lsqlite3"
	.linker_option "-framework", "AVFoundation"
	.globl _main
	.p2align 2
_main:
	bl _AAA
	bl _Zzz
	bl _zlibVersion
	bl _sqlite3_libversion
	mov w0, #0
	ret
	.section __DATA,__data
	.p2align 3
	.quad _OBJC_CLASS_$_UIView
	.quad _OBJC_CLASS_$_AVPlayer
	.subsections_via_symbols
""",
    "lc-lib.m": "#import <Foundation/Foundation.h>\nint lib(void) { return (int)[NSObject new].hash; }\n",
}
LOAD_COMMAND_LINKS = {
    "load commands explicit": ["lc-main", "lc-use", "-lz", "-lsqlite3", "-framework", "UIKit", "-framework",
                               "AVFoundation", "-framework", "Foundation"],
    "load commands explicit reordered": ["lc-use", "lc-main", "-framework", "Foundation", "-framework", "AVFoundation",
                                         "-lsqlite3", "-framework", "UIKit", "-lz"],
    "load commands autolinked": ["lc-autolink", "-Wl,-rpath,@executable_path/Frameworks"],
    "load commands dylib": ["lc-lib", "-dynamiclib", "-install_name", "@rpath/L.framework/L",
                            "-Wl,-rpath,@executable_path/Frameworks", "-framework", "Foundation", "-lobjc"],
    "load commands bundle": ["lc-main", "lc-use", "-bundle", "-framework", "UIKit", "-framework", "AVFoundation",
                             "-framework", "Foundation", "-lz", "-lsqlite3"],
}
LITERALS = {"literals-1.c": """double f1(double x) { return x * 3.14159; }
float g1(float x) { return x * 1.1f; }
extern const int c1[3]; const int c1[3] = {1, 2, 3};
typedef float v4 __attribute__((ext_vector_type(4)));
v4 h1(v4 x) { return x * (v4){1.5f, 2.5f, 3.5f, 4.5f}; }
int main(void) { return 0; }
""", "literals-2.c": """double f2(double x) { return x * 3.14159 + 2.71828; }
float g2(float x) { return x * 1.1f + 2.2f; }
extern const int c2[2]; const int c2[2] = {9, 8};
typedef float v4 __attribute__((ext_vector_type(4)));
v4 h2(v4 x) { return x * (v4){1.5f, 2.5f, 3.5f, 4.5f}; }
"""}

ORDER_TARGETS = ["arm64-apple-ios18.0", "arm64-apple-ios12.0"]

OBJC_TARGETS = ["arm64-apple-ios17.0", "arm64-apple-ios17.4", "arm64-apple-ios18.0", "arm64-apple-ios18.6",
                "x86_64-apple-ios18.0-simulator", "arm64-apple-ios17.4-simulator"]
ARCHIVE_TARGET = "arm64-apple-ios18.0"


def sdk_for(developer, target):
    platform = "iPhoneSimulator" if target.endswith("-simulator") else "iPhoneOS"
    return str(Path(developer) / f"Platforms/{platform}.platform/Developer/SDKs/{platform}.sdk")


def tool(developer, name):
    return str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin" / name)


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, check=True, **kwargs).stdout


def has_foundation(developer, target):
    return (Path(sdk_for(developer, target)) / "System/Library/Frameworks/Foundation.framework").is_dir()


def compile_objects(developer, out):
    objects = out / "objects"
    objects.mkdir(parents=True, exist_ok=True)
    (objects / "objc.m").write_text(OBJC)
    for target in OBJC_TARGETS:
        run([tool(developer, "clang"), "-target", target, "-isysroot", sdk_for(developer, target), "-fobjc-arc", "-Os",
             "-c", str(objects / "objc.m"), "-o", str(objects / f"objc.{target}.o")])
    for name, text in {**ARCHIVE, **HINTS, **CATEGORIES, **LOAD_CATEGORIES, **METADATA, **GOT,
                       **CLASS_REFERENCES, **LOAD_COMMANDS}.items():
        (objects / name).write_text(text)
        run([tool(developer, "clang"), "-target", ARCHIVE_TARGET, "-isysroot", sdk_for(developer, ARCHIVE_TARGET), "-Os",
             "-fobjc-arc", "-c", str(objects / name), "-o", str(objects / (Path(name).stem + ".o"))])
    entry = "int main(void) { return 0; }\n"
    for name in ("lc-main.c", "lc-use.m"):
        run([tool(developer, "clang"), "-target", "arm64-apple-ios12.0", "-isysroot",
             sdk_for(developer, ARCHIVE_TARGET), "-Os", "-fobjc-arc", "-c", str(objects / name),
             "-o", str(objects / (Path(name).stem + "-ios12.o"))])
    sources = {f"unwind-{name.replace(' ', '-')}.c": "\n".join(["void g(int);", *lines, entry])
               for name, lines in UNWIND.items()}
    sources.update({"unwind-callee.c": UNWIND_CALLEE, "unwind-cxx.cpp": UNWIND_CXX, **LITERALS, **MEMBER_ORDER})
    for name, text in sources.items():
        (objects / name).write_text(text)
        run([tool(developer, "clang"), "-target", ARCHIVE_TARGET, "-isysroot", sdk_for(developer, ARCHIVE_TARGET),
             "-Os", "-fno-stack-protector", "-c", str(objects / name), "-o", str(objects / (Path(name).stem + ".o"))])


def compile_order_objects(developer, objects):
    for target in ORDER_TARGETS:
        for name, text in ORDER.items():
            source = objects / f"order-{name}"
            source.write_text(text)
            profile = ["-fprofile-instr-generate", "-fcoverage-mapping"] if name == "profile.c" else []
            run([tool(developer, "clang"), "-target", target, "-isysroot", sdk_for(developer, target), "-Os",
                 "-fobjc-arc", "-Wno-#warnings"] + profile + ["-c", str(source),
                 "-o", str(objects / f"order-{Path(name).stem}.{target}.o")])


def link_order(developer, objects, products):
    clang = tool(developer, "clang")
    links = {
        "order ios18": ("arm64-apple-ios18.0", ["first", "second", "literals", "objc"]),
        "order ios18 reversed": ("arm64-apple-ios18.0", ["objc", "literals", "second", "first"]),
        "order ios12": ("arm64-apple-ios12.0", ["init", "first", "second", "literals"]),
        "order profile": ("arm64-apple-ios18.0", ["profile"]),
        "order text": ("arm64-apple-ios18.0", ["text", "init", "first", "literals", "objc"]),
    }
    for name, (target, stems) in links.items():
        inputs = [str(objects / (f"objc.{target}.o" if stem == "objc" else f"order-{stem}.{target}.o"))
                  for stem in stems]
        profile = ["-fprofile-instr-generate"] if stems == ["profile"] else []
        run([clang, "-target", target, "-isysroot", sdk_for(developer, target)] + inputs + profile +
            ["-framework", "Foundation", "-lc++", "-Xlinker", "-e", "-Xlinker", "_entry",
             "-o", str(products / name.replace(" ", "-"))])
    return list(links)


def link_all(developer, out, products):
    objects = out / "objects"
    products.mkdir(parents=True, exist_ok=True)
    clang = tool(developer, "clang")
    for target in OBJC_TARGETS:
        if not has_foundation(developer, target):
            print(f"objc {target}: skipped, the SDK has no Foundation")
            continue
        run([clang, "-target", target, "-isysroot", sdk_for(developer, target), str(objects / f"objc.{target}.o"),
             "-framework", "Foundation", "-o", str(products / f"objc.{target}")])
    archive = products / "lib.a"
    archive.unlink(missing_ok=True)
    run([tool(developer, "libtool"), "-static", "-o", str(archive)] +
        [str(objects / f"{stem}.o") for stem in ("strong", "weak", "first", "second")])
    sdk = sdk_for(developer, ARCHIVE_TARGET)
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(objects / "main.o"), str(archive),
         "-o", str(products / "archive-after")])
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(archive), str(objects / "main.o"),
         "-o", str(products / "archive-before")])
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(objects / "hints.o"), str(objects / "ext.o"),
         "-o", str(products / "hints")])
    link_order(developer, objects, products)
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk] +
        [str(objects / f"category-{stem}.o") for stem in ("own", "a", "b")] +
        ["-framework", "Foundation", "-o", str(products / "categories")])
    for stems in LOAD_LINKS:
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk] +
            [str(objects / f"load-{stem}.o") for stem in stems] +
            ["-framework", "Foundation", "-o", str(products / ("load-" + "-".join(stems)))])
    for name in list(UNWIND) + ["cxx"]:
        stem = "unwind-" + name.replace(" ", "-")
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(objects / f"{stem}.o"),
             str(objects / "unwind-callee.o"), "-lc++", "-o", str(products / stem)])
    for name, stems in METADATA_LINKS.items():
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk] + [str(objects / f"{stem}.o") for stem in stems] +
            ["-framework", "Foundation", "-o", str(products / name.replace(" ", "-"))])
    for name, (stems, flags) in GOT_LINKS.items():
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk] + [str(objects / f"{stem}.o") for stem in stems] +
            flags + ["-o", str(products / name.replace(" ", "-"))])
    for framework in ("AAA", "Zzz"):
        (products / f"F/{framework}.framework").mkdir(parents=True, exist_ok=True)
        (products / f"{framework}.c").write_text(f"int {framework}(void) {{ return 1; }}\n")
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, "-dynamiclib", str(products / f"{framework}.c"),
             "-install_name", f"@rpath/{framework}.framework/{framework}",
             "-o", str(products / f"F/{framework}.framework/{framework}")])
    for name, inputs in LOAD_COMMAND_LINKS.items():
        paths = [str(objects / f"{i}.o") if i.startswith("lc-") else i for i in inputs]
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, *paths, "-F", str(products / "F"),
             "-o", str(products / name.replace(" ", "-"))])
    run([clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk, str(objects / "lc-main-ios12.o"),
         str(objects / "lc-use-ios12.o"), "-framework", "UIKit", "-framework", "AVFoundation", "-framework",
         "Foundation", "-lz", "-lsqlite3",
         "-Wl,-rpath,@executable_path/Frameworks", "-o", str(products / "load-commands-ios12")])
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(objects / "class-references.o"),
         str(objects / "class-references-own.o"), "-framework", "Foundation", "-o", str(products / "class-references")])
    for name, members in {"lib": ["a", "b", "c"], "lib2": ["d"]}.items():
        (products / f"member-{name}.a").unlink(missing_ok=True)
        run([tool(developer, "libtool"), "-static", "-o", str(products / f"member-{name}.a")] +
            [str(objects / f"member-{member}.o") for member in members])
    for name, inputs in MEMBER_LINKS.items():
        paths = [str(products / f"member-{i}.a") if i.startswith("lib") else str(objects / f"member-{i}.o")
                 for i in inputs]
        run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, *paths, "-o", str(products / name.replace(" ", "-"))])
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, str(objects / "literals-1.o"),
         str(objects / "literals-2.o"), "-o", str(products / "literals")])
    run([clang, "-target", ARCHIVE_TARGET, "-isysroot", sdk, "-dynamiclib", str(objects / "helper.o"),
         "-framework", "Foundation", "-Xlinker", "-alias", "-Xlinker", "_NSExtensionMain", "-Xlinker",
         "___debug_main_executable_dylib_entry_point", "-install_name", "@rpath/X.debug.dylib",
         "-o", str(products / "alias.dylib")])


def section_bytes(path, name):
    image = Path(path).read_bytes()
    offset = 32
    for _ in range(struct.unpack_from("<I", image, 16)[0]):
        command, size = struct.unpack_from("<II", image, offset)
        if command == 0x19:
            for index in range(struct.unpack_from("<I", image, offset + 64)[0]):
                header = offset + 72 + 80 * index
                if image[header:header + 16].rstrip(b"\0") == name:
                    length, start = struct.unpack_from("<QI", image, header + 40)
                    return image[start:start + length]
        offset += size
    return b""


def section_names(objdump, path):
    return [line.split()[1] for line in run([objdump, "--macho", "--section-headers", str(path)]).splitlines()
            if line.split()[:1] and line.split()[0].isdigit()]


def got_targets(objdump, path):
    """The GOT's slots in order: the symbol a rebase points to, or dylib/symbol for a bind."""
    image = Path(path).read_bytes()
    got = section_bytes(path, b"__got")
    names = {}
    for line in run([str(Path(objdump).with_name("llvm-nm")), "--defined-only", str(path)]).splitlines():
        fields = line.split()
        names.setdefault(int(fields[0], 16), fields[2])
    dylibs, fixups, offset = [], 0, 32
    for _ in range(struct.unpack_from("<I", image, 16)[0]):
        command, size = struct.unpack_from("<II", image, offset)
        if command in (0xC, 0x80000018, 0x8000001F):
            name = image[offset + struct.unpack_from("<I", image, offset + 8)[0]:offset + size].split(b"\0")[0]
            dylibs.append(name.decode().rsplit("/", 1)[-1].split(".")[0])
        elif command == 0x80000034:
            fixups = struct.unpack_from("<I", image, offset + 8)[0]
        offset += size
    special = {0xFF: "<main>", 0xFE: "<flat-namespace>", 0xFD: "<weak-def-coalesce>"}
    slots = []
    _, _, imports, symbols, _, _, _ = struct.unpack_from("<7I", image, fixups)
    for index in range(len(got) // 8):
        value = struct.unpack_from("<Q", got, 8 * index)[0]
        if value >> 63:
            entry = struct.unpack_from("<I", image, fixups + imports + 4 * (value & 0xFFFFFF))[0]
            ordinal, name_offset = entry & 0xFF, entry >> 9
            name = image[fixups + symbols + name_offset:].split(b"\0")[0].decode()
            slots.append(f"{special.get(ordinal) or dylibs[ordinal - 1]}/{name}")
        else:
            target = value & 0xFFFFFFFFF
            slots.append(names.get(target, names.get(target + 0x100000000, hex(target))))
    return slots


def unwind_layout(path):
    """__unwind_info's counts, the gap after its index, its pages, and a digest of its bytes."""
    data = section_bytes(path, b"__unwind_info")
    _, _, commons, _, personalities, index_offset, indices = struct.unpack_from("<7I", data)
    index = [struct.unpack_from("<3I", data, index_offset + 12 * k) for k in range(indices)]
    pages = []
    for _, page, _ in index[:-1]:
        kind, _, entries, _, local = struct.unpack_from("<IHHHH", data, page)
        if kind == 3:
            pages.append(f"compressed at {page:#x}: {entries} entries, {local} local")
        else:
            pages.append(f"regular at {page:#x}: {entries} entries")
    return {"size": hex(len(data)), "common": commons, "personalities": personalities,
            "gap after index": index[0][2] - index_offset - 12 * indices, "sentinel": hex(index[-1][0]), "pages": pages,
            "sha256": hashlib.sha256(data).hexdigest()[:16]}


def describe(objdump, products):
    """Per product: its data sections with their segments, the mnemonics of main, and the exported
    mm_set with its flags."""
    report = {}
    for target in OBJC_TARGETS:
        binary = str(products / f"objc.{target}")
        if not Path(binary).exists():
            continue
        sections, section = [], None
        for line in run([objdump, "--macho", "--private-headers", binary]).splitlines():
            fields = line.split()
            if fields[:1] == ["sectname"]:
                section = fields[1]
            elif fields[:1] == ["segname"] and section:
                if "DATA" in fields[1]:
                    sections.append(f"{fields[1]},{section}")
                section = None
        sections.sort()
        disassembly = run([objdump, "--macho", "--disassemble-symbols=_main", "--no-show-raw-insn", binary])
        mnemonics = [line.split()[1] for line in disassembly.splitlines() if re.match(r"\s*[0-9a-f]+:\s", line)]
        report[f"objc {target}"] = {"sections": sections, "main": " ".join(mnemonics)}
    for name in ("archive-after", "archive-before"):
        exports = run([objdump, "--macho", "--exports-trie", str(products / name)])
        report[name] = [line.split(None, 1)[1] for line in exports.splitlines() if "_mm_set" in line]
    disassembly = run([objdump, "--macho", "-d", "--no-show-raw-insn", str(products / "hints")])
    report["hints"] = " ".join(line.split()[1] for line in disassembly.splitlines()
                               if re.match(r"\s*[0-9a-f]+:\s", line))
    alias = str(products / "alias.dylib")
    exports = run([objdump, "--macho", "--exports-trie", alias])
    symbols = run([objdump, "--macho", "--syms", alias])
    report["alias exports"] = sorted(line.split(None, 1)[1] if line.split()[0].startswith("0x") else line.strip()
                                     for line in exports.splitlines()[1:] if line.strip())
    for name in ("order ios18", "order ios18 reversed", "order ios12", "order profile", "order text"):
        sections, section = [], None
        for line in run([objdump, "--macho", "--private-headers", str(products / name.replace(" ", "-"))]).splitlines():
            fields = line.split()
            if fields[:1] == ["sectname"]:
                section = fields[1]
            elif fields[:1] == ["segname"] and section:
                if fields[1].startswith(("__TEXT", "__DATA")):
                    sections.append(f"{fields[1]},{section}")
                section = None
        report[name] = sections
    categories = str(products / "categories")
    headers = run([objdump, "--macho", "--section-headers", categories])
    for stems in LOAD_LINKS:
        image = str(products / ("load-" + "-".join(stems)))
        headers = run([objdump, "--macho", "--section-headers", image])
        lists = sorted(" ".join(line.split()[1:3]) for line in headers.splitlines()
                       if re.search(r"objc_(nl)?(cat|cls|class)list", line))
        names = sorted(line.split()[-1] for line in run([objdump, "--macho", "--syms", image]).splitlines()
                       if "METHODS" in line or "CATEGORY" in line)
        report[f"+load {' '.join(stems)}"] = {"lists": lists, "symbols": names}
    report["categories lists"] = sorted(" ".join(line.split()[1:3]) for line in headers.splitlines()
                                        if "objc_catlist" in line or "objc_classlist" in line)
    report["categories symbols"] = sorted(line.split()[-1] for line in run([objdump, "--macho", "--syms", categories]).splitlines()
                                          if "METHODS" in line or "CATEGORY" in line)
    for name in ["categories"] + list(METADATA_LINKS):
        image = str(products / name.replace(" ", "-"))
        headers = run([objdump, "--macho", "--section-headers", image]).splitlines()
        report[f"{name} layout"] = {
            "sizes": [" ".join(line.split()[1:3]) for line in headers if re.search(r"__objc_(methlist|const)\b", line)],
            "symbols": [name for _, name in sorted(
                (int(line.split()[0], 16), line.split()[-1])
                for line in run([objdump, "--macho", "--syms", image]).splitlines()
                if re.search(r"OBJC_(\$_|CLASS_PROTOCOLS)", line))]}
    for name in GOT_LINKS:
        report[name] = got_targets(objdump, products / name.replace(" ", "-"))
    for name in MEMBER_LINKS:
        symbols = run([str(Path(objdump).with_name("llvm-nm")), "-n", str(products / name.replace(" ", "-"))])
        report[name] = [line.split()[-1] for line in symbols.splitlines() if " T " in line]
    for name in list(LOAD_COMMAND_LINKS) + ["load commands ios12"]:
        headers = run([objdump, "--macho", "--private-headers", str(products / name.replace(" ", "-"))])
        commands, command = [], None
        for line in headers.splitlines():
            fields = line.split()
            if fields[:1] == ["cmd"]:
                command = fields[1]
                commands.append(command)
            elif fields[:1] == ["name"] and command and "DYLIB" in command or fields[:1] == ["path"]:
                commands[-1] += " " + fields[1].rsplit("/", 1)[-1]
            elif fields[:1] == ["version"] and command == "LC_SOURCE_VERSION":
                commands[-1] += " " + fields[1]
        report[name] = commands
    references = str(products / "class-references")
    disassembly = run([objdump, "--macho", "--disassemble-symbols=_main", "--no-show-raw-insn", references])
    report["class references"] = {
        "sections": section_names(objdump, references),
        "main": [line.split(":", 1)[1].split(";")[0].strip() for line in disassembly.splitlines()
                 if re.match(r"\s*[0-9a-f]+:\s", line)],
        "got": got_targets(objdump, products / "class-references")}
    literals = str(products / "literals")
    report["literals"] = {"sections": section_names(objdump, literals),
                          "const": section_bytes(literals, b"__const").hex()}
    for name in list(UNWIND) + ["cxx"]:
        report[f"unwind {name}"] = unwind_layout(products / ("unwind-" + name.replace(" ", "-")))
    report["alias symbols"] = sorted(" ".join(line.split()[1:]) for line in symbols.splitlines()
                                     if "NSExtensionMain" in line or "debug_main" in line)
    return report


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        out = Path(sys.argv[2]).resolve()
        developer = os.environ.get("DEVELOPER_DIR") or run(["xcode-select", "-p"]).strip()
        compile_objects(developer, out)
        compile_order_objects(developer, out / "objects")
        link_all(developer, out, out / "xcode")
        print(f"objects and Xcode's products in {out}")
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        out = Path(sys.argv[2]).resolve()
        developer = sys.argv[3]
        link_all(developer, out, out / "lld")
        objdump = tool(developer, "llvm-objdump")
        expected = describe(objdump, out / "xcode")
        report = describe(objdump, out / "lld")
        (out / "run.json").write_text(json.dumps({"xcode": expected, "lld": report}, indent=2) + "\n")
        cases = [case for case in expected if case in report]
        differences = [case for case in cases if report[case] != expected[case]]
        for case in differences:
            print(f"{case}: Xcode's {expected[case]}\n    lld's {report[case]}")
        print(f"{len(cases) - len(differences)} of {len(cases)} cases as Xcode's ld")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

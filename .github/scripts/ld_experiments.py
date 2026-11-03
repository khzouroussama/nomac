#!/usr/bin/env python3
"""Which load commands a linker writes for self-written library stubs, one property varied at a time.

The iOS 27.0 SDK's `libswift_Builtin_float.tbd` (versions 0) is re-exported by
`libswiftDarwin.tbd` (428.0.10) and says `$ld$previous$/usr/lib/swift/libswiftDarwin.dylib$$2$12.2$18.0$$`;
Xcode's `ld` and lld then write `libswiftDarwin` with other versions (docs/BACKLOG.md B-116). These
variants isolate the rule with stubs of the same shape, a parent `libP` re-exporting a child `libC`.

Usage:
  ld_experiments.py <output-dir>                   on a Mac: compile main.o, link it with Xcode's ld
                                                   (DEVELOPER_DIR selects the Xcode), write xcode.json
  ld_experiments.py <output-dir> --lld <lld>       anywhere: link the same main.o with lld, write lld.json
                                                   (a toolchain's `ld64.lld`: as clang runs it)

Each variant gets <output-dir>/<name>/ with its sysroot of stubs and, per linker, the dylib and a JSON
record: the exit status, the libraries the dylib loads (command, name, current and compatibility
versions) and the library each import binds to, and whether it is weak. `summary.txt` lists them
side by side.

The `two-owners-*` variants have the iOS SDK's shape for CGFloat at iOS 15.0: CoreGraphics.tbd moves
its symbols to libswiftCoreGraphics with a version ($1.0.0$, to 18.0), libswiftCoreFoundation.tbd
moves CGFloat's to it without one (to 16.0), and libswiftCoreGraphics.tbd re-exports CoreGraphics.
Here `libA` is CoreGraphics, `libB` libswiftCoreFoundation and `libM` libswiftCoreGraphics.

The `fixups-*` variants record whether the image gets chained fixups or dyld's opcodes, with and
without `-undefined dynamic_lookup` (B-187, ADR 0102 item 11); the `init-*` and `tlv` variants list
the sections an initializer and a thread-local variable get; `stabs-relocatable` the debug map of
an image linked from a relocatable object (B-128).
"""

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

def main_c(*used, autolink=(), entry=False):
    """A function that calls the stubs' `used` functions, in an object that autolinks `autolink`; with
    `entry`, a `main` that calls it."""
    lines = [f'__asm__(".linker_option \\"-framework\\", \\"{library[10:]}\\"");' if library.startswith("framework:")
             else f'__asm__(".linker_option \\"-l{library}\\"");' for library in autolink]
    lines += [f"extern int {name}(void);" for name in used]
    lines.append("int f(void) { return " + " + ".join(f"{name}()" for name in used) + "; }")
    if entry:
        lines.append("int main(void) { return f(); }")
    return "\n".join(lines) + "\n"


def stub(install_name, current, compat, symbols, reexports=(), target="arm64-ios"):
    text = (f"--- !tapi-tbd\ntbd-version:     4\ntargets:         [ {target} ]\n"
            f"install-name:    '{install_name}'\ncurrent-version: {current}\ncompatibility-version: {compat}\n")
    if reexports:
        text += f"reexported-libraries:\n  - targets:         [ {target} ]\n    libraries:       [ "
        text += ", ".join(f"'{path}'" for path in reexports) + " ]\n"
    text += f"exports:\n  - targets:         [ {target} ]\n    symbols:         [ "
    text += ", ".join(f"'{symbol}'" for symbol in symbols) + " ]\n...\n"
    return text


PARENT = stub("/usr/lib/libP.dylib", "5", "1", ["_p"], reexports=["/usr/lib/libC.dylib"])
LONE_PARENT = stub("/usr/lib/libP.dylib", "5", "1", ["_p"])
RENAMED = "$ld$previous$/usr/lib/libP.dylib$$2$12.2$18.0$$"
RENAMED_15 = "$ld$previous$/usr/lib/libP.dylib$1.5$2$12.2$18.0$$"
RENAMED_OTHER = "$ld$previous$/usr/lib/libOld.dylib$$2$12.2$18.0$$"
MOVED = "$ld$previous$/usr/lib/libP.dylib$$2$12.2$18.0$_c$"
MOVED_15 = "$ld$previous$/usr/lib/libP.dylib$1.5$2$12.2$18.0$_c$"


def child(previous=None, current="0", compat="0"):
    return stub("/usr/lib/libC.dylib", current, compat, ([previous] if previous else []) + ["_c"])


def variant(parent, child_stub, libs, main=None, minos="15.0", stubs=None, flags=(), kind="-dylib", sections=False):
    return {"stubs": stubs or {"P": parent, "C": child_stub}, "libs": libs, "main": main or main_c("p", "c"), "minos": minos,
            "flags": list(flags), "kind": kind, "sections": sections}



MOVED_A = "$ld$previous$/usr/lib/libM.dylib$1.0.0$2$12.2$18.0$_a$"
MOVED_B = "$ld$previous$/usr/lib/libM.dylib$$2$12.2$16.0$_b$"


def two_owners(libs, used, autolink, destination=True, target="arm64-ios", b_symbol="_b", frameworks=(), a_name="A"):
    def path(name):
        return f"/System/Library/Frameworks/{name}.framework/{name}" if name in frameworks else f"/usr/lib/lib{name}.dylib"
    moved_b = MOVED_B.replace("_b$", b_symbol + "$")
    stubs = {a_name: stub(path(a_name), "2050", "64", [MOVED_A, "_a", "_a2"], target=target),
             "B": stub(path("B"), "120.100", "1", [moved_b, b_symbol], target=target)}
    stubs = {(f"framework:{name}" if name in frameworks else name): text for name, text in stubs.items()}
    if destination:
        stubs["M"] = stub("/usr/lib/libM.dylib", "17", "1", [], reexports=[path(a_name)], target=target)
    return variant(None, None, libs, main_c(*used, autolink=autolink), stubs=stubs)


C_ONLY = main_c("c")
DYNAMIC_LOOKUP = ["-undefined", "dynamic_lookup"]


def lookup(libs=(), main=C_ONLY, minos="15.1", flags=DYNAMIC_LOOKUP, kind="-dylib", sections=False):
    """`libC`'s `_c` used, linked with libSystem, `libs` and `flags`: which dyld information the image
    gets. Xcode's `ld` refuses an image without libSystem when something is left to dynamic lookup."""
    stubs = {"C": child(), "System": stub("/usr/lib/libSystem.B.dylib", "1351", "1", ["dyld_stub_binder", "__tlv_bootstrap"])}
    return variant(None, None, ["-lSystem", *libs], main, minos, stubs=stubs, flags=flags, kind=kind, sections=sections)


INITIALIZER = "__attribute__((constructor)) static void start(void) {}\nint f(void) { return 0; }\n"
THREAD_LOCAL = "__thread int counter;\nint f(void) { return ++counter; }\n"
# A format string where os_log puts it, and a 16-byte constant clang emits as a literal.
OS_LOG_STRING = ('__attribute__((section("__TEXT,__oslogstring,cstring_literals"))) const char message[] = "count %d";\n'
                 '__attribute__((section("__TEXT,__oslogstring,cstring_literals"))) const char again[] = "count %d";\n'
                 'const char *f(int i) { return i ? message : again; }\n')
LITERAL_16 = "typedef float v4 __attribute__((ext_vector_type(4)));\nv4 f(v4 x) { return x * (v4){1.5f, 2.5f, 3.5f, 4.5f}; }\n"
OWN_CSTRINGS = ('__attribute__((section("__TEXT,__nomac_strs,cstring_literals"))) const char a[] = "one";\n'
                '__attribute__((section("__TEXT,__nomac_strs,cstring_literals"))) const char b[] = "one";\n'
                'const char *f(int i) { return i ? a : b; }\n')
# One object of sections-across-objects: a class with a method, a protocol, a C string, an os_log
# string, a string of a custom section and 16-, 8- and 4-byte literals, the same in both objects
# but for the class.
OBJECTS_SOURCE = """#include <objc/NSObject.h>
typedef float v4 __attribute__((ext_vector_type(4)));
@protocol Shared - (void)ping; @end
__attribute__((objc_root_class)) @interface {name} @end
@implementation {name}
- (void)run:(int)x {{}}
@end
__attribute__((section("__TEXT,__oslogstring,cstring_literals"))) const char log{name}[] = "count %d";
__attribute__((section("__TEXT,__nomac_strs,cstring_literals"))) const char own{name}[] = "one";
const char *string{name}(void) {{ return "shared"; }}
v4 scale{name}(v4 x) {{ return x * (v4){{1.5f, 2.5f, 3.5f, 4.5f}}; }}
Protocol *protocol{name}(void) {{ return @protocol(Shared); }}
__attribute__((section("__TEXT,__literal8,8byte_literals"))) const long long eight{name} = 0x1234567812345678;
__attribute__((section("__TEXT,__literal4,4byte_literals"))) const int four{name} = 0x12345678;
"""
# Code nothing references, which uses a class and a selector reference and a C string (an asset catalog's
# GeneratedAssetSymbols.swift: `Bundle(for:)` and the resources' names), linked with -dead_strip.
UNREFERENCED_OBJC = """#include <objc/NSObject.h>
#include <stdio.h>
__attribute__((visibility("hidden"))) id unused(void) { puts("unused string"); return [NSObject new]; }
__attribute__((visibility("hidden"))) SEL unusedSelector(void) { return @selector(unusedSelectorName); }
int f(void) { return 1; }
"""
# An object that autolinks libC and calls it only from code nothing references (rn-bare's
# GeneratedAssetSymbols.o, autolinking SwiftUI for Color(_:bundle:) in unused code).
AUTOLINKED_DEAD = ('__asm__(".linker_option \\"-lC\\"");\nextern int c(void);\n'
                   '__attribute__((visibility("hidden"))) int unused(void) { return c(); }\nint f(void) { return 1; }\n')
NOTHING_USED = "int f(void) { return 1; }\n"
AUTOLINKED_DEAD_FRAMEWORK = AUTOLINKED_DEAD.replace('\\"-lC\\"', '\\"-framework\\", \\"F\\"').replace("c(void)", "fc(void)").replace("return c()", "return fc()")


def reexport_lookup(symbol, libs=(), flags=("-dead_strip",)):
    """libP re-exporting libC, autolinked by an object whose dead code calls `symbol` (`c`, libC's,
    or `p`, libP's own): SwiftUI re-exports SwiftUICore, which defines Color."""
    main = (f'__asm__(".linker_option \\"-lP\\"");\nextern int {symbol}(void);\n'
            f'__attribute__((visibility("hidden"))) int unused(void) {{ return {symbol}(); }}\nint f(void) {{ return 1; }}\n')
    image = lookup(libs, main=main, flags=list(flags))
    image["stubs"] = {**image["stubs"], "P": PARENT}
    return image


def moved_lookup(dead=True, libs=(), flags=("-dead_strip",), restricted=False):
    """SwiftUI's shape at iOS 17: libP re-exports libC, which moves `_c` to libP's install name
    below 18.0 (`$ld$previous$`, SwiftUICore's Color moved to SwiftUI); an object autolinks libP
    and calls `_c`, from dead code or not."""
    image = reexport_lookup("c", libs=libs, flags=flags)
    image["stubs"] = {**image["stubs"], "C": child(MOVED)}
    if restricted:
        # Only libP may link libC, as only SwiftUI and a few others may link SwiftUICore.
        image["stubs"]["C"] = image["stubs"]["C"].replace(
            "exports:", "allowable-clients:\n  - targets:         [ arm64-ios ]\n    clients:         [ P ]\nexports:", 1)
    if not dead:
        image["main"] = image["main"].replace("int f(void) { return 1; }", "int f(void) { return c(); }")
    return image


RESTRICTED_TO_P = "allowable-clients:\n  - targets:         [ arm64-ios ]\n    clients:         [ P ]\nexports:"


def reexport_binding(child_path, restricted=False, autolink_child=None, search=()):
    """libP re-exports a child at `child_path` that defines `_c`, which live code calls: whether the
    import binds to the child or to libP (SwiftUI and SwiftUICore, libswiftDarwin and
    libswift_Builtin_float)."""
    text = stub(child_path, "1", "1", ["_c"])
    if restricted:
        text = text.replace("exports:", RESTRICTED_TO_P, 1)
    stub_key = child_path[:-len(".dylib")] + ".tbd" if child_path.endswith(".dylib") else child_path + ".tbd"
    stubs = {"System": stub("/usr/lib/libSystem.B.dylib", "1351", "1", ["dyld_stub_binder"]),
             "P": stub("/usr/lib/libP.dylib", "5", "1", ["_p"], reexports=[child_path]),
             stub_key: text}
    main = "extern int c(void);\nint f(void) { return c(); }\n"
    if autolink_child:
        # The object also autolinks the child itself, as Swift objects autolink SwiftUICore and
        # libswift_Builtin_float besides SwiftUI and libswiftDarwin.
        main = f'__asm__(".linker_option {autolink_child}");\n' + main
    return variant(None, None, [*search, "-lSystem", "-lP"], main, "15.1", stubs=stubs, flags=["-dead_strip"])


def framework_lookup(main, flags, kind="-dylib", libs=()):
    """lookup()'s image with a framework F exporting `_fc` in its sysroot."""
    image = lookup(libs, main=main, flags=flags, kind=kind)
    image["stubs"] = {**image["stubs"], "framework:F": stub("/System/Library/Frameworks/F.framework/F", "1", "1", ["_fc"])}
    return image
WEAK_THREAD_LOCAL = "__attribute__((weak)) __thread int counter;\nint f(void) { return ++counter; }\n"
HIDDEN_WEAK_THREAD_LOCAL = "__attribute__((weak, visibility(\"hidden\"))) __thread int counter;\nint f(void) { return ++counter; }\n"


def image(main, minos="15.1", flags=(), kind="-dylib", libs=()):
    """An image of `main` (with `libs`), for the sections a linker gives it."""
    return lookup(libs, main=main, minos=minos, flags=flags, kind=kind, sections=True)


def thread_local_library():
    """libT, exporting the thread-local variable `_counter`."""
    return ("--- !tapi-tbd\ntbd-version:     4\ntargets:         [ arm64-ios ]\ninstall-name:    '/usr/lib/libT.dylib'\n"
            "exports:\n  - targets:         [ arm64-ios ]\n    thread-local-symbols: [ '_counter' ]\n...\n")


VARIANTS = {
    # The SDK's shape: the child, renamed to its parent for the deployment target, re-exported by it.
    "renamed-reexport": variant(PARENT, child(RENAMED), ["-lP"]),
    "renamed-reexport-outside-range": variant(PARENT, child(RENAMED), ["-lP"], minos="18.0"),
    "reexport": variant(PARENT, child(), ["-lP"]),
    "renamed-reexport-other-name": variant(PARENT, child(RENAMED_OTHER), ["-lP"]),
    "renamed-reexport-versions": variant(PARENT, child(RENAMED, "7", "3"), ["-lP"]),
    # Both linked: which file's versions the shared install name gets.
    "renamed-child-linked-first": variant(PARENT, child(RENAMED), ["-lC", "-lP"]),
    "renamed-parent-linked-first": variant(PARENT, child(RENAMED), ["-lP", "-lC"]),
    "renamed-compat-child-linked-first": variant(LONE_PARENT, child(RENAMED_15, "7", "3"), ["-lC", "-lP"]),
    "renamed-compat-parent-linked-first": variant(LONE_PARENT, child(RENAMED_15, "7", "3"), ["-lP", "-lC"]),
    "renamed-both-linked-child-used": variant(LONE_PARENT, child(RENAMED, "7", "3"), ["-lC", "-lP"], C_ONLY),
    # The child alone: the rename, with and without a compatibility version.
    "renamed-direct": variant(LONE_PARENT, child(RENAMED, "3", "2"), ["-lC"], C_ONLY),
    "renamed-direct-compat": variant(LONE_PARENT, child(RENAMED_15, "3", "2"), ["-lC"], C_ONLY),
    # One symbol moved to another library: a synthetic library, alone or with the real one.
    "moved-symbol": variant(LONE_PARENT, child(MOVED, "7", "3"), ["-lC"], C_ONLY),
    "moved-symbol-compat": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lC"], C_ONLY),
    "moved-symbol-child-linked-first": variant(LONE_PARENT, child(MOVED, "7", "3"), ["-lC", "-lP"]),
    "moved-symbol-compat-parent-linked-first": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lP", "-lC"]),
    "moved-symbol-compat-child-linked-first": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lC", "-lP"]),
    "moved-symbol-compat-parent-unreferenced": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lP", "-lC"], C_ONLY),
    # The real library only autolinked, as Engine's objects autolink libswiftDarwin and
    # libswiftFoundation: renamed libraries take its versions, moved symbols only when it is used.
    "renamed-reexport-autolinked": variant(PARENT, child(RENAMED), [], main_c("c", autolink=["P"])),
    "renamed-reexport-both-autolinked-child-first": variant(PARENT, child(RENAMED), [], main_c("c", autolink=["C", "P"])),
    "renamed-reexport-both-autolinked-parent-first": variant(PARENT, child(RENAMED), [], main_c("c", autolink=["P", "C"])),
    "renamed-both-autolinked": variant(LONE_PARENT, child(RENAMED, "7", "3"), [], main_c("c", autolink=["C", "P"])),
    "renamed-parent-autolinked-unreferenced": variant(LONE_PARENT, child(RENAMED, "7", "3"), ["-lC"], main_c("c", autolink=["P"])),
    "renamed-compat-parent-autolinked-unreferenced": variant(LONE_PARENT, child(RENAMED_15, "7", "3"), ["-lC"], main_c("c", autolink=["P"])),
    "reexport-autolinked": variant(PARENT, child(), [], main_c("c", autolink=["P"])),
    "renamed-reexport-other-name-autolinked": variant(PARENT, child(RENAMED_OTHER), [], main_c("c", autolink=["P"])),
    "moved-symbol-parent-autolinked-unreferenced": variant(LONE_PARENT, child(MOVED, "7", "3"), ["-lC"], main_c("c", autolink=["P"])),
    "moved-symbol-compat-parent-autolinked-unreferenced": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lC"], main_c("c", autolink=["P"])),
    "moved-symbol-compat-parent-autolinked": variant(LONE_PARENT, child(MOVED_15, "7", "3"), ["-lC"], main_c("p", "c", autolink=["P"])),
    # Two libraries move symbols to one install name, one with a version and one without.
    "two-owners-sdk-shape": two_owners(["-lA"], ["a", "b"], ["M", "B"]),
    "two-owners-sdk-shape-unmoved-used": two_owners(["-lA"], ["a", "a2", "b"], ["M", "B"]),
    "two-owners-no-destination-stub": two_owners(["-lA"], ["a", "b"], ["B"], destination=False),
    "two-owners-both-linked-a-first": two_owners(["-lA", "-lB"], ["a", "b"], ["M"]),
    "two-owners-both-linked-b-first": two_owners(["-lB", "-lA"], ["a", "b"], ["M"]),
    "two-owners-only-unversioned-used": two_owners(["-lA"], ["b"], ["M", "B"]),
    "two-owners-only-versioned-used": two_owners(["-lA"], ["a"], ["M", "B"]),
    # Both owners autolinked, the unversioned one first as in flappy-fly-bird's objects.
    "two-owners-autolinked-b-first": two_owners([], ["a", "b"], ["B", "A"]),
    "two-owners-autolinked-a-first": two_owners([], ["a", "b"], ["A", "B"]),
    "two-owners-autolinked-b-first-arm64e": two_owners([], ["a", "b"], ["B", "A"], target="arm64e-ios"),
    "two-owners-autolinked-b-first-b-used-first": two_owners([], ["b", "a"], ["B", "A"]),
    # Which autolinked owner comes first: its symbols' order, or frameworks before libraries.
    "two-owners-autolinked-b-first-b-sorts-first": two_owners([], ["a", "Ab"], ["B", "A"], b_symbol="_Ab"),
    "two-owners-autolinked-b-first-a-framework": two_owners([], ["a", "b"], ["B", "framework:A"], frameworks=("A",)),
    "two-owners-autolinked-a-first-b-framework": two_owners([], ["a", "b"], ["A", "framework:B"], frameworks=("B",)),
    "two-owners-autolinked-b-first-b-sorts-first-a-framework": two_owners([], ["a", "Ab"], ["B", "framework:A"], b_symbol="_Ab", frameworks=("A",)),
    # The versioned owner named Z: libraries by name, or in autolink order.
    "two-owners-autolinked-z-first": two_owners([], ["a", "b"], ["Z", "B"], a_name="Z"),
    "two-owners-autolinked-z-last": two_owners([], ["a", "b"], ["B", "Z"], a_name="Z"),
    "two-owners-autolinked-z-first-z-framework": two_owners([], ["a", "b"], ["framework:Z", "B"], a_name="Z", frameworks=("Z",)),
    "two-owners-autolinked-frameworks-z-first": two_owners([], ["a", "b"], ["framework:Z", "framework:B"], a_name="Z", frameworks=("Z", "B")),
    # Chained fixups or dyld opcodes (B-187): `-undefined dynamic_lookup`, by deployment target,
    # output kind and what stays undefined.
    "fixups-default": lookup(["-lC"], flags=()),
    "fixups-dynamic-lookup": lookup(),
    "fixups-dynamic-lookup-all-defined": lookup(["-lC"]),
    "fixups-dynamic-lookup-ios13": lookup(minos="13.0"),
    "fixups-dynamic-lookup-ios14": lookup(minos="14.0"),
    "fixups-dynamic-lookup-ios17": lookup(minos="17.0"),
    "fixups-dynamic-lookup-ios26": lookup(minos="26.0"),
    "fixups-dynamic-lookup-fixup-chains": lookup(flags=DYNAMIC_LOOKUP + ["-fixup_chains"]),
    "fixups-dynamic-lookup-fixup-chains-first": lookup(flags=["-fixup_chains"] + DYNAMIC_LOOKUP),
    "fixups-dynamic-lookup-then-error": lookup(["-lC"], flags=DYNAMIC_LOOKUP + ["-undefined", "error"]),
    "fixups-error-then-dynamic-lookup": lookup(["-lC"], flags=["-undefined", "error"] + DYNAMIC_LOOKUP),
    "fixups-undefined-error": lookup(["-lC"], flags=["-undefined", "error"]),
    "fixups-undefined-suppress": lookup(flags=["-flat_namespace", "-undefined", "suppress"]),
    "fixups-dynamic-lookup-symbol": lookup(flags=["-U", "_c"]),
    "fixups-flat-namespace": lookup(["-lC"], flags=["-flat_namespace"]),
    "fixups-dynamic-lookup-bundle": lookup(kind="-bundle"),
    "fixups-dynamic-lookup-executable": lookup(main=main_c("c", entry=True), kind="-execute"),
    "fixups-executable": lookup(["-lC"], main=main_c("c", entry=True), flags=(), kind="-execute"),
    # Initializers: `__mod_init_func` pointers or `__init_offsets`, by deployment target and fixups.
    **{f"init-ios{minos}": image(INITIALIZER, minos) for minos in ("12.0", "13.0", "13.3", "13.4", "14.0", "15.0", "16.0", "17.0", "26.0")},
    "init-dynamic-lookup": image(INITIALIZER, flags=DYNAMIC_LOOKUP),
    "init-no-fixup-chains": image(INITIALIZER, flags=["-no_fixup_chains"]),
    "init-executable": image(INITIALIZER + "int main(void) { return f(); }\n", kind="-execute"),
    # Thread-local variables: their sections, with chained fixups and without.
    # Sections lld lays out otherwise: os_log's strings, literals.
    "sections-oslogstring": image(OS_LOG_STRING),
    "sections-literal16": image(LITERAL_16),
    "sections-own-cstrings": image(OWN_CSTRINGS),
    # The same strings, ObjC names and literal in two objects: which sections Xcode's ld merges.
    "dead-strip-classrefs": {**image("", flags=DYNAMIC_LOOKUP + ["-dead_strip"]), "objects": ["u.o"], "sources": {"u.m": UNREFERENCED_OBJC}},
    "dead-strip-classrefs-kept": {**image("", flags=DYNAMIC_LOOKUP), "objects": ["u.o"], "sources": {"u.m": UNREFERENCED_OBJC}},
    # Libraries kept or dropped once dead stripping removed every reference to them.
    "autolink-dead": lookup(main=AUTOLINKED_DEAD, flags=["-dead_strip"]),
    "autolink-dead-explicit": lookup(["-lC"], main=AUTOLINKED_DEAD, flags=["-dead_strip"]),
    "autolink-dead-no-dead-strip": lookup(main=AUTOLINKED_DEAD, flags=()),
    "autolink-live": lookup(main='__asm__(".linker_option \\"-lC\\"");\nextern int c(void);\nint f(void) { return c(); }\n', flags=["-dead_strip"]),
    "explicit-unreferenced": lookup(["-lC"], main=NOTHING_USED, flags=["-dead_strip"]),
    "autolink-dead-reexported": reexport_lookup("c"),
    "autolink-dead-reexported-explicit": reexport_lookup("c", libs=["-lP"]),
    "autolink-dead-parent-own": reexport_lookup("p"),
    "explicit-reexporting-unreferenced": {**reexport_lookup("c", libs=["-lP"]), "main": NOTHING_USED},
    "autolink-dead-moved": moved_lookup(),
    "autolink-dead-moved-explicit": moved_lookup(libs=["-lP"]),
    "autolink-dead-moved-no-dead-strip": moved_lookup(flags=()),
    "autolink-live-moved": moved_lookup(dead=False),
    "autolink-dead-moved-restricted": moved_lookup(restricted=True),
    "autolink-dead-moved-restricted-explicit": moved_lookup(libs=["-lP"], restricted=True),
    "autolink-live-moved-restricted-explicit": moved_lookup(dead=False, libs=["-lP"], restricted=True),
    "autolink-dead-moved-restricted-explicit-no-dead-strip": moved_lookup(libs=["-lP"], restricted=True, flags=()),
    "explicit-moved-restricted-unreferenced": {**moved_lookup(libs=["-lP"], restricted=True), "main": NOTHING_USED},
    "binding-usr-lib": reexport_binding("/usr/lib/libC.dylib"),
    "binding-usr-lib-swift": reexport_binding("/usr/lib/swift/libC.dylib"),
    "binding-usr-lib-restricted": reexport_binding("/usr/lib/libC.dylib", restricted=True),
    "binding-framework": reexport_binding("/System/Library/Frameworks/C.framework/C"),
    "binding-framework-restricted": reexport_binding("/System/Library/Frameworks/C.framework/C", restricted=True),
    "binding-framework-other-name": reexport_binding("/System/Library/Frameworks/C.framework/Versions/A/D"),
    "binding-autolinked-child-swift": reexport_binding("/usr/lib/swift/libC.dylib", autolink_child='\\"-lC\\"'),
    "binding-autolinked-child-swift-searched": reexport_binding("/usr/lib/swift/libC.dylib", autolink_child='\\"-lC\\"',
                                                                search=["-L", "{sysroot}/usr/lib/swift"]),
    "binding-autolinked-child-restricted": reexport_binding("/usr/lib/libC.dylib", restricted=True, autolink_child='\\"-lC\\"'),
    "binding-autolinked-child-framework-restricted": reexport_binding("/System/Library/Frameworks/C.framework/C", restricted=True,
                                                                      autolink_child='\\"-framework\\", \\"C\\"'),
    "autolink-dead-executable": lookup(main=AUTOLINKED_DEAD + "int main(void) { return f(); }\n", flags=["-dead_strip"], kind="-execute"),
    "autolink-dead-framework": framework_lookup(AUTOLINKED_DEAD_FRAMEWORK, ["-dead_strip"]),
    "autolink-live-framework": framework_lookup(AUTOLINKED_DEAD_FRAMEWORK.replace("int f(void) { return 1; }", "int f(void) { return fc(); }"), ["-dead_strip"]),
    "autolink-dead-framework-executable": framework_lookup(AUTOLINKED_DEAD_FRAMEWORK + "int main(void) { return f(); }\n", ["-dead_strip"], kind="-execute"),
    "sections-across-objects": {**image("", flags=DYNAMIC_LOOKUP), "objects": ["a.o", "b.o"], "sources": {"a.m": OBJECTS_SOURCE.format(name="A"),
                                                                                       "b.m": OBJECTS_SOURCE.format(name="B")}},
    "tlv": image(THREAD_LOCAL),
    "tlv-dynamic-lookup": image(THREAD_LOCAL, flags=DYNAMIC_LOOKUP),
    "tlv-weak": image(WEAK_THREAD_LOCAL),
    "tlv-weak-hidden": image(HIDDEN_WEAK_THREAD_LOCAL),
    # Debug maps: an image of a relocatable object (`clang -r`) of objects with debug information,
    # which keeps their stabs, not their DWARF.
    "stabs-relocatable": {**image(""), "parts": {"a.c": "static int twice(int x) { return 2 * x; }\nint shared = 3;\nint a(void) { return twice(shared); }\n",
                                                  "b.c": "static int local = 4;\nint b(void) { return local + 1; }\n"}},
    "tlv-imported": {**image("extern __thread int counter;\nint f(void) { return ++counter; }\n", libs=["-lT"]),
                     "stubs": {"T": thread_local_library(), **image("").get("stubs")}},
}

# The debug map's stabs: source files, object files (their names), functions and data.
STABS = {0x64: "SO", 0x66: "OSO", 0x24: "FUN", 0x26: "STSYM", 0x20: "GSYM", 0x2e: "BNSYM", 0x4e: "ENSYM"}
DYLD_INFO_COMMANDS = {0x80000022: "LC_DYLD_INFO_ONLY", 0x80000033: "LC_DYLD_EXPORTS_TRIE", 0x80000034: "LC_DYLD_CHAINED_FIXUPS"}
LIBRARY_COMMANDS = {0xc: "LC_LOAD_DYLIB", 0x80000018: "LC_LOAD_WEAK_DYLIB", 0x8000001f: "LC_REEXPORT_DYLIB",
                    0x20: "LC_LAZY_LOAD_DYLIB", 0x80000023: "LC_LOAD_UPWARD_DYLIB"}


def version(value):
    return f"{value >> 16}.{(value >> 8) & 0xff}.{value & 0xff}"


def record(path):
    """The libraries a thin 64-bit Mach-O file loads, the library each undefined symbol names, and the
    load commands that hold dyld's information."""
    data = path.read_bytes()
    libraries, dyld, sections, symtab, offset = [], [], [], None, 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        if command in LIBRARY_COMMANDS:
            name_offset, _, current, compat = struct.unpack_from("<IIII", data, offset + 8)
            name = data[offset + name_offset:offset + size].split(b"\0")[0].decode()
            libraries.append([LIBRARY_COMMANDS[command], name, version(current), version(compat)])
        elif command == 0x19:
            for index in range(struct.unpack_from("<I", data, offset + 64)[0]):
                name, segment = struct.unpack_from("<16s16s", data, offset + 72 + 80 * index)
                sections.append(segment.rstrip(b"\0").decode() + "," + name.rstrip(b"\0").decode())
        elif command in DYLD_INFO_COMMANDS:
            dyld.append(DYLD_INFO_COMMANDS[command])
        elif command == 0x2:
            symtab = struct.unpack_from("<IIII", data, offset + 8)
        offset += size
    imports, stabs = {}, []
    if symtab:
        symbols, count, strings, _ = symtab
        for index in range(count):
            name_offset, kind, _, description, value = struct.unpack_from("<IBBHQ", data, symbols + 16 * index)
            if kind in STABS:
                text = data[strings + name_offset:data.index(b"\0", strings + name_offset)].decode()
                stabs.append(f"{STABS[kind]} {Path(text).name if kind == 0x66 else text}".rstrip())
            if kind & 0xe0 == 0 and kind & 0x0e == 0 and kind & 0x01 and value == 0:
                name = data[strings + name_offset:data.index(b"\0", strings + name_offset)].decode()
                ordinal = description >> 8
                library = libraries[ordinal - 1][1] if 0 < ordinal <= len(libraries) else f"ordinal {ordinal}"
                imports[name] = library + (" (weak)" if description & 0x0040 else "")
    return {"libraries": libraries, "imports": imports, "dyld": dyld, "sections": sections, "stabs": stabs}


def link(linker, work, variant, label):
    sysroot = work / "sysroot"
    output = work / f"{label}.dylib"
    install_name = ["-install_name", "@rpath/libX.dylib"] if variant["kind"] == "-dylib" else []
    command = linker + ["-arch", "arm64", "-platform_version", "ios", variant["minos"], "27.0", variant["kind"], *install_name,
                        *variant["flags"], "-syslibroot", str(sysroot), "-L", str(sysroot / "usr/lib"), "-o", str(output),
                        *[str(work / name) for name in variant.get("objects", ["main.o"])],
                        *[argument.replace("{sysroot}", str(sysroot)) for argument in variant["libs"]]]
    proc = subprocess.run(command, cwd=work, capture_output=True, text=True)
    result = {"command": command, "exit": proc.returncode, "output": proc.stdout + proc.stderr}
    if proc.returncode == 0:
        result.update(record(output))
    (work / f"{label}.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    out = Path(sys.argv[1]).resolve()
    if "--lld" in sys.argv:
        lld = sys.argv[sys.argv.index("--lld") + 1]
        # A toolchain's `ld64.lld` (nomac's dispatcher, or lld by that name) is already Darwin's flavor.
        linker, label = [lld] + ([] if Path(lld).name == "ld64.lld" else ["-flavor", "darwin"]), "lld"
    else:
        developer = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer"))
        toolchain = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
        sdk = developer / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        linker, label = [str(toolchain / "ld")], "xcode"
        for name, variant in VARIANTS.items():
            work = out / name
            (work / "sysroot/usr/lib").mkdir(parents=True, exist_ok=True)
            for stub_name, text in variant["stubs"].items():
                if stub_name.startswith("/"):
                    # A stub at its install name's place in the sysroot (`/usr/lib/swift/libC.tbd`).
                    (work / f"sysroot{stub_name}").parent.mkdir(parents=True, exist_ok=True)
                    (work / f"sysroot{stub_name}").write_text(text)
                elif stub_name.startswith("framework:"):
                    framework = work / f"sysroot/System/Library/Frameworks/{stub_name[10:]}.framework"
                    framework.mkdir(parents=True, exist_ok=True)
                    (framework / f"{stub_name[10:]}.tbd").write_text(text)
                else:
                    (work / f"sysroot/usr/lib/lib{stub_name}.tbd").write_text(text)
            clang = [str(toolchain / "clang"), "-target", "arm64-apple-ios15.0", "-isysroot", str(sdk)]
            if variant.get("objects"):
                # Objects linked as they are, for what the linker merges across them.
                for part, text in variant["sources"].items():
                    (work / part).write_text(text)
                    language = ["-x", "objective-c"] if part.endswith(".m") else []
                    subprocess.run(clang + language + ["-c", "-o", str(work / (Path(part).stem + ".o")), str(work / part)], check=True)
                continue
            if variant.get("parts"):
                # Objects with debug information, linked into main.o as Swift Build links a package
                # product (`clang -r`).
                objects = []
                for part, text in variant["parts"].items():
                    (work / part).write_text(text)
                    objects.append(str(work / (Path(part).stem + ".o")))
                    subprocess.run(clang + ["-g", "-c", "-o", objects[-1], str(work / part)], check=True)
                subprocess.run(clang + ["-r", "-nostdlib", "-o", str(work / "main.o"), *objects], check=True)
                continue
            (work / "main.c").write_text(variant["main"])
            subprocess.run(clang + ["-c", "-o", str(work / "main.o"), str(work / "main.c")], check=True)
    lines = []
    for name, variant in VARIANTS.items():
        result = link(linker, out / name, variant, label)
        lines.append(f"{name} [{label}] exit {result['exit']}")
        if result.get("dyld"):
            lines.append("    dyld: " + " ".join(result["dyld"]))
        if variant["sections"] and result.get("sections"):
            lines.append("    sections: " + " ".join(result["sections"]))
        if variant.get("parts"):
            lines.append("    stabs: " + ", ".join(result.get("stabs", [])))
        for library in result.get("libraries", []):
            lines.append("    " + " ".join(library))
        for symbol, library in sorted(result.get("imports", {}).items()):
            lines.append(f"    {symbol} -> {library}")
        if result["exit"] != 0:
            lines.append("    " + result["output"].strip().replace("\n", "\n    "))
    (out / f"summary-{label}.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()

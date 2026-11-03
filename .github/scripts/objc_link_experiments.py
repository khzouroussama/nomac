#!/usr/bin/env python3
"""How Xcode's ld and lld lay out Objective-C metadata, for self-written classes and categories.

The same objects, compiled once by Xcode's clang and swiftc at several iOS deployment targets, are
linked by each linker with the same arguments, and with each linker's Objective-C options. Every
output section is recorded with its size, and for a method list whether it is relative (the
entsize word's high bit).

Usage:
  objc_link_experiments.py <output-dir>                          on a Mac: compile the objects, link
                                                                 them with Xcode's ld (DEVELOPER_DIR
                                                                 selects the Xcode), write xcode.json
  objc_link_experiments.py <output-dir> --lld <lld> --sdk <sdk> --swift-lib <dir>
                                                                 anywhere: link the same objects with
                                                                 lld against <sdk> and the toolchain's
                                                                 lib/swift/iphoneos, write lld.json

`summary.txt` lists the sections of each output side by side, once both records exist.
"""

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

OBJC = """#import <Foundation/Foundation.h>
@interface A : NSObject
- (int)a;
- (int)b;
@end
@implementation A
- (int)a { return 1; }
- (int)b { return 2; }
@end
@interface A (Own)
- (int)c;
@end
@implementation A (Own)
- (int)c { return 3; }
@end
@interface NSObject (External)
- (int)e;
@end
@implementation NSObject (External)
- (int)e { return 4; }
@end
"""

SWIFT = """import Foundation
public class S: NSObject {
    @objc public func a() -> Int { 1 }
    @objc public func b() -> Int { 2 }
}
extension S {
    @objc public func c() -> Int { 3 }
}
extension NSObject {
    @objc public func e() -> Int { 4 }
}
"""

TARGETS = ["13.0", "14.0", "15.0", "17.0", "26.0"]
XCODE_OPTIONS = {"default": [], "no-relative": ["-no_objc_relative_method_lists"], "no-merging": ["-no_objc_category_merging"]}
LLD_OPTIONS = {"default": [], "relative": ["-objc_relative_method_lists"], "merging": ["-objc_category_merging"],
               "both": ["-objc_relative_method_lists", "-objc_category_merging"]}
SDK_VERSION = "27.0"


def sections(path):
    """(segment, section, size, first word) of every section of a thin 64-bit Mach-O file."""
    data = Path(path).read_bytes()
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from("<8I", data, 0)
    assert magic == 0xFEEDFACF, path
    found, offset = [], 32
    for _ in range(ncmds):
        command, size = struct.unpack_from("<2I", data, offset)
        if command == 0x19:
            nsects = struct.unpack_from("<I", data, offset + 64)[0]
            for index in range(nsects):
                header = offset + 72 + index * 80
                name = data[header:header + 16].rstrip(b"\0").decode()
                segment = data[header + 16:header + 32].rstrip(b"\0").decode()
                sect_size, file_offset = struct.unpack_from("<Q", data, header + 40)[0], struct.unpack_from("<I", data, header + 48)[0]
                first = struct.unpack_from("<I", data, file_offset)[0] if file_offset and sect_size >= 4 else None
                found.append([segment, name, sect_size, first])
        offset += size
    return found


def link_arguments(objects, minos, sdk, swift_lib, output, extra):
    return (["-arch", "arm64", "-platform_version", "ios", minos, SDK_VERSION, "-syslibroot", sdk, "-dylib",
             "-install_name", "@rpath/" + Path(output).name, "-dead_strip", "-o", str(output)] + [str(o) for o in objects]
            + ["-L" + sdk + "/usr/lib/swift", "-L" + swift_lib, "-lobjc", "-lSystem", "-framework", "Foundation"] + extra)


def compile_objects(out):
    sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
    (out / "A.m").write_text(OBJC)
    (out / "S.swift").write_text(SWIFT)
    for minos in TARGETS:
        directory = out / minos
        directory.mkdir(parents=True, exist_ok=True)
        target = f"arm64-apple-ios{minos}"
        subprocess.run(["xcrun", "clang", "-target", target, "-isysroot", sdk, "-Os", "-fobjc-arc", "-c", str(out / "A.m"),
                        "-o", str(directory / "A.o")], check=True)
        subprocess.run(["xcrun", "swiftc", "-target", target, "-sdk", sdk, "-O", "-parse-as-library", "-module-name", "S",
                        "-c", str(out / "S.swift"), "-o", str(directory / "S.o")], check=True)
    return sdk


def link_all(out, linker, sdk, swift_lib, options, label):
    record = {}
    for minos in TARGETS:
        for language, objects in [("objc", ["A.o"]), ("swift", ["S.o"])]:
            for option, extra in options.items():
                output = out / minos / f"{language}-{label}-{option}.dylib"
                proc = subprocess.run(linker + link_arguments([out / minos / o for o in objects], minos, sdk, swift_lib, output, extra),
                                      capture_output=True, text=True)
                key = f"{minos}/{language}/{option}"
                record[key] = {"exit": proc.returncode, "stderr": proc.stderr[-2000:],
                               "sections": sections(output) if proc.returncode == 0 else []}
    (out / f"{label}.json").write_text(json.dumps(record, indent=1) + "\n")
    return record


def summarize(out):
    if not ((out / "xcode.json").exists() and (out / "lld.json").exists()):
        return
    lines = []
    for name in ["xcode", "lld"]:
        record = json.loads((out / f"{name}.json").read_text())
        for key, value in record.items():
            if value["exit"] != 0:
                lines.append(f"{name} {key}: exit {value['exit']}: {value['stderr'].strip().splitlines()[-1:]}")
                continue
            listed = [f"{s[0]},{s[1]}={s[2]}" + (f"(0x{s[3]:08x})" if s[1] == "__objc_methlist" or (s[1] == "__objc_const" and s[3] is not None) else "")
                      for s in value["sections"] if "objc" in s[1] or s[1] in ("__cstring", "__unwind_info", "__data")]
            lines.append(f"{name} {key}: " + " ".join(listed))
    (out / "summary.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


def main():
    out = Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    if "--lld" in sys.argv:
        lld = sys.argv[sys.argv.index("--lld") + 1]
        sdk = sys.argv[sys.argv.index("--sdk") + 1]
        swift_lib = sys.argv[sys.argv.index("--swift-lib") + 1]
        link_all(out, [lld, "-flavor", "darwin"], sdk, swift_lib, LLD_OPTIONS, "lld")
    else:
        sdk = compile_objects(out)
        swiftc = subprocess.run(["xcrun", "--find", "swiftc"], capture_output=True, text=True, check=True).stdout.strip()
        swift_lib = str(Path(swiftc).parent.parent / "lib" / "swift" / "iphoneos")
        link_all(out, ["xcrun", "ld"], sdk, swift_lib, XCODE_OPTIONS, "xcode")
    summarize(out)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main()

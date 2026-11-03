#!/usr/bin/env python3
"""Relocatable links (`clang -r`, as Swift Build links a Swift package product) against Xcode 27.0's.

Xcode's `ld` leaves the inputs' linker optimization hints out of a relocatable object; cctools-port's
`ld64`, which links them on Linux (ADR 0104), kept them as `LC_LINKER_OPTIMIZATION_HINT`
(netnewswire's `Minizip.o` and its Swift package objects, B-172). Xcode's `ld` also leaves out a
section with no content and the local labels in it, where `ld64` kept an empty `__TEXT,__text`
(netnewswire's `RSCoreObjC.o`, whose sources compile to nothing for iOS: the `empty-*` cases).
A Swift object's `__LLVM,__swift_modhash` is left out by Xcode's `ld` too; `ld64` copies `__LLVM` sections
when it links a single input, as it does for bitcode (B-173: swiftfin's one-file package products;
the `two-swift` case links two).

Usage:
  relocatable_experiments.py inputs <out>               Mac: compile the inputs with Xcode's clang and
                                                        swiftc (DEVELOPER_DIR), link each with Xcode's
                                                        `clang -r`; writes <out>/xcode.json
  relocatable_experiments.py run <out> <developer-dir>  link the same objects with that developer
                                                        directory's `clang -r`; writes <out>/<label>.json
                                                        and prints each case beside Xcode's
"""

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

SOURCES = {
    "c.c": "extern int g;\nint get(void) { return g; }\nint *address(void) { return &g; }\n",
    "objc.m": "#import <Foundation/Foundation.h>\n@interface Box : NSObject\n@property NSInteger value;\n@end\n"
              "@implementation Box\n@end\nNSInteger total(Box *box) { return box.value + [NSProcessInfo processInfo].processorCount; }\n",
    "empty-c.c": "#if 0\nint f(void) { return 1; }\n#endif\n",
    "empty-objc.m": "#import <Foundation/Foundation.h>\n#if 0\n@interface A : NSObject\n@end\n#endif\n",
    "s.swift": "public final class Box { public var value = 1; public init() {} }\n"
               "public func api(_ boxes: [Box]) -> Int { boxes.map { $0.value }.reduce(0, +) }\n",
}
# Cases that link several of the objects above together (`clang -r a.o b.o`).
GROUPS = {"two-swift": ["s.swift", "t.swift"]}
EXTRA = {"t.swift": "public func twice(_ x: Int) -> Int { x &* 2 }\n"}
LINK = ["-target", "arm64-apple-ios15.0", "-r", "-nostdlib", "-Xlinker", "-reproducible"]


def load_commands(path):
    """The names of a 64-bit Mach-O file's load commands and sections, in file order."""
    data = path.read_bytes()
    names = {0x2: "LC_SYMTAB", 0xb: "LC_DYSYMTAB", 0x19: "LC_SEGMENT_64", 0x29: "LC_DATA_IN_CODE",
             0x2d: "LC_LINKER_OPTION", 0x2e: "LC_LINKER_OPTIMIZATION_HINT", 0x32: "LC_BUILD_VERSION"}
    commands, sections, offset = [], [], 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        commands.append(names.get(command, hex(command)))
        if command == 0x19:
            for index in range(struct.unpack_from("<I", data, offset + 64)[0]):
                section, segment = struct.unpack_from("<16s16s", data, offset + 72 + 80 * index)
                sections.append(segment.rstrip(b"\0").decode() + "," + section.rstrip(b"\0").decode())
        offset += size
    return {"commands": commands, "sections": sections}


def link(out, toolchain, label):
    results = {}
    for name, sources in {**{source: [source] for source in SOURCES}, **GROUPS}.items():
        output = out / f"{Path(name).stem}-{label}-r.o"
        objects = [str(out / (Path(source).stem + ".o")) for source in sources]
        proc = subprocess.run([str(toolchain / "clang"), *LINK, *objects, "-o", str(output)], capture_output=True, text=True)
        results[name] = load_commands(output) if proc.returncode == 0 else {"exit": proc.returncode, "output": proc.stderr}
    (out / f"{label}.json").write_text(json.dumps(results, indent=2) + "\n")
    return results


def inputs(out):
    developer = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer"))
    toolchain = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    sdk = developer / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    out.mkdir(parents=True, exist_ok=True)
    for source, text in {**SOURCES, **EXTRA}.items():
        (out / source).write_text(text)
        obj = str(out / (Path(source).stem + ".o"))
        if source.endswith(".swift"):
            command = [str(toolchain / "swiftc"), "-target", "arm64-apple-ios15.0", "-sdk", str(sdk), "-O", "-parse-as-library",
                       "-module-name", Path(source).stem.upper(), "-c", str(out / source), "-o", obj]
        else:
            command = [str(toolchain / "clang"), "-target", "arm64-apple-ios15.0", "-isysroot", str(sdk), "-Os", "-fobjc-arc",
                       "-c", str(out / source), "-o", obj]
        subprocess.run(command, check=True)
    for source, result in link(out, toolchain, "xcode").items():
        print(source, "xcode:", " ".join(result.get("commands", [])))


def run(out, developer):
    toolchain = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    xcode = json.loads((out / "xcode.json").read_text())
    ours = link(out, toolchain, "nomac")
    same = 0
    for source, result in ours.items():
        identical = result == xcode[source]
        same += identical
        print(source, "identical" if identical else f"differs: {result} vs Xcode's {xcode[source]}")
    print(f"{same} / {len(ours)} as Xcode's")


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "inputs":
        inputs(out)
    else:
        run(out, sys.argv[3])


if __name__ == "__main__":
    main()

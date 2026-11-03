#!/usr/bin/env python3
"""What Xcode 27.0's Swift compiler and linker write that swift.org's toolchain does not, on self-written
Swift (netnewswire's frameworks on Linux, docs/VERIFICATION.md "Build products").

- `retain-<target>`: the reference-counting entry points an object imports at each deployment target.
  Xcode's compiler calls `swift_retain_x<N>` and `swift_release_x<N>`, which take the object in register
  `x<N>`, from iOS 17.0; swift.org's calls `swift_retain` and `swift_release`.
- `oslog`: the sections of a dylib whose code logs through `Logger`. Both compilers put the format
  strings into `__TEXT,__oslogstring` in the object; Xcode's `ld` keeps the section, lld merges it into
  `__TEXT,__cstring` (B-174).
- `actor`: the Objective-C sections of a dylib with an actor that has an `@objc` method. Both compilers put
  the actor's method list into `__DATA,__objc_data`; Xcode's `ld` makes it relative in
  `__TEXT,__objc_methlist`, and lld keeps `__objc_data` (netnewswire's ErrorLog).

Usage: swift_codegen_experiments.py <out> <developer-dir> <label>
  Compiles and links each case with the developer directory's swiftc (Xcode's on a Mac, nomac's
  toolchain on Linux) and writes <out>/<label>.json.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

RETAIN = ("public final class C { var x = 0 }\n"
          "public func f(_ a: C, _ b: C) -> Int { [a, b].map { $0.x }.reduce(0, +) }\n")
OSLOG = ("import os\npublic struct N {\n    private static let logger = Logger(subsystem: \"s\", category: \"c\")\n"
         "    public static func a() { logger.info(\"Posting low memory notification.\") }\n"
         "    public static func b(_ w: Int) { logger.info(\"Width \\(w, privacy: .public)\") }\n}\n")
CONFORMS = ("public protocol P {}\npublic func f(_ x: Any) -> Bool { x is P }\n"
            "public func g<T>(_ t: T.Type) -> Bool { t is P.Type }\n")
ACTOR = ("import Foundation\npublic actor Store {\n    var count = 0\n    public init() {}\n"
         "    @objc nonisolated func handle(_ notification: Notification) {}\n}\n")
TARGETS = ["15.0", "16.0", "16.4", "17.0", "18.0", "26.0", "27.0"]


def main():
    out, developer, label = Path(sys.argv[1]).resolve(), Path(sys.argv[2]), sys.argv[3]
    bin = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    sdk = developer / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    out.mkdir(parents=True, exist_ok=True)
    (out / "retain.swift").write_text(RETAIN)
    (out / "oslog.swift").write_text(OSLOG)
    (out / "actor.swift").write_text(ACTOR)
    (out / "conforms.swift").write_text(CONFORMS)
    swiftc = [str(bin / "swiftc"), "-sdk", str(sdk), "-O", "-parse-as-library", "-module-name", "m"]
    results = {}
    for target in TARGETS:
        obj = out / f"retain-{target}-{label}.o"
        subprocess.run(swiftc + ["-target", f"arm64-apple-ios{target}", "-c", str(out / "retain.swift"), "-o", str(obj)], check=True)
        symbols = subprocess.run([str(bin / "llvm-nm"), "-u", str(obj)], capture_output=True, text=True, check=True).stdout.split()
        results[f"retain-{target}"] = sorted(s for s in symbols if re.fullmatch(r"_swift_(retain|release)(_x\d+)?", s))
        obj = out / f"conforms-{target}-{label}.o"
        subprocess.run(swiftc + ["-target", f"arm64-apple-ios{target}", "-c", str(out / "conforms.swift"), "-o", str(obj)], check=True)
        symbols = subprocess.run([str(bin / "llvm-nm"), "-u", str(obj)], capture_output=True, text=True, check=True).stdout.split()
        results[f"conforms-{target}"] = sorted(s for s in symbols if s.startswith("_swift_conformsToProtocol"))
    for case in ("oslog", "actor"):
        dylib = out / f"{case}-{label}.dylib"
        subprocess.run(swiftc + ["-target", "arm64-apple-ios17.0", "-emit-library", str(out / f"{case}.swift"), "-o", str(dylib)], check=True)
        headers = subprocess.run([str(bin / "llvm-objdump"), "--macho", "--section-headers", str(dylib)],
                                 capture_output=True, text=True, check=True).stdout
        results[case] = sorted({line.split()[1] for line in headers.splitlines() if re.match(r"\s*\d+ __", line)})
    (out / f"{label}.json").write_text(json.dumps(results, indent=2) + "\n")
    for case, value in results.items():
        print(case, " ".join(value))


if __name__ == "__main__":
    main()

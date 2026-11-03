#!/usr/bin/env python3
"""What Xcode's `tapi stubify` writes for self-written dylibs, one property varied at a time.

Swift Build runs `tapi stubify` for every framework it links (GenerateTAPI, the eager-linking
`.tbd` in Build/Intermediates.noindex/EagerLinkingTBDs). nomac reproduces it (docs/adr/0102-linker.md);
this records the rules on a Mac with Xcode 27.0.

Usage: tapi_experiments.py <output-dir>    (DEVELOPER_DIR selects the Xcode)

Each variant gets <output-dir>/<name>/ with its sources, the dylib and `stub.tbd`; `summary.json`
lists the variants and their exit statuses.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

C_FUNCTION = "int nomac_function(void) { return 1; }\n"
C_DATA = "int nomac_data = 2;\nconst int nomac_constant = 3;\n"
OBJC_CLASS = (
    "#import <Foundation/Foundation.h>\n"
    "@interface NomacClass : NSObject\n@end\n"
    "@implementation NomacClass\n@end\n"
)

OBJC_IVARS = (
    "#import <Foundation/Foundation.h>\n"
    "@interface NomacIvars : NSObject {\n@public\n    int _public;\n@protected\n    int _protected;\n@private\n    int _private;\n@package\n    int _package;\n}\n@end\n"
    "@implementation NomacIvars\n@end\n"
)
OBJC_EXCEPTION = (
    "#import <Foundation/Foundation.h>\n"
    "__attribute__((objc_exception))\n@interface NomacException : NSObject\n@end\n"
    "@implementation NomacException\n@end\n"
)
VARIANTS = {
    "function": {"c": C_FUNCTION},
    "data": {"c": C_DATA},
    "function-and-data": {"c": C_FUNCTION + C_DATA},
    "weak": {"c": "__attribute__((weak)) int nomac_weak(void) { return 4; }\n"},
    "thread-local": {"c": "__thread int nomac_thread_local = 5;\n"},
    "hidden": {"c": C_FUNCTION + "__attribute__((visibility(\"hidden\"))) int nomac_hidden(void) { return 6; }\n"},
    "versions": {"c": C_FUNCTION, "ld": ["-current_version", "2.3.4", "-compatibility_version", "1.2"]},
    "extension-safe": {"c": C_FUNCTION, "ld": ["-Xlinker", "-application_extension"]},
    "minos-15.4": {"c": C_FUNCTION, "minos": "15.4"},
    "minos-16.0.1": {"c": C_FUNCTION, "minos": "16.0.1"},
    "objc-class": {"m": OBJC_CLASS, "ld": ["-framework", "Foundation"]},
    # Instance variables of each visibility (mastodon's MastodonSDKDynamic), and an exception type.
    "objc-ivars": {"m": OBJC_IVARS, "ld": ["-framework", "Foundation"]},
    "objc-exception-type": {"m": OBJC_EXCEPTION, "ld": ["-framework", "Foundation"]},
    "swift-function": {"swift": "public func nomacFunction() -> Int { 1 }\n"},
    "swift-data": {"swift": "public var nomacData = 2\n"},
    "swift-struct": {"swift": "public struct NomacStruct { public var value = 3\n public init() {} }\n"},
    "swift-and-c": {"swift": "public func nomacFunction() -> Int { 1 }\n", "c": C_FUNCTION + C_DATA},
    "weak-data": {"c": "__attribute__((weak)) int nomac_weak_data = 7;\n"},
    "versions-1.0": {"c": C_FUNCTION, "ld": ["-current_version", "1.0", "-compatibility_version", "1.0"]},
    "current-1.0": {"c": C_FUNCTION, "ld": ["-current_version", "1.0", "-compatibility_version", "1.2"]},
    "compatibility-1.0": {"c": C_FUNCTION, "ld": ["-current_version", "2.0", "-compatibility_version", "1.0"]},
    "no-exports": {"c": "static int nomac_hidden(void) { return 8; }\nint (*nomac_unused)(void) __attribute__((visibility(\"hidden\"))) = nomac_hidden;\n"},
    # The options Swift Build's GenerateTAPI passes besides -isysroot, -F and -L.
    "swift-build-options": {"c": C_FUNCTION, "tapi": ["-iframework", "@SDK@/System/Library/Frameworks", "--inline-private-frameworks"]},
}


def run(cmd, cwd):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    (cwd / "commands.txt").open("a").write(" ".join(cmd) + f"\n# exit {proc.returncode}\n{proc.stdout}{proc.stderr}\n")
    return proc.returncode


def main():
    out = Path(sys.argv[1]).resolve()
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
    toolchain = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    sdk = Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    summary = {}
    for name, variant in VARIANTS.items():
        work = out / name
        work.mkdir(parents=True, exist_ok=True)
        (work / "commands.txt").write_text("")
        minos = variant.get("minos", "15.0")
        dylib = work / "libNomac.dylib"
        if "swift" in variant:
            source = work / "source.swift"
            source.write_text(variant["swift"])
            objects = []
            if "c" in variant:
                (work / "source.c").write_text(variant["c"])
                run([str(toolchain / "clang"), "-target", f"arm64-apple-ios{minos}", "-isysroot", str(sdk), "-c",
                     "-o", str(work / "c.o"), str(work / "source.c")], work)
                objects = [str(work / "c.o")]
            compile_command = [str(toolchain / "swiftc"), "-target", f"arm64-apple-ios{minos}", "-sdk", str(sdk), "-O",
                               "-module-name", "Nomac", "-emit-library", "-Xlinker", "-install_name",
                               "-Xlinker", "@rpath/libNomac.dylib", "-o", str(dylib), str(source)] + objects
        else:
            source = work / ("source.m" if "m" in variant else "source.c")
            source.write_text(variant.get("m", variant.get("c", "")))
            compile_command = [str(toolchain / "clang"), "-target", f"arm64-apple-ios{minos}", "-isysroot", str(sdk),
                               "-dynamiclib", "-install_name", "@rpath/libNomac.dylib", "-o", str(dylib), str(source)]
        status = run(compile_command + variant.get("ld", []), work)
        if status == 0:
            options = [option.replace("@SDK@", str(sdk)) for option in variant.get("tapi", [])]
            status = run([str(toolchain / "tapi"), "stubify", "-isysroot", str(sdk), *options, str(dylib), "-o", str(work / "stub.tbd")], work)
        summary[name] = status
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

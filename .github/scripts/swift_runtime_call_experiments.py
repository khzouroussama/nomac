#!/usr/bin/env python3
"""How Xcode 27.0's swift-frontend calls the Objective-C and Swift runtimes (ADR 0106): when it sends
Objective-C messages through selector stubs (`objc_msgSend$<selector>`) instead of `objc_msgSend` and a
selector reference, and when it marks a module for the Swift runtime's entry points by register
(the module flag "Swift DirectReg Version", which Xcode's LLVM turns into calls of swift_retain_x19
and the others).

Each case compiles self-written Swift with the frontend for a target and options, and lists, from the
LLVM IR, the functions each Objective-C message is sent through, the selectors the module references,
how a stub is declared and called, and the module's "Swift DirectReg Version".

Usage:
  swift_selector_stub_experiments.py xcode <out>                Mac: Xcode's swift-frontend (DEVELOPER_DIR);
                                                               writes <out>/xcode.json
  swift_selector_stub_experiments.py run <out> <developer-dir>  the developer directory's swift-frontend;
                                                               writes <out>/run.json and prints the differences
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

SOURCE = """import Foundation
@objc public protocol Listener { @objc optional func heard(_ value: Int) }
public class Counter: NSObject {
    @objc public dynamic var count = 0
    public weak var listener: Listener?
    public override var description: String { super.description + "!" }
    public func tell() { listener?.heard?(count) }
}
public func length(_ string: NSString) -> Int { string.length + string.hash }
public func past() -> Date { NSDate.distantPast }
public func make() -> NSObject { NSObject() }
public func count(_ counter: Counter) -> Int { counter.count }
public func set(_ counter: Counter) { counter.count = 2 }
public func responds(_ object: NSObject) -> Bool { object.responds(to: #selector(NSObject.copy)) }
public func lookup(_ object: AnyObject) -> Int? { object.length }
public func perform(_ object: NSObject) { _ = object.perform(#selector(NSObject.copy)) }
"""

CASES = [
    ("arm64-apple-ios15.0", "iphoneos", ["-O"]),
    ("arm64-apple-ios15.0", "iphoneos", ["-Onone"]),
    ("arm64-apple-ios12.0", "iphoneos", ["-O"]),
    ("arm64e-apple-ios15.0", "iphoneos", ["-O"]),
    ("arm64-apple-ios15.0-simulator", "iphonesimulator", ["-O"]),
    ("x86_64-apple-ios15.0-simulator", "iphonesimulator", ["-O"]),
    ("arm64_32-apple-watchos8.0", "watchos", ["-O"]),
    ("arm64-apple-ios15.0", "iphoneos", ["-O", "-disable-objc-msgsend-selector-stubs"]),
    ("arm64-apple-ios15.0", "iphoneos", ["-O", "-enable-objc-msgsend-selector-stubs"]),
    ("arm64-apple-ios15.0", "iphoneos", ["-O", "-enable-objc-msgsend-selector-stubs", "-disable-objc-msgsend-selector-stubs"]),
    ("arm64-apple-ios15.0", "iphoneos", ["-O", "-disable-objc-msgsend-selector-stubs", "-enable-objc-msgsend-selector-stubs"]),
    ("x86_64-apple-ios15.0-simulator", "iphonesimulator", ["-O", "-enable-objc-msgsend-selector-stubs"]),
]
DIRECT_REG_CASES = [
    ("arm64-apple-ios16.4", "iphoneos", ["-O"]),
    ("arm64-apple-ios17.0", "iphoneos", ["-O"]),
    ("arm64-apple-ios17.0", "iphoneos", ["-Onone"]),
    ("arm64e-apple-ios17.0", "iphoneos", ["-O"]),
    ("arm64-apple-ios17.0-simulator", "iphonesimulator", ["-O"]),
    ("x86_64-apple-ios17.0-simulator", "iphonesimulator", ["-O"]),
    ("arm64-apple-ios16.0-macabi", "macosx", ["-O"]),
    ("arm64-apple-ios17.0-macabi", "macosx", ["-O"]),
    ("arm64-apple-tvos16.0", "appletvos", ["-O"]),
    ("arm64-apple-tvos17.0", "appletvos", ["-O"]),
    ("arm64_32-apple-watchos9.0", "watchos", ["-O"]),
    ("arm64_32-apple-watchos10.0", "watchos", ["-O"]),
    ("arm64-apple-watchos10.0", "watchos", ["-O"]),
    ("arm64-apple-xros1.0", "xros", ["-O"]),
    ("arm64-apple-macos14.0", "macosx", ["-O"]),
    ("arm64-apple-macos26.0", "macosx", ["-O"]),
]
PLATFORMS = {"iphoneos": "iPhoneOS", "iphonesimulator": "iPhoneSimulator", "watchos": "WatchOS", "appletvos": "AppleTVOS",
             "xros": "XROS", "macosx": "MacOSX"}
DIRECT_REG = re.compile(r'!"Swift DirectReg Version", i32 (\d+)')


def messages(text):
    """The Objective-C messengers the module calls, the selectors it references, and the stubs' forms."""
    calls = sorted(set(re.findall(r'call [^@\n]*@("?objc_msgSend[^"(\s]*"?)\(', text)))
    selectors = sorted(set(re.findall(r'@"\\01L_selector_data\(([^)]*)\)"', text)))
    declarations = sorted(set(line for line in text.splitlines() if line.startswith("declare") and "objc_msgSend$" in line))
    arguments = sorted(set(re.sub(r"%\d+", "%N", argument)
                           for argument in re.findall(r'call [^@\n]*@"objc_msgSend\$[^"]*"\(([^)]*)\)', text)))
    flag = DIRECT_REG.search(text)
    return {"directRegVersion": int(flag.group(1)) if flag else None, "messengers": [name.strip('"') for name in calls], "selectorReferences": selectors,
            "stubDeclarations": [re.sub(r'@"objc_msgSend\$[^"]*"', '@"objc_msgSend$<selector>"', line) for line in declarations][:1],
            "stubArguments": arguments}


def report(frontend, sdks, out):
    source = out / "src" / "messages.swift"
    source.parent.mkdir(parents=True, exist_ok=True)
    source.write_text(SOURCE)
    results = {}
    for target, sdk, flags in CASES + DIRECT_REG_CASES:
        if not Path(sdks[sdk]).is_dir():
            continue
        command = [frontend, "-frontend", "-c", "-emit-ir", "-target", target, "-sdk", sdks[sdk], "-parse-as-library",
                   str(source), "-module-name", "Messages", "-o", "-"] + flags
        result = subprocess.run(command, capture_output=True, text=True)
        case = f"{target} {' '.join(flags)}"
        results[case] = messages(result.stdout) if result.returncode == 0 else {"error": (result.stderr.strip().splitlines() or [""])[:1]}
    return results


def xcode(out):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    frontend = str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend")
    sdks = {sdk: subprocess.run(["xcrun", "--sdk", sdk, "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
            for sdk in PLATFORMS}
    results = report(frontend, sdks, out)
    (out / "xcode.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


def run(out, developer):
    frontend = str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend")
    sdks = {sdk: str(Path(developer) / f"Platforms/{name}.platform/Developer/SDKs/{name}.sdk") for sdk, name in PLATFORMS.items()}
    ours = report(frontend, sdks, out)
    expected = json.loads((out / "xcode.json").read_text())
    differences = {case: {key: {"ours": ours[case].get(key), "xcode": expected[case].get(key)}
                          for key in expected[case] if ours[case].get(key) != expected[case].get(key)}
                   for case in ours if ours[case] != expected.get(case)}
    (out / "run.json").write_text(json.dumps(ours, indent=2) + "\n")
    print(json.dumps({"cases": len(ours), "withoutSDK": len(expected) - len(ours), "differences": differences}, indent=2))


if __name__ == "__main__":
    if sys.argv[1:2] == ["xcode"]:
        xcode(Path(sys.argv[2]).resolve())
    elif sys.argv[1:2] == ["run"]:
        run(Path(sys.argv[2]).resolve(), sys.argv[3])
    else:
        sys.exit(__doc__)

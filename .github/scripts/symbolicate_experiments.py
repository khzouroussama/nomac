#!/usr/bin/env python3
"""Compare `nomac atos -i` with Xcode's `atos -i` on the dSYMs of builds (docs/formats/crash-report.md).

Runs on a Mac with Xcode. For each DWARF file of each dSYM given, samples addresses across its
text symbols (each symbol's start and three points inside it, up to --limit), asks both tools
for them in one run each, with the image loaded at its `__TEXT` address, and prints one line per
DWARF file: the addresses compared and how many results differ, then the first differences. The
outputs stay in --output, outside the repository.

With --report, a crash report (.ips) instead: every frame of an image a given dSYM has the UUID
of, as `nomac device symbolicate` prints it, against `atos -i` at the frame's address with the
image loaded at the report's base.

With --crash-demo, a self-written app (signing_experiments.py's app with Kit, CRASH_APP_SOURCE and
CRASH_KIT_SOURCE: an Objective-C exception three calls deep in the framework, one call inlined)
crashes and its report is compared as with --report. On the simulator by default: built with
xcodebuild (Release), run in a simulator created for it and deleted after, its report taken
from ~/Library/Logs/DiagnosticReports (and removed there). With --device UDID and --archive, an
archive of that app nomac built and signed for the device: `nomac install`, `nomac launch
--console` until the app closes it, `nomac device crashes` for the report.

usage: symbolicate_experiments.py --output DIR [--nomac .build/debug/nomac] [--limit N] DSYM...
       symbolicate_experiments.py --output DIR --report REPORT.ips DSYM...
       symbolicate_experiments.py --output DIR --crash-demo [--device UDID --archive APP.xcarchive]
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

DEVELOPER_DIR = "/Applications/Xcode_27.app/Contents/Developer"

CRASH_APP_SOURCE = """import Foundation
import Kit
import SwiftUI

@main
struct CrashDemoApp: App {
    init() {
        print("crashdemo: started")
        FileHandle.standardError.write(Data("crashdemo: crashing in 2 seconds\\n".utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Crasher.crash() }
    }

    var body: some Scene {
        WindowGroup {
            Text("nomac crash demo")
        }
    }
}
"""

CRASH_KIT_SOURCE = """import Foundation

public enum Crasher {
    public static func crash() { level1(3) }

    @inline(never) static func level1(_ value: Int) { level2(value * 2) }

    @inline(__always) static func level2(_ value: Int) { level3(value + 1) }

    @inline(never) static func level3(_ value: Int) {
        NSException(name: .invalidArgumentException, reason: "nomac crash demo: level3(\\(value))").raise()
    }
}
"""


def text_symbols(path, arch):
    lines = subprocess.run(["nm", "-n", "-arch", arch, path], capture_output=True, text=True, check=True).stdout.splitlines()
    return sorted({int(fields[0], 16) for fields in (line.split() for line in lines) if len(fields) >= 3 and fields[1] in "tT"})


def text_address(path, arch):
    output = subprocess.run(["otool", "-arch", arch, "-l", path], capture_output=True, text=True, check=True).stdout
    match = re.search(r"segname __TEXT\n\s+vmaddr (0x[0-9a-f]+)", output)
    return int(match.group(1), 16) if match else 0


def addresses(symbols, limit):
    sampled = set()
    for start, end in zip(symbols, symbols[1:]):
        for quarter in range(4):
            sampled.add(start + (end - start) * quarter // 4 // 4 * 4)
    ordered = sorted(sampled)
    step = max(1, len(ordered) // limit)
    return ordered[::step][:limit]


def compare(dwarf, arch, nomac, limit, output):
    symbols = text_symbols(dwarf, arch)
    if len(symbols) < 2:
        return None
    sample = addresses(symbols, limit)
    load = hex(text_address(dwarf, arch))
    arguments = ["-i", "-o", dwarf, "-arch", arch, "-l", load] + [hex(a) for a in sample]
    xcode = subprocess.run(["xcrun", "atos"] + arguments, capture_output=True, text=True, check=True,
                           env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}).stdout
    ours = subprocess.run([nomac, "atos", "--developer-dir", DEVELOPER_DIR] + arguments, capture_output=True, text=True, check=True).stdout
    name = os.path.basename(dwarf)
    with open(os.path.join(output, name + ".atos"), "w") as file:
        file.write(xcode)
    with open(os.path.join(output, name + ".nomac"), "w") as file:
        file.write(ours)
    left, right = xcode.split("\n\n"), ours.split("\n\n")
    differences = [(hex(a), x, y) for a, x, y in zip(sample, left, right) if x != y]
    if len(left) != len(right):
        differences.append(("count", str(len(left)), str(len(right))))
    return name, len(sample), differences


def dwarf_files(dsym):
    folder = os.path.join(dsym, "Contents/Resources/DWARF")
    return [os.path.join(folder, name) for name in sorted(os.listdir(folder))]


def uuids(dwarf):
    output = subprocess.run(["dwarfdump", "--uuid", dwarf], capture_output=True, text=True, check=True).stdout
    return {match.group(1).upper(): match.group(2) for match in re.finditer(r"UUID: ([0-9A-F-]+) \((\w+)\)", output)}


def compare_report(report, dsyms, nomac, output):
    """Each app frame's `atos -i` lines against `nomac device symbolicate`'s."""
    header, body = open(report).read().split("\n", 1)
    body = json.loads(body)
    images = body["usedImages"]
    by_uuid = {}
    for dsym in dsyms:
        for dwarf in dwarf_files(dsym):
            for uuid, arch in uuids(dwarf).items():
                by_uuid[uuid] = (dwarf, arch)
    rendered = subprocess.run([nomac, "device", "symbolicate", report, "--developer-dir", DEVELOPER_DIR] + [x for d in dsyms for x in ("--dsym", d)],
                              capture_output=True, text=True, check=True).stdout
    with open(os.path.join(output, os.path.basename(report) + ".txt"), "w") as file:
        file.write(rendered)
    frames = list(body.get("lastExceptionBacktrace", []))
    for thread in body["threads"]:
        frames += thread["frames"]
    compared = differing = 0
    for frame in frames:
        image = images[frame["imageIndex"]]
        found = by_uuid.get(image.get("uuid", "").upper())
        if not found:
            continue
        dwarf, arch = found
        xcode = subprocess.run(["xcrun", "atos", "-i", "-o", dwarf, "-arch", arch, "-l", hex(image["base"]), hex(image["base"] + frame["imageOffset"])],
                               capture_output=True, text=True, check=True, env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}).stdout.strip()
        lines = [line.replace("(in " + os.path.basename(dwarf) + ")", "(in " + image["name"] + ")") for line in xcode.split("\n") if line]
        compared += 1
        if not all(line in rendered for line in lines):
            differing += 1
            print(f"  {image['name']} +{hex(frame['imageOffset'])}: atos {lines}")
    print(f"{os.path.basename(report)}: {compared} app frames, {differing} differ")


def run(argv, **options):
    return subprocess.run(argv, capture_output=True, text=True, check=True, env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}, **options)


def write_crash_demo(folder):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import signing_experiments
    files = signing_experiments.app_project(["Kit"], [], app_source=CRASH_APP_SOURCE, kit_source=CRASH_KIT_SOURCE)
    for path, text in files.items():
        os.makedirs(os.path.dirname(os.path.join(folder, path)), exist_ok=True)
        with open(os.path.join(folder, path), "w") as file:
            file.write(text)


def crash_demo_simulator(output, nomac):
    source = os.path.join(output, "crash-demo")
    shutil.rmtree(source, ignore_errors=True)
    write_crash_demo(source)
    derived = os.path.join(output, "crash-demo-dd")
    run(["xcodebuild", "-project", "Signing.xcodeproj", "-scheme", "App", "-configuration", "Release",
         "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived, "CODE_SIGN_IDENTITY=-",
         "INFOPLIST_KEY_UIApplicationSceneManifest_Generation=YES", "build"], cwd=source)
    products = os.path.join(derived, "Build/Products/Release-iphonesimulator")
    simulator = run(["xcrun", "simctl", "create", "nomac-crash-demo", "iPhone 16", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"]).stdout.strip()
    reports = os.path.expanduser("~/Library/Logs/DiagnosticReports")
    started = time.time()
    try:
        run(["xcrun", "simctl", "boot", simulator])
        run(["xcrun", "simctl", "bootstatus", simulator, "-b"])
        run(["xcrun", "simctl", "install", simulator, os.path.join(products, "App.app")])
        # Launched without --console-pty: with it, the simulator's crash reporter wrote nothing.
        run(["xcrun", "simctl", "launch", simulator, "org.nomac.signing"])
        report = None
        for _ in range(30):
            time.sleep(2)
            for path in glob.glob(os.path.join(reports, "App-*.ips")):
                with open(path) as file:
                    if os.path.getmtime(path) >= started and json.loads(file.readline()).get("bundleID") == "org.nomac.signing":
                        report = path
            if report:
                break
        if not report:
            sys.exit("the simulator wrote no crash report")
        copy = os.path.join(output, "crash-demo-simulator.ips")
        shutil.copyfile(report, copy)
        for path in glob.glob(os.path.join(reports, "App-*.ips")):
            with open(path) as file:
                if os.path.getmtime(path) >= started and json.loads(file.readline()).get("bundleID") == "org.nomac.signing":
                    os.remove(path)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True, env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR})
        subprocess.run(["xcrun", "simctl", "delete", simulator], capture_output=True, env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR})
    compare_report(copy, [os.path.join(products, "App.app.dSYM"), os.path.join(products, "Kit.framework.dSYM")], nomac, output)


def crash_demo_device(output, nomac, device, archive):
    app = glob.glob(os.path.join(archive, "Products/Applications/*.app"))[0]
    with open(os.path.join(app, "Info.plist"), "rb") as file:
        import plistlib
        identifier = plistlib.load(file)["CFBundleIdentifier"]
    run([nomac, "install", app, "--device", device])
    console = run([nomac, "launch", identifier, "--device", device, "--console"], timeout=120).stdout
    with open(os.path.join(output, "crash-demo-console.txt"), "w") as file:
        file.write(console)
    print("console:", "uncaught exception printed" if "nomac crash demo: level3(7)" in console else "no exception message",
          "/", "closed" if "closed its console" in console else "not closed")
    time.sleep(3)
    folder = os.path.join(output, "crash-demo-device")
    shutil.rmtree(folder, ignore_errors=True)
    run([nomac, "device", "crashes", "--device", device, "--process", "App", "--last", "1", "--output", folder])
    report = glob.glob(os.path.join(folder, "*.ips"))[0]
    compare_report(report, sorted(glob.glob(os.path.join(archive, "dSYMs/*.dSYM"))), nomac, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", required=True)
    parser.add_argument("--nomac", default=".build/debug/nomac")
    parser.add_argument("--limit", type=int, default=3000)
    parser.add_argument("--arch", default="arm64")
    parser.add_argument("--report")
    parser.add_argument("--crash-demo", action="store_true")
    parser.add_argument("--device")
    parser.add_argument("--archive")
    parser.add_argument("dsyms", nargs="*")
    arguments = parser.parse_args()
    os.makedirs(arguments.output, exist_ok=True)
    if arguments.crash_demo:
        nomac = os.path.abspath(arguments.nomac)
        if arguments.device:
            return crash_demo_device(arguments.output, nomac, arguments.device, os.path.abspath(arguments.archive))
        return crash_demo_simulator(arguments.output, nomac)
    if arguments.report:
        return compare_report(arguments.report, arguments.dsyms, os.path.abspath(arguments.nomac), arguments.output)
    for dsym in arguments.dsyms:
        folder = os.path.join(dsym, "Contents/Resources/DWARF")
        for name in sorted(os.listdir(folder)):
            result = compare(os.path.join(folder, name), arguments.arch, os.path.abspath(arguments.nomac), arguments.limit, arguments.output)
            if result is None:
                continue
            name, count, differences = result
            print(f"{name}: {count} addresses, {len(differences)} differ")
            for address, xcode, ours in differences[:3]:
                print(f"  {address}\n    atos:  {xcode.strip()[:300]}\n    nomac: {ours.strip()[:300]}")


if __name__ == "__main__":
    main()

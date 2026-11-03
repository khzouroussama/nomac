#!/usr/bin/env python3
"""Another embeddedBinaryValidationUtility against Xcode's, on apps with embedded bundles.

Swift Build runs `embeddedBinaryValidationUtility <bundle> [-signing-cert <identity>]
-info-plist-path <app's Info.plist>` for each app extension and app an app embeds
(`ValidateEmbeddedBinary`); the RN sweep's Linux builds have no such tool (expo-with-widgets, zeus).
This makes an app with one embedded bundle per case (an extension, a watch app, an App Clip), varies
the bundle's Info.plist, the signatures and the arguments, and records what Xcode 27.0's utility
prints and returns.

Usage:
  embedded_binary_validation_experiments.py capture <out>            Mac: record Xcode's
  embedded_binary_validation_experiments.py run <out> <command ...>  run the cases with <command>, compare
Messages are compared with object addresses (`0x…`) left out.
"""

import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

UTILITY = "/Applications/Xcode_27.app/Contents/Developer/usr/bin/embeddedBinaryValidationUtility"
APP = {"CFBundleIdentifier": "com.example.app", "CFBundleExecutable": "App", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
EXTENSION = {"NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}

# name: (folder and bundle name, Info.plist changes (None deletes), signing of app and bundle, -signing-cert)
CASES = {
    "extension": ("PlugIns/W.appex", EXTENSION, None, None),
    "extension-short-version": ("PlugIns/W.appex", {**EXTENSION, "CFBundleShortVersionString": "2.0"}, None, None),
    "extension-version": ("PlugIns/W.appex", {**EXTENSION, "CFBundleVersion": "7"}, None, None),
    "extension-both-versions": ("PlugIns/W.appex", {**EXTENSION, "CFBundleShortVersionString": "2.0", "CFBundleVersion": "7"}, None, None),
    "extension-no-version": ("PlugIns/W.appex", {**EXTENSION, "CFBundleVersion": None}, None, None),
    "extension-no-short-version": ("PlugIns/W.appex", {**EXTENSION, "CFBundleShortVersionString": None}, None, None),
    "extension-prefix": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.other.w"}, None, None),
    "extension-prefix-and-version": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.other.w", "CFBundleVersion": "7"}, None, None),
    "extension-prefix-case": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "COM.example.app.w"}, None, None),
    "extension-prefix-no-dot": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.example.appx"}, None, None),
    "extension-same-identifier": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.example.app"}, None, None),
    "extension-no-identifier": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": None}, None, None),
    "extension-empty-dictionary": ("PlugIns/W.appex", {"NSExtension": {}, "CFBundleIdentifier": "com.other.w"}, None, None),
    "extensionkit": ("Extensions/W.appex", {"EXAppExtensionAttributes": {}, "CFBundleIdentifier": "com.other.w", "CFBundleVersion": "7"}, None, None),
    "plain-bundle-prefix": ("PlugIns/W.appex", {"CFBundleIdentifier": "com.other.w", "CFBundleVersion": "7"}, None, None),
    "binary-info-plist": ("PlugIns/W.appex", {**EXTENSION, "CFBundleVersion": "7", "binary": True}, None, None),
    "no-info-plist": ("PlugIns/W.appex", {"remove": True}, None, None),
    "parent-no-identifier": ("PlugIns/W.appex", {**EXTENSION, "parent": {"CFBundleIdentifier": None}}, None, None),
    "parent-no-version": ("PlugIns/W.appex", {**EXTENSION, "parent": {"CFBundleVersion": None}}, None, None),
    "watch-app": ("Watch/W.app", {"WKWatchKitApp": True, "WKCompanionAppBundleIdentifier": "com.example.app", "CFBundleVersion": "7"}, None, None),
    "watch-app-prefix": ("Watch/W.app", {"WKWatchKitApp": True, "WKCompanionAppBundleIdentifier": "com.example.app", "CFBundleIdentifier": "com.other.w"}, None, None),
    "watch-application-prefix": ("Watch/W.app", {"WKApplication": True, "WKCompanionAppBundleIdentifier": "com.example.app", "CFBundleIdentifier": "com.other.w"}, None, None),
    "app-clip": ("AppClips/W.app", {"NSAppClip": {}, "CFBundleIdentifier": "com.example.app.Clip", "CFBundleVersion": "7"}, None, None),
    "app-clip-prefix": ("AppClips/W.app", {"NSAppClip": {}, "CFBundleIdentifier": "com.other.w"}, None, None),
    "ad-hoc": ("PlugIns/W.appex", EXTENSION, "ad-hoc", "-"),
    "ad-hoc-plain-bundle": ("PlugIns/W.appex", {}, "ad-hoc", "-"),
    "unsigned-bundle": ("PlugIns/W.appex", EXTENSION, "app", "-"),
    "unsigned-plain-bundle": ("PlugIns/W.appex", {}, "app", "-"),
    "unsigned-watch-app": ("Watch/W.app", {"WKWatchKitApp": True, "WKCompanionAppBundleIdentifier": "com.example.app"}, "app", "-"),
    "unknown-identity": ("PlugIns/W.appex", EXTENSION, "ad-hoc", "0000000000000000000000000000000000000000"),
    "unknown-identity-unsigned": ("PlugIns/W.appex", EXTENSION, None, "Apple Development"),
    "unknown-identity-and-prefix": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.other.w"}, "ad-hoc", "Apple Development"),
    "empty-identity": ("PlugIns/W.appex", EXTENSION, None, ""),
    "no-info-plist-unsigned": ("PlugIns/W.appex", {"remove": True}, "app", "-"),
    "no-parent-info-plist": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.other.w", "parent": {"remove": True}}, None, None),
    "no-arguments": ("PlugIns/W.appex", EXTENSION, None, None),
    "two-bundles": ("PlugIns/W.appex", EXTENSION, None, None),
    "no-info-plist-path": ("PlugIns/W.appex", {**EXTENSION, "CFBundleIdentifier": "com.other.w"}, None, None),
}


def make(root, case, executable):
    folder, changes, signing, _ = CASES[case]
    app = root / case / "App.app"
    shutil.rmtree(root / case, ignore_errors=True)
    bundle = app / folder
    bundle.mkdir(parents=True)
    shutil.copy(executable, app / "App")
    name = Path(folder).stem
    shutil.copy(executable, bundle / name)
    parent = {**APP}
    for key, value in changes.get("parent", {}).items():
        if key != "remove":
            parent.pop(key) if value is None else parent.__setitem__(key, value)
    if not changes.get("parent", {}).get("remove"):
        (app / "Info.plist").write_bytes(plistlib.dumps(parent))
    embedded = {**APP, "CFBundleIdentifier": "com.example.app." + name, "CFBundleExecutable": name}
    for key, value in changes.items():
        if key in ("parent", "binary", "remove"):
            continue
        embedded.pop(key) if value is None else embedded.__setitem__(key, value)
    if not changes.get("remove"):
        form = plistlib.FMT_BINARY if changes.get("binary") else plistlib.FMT_XML
        (bundle / "Info.plist").write_bytes(plistlib.dumps(embedded, fmt=form))
    if signing == "ad-hoc":
        subprocess.run(["codesign", "-s", "-", "-f", str(bundle)], check=True, capture_output=True)
    if signing in ("ad-hoc", "app"):
        subprocess.run(["codesign", "-s", "-", "-f", str(app)], check=True, capture_output=True)
    return app, bundle


def arguments(case, app, bundle):
    if case == "no-arguments":
        return []
    if case == "two-bundles":
        return [str(bundle), str(bundle), "-info-plist-path", str(app / "Info.plist")]
    if case == "no-info-plist-path":
        return [str(bundle)]
    identity = CASES[case][3]
    return [str(bundle)] + (["-signing-cert", identity] if identity is not None else []) + ["-info-plist-path", str(app / "Info.plist")]


def tree(path):
    return {str(p.relative_to(path)): p.read_bytes() for p in sorted(path.rglob("*")) if p.is_file()}


def run_cases(command, out):
    found = {}
    for case in CASES:
        app = out / "apps" / case / "App.app"
        bundle = app / CASES[case][0]
        before = tree(app)
        proc = subprocess.run(command + arguments(case, app, bundle), capture_output=True, text=True)
        normal = lambda text: re.sub(r"0x[0-9a-f]+", "0x", text.replace(str(out), "<out>"))
        found[case] = {"status": proc.returncode, "stdout": normal(proc.stdout), "stderr": normal(proc.stderr), "unchanged": tree(app) == before}
    return found


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "capture":
        (out / "apps").mkdir(parents=True, exist_ok=True)
        sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
        (out / "main.c").write_text("int main(void) { return 0; }\n")
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk, str(out / "main.c"), "-o", str(out / "executable")], check=True)
        for case in CASES:
            make(out / "apps", case, out / "executable")
        (out / "macos.json").write_text(json.dumps(run_cases([UTILITY], out), indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = run_cases(sys.argv[3:], out)
    same = [case for case in expected if found.get(case) == expected[case]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(expected)} cases like Xcode's embeddedBinaryValidationUtility")
    for case in expected:
        if case not in same:
            print(f"    {case}: {expected[case]} vs {found.get(case)}")


if __name__ == "__main__":
    main()

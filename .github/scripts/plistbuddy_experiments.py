#!/usr/bin/env python3
"""Another PlistBuddy against macOS's /usr/libexec/PlistBuddy, for the commands build scripts run.

script_phase_survey.py finds `/usr/libexec/PlistBuddy -c '<command>' <file>` in 9 of 45 test apps:
React Native's asset-catalog.sh (`Print :RCTUseAssetCatalog`, every React Native and Expo Release
build), and `Add`, `Set`, `Delete` and `Print` on Info.plist, entitlements and Settings bundles
(home-assistant, signal, session, habitica). Each case runs commands on a copy of an input file;
the standard output and error, the exit status and the file's bytes afterwards are compared.

Usage:
  plistbuddy_experiments.py inputs <out>               Mac: write the inputs, run /usr/libexec/PlistBuddy
  plistbuddy_experiments.py run <out> <command ...>    run the cases with <command>, compare; writes <out>/results.json
"""

import json
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

INFO = {"CFBundleName": "App", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSRequiresIPhoneOS": True,
        "RCTUseAssetCatalog": False, "UIRequiredDeviceCapabilities": ["arm64"], "Count": 3, "Ratio": 0.5,
        "Blob": b"\x00\x01binary", "When": __import__("datetime").datetime(2026, 10, 24, 12, 0, 0),
        "PreferenceSpecifiers": [{"Type": "PSGroupSpecifier", "Title": "About"},
                                 {"Type": "PSTitleValueSpecifier", "Key": "version", "DefaultValue": "0"}],
        "Zeta": "z", "alpha": "a", "Été": "accent"}

INPUTS = {
    "info.plist": lambda: plistlib.dumps(INFO, fmt=plistlib.FMT_XML, sort_keys=False),
    "binary.plist": lambda: plistlib.dumps(INFO, fmt=plistlib.FMT_BINARY, sort_keys=False),
    "entitlements.plist": lambda: plistlib.dumps({"aps-environment": "development"}, fmt=plistlib.FMT_XML),
}

CASES = {
    "print-string": ("info.plist", ["Print :CFBundleName"]),
    "print-without-colon": ("info.plist", ["Print CFBundleName"]),
    "print-lowercase": ("info.plist", ["print :CFBundleVersion"]),
    "print-false": ("info.plist", ["Print :RCTUseAssetCatalog"]),
    "print-true": ("info.plist", ["Print :LSRequiresIPhoneOS"]),
    "print-integer": ("info.plist", ["Print :Count"]),
    "print-real": ("info.plist", ["Print :Ratio"]),
    "print-data": ("info.plist", ["Print :Blob"]),
    "print-date": ("info.plist", ["Print :When"]),
    "print-array": ("info.plist", ["Print :UIRequiredDeviceCapabilities"]),
    "print-dict-in-array": ("info.plist", ["Print :PreferenceSpecifiers:1"]),
    "print-nested": ("info.plist", ["Print :PreferenceSpecifiers:1:DefaultValue"]),
    "print-whole": ("info.plist", ["Print"]),
    "print-missing": ("info.plist", ["Print :Missing"]),
    "print-binary": ("binary.plist", ["Print :CFBundleName"]),
    "add-string": ("info.plist", ["Add :GitCommitHash string abc1234"]),
    "add-string-empty": ("info.plist", ["Add :GitCommitHash string"]),
    "add-lowercase-bool": ("entitlements.plist", ["add com.apple.developer.usernotifications.critical-alerts bool true"]),
    "add-array-then-quoted-item": ("entitlements.plist", ["add com.apple.developer.networking.networkextension array",
                                                          "add com.apple.developer.networking.networkextension:0 string 'app-push-provider'"]),
    "add-dict-then-children": ("info.plist", ["Delete BuildDetails", "add BuildDetails dict",
                                              "add :BuildDetails:XCodeVersion string '27.0'",
                                              "add :BuildDetails:Timestamp integer 1793000000"]),
    "add-real-date-data": ("info.plist", ["Add :R real 2.25", "Add :D date 'Sat Oct 24 12:00:00 UTC 2026'", "Add :B data hello"]),
    "add-existing": ("info.plist", ["Add :CFBundleName string Other"]),
    "add-binary": ("binary.plist", ["Add :GitCommitHash string abc1234"]),
    "set-string": ("info.plist", ["Set :CFBundleVersion 42"]),
    "set-in-array": ("info.plist", ["Set PreferenceSpecifiers:1:DefaultValue 2.3.4"]),
    "set-backquote-style": ("info.plist", ["Set :GitCommitHash abc"]),
    "set-bool": ("info.plist", ["Set :RCTUseAssetCatalog true"]),
    "set-two-words": ("info.plist", ["Set :CFBundleName Two Words"]),
    "add-quoted-spaces": ("info.plist", ["Add :Sentence string 'a b  c'", "Print :Sentence"]),
    "add-double-quoted": ("info.plist", ['Add :Quoted string "x y"', "Print :Quoted"]),
    "add-bool-yes": ("info.plist", ["Add :Flag bool YES", "Add :Other bool 0", "Print :Flag", "Print :Other"]),
    "add-integer-negative": ("info.plist", ["Add :Neg integer -5", "Print :Neg"]),
    "print-after-add": ("info.plist", ["Add :Late string x", "Print"]),
    "delete": ("info.plist", ["Delete :Zeta"]),
    "delete-missing": ("info.plist", ["Delete BuildDetails"]),
    "missing-file-add": (None, ["Add :Key string value"]),
    "missing-file-print": (None, ["Print :Key"]),
}


def run_case(command, inputs, work, name, case):
    source, commands = case
    work.mkdir(parents=True, exist_ok=True)
    target = work / name
    if target.exists():
        target.unlink()
    if source:
        shutil.copy(inputs / source, target)
    argv = command + [part for c in commands for part in ("-c", c)] + [str(target)]
    proc = subprocess.run(argv, capture_output=True, cwd=work, env={**__import__("os").environ, "TZ": "UTC"})
    clean = lambda text: text.decode(errors="replace").replace(str(target), "<file>")
    return {"status": proc.returncode, "stdout": clean(proc.stdout), "stderr": clean(proc.stderr),
            "file": target.read_bytes().hex() if target.exists() else None}


def main():
    out = Path(sys.argv[2]).resolve()
    inputs = out / "inputs"
    if sys.argv[1] == "inputs":
        inputs.mkdir(parents=True, exist_ok=True)
        for name, make in INPUTS.items():
            (inputs / name).write_bytes(make())
        expected = {name: run_case(["/usr/libexec/PlistBuddy"], inputs, out / "macos", name, case) for name, case in CASES.items()}
        (out / "macos.json").write_text(json.dumps(expected, indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = {name: run_case(sys.argv[3:], inputs, out / "other", name, case) for name, case in CASES.items()}
    same = [name for name in CASES if found[name] == expected[name]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(CASES)} cases like macOS's PlistBuddy")
    for name in CASES:
        if name not in same:
            diff = [k for k in ("status", "stdout", "stderr", "file") if found[name][k] != expected[name][k]]
            print(f"    {name}: {', '.join(diff)}")


if __name__ == "__main__":
    main()

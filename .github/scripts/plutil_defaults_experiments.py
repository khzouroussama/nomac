#!/usr/bin/env python3
"""Another plutil and defaults against macOS's, for the forms build scripts run.

script_phase_survey.py finds `plutil -extract <keypath> raw -expect <type>`, `-replace <keypath>
-array` and `-insert <keypath> -string <value>` on a built Info.plist (pocket-casts) and `defaults
write <Info.plist path without .plist> <key> <value>` (owncloud). Each case runs on a copy of an
input; the standard output and error, the exit status and the file's bytes afterwards are compared.

Usage:
  plutil_defaults_experiments.py inputs <out>                          Mac: write the inputs, run macOS's tools
  plutil_defaults_experiments.py run <out> <plutil command> <defaults command>   compare; writes <out>/results.json
  (each command a single word or a quoted string, for example "nomac plutil")
"""

import json
import plistlib
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

INFO = {"CFBundleName": "App", "CFBundleVersion": "1", "LSRequiresIPhoneOS": True, "Count": 3,
        "CFBundleURLTypes": [{"CFBundleURLName": "GoogleSignIn", "CFBundleURLSchemes": ["old"]},
                             {"CFBundleURLName": "Other", "CFBundleURLSchemes": ["x"]}]}
INPUTS = {
    "info.plist": lambda: plistlib.dumps(INFO, fmt=plistlib.FMT_XML),
    "built.plist": lambda: plistlib.dumps(INFO, fmt=plistlib.FMT_BINARY),
}

# (tool, input, arguments with {file} for the copy, {domain} for the copy without .plist)
CASES = {
    "extract-array-count": ("plutil", "built.plist", ["-extract", "CFBundleURLTypes", "raw", "-expect", "array", "{file}"]),
    "extract-string": ("plutil", "built.plist", ["-extract", "CFBundleURLTypes.0.CFBundleURLName", "raw", "-expect", "string", "{file}"]),
    "extract-integer": ("plutil", "info.plist", ["-extract", "Count", "raw", "{file}"]),
    "extract-bool": ("plutil", "info.plist", ["-extract", "LSRequiresIPhoneOS", "raw", "{file}"]),
    "extract-wrong-type": ("plutil", "info.plist", ["-extract", "CFBundleName", "raw", "-expect", "array", "{file}"]),
    "extract-missing": ("plutil", "info.plist", ["-extract", "Missing", "raw", "{file}"]),
    "extract-xml1-to-stdout": ("plutil", "info.plist", ["-extract", "CFBundleURLTypes.1", "xml1", "-o", "-", "{file}"]),
    "replace-array-binary": ("plutil", "built.plist", ["-replace", "CFBundleURLTypes.0.CFBundleURLSchemes", "-array", "{file}"]),
    "insert-string-binary": ("plutil", "built.plist", ["-insert", "CFBundleURLTypes.0.CFBundleURLSchemes.0", "-string", "com.example", "{file}"]),
    "replace-string-xml": ("plutil", "info.plist", ["-replace", "CFBundleVersion", "-string", "42", "{file}"]),
    "insert-existing": ("plutil", "info.plist", ["-insert", "CFBundleName", "-string", "Other", "{file}"]),
    "insert-integer-bool": ("plutil", "info.plist", ["-insert", "Build", "-integer", "7", "{file}"]),
    "defaults-write-binary": ("defaults", "built.plist", ["write", "{domain}", "LastGitCommit", "abc1234"]),
    "defaults-write-xml": ("defaults", "info.plist", ["write", "{domain}", "GitBranch", "main"]),
    "defaults-write-new-file": ("defaults", None, ["write", "{domain}", "BuildDate", "2026-10-24"]),
    "defaults-read-key": ("defaults", "info.plist", ["read", "{domain}", "CFBundleName"]),
}


def run_case(commands, inputs, work, name, case):
    tool, source, arguments = case
    work.mkdir(parents=True, exist_ok=True)
    target = work / f"{name}.plist"
    if target.exists():
        target.unlink()
    if source:
        shutil.copy(inputs / source, target)
    argv = commands[tool] + [a.replace("{file}", str(target)).replace("{domain}", str(target.with_suffix(""))) for a in arguments]
    proc = subprocess.run(argv, capture_output=True, cwd=work)
    clean = lambda text: text.decode(errors="replace").replace(str(target.with_suffix("")), "<file>")
    return {"status": proc.returncode, "stdout": clean(proc.stdout), "stderr": clean(proc.stderr),
            "file": target.read_bytes().hex() if target.exists() else None}


def main():
    out = Path(sys.argv[2]).resolve()
    inputs = out / "inputs"
    if sys.argv[1] == "inputs":
        inputs.mkdir(parents=True, exist_ok=True)
        for name, make in INPUTS.items():
            (inputs / name).write_bytes(make())
        commands = {"plutil": ["/usr/bin/plutil"], "defaults": ["/usr/bin/defaults"]}
        expected = {name: run_case(commands, inputs, out / "macos", name, case) for name, case in CASES.items()}
        (out / "macos.json").write_text(json.dumps(expected, indent=2) + "\n")
        return
    commands = {"plutil": shlex.split(sys.argv[3]), "defaults": shlex.split(sys.argv[4])}
    expected = json.loads((out / "macos.json").read_text())
    found = {name: run_case(commands, inputs, out / "other", name, case) for name, case in CASES.items()}
    same = [name for name in CASES if found[name] == expected[name]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(CASES)} cases like macOS's plutil and defaults")
    for name in CASES:
        if name not in same:
            print(f"    {name}: {', '.join(k for k in ('status', 'stdout', 'stderr', 'file') if found[name][k] != expected[name][k])}")


if __name__ == "__main__":
    main()

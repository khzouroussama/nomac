#!/usr/bin/env python3
"""Another `derq` against macOS's, for the form Swift Build runs.

Swift Build's `ProcessProductPackagingDER` task, which every build that signs with entitlements
runs (an app signed with a development identity: `application-identifier`, the team and
`get-task-allow`), is `/usr/bin/derq query -f xml -i <App.app.xcent> -o <App.app.xcent.der> --raw`
(SWBTaskConstruction's GeneratedFilesTaskProducer). Linux has no derq.

Usage:
  derq_experiments.py inputs <out>              Mac: write the entitlements files and encode them
                                                with /usr/bin/derq
  derq_experiments.py run <out> <command ...>   encode them with <command> (for example
                                                `nomac derq`), compare with macOS's; writes
                                                <out>/results.json
"""

import json
import plistlib
import subprocess
import sys
from pathlib import Path

CASES = {
    "empty": {},
    "development": {"application-identifier": "TEAM123456.dev.nomac.App", "com.apple.developer.team-identifier": "TEAM123456",
                    "get-task-allow": True},
    "arrays": {"keychain-access-groups": ["TEAM123456.dev.nomac.App", "TEAM123456.shared"],
               "com.apple.security.application-groups": ["group.dev.nomac"]},
    "nested": {"com.apple.developer.associated-domains": ["applinks:example.com"],
               "com.apple.developer.icloud-container-environment": "Production",
               "com.apple.developer.ubiquity-kvstore-identifier": "TEAM123456.*"},
    "false-and-integers": {"get-task-allow": False, "com.apple.developer.kernel.increased-memory-limit": True,
                           "com.example.small": 1, "com.example.negative": -2, "com.example.large": 300000, "com.example.zero": 0},
    "unicode-and-order": {"zeta": "ä€😀", "Alpha": "x", "alpha": "y", "a.b": "z", "a": {"inner": ["é", True]}},
}


def write_inputs(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name, value in CASES.items():
        (folder / f"{name}.xcent").write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_XML))


def encode(command, inputs, outputs):
    outputs.mkdir(parents=True, exist_ok=True)
    found = {}
    for name in CASES:
        output = outputs / f"{name}.der"
        if output.exists():
            output.unlink()
        proc = subprocess.run(command + ["query", "-f", "xml", "-i", str(inputs / f"{name}.xcent"), "-o", str(output), "--raw"],
                              capture_output=True)
        found[name] = {"status": proc.returncode, "der": output.read_bytes().hex() if output.exists() else None}
    return found


def main():
    out = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "inputs":
        write_inputs(out / "inputs")
        (out / "macos.json").write_text(json.dumps(encode(["/usr/bin/derq"], out / "inputs", out / "macos"), indent=2) + "\n")
        return
    expected = json.loads((out / "macos.json").read_text())
    found = encode(sys.argv[3:], out / "inputs", out / "other")
    same = [name for name in CASES if found[name] == expected[name]]
    (out / "results.json").write_text(json.dumps({"identical": same, "found": found}, indent=2) + "\n")
    print(f"{len(same)} of {len(CASES)} entitlements files encoded like macOS's derq")
    for name in CASES:
        if name not in same:
            print(f"    {name}: {expected[name]} vs {found[name]}")


if __name__ == "__main__":
    main()

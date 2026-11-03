#!/usr/bin/env python3
"""Check whether the SDKs' version maps reproduce the deployment targets Xcode aligns.

Runs after package_experiments.py on the same Mac. For every SDK of the selected Xcode it
reads the `VersionMap` dictionary of SDKSettings.json and, for each map named `iOS_<X>`,
checks whether looking up each package's declared iOS version (the greatest key not above it)
gives the tvOS, watchOS or visionOS deployment target Xcode put in the PIF.

Only map names and match results are printed: no SDK contents are copied or uploaded.

Usage: sdk_version_maps.py <observations.json>
"""

import json
import subprocess
import sys
from pathlib import Path

SETTINGS = {"tvOS": "TVOS_DEPLOYMENT_TARGET", "watchOS": "WATCHOS_DEPLOYMENT_TARGET", "xrOS": "XROS_DEPLOYMENT_TARGET", "visionOS": "XROS_DEPLOYMENT_TARGET"}


def version(text):
    return tuple(int(part) for part in text.split("."))


def normalized(text):
    parts = list(version(text))
    while len(parts) > 2 and parts[-1] == 0:
        parts.pop()
    return parts


def main():
    observations = json.loads(Path(sys.argv[1]).read_text())
    # Packages that declare only iOS (the others declare the platform being aligned).
    packages = [entry["project"]["Debug"] for guid, entry in observations["first"]["packages"].items()
                if guid.startswith("PACKAGE:ios") and guid != "PACKAGE:iosandwatch"]
    developer = Path(subprocess.run(["xcode-select", "-p"], check=True, capture_output=True, text=True).stdout.strip())
    for settings_file in sorted((developer / "Platforms").glob("*.platform/Developer/SDKs/*.sdk/SDKSettings.json")):
        if settings_file.parent.is_symlink():
            continue
        maps = json.loads(settings_file.read_text()).get("VersionMap", {})
        print(f"{settings_file.parent.name}: maps {sorted(maps)}")
        for name, table in sorted(maps.items()):
            source, _, target = name.partition("_")
            if source != "iOS" or target not in SETTINGS:
                continue
            keys = sorted(table, key=version)
            # SwiftPM keeps the platform's oldest supported version when the mapped one is older.
            oldest = min((normalized(package[SETTINGS[target]]) for package in packages))
            mismatches = 0
            for package in packages:
                declared = version(package["IPHONEOS_DEPLOYMENT_TARGET"])
                candidates = [key for key in keys if version(key) <= declared]
                expected = normalized(package[SETTINGS[target]])
                mapped = max(normalized(table[candidates[-1]]), oldest) if candidates else oldest
                if mapped != expected:
                    mismatches += 1
            print(f"  {name}: {len(keys)} entries, {mismatches} of {len(packages)} packages differ")


if __name__ == "__main__":
    main()

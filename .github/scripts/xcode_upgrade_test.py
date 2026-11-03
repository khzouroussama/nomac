#!/usr/bin/env python3
"""Tests of xcode_upgrade.py's comparison, without Xcode: a baseline run of Xcode 27.0 (27A266a)
and a candidate run of another build, 27.1 (27A9275), whose outputs differ only by the Xcode's
identity must compare identical, and a changed output must not.

Usage: python3 .github/scripts/xcode_upgrade_test.py
"""

import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("xcode_upgrade", SCRIPTS / "xcode_upgrade.py")
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)

XCODES = {
    "baseline": {"version": "27.0", "build": "27A266a", "actual": "2700", "sdk": "27.0", "sdkBuild": "24A430",
                 "developer": "/Applications/Xcode_27.app/Contents/Developer"},
    "candidate": {"version": "27.1", "build": "27A9275", "actual": "2710", "sdk": "27.1", "sdkBuild": "24B5070",
                  "developer": "/Applications/Xcode_27.1.app/Contents/Developer"},
}


def write_run(root, xcode, setting="NO", warn=False):
    """The files of one run that carry the Xcode's identity, as the suites and captures write them."""
    developer, sdk = xcode["developer"], xcode["sdk"]
    sdk_path = f"{developer}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS{sdk}.sdk"
    settings = {"XCODE_VERSION_ACTUAL": xcode["actual"], "XCODE_VERSION_MAJOR": "2700", "XCODE_VERSION_MINOR": xcode["actual"],
                "XCODE_PRODUCT_BUILD_VERSION": xcode["build"], "SDK_NAME": f"iphoneos{sdk}", "SDKROOT": sdk_path,
                "SDK_VERSION": sdk, "SDK_PRODUCT_BUILD_VERSION": xcode["sdkBuild"], "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
                "ENABLE_TESTABILITY": setting}
    warning = (f"warning: {developer} is Xcode {xcode['version']} ({xcode['build']}), but nomac 27.0.1 reproduces Xcode 27.0 "
               "(27A266a) only; outputs may differ from that Xcode's (--strict-xcode refuses other builds)\n") if warn else ""
    files = {
        "reference/App/host.json": json.dumps({"developerDirectory": developer, "xcodeBuild": xcode["build"],
                                               "xcodeVersion": xcode["version"], "userName": "user"}, indent=2, sort_keys=True),
        "reference/App/settings/scheme-App-iphoneos.txt": "Build settings for action build and target App:\n"
            + "".join(f"    {key} = {value}\n" for key, value in sorted(settings.items())),
        "reference/App/settings/scheme-App-iphoneos.json": json.dumps([{"action": "build", "buildSettings": settings}], indent=2),
        "experiments/envelope/case/verify.log": warning + "pif: identical\nsettings: identical\n",
        "experiments/envelope/case/nomac-list.txt": warning + "Information about project \"P\":\n    Targets:\n        App\n",
        "experiments/build/dd/Build/Products/Release-iphoneos/App.app/Info.plist": plistlib.dumps({
            "BuildMachineOSBuild": "26A434", "DTCompiler": "com.apple.compilers.llvm.clang.1_0", "DTPlatformBuild": xcode["sdkBuild"],
            "DTPlatformName": "iphoneos", "DTPlatformVersion": sdk, "DTSDKBuild": xcode["sdkBuild"], "DTSDKName": f"iphoneos{sdk}",
            "DTXcode": xcode["actual"], "DTXcodeBuild": xcode["build"], "MinimumOSVersion": "18.0"}, fmt=plistlib.FMT_BINARY),
    }
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
    return {"out": str(root), "developerDirectory": developer, "xcode": {"version": xcode["version"], "build": xcode["build"]},
            "sdks": [{"canonicalName": f"iphoneos{sdk}", "platform": "iphoneos", "version": sdk, "build": xcode["sdkBuild"]}]}


class UpgradeComparison(unittest.TestCase):
    def compare(self, candidate_setting="NO"):
        with tempfile.TemporaryDirectory() as folder:
            roots = {side: Path(folder) / side for side in XCODES}
            runs = {"baseline": write_run(roots["baseline"], XCODES["baseline"]),
                    "candidate": write_run(roots["candidate"], XCODES["candidate"], candidate_setting, warn=True)}
            normalize = {side: upgrade.Normalizer(run) for side, run in runs.items()}
            changed = []
            for tree, suite in (("reference/App", None), ("experiments/envelope", "envelope"), ("experiments/build", "build")):
                found, removed, added = upgrade.compare_trees(roots["baseline"] / tree, roots["candidate"] / tree,
                                                              normalize["baseline"], normalize["candidate"], suite)
                self.assertEqual((removed, added), ([], []))
                changed += [f"{tree}/{name}" for name in found]
            return changed

    def test_another_xcode_build_alone_changes_nothing(self):
        self.assertEqual(self.compare(), [])

    def test_a_changed_output_is_found(self):
        self.assertEqual(self.compare(candidate_setting="YES"), ["reference/App/settings/scheme-App-iphoneos.json",
                                                                 "reference/App/settings/scheme-App-iphoneos.txt"])

    def test_outputs_inside_the_repository_are_refused(self):
        with self.assertRaises(SystemExit):
            upgrade.outside_repository(upgrade.REPO_ROOT / "xcode-upgrade", "--out")
        self.assertEqual(upgrade.outside_repository("~/nomac-out/x", "--out"), Path.home() / "nomac-out" / "x")
        capture = subprocess.run([sys.executable, str(upgrade.REPO_ROOT / "corpus" / "scripts" / "capture_reference.py"),
                                  "retro-rampage", "reference"], cwd=upgrade.REPO_ROOT, capture_output=True, text=True)
        self.assertEqual(capture.returncode, 1)
        self.assertIn("is inside the repository", capture.stderr)


if __name__ == "__main__":
    unittest.main()

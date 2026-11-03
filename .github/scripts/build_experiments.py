#!/usr/bin/env python3
"""The build requests xcodebuild hands Swift Build, for self-written projects.

Swift Build records each build's request in
`Build/Intermediates.noindex/XCBuildData/<id>.xcbuilddata/build-request.json`. `nomac build`
makes the same request (docs/state/build-driver.md); this records which targets xcodebuild
configures and which flags it sets, scheme by scheme, on a Mac with Xcode 27.0.

Usage: build_experiments.py <output-dir> [experiment ...]    (DEVELOPER_DIR selects the Xcode)

Each experiment's project comes from loader_experiments.py. For every scheme listed (with any
extra xcodebuild options after it), the experiment is built for `generic/platform=iOS` with code
signing off, and <output-dir>/<experiment>/<label>.build-request.json and .log are kept; summary.json lists
each build's exit status, configured targets and `generatePrecompiledModulesReport`.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402


def app_without_packages():
    """`local-packages`' project without its package references and product dependencies."""
    files = loader.local_packages()
    project = files["P.xcodeproj/project.pbxproj"]
    project = re.sub(r"\t\t\tpackageReferences = \(\n.*?\t\t\t\);\n", "", project, flags=re.S)
    project = re.sub(r"\t\t\tpackageProductDependencies = \(\n.*?\t\t\t\);\n", "", project, flags=re.S)
    project = re.sub(r"\t\t[DE]0{22}\d+ .*?;\n", "", project)
    return {"P.xcodeproj/project.pbxproj": project}


EXPERIMENTS = {
    # An app that links products of local packages, and the packages' own schemes.
    "local-packages": (loader.local_packages, "P.xcodeproj", ["App", "Plain", "MultiA"]),
    # The same app without packages, built plain, with -showBuildTimingSummary, and with Xcode's
    # "Continue building after errors" user default.
    "app-without-packages": (app_without_packages, "P.xcodeproj", ["App", "App -showBuildTimingSummary",
                                                                  "App -IDEBuildingContinueBuildingAfterErrors=YES", "App archive"]),
    # An autocreated scheme of a project whose configurations are Alpha and Beta (the default),
    # archived: which configuration xcodebuild archives with.
    "autocreate-names": (lambda: loader.configuration_experiment(["Alpha", "Beta"], "Beta"), "P.xcodeproj", ["App archive"]),
}


def main():
    out = Path(sys.argv[1]).resolve()
    chosen = sys.argv[2:] or list(EXPERIMENTS)
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "LANG": "en_US.UTF-8",
                   "DEVELOPER_DIR": developer, "TMPDIR": os.environ.get("TMPDIR", "/tmp/")}
    summary = {}
    for name in chosen:
        files, container, schemes = EXPERIMENTS[name]
        work = out / name
        shutil.rmtree(work, ignore_errors=True)
        for path, text in files().items():
            target = work / "src" / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        for label in schemes:
            scheme, *options = label.split(" ")
            derived = work / f"dd-{label.replace(' ', '')}"
            if "archive" in options:
                # The scheme's archive configuration, so no -configuration.
                action = ["archive", "-archivePath", str(work / f"{label.replace(' ', '')}.xcarchive")]
                options = [option for option in options if option != "archive"]
            else:
                action = ["-configuration", "Debug", "build"]
            completed = subprocess.run(["xcodebuild", "-project", container, "-scheme", scheme,
                                        "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived),
                                        "CODE_SIGNING_ALLOWED=NO", *options, *action],
                                       cwd=work / "src", env=environment, capture_output=True, text=True)
            label = label.replace(" ", "")
            (work / f"{label}.log").write_text(completed.stdout + completed.stderr)
            requests = sorted(derived.glob("Build/Intermediates.noindex/**/XCBuildData/*.xcbuilddata/build-request.json"))
            entry = {"exitStatus": completed.returncode}
            if requests:
                shutil.copy(requests[0], work / f"{label}.build-request.json")
                request = json.loads(requests[0].read_text())
                entry["configuredTargets"] = [target["guid"] for target in request["configuredTargets"]]
                entry["generatePrecompiledModulesReport"] = request.get("generatePrecompiledModulesReport")
                entry["continueBuildingAfterErrors"] = request.get("continueBuildingAfterErrors")
                entry["schemeCommand"] = request.get("schemeCommand")
                entry["action"] = request["parameters"].get("action")
                entry["configurationName"] = request["parameters"].get("configurationName")
                entry["synthesized"] = sorted(request["parameters"]["overrides"].get("synthesized", {}).get("table", {}))
            summary[f"{name}/{label}"] = entry
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

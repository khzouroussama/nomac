#!/usr/bin/env python3
"""What xcodebuild prints when a build or an archive fails, for self-written projects (B-112).

Each variant builds loader_experiments.py's one-app project, alone (`-project`) or in a workspace
(`-workspace`), by scheme, by target or by neither, or a Swift package in its folder by its scheme, for
`generic/platform=iOS` with code signing off:

- compile: `App.swift` does not compile, so one task (SwiftCompile) fails;
- planning: `SWIFT_VERSION` left empty, an error Swift Build reports while planning, with no task.

Usage: failure_experiments.py <output-dir>    (on a Mac; DEVELOPER_DIR selects the Xcode)

<output-dir>/<variant>.log keeps each run's output; summary.json lists each run's exit status,
how many `error:` lines each stream has, and, per stream, its `** BUILD FAILED **` or
`** ARCHIVE FAILED **` line and what follows it.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402

SOURCES = {"compile": "@main struct App { static func main() { undefinedName() } }\n",
           "planning": "@main struct App { static func main() {} }\n"}
# A scheme, a target, or neither (the project's first target).
SELECTIONS = {"scheme": ["-scheme", "App"], "target": ["-target", "App"], "default": []}
CONTAINERS = {"project": ["-project", "P.xcodeproj"], "workspace": ["-workspace", "W.xcworkspace"], "package": []}
VARIANTS = {
    f"{container}-{selection}-{action}-{failure}": (failure, CONTAINERS[container] + SELECTIONS[selection], action)
    for failure in SOURCES for container in CONTAINERS for selection in SELECTIONS for action in ("build", "archive")
    if not (container in ("workspace", "package") and selection != "scheme") and not (selection != "scheme" and action == "archive")
    and not (container == "package" and (action == "archive" or failure == "planning"))
}


def main():
    out = Path(sys.argv[1]).resolve()
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "LANG": "en_US.UTF-8",
                   "DEVELOPER_DIR": developer, "TMPDIR": os.environ.get("TMPDIR", "/tmp/")}
    summary = {}
    for name, (failure, selection, action) in VARIANTS.items():
        work = out / name
        shutil.rmtree(work, ignore_errors=True)
        (work / "src").mkdir(parents=True)
        if not name.startswith("package-"):
            (work / "src/W.xcworkspace").mkdir()
            (work / "src/P.xcodeproj").mkdir()
            (work / "src/P.xcodeproj/project.pbxproj").write_text(loader.simple_project("App"))
            (work / "src/W.xcworkspace/contents.xcworkspacedata").write_text(loader.workspace_contents(["P.xcodeproj"]))
            (work / "src/App.swift").write_text(SOURCES[failure])
        else:
            # A Swift package's folder, its scheme named after its product, as Expo's nested build runs it.
            for path, text in loader.package_files("src", "App", ['.library(name: "App", targets: ["App"])'], {"App": ("library", [])}).items():
                (work / path).parent.mkdir(parents=True, exist_ok=True)
                (work / path).write_text(text)
            (work / "src/Sources/App/App.swift").write_text("public func f() { undefinedName() }\n")
        settings = ["SWIFT_VERSION=5.0"] if failure == "compile" else []
        if action == "archive":
            command = ["xcodebuild", *selection, "-destination", "generic/platform=iOS", "-derivedDataPath", str(work / "dd"),
                       "CODE_SIGNING_ALLOWED=NO", *settings, "archive", "-archivePath", str(work / "App.xcarchive")]
        else:
            command = ["xcodebuild", *selection, "-configuration", "Debug", *(["-destination", "generic/platform=iOS"] if "-scheme" in selection else ["-sdk", "iphoneos"]),
                       *(["-derivedDataPath", str(work / "dd")] if "-scheme" in selection else []), "CODE_SIGNING_ALLOWED=NO", *settings, "build"]
        completed = subprocess.run(command, cwd=work / "src", env=environment, capture_output=True, text=True)
        (out / f"{name}.log").write_text(completed.stdout + "\n--- stderr ---\n" + completed.stderr)
        streams = {}
        for stream, text in (("stdout", completed.stdout), ("stderr", completed.stderr)):
            lines = text.splitlines()
            marker = next((i for i, line in enumerate(lines) if line.startswith("** ") and "FAILED" in line), None)
            if marker is not None:
                streams[stream] = [line.replace(str(work), "<work>") for line in lines[marker:]]
        summary[name] = {
            "exitStatus": completed.returncode,
            "errorsOnStdout": len([line for line in completed.stdout.splitlines() if "error:" in line]),
            "errorsOnStderr": len([line for line in completed.stderr.splitlines() if "error:" in line]),
            "afterFailed": streams,
        }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Script phases under user script sandboxing (`ENABLE_USER_SCRIPT_SANDBOXING = YES`, Xcode's
default for new projects), for a self-written app.

envelope_experiments.py's objectVersion-77 app, with sandboxing on and its script phase changed:

- declared: the script copies its declared input (`App/stamp.txt`) to its declared output in the
  app's resources;
- undeclared: the same, and it also writes a file it did not declare (`$(DERIVED_FILE_DIR)`).

Usage:
  script_sandbox_experiments.py <out>                  on a Mac: xcodebuild (DEVELOPER_DIR)
  script_sandbox_experiments.py <out> --nomac <nomac> [nomac build options...]
                                                       nomac build, e.g. on Linux with
                                                       --developer-dir and --host-identity

<out>/<variant>/<tool>.log keeps each build's output; <out>/<tool>.json lists each build's exit
status, whether its log runs the script under sandbox-exec, and the bytes of the declared output
in the app.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import envelope_experiments as envelope  # noqa: E402

COPY = 'cp "$SCRIPT_INPUT_FILE_0" "$SCRIPT_OUTPUT_FILE_0"\n'
VARIANTS = {
    "declared": COPY,
    "undeclared": COPY + 'echo undeclared > "$DERIVED_FILE_DIR/undeclared.txt"\n',
}


def project(script):
    def edit(p, files):
        phase = p.objects[p.ids("app/script")]
        phase.update(shellScript=script, inputPaths=["$(SRCROOT)/App/stamp.txt"],
                     outputPaths=["$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/stamp.txt"])
        files["App/stamp.txt"] = "stamped by the script phase\n"
        # Without the Core Data model, whose compile nomac does not reproduce yet (B-256).
        sources = p.objects[p.ids("app/sources")]
        sources["files"] = [build for build in sources["files"] if build != p.ids("app/model/build")]
    return envelope.era_project(77, edit=edit)


def main():
    out = Path(sys.argv[1]).resolve()
    nomac = sys.argv[sys.argv.index("--nomac") + 1] if "--nomac" in sys.argv else None
    extra = sys.argv[sys.argv.index("--nomac") + 2:] if nomac else []
    tool = "nomac" if nomac else "xcode"
    results = {}
    for name, script in VARIANTS.items():
        work = out / name
        source = work / f"src-{tool}"
        shutil.rmtree(source, ignore_errors=True)
        for path, text in project(script).items():
            (source / path).parent.mkdir(parents=True, exist_ok=True)
            (source / path).write_text(text)
        derived = work / f"dd-{tool}"
        shutil.rmtree(derived, ignore_errors=True)
        command = ([nomac, "build"] if nomac else ["xcodebuild"]) + [
            "-project", "P.xcodeproj", "-scheme", "App", "-configuration", "Debug", "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "ASSETCATALOG_COMPILER_APPICON_NAME=", "ENABLE_USER_SCRIPT_SANDBOXING=YES", *extra, "build"]
        completed = subprocess.run(command, cwd=source, capture_output=True, text=True, env=os.environ)
        log = completed.stdout + completed.stderr
        (work / f"{tool}.log").write_text(log)
        stamp = derived / "Build/Products/Debug-iphoneos/App.app/stamp.txt"
        results[name] = {
            "exitStatus": completed.returncode,
            "sandboxExec": "sandbox-exec" in log,
            "declaredOutput": stamp.read_text() if stamp.exists() else None,
            "denied": sorted({line.strip()[:160] for line in log.splitlines() if "deny" in line.lower() or "Operation not permitted" in line}),
        }
    (out / f"{tool}.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

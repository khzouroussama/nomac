#!/usr/bin/env python3
"""How xcodebuild runs a scheme's pre-actions and post-actions (shell script execution actions).

netnewswire's `NetNewsWire` scheme has a build pre-action that runs `buildscripts/updateSecrets.sh`,
which writes the Secrets package's `SecretKey.swift` from a gyb template; nomac's build did not run it,
so the Secrets framework lacked `SecretKey` (B-175). Each variant builds loader_experiments.py's
one-app project by its scheme (`generic/platform=iOS`, code signing off) with actions whose script
records `$0`, its arguments, the working directory, the parent process, bash's version, what the
build has written into `BUILT_PRODUCTS_DIR` and the archive so far, and its environment.

Usage: scheme_action_experiments.py <output-dir>    (on a Mac; DEVELOPER_DIR selects the Xcode)

<output-dir>/<variant>/ keeps the project, the build log and each action's record
(`<action>.txt`); summary.json lists each variant's exit status, the actions that ran with their
records (the environment as a dictionary), and the log lines that mention a scheme action.
`pre-generates-package-source` builds when Xcode reads the package's sources after the pre-action
has written one of them.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402

APP = ("C00000000000000000000001", "App.app", "App", "container:P.xcodeproj")
GOOD = "@main struct App { static func main() {} }\n"
BAD = "@main struct App { static func main() { undefinedName() } }\n"
GENERATE = 'printf "public func generated() -> Int { 2 }\\n" > "$PROJECT_DIR/Deps/Dep/Sources/Dep/Gen.swift"\n'


def record(name, status=0):
    """A script writing its record to `<name>.txt` in the variant's folder ($MARKERS), then exiting `status`."""
    return (f'{{ echo "argv0=$0"; echo "args=$*"; echo "pwd=$(pwd)"; echo "parent=$(ps -o comm= -p $PPID)"; '
            f'echo "bash=${{BASH_VERSION-}}"; echo "products=$(ls "$BUILT_PRODUCTS_DIR" 2>/dev/null | tr \'\\n\' \' \')"; '
            f'echo "archive=$(ls "$MARKERS/App.xcarchive" 2>/dev/null | tr \'\\n\' \' \')"; '
            f'echo "stdout line from {name}"; echo "---"; env | sort; }} > "$MARKERS/{name}.txt"\n'
            f'echo "printed by {name}"\nexit {status}\n')


def action(script, environment=True, shell=None):
    shell_attribute = f'\n               shellToInvoke = "{shell}"' if shell else ""
    text = escape(script, {'"': "&quot;", "\n": "&#10;"})
    buildable = ("               <EnvironmentBuildable>\n" + "".join("   " + line + "\n" for line in loader.scheme_buildable(*APP).splitlines())
                 + "               </EnvironmentBuildable>\n") if environment else ""
    return ("         <ExecutionAction\n            ActionType = \"Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction\">\n"
            f"            <ActionContent\n               title = \"Run Script\"\n               scriptText = \"{text}\"{shell_attribute}>\n"
            f"{buildable}            </ActionContent>\n         </ExecutionAction>\n")


def scheme(pre=(), post=(), archive_pre=(), archive_post=(), post_on_failure=False):
    def actions(tag, items):
        return f"      <{tag}>\n" + "".join(items) + f"      </{tag}>\n" if items else ""
    failure = '\n      runPostActionsOnFailure = "YES"' if post_on_failure else ""
    entry = ("         <BuildActionEntry\n            buildForTesting = \"YES\"\n            buildForRunning = \"YES\"\n"
             "            buildForProfiling = \"YES\"\n            buildForArchiving = \"YES\"\n            buildForAnalyzing = \"YES\">\n"
             + "".join("   " + line + "\n" for line in loader.scheme_buildable(*APP).splitlines()) + "         </BuildActionEntry>\n")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme\n   LastUpgradeVersion = "2700"\n   version = "1.7">\n'
            f'   <BuildAction\n      parallelizeBuildables = "YES"\n      buildImplicitDependencies = "YES"{failure}>\n'
            + actions("PreActions", pre) + actions("PostActions", post)
            + f"      <BuildActionEntries>\n{entry}      </BuildActionEntries>\n   </BuildAction>\n"
            '   <ArchiveAction\n      buildConfiguration = "Release"\n      revealArchiveInOrganizer = "YES">\n'
            + actions("PreActions", archive_pre) + actions("PostActions", archive_post) + "   </ArchiveAction>\n</Scheme>\n")


VARIANTS = {
    "pre": (scheme(pre=[action(record("pre"))]), GOOD, "build"),
    "pre-without-environment": (scheme(pre=[action(record("pre"), environment=False)]), GOOD, "build"),
    "pre-bash": (scheme(pre=[action(record("pre"), shell="/bin/bash")]), GOOD, "build"),
    "pre-two": (scheme(pre=[action(record("pre1")), action(record("pre2"))]), GOOD, "build"),
    "pre-fails": (scheme(pre=[action(record("pre", 3))]), GOOD, "build"),
    "pre-fails-without-environment": (scheme(pre=[action(record("pre", 3), environment=False)]), GOOD, "build"),
    "pre-fails-then-pre": (scheme(pre=[action(record("pre1", 3)), action(record("pre2"))]), GOOD, "build"),
    "post": (scheme(post=[action(record("post"))]), GOOD, "build"),
    "post-build-fails": (scheme(pre=[action(record("pre"))], post=[action(record("post"))]), BAD, "build"),
    "post-build-fails-on-failure": (scheme(post=[action(record("post"))], post_on_failure=True), BAD, "build"),
    "post-fails": (scheme(post=[action(record("post", 3))]), GOOD, "build"),
    "archive": (scheme(pre=[action(record("pre"))], post=[action(record("post"))],
                       archive_pre=[action(record("archive-pre"))], archive_post=[action(record("archive-post"))]), GOOD, "archive"),
    "target": (scheme(pre=[action(record("pre"))], post=[action(record("post"))]), GOOD, "target"),
    "pre-generates-package-source": (scheme(pre=[action(GENERATE + record("pre"))]), None, "build"),
}


def app_project():
    """loader_experiments.py's one-app project, with its product's file reference."""
    return loader.simple_project("App", extra_objects=loader.product_file("P00000000000000000000001", "App", loader.APPLICATION),
                                 extra_target="\t\t\tproductReference = P00000000000000000000001;\n",
                                 group_children="\t\t\t\tP00000000000000000000001,\n")


def package_project():
    """loader_experiments.py's one-app project with a local package `Deps/Dep` the app depends on, and a
    `Dep` source the pre-action writes (`Gen.swift`, absent before the build) that the app calls."""
    files = loader.package_files("Deps/Dep", "Dep", ['.library(name: "Dep", targets: ["Dep"])'], {"Dep": ("library", [])})
    files["Deps/Dep/Sources/Dep/Base.swift"] = "public let base = 1\n"
    objects = """\t\tA00000000000000000000003 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000004 /* App.swift */; };
\t\tA00000000000000000000004 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
\t\tA00000000000000000000008 /* Dep in Frameworks */ = {isa = PBXBuildFile; productRef = E00000000000000000000001 /* Dep */; };
\t\tD00000000000000000000001 /* XCLocalSwiftPackageReference "Deps/Dep" */ = {isa = XCLocalSwiftPackageReference; relativePath = Deps/Dep; };
\t\tE00000000000000000000001 /* Dep */ = {isa = XCSwiftPackageProductDependency; package = D00000000000000000000001; productName = Dep; };
\t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000004 /* App.swift */, P00000000000000000000001, ); sourceTree = "<group>"; };
\t\tF00000000000000000000004 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000003 /* App.swift in Sources */, ); runOnlyForDeploymentPostprocessing = 0; };
\t\tF00000000000000000000005 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000008 /* Dep in Frameworks */, ); runOnlyForDeploymentPostprocessing = 0; };
""" + loader.product_file("P00000000000000000000001", "App", loader.APPLICATION) \
      + loader.app_target(APP[0], "App", ["F00000000000000000000004 /* Sources */", "F00000000000000000000005 /* Frameworks */"],
                          ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], loader.APP_SETTINGS,
                          extra="\t\t\tpackageProductDependencies = (\n\t\t\t\tE00000000000000000000001 /* Dep */,\n\t\t\t);\n",
                          product_reference="P00000000000000000000001")
    references = "\t\t\tpackageReferences = (\n\t\t\t\tD00000000000000000000001 /* XCLocalSwiftPackageReference \"Deps/Dep\" */,\n\t\t\t);\n"
    files["P.xcodeproj/project.pbxproj"] = loader.project("F00000000000000000000006", "F00000000000000000000002", [APP[0]], objects,
                                                          package_references=references)
    files["App.swift"] = "import Dep\n@main struct App { static func main() { print(generated() + base) } }\n"
    return files



def parse(text):
    head, _, environment = text.partition("\n---\n")
    fields = dict(line.split("=", 1) for line in head.splitlines() if "=" in line)
    fields["environment"] = dict(line.split("=", 1) for line in environment.splitlines() if "=" in line)
    return fields


def main():
    out = Path(sys.argv[1]).resolve()
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
    summary = {}
    for name, (scheme_text, source, kind) in VARIANTS.items():
        work = out / name
        shutil.rmtree(work, ignore_errors=True)
        (work / "src/P.xcodeproj/xcshareddata/xcschemes").mkdir(parents=True)
        files = package_project() if source is None else {"P.xcodeproj/project.pbxproj": app_project(), "App.swift": source}
        for path, text in files.items():
            (work / "src" / path).parent.mkdir(parents=True, exist_ok=True)
            (work / "src" / path).write_text(text)
        (work / "src/P.xcodeproj/xcshareddata/xcschemes/App.xcscheme").write_text(scheme_text)
        environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "LANG": "en_US.UTF-8",
                       "DEVELOPER_DIR": developer, "TMPDIR": os.environ.get("TMPDIR", "/tmp/"), "MARKERS": str(work)}
        common = ["-project", "P.xcodeproj", "-destination", "generic/platform=iOS", "-derivedDataPath", str(work / "dd"),
                  "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0"]
        if kind == "archive":
            command = ["xcodebuild", "-scheme", "App", *common, "archive", "-archivePath", str(work / "App.xcarchive")]
        elif kind == "target":
            command = ["xcodebuild", "-project", "P.xcodeproj", "-target", "App", "-sdk", "iphoneos", "CODE_SIGNING_ALLOWED=NO",
                       "SWIFT_VERSION=5.0", "build"]
        else:
            command = ["xcodebuild", "-scheme", "App", "-configuration", "Debug", *common, "build"]
        completed = subprocess.run(command, cwd=work / "src", env=environment, capture_output=True, text=True)
        (work / "build.log").write_text(completed.stdout + "\n--- stderr ---\n" + completed.stderr)
        lines = (completed.stdout + completed.stderr).splitlines()
        mentions = [i for i, line in enumerate(lines) if "SchemeScriptAction" in line or "printed by" in line or "Run Script" in line]
        summary[name] = {
            "exitStatus": completed.returncode,
            "ran": {path.stem: parse(path.read_text()) for path in sorted(work.glob("*.txt"))},
            "log": [line.replace(str(work), "<work>") for i in mentions for line in lines[max(0, i - 1):i + 2]],
        }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for name, result in summary.items():
        print(name, "exit", result["exitStatus"], "ran", " ".join(result["ran"]))


if __name__ == "__main__":
    main()

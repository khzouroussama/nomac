#!/usr/bin/env python3
"""Survey of what build-phase scripts need from macOS: run-script phases and the scripts they call.

For each app folder: every Xcode project under it (CocoaPods' Pods.xcodeproj included; projects in
node_modules, package checkouts and build folders left out), every PBXShellScriptBuildPhase's
script, and every shell script a script names (`"${PODS_ROOT}/Target Support Files/…-frameworks.sh"`,
`source ".../with-environment.sh"`), followed to any depth. Phases whose shell is not a POSIX
shell (Python, Ruby, Node) are counted, not read. Build settings in a path are resolved
for the project (SRCROOT, PROJECT_DIR, PODS_ROOT, REACT_NATIVE_PATH); a path still unresolved is
looked up by its file name under the app folder. Comments are left out; JavaScript and Ruby files
that scripts run are not read (they reach tools through their own APIs).

Counted: macOS-only commands (PlistBuddy, plutil, sips, osascript, defaults, security, sw_vers,
xattr, …) and usages whose meaning differs between macOS's BSD tools and GNU ones (`sed -i ''`,
`date -j`, `stat -f`, `md5`, `base64 -D`, `find -E`, …), with shebangs and system checks.

Usage:
  script_phase_survey.py [--json out.json] [--examples N] <app folder> ...
Prints a table of every pattern found: occurrences, scripts, apps, and examples.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

SKIPPED_FOLDERS = {".git", "node_modules", "DerivedData", "SourcePackages", "checkouts", "build", "Build", "Carthage",
                   ".build", ".DerivedData"}

# Commands macOS has and Linux lacks (or has with another meaning), by the name scripts call.
MACOS_COMMANDS = [
    "PlistBuddy", "plutil", "sips", "osascript", "defaults", "security", "sw_vers", "xattr", "iconutil", "ditto",
    "codesign", "xcrun", "xcodebuild", "xcode-select", "lipo", "otool", "install_name_tool", "dsymutil", "dwarfdump",
    "actool", "ibtool", "agvtool", "mdfind", "mdls", "pbcopy", "pbpaste", "open", "launchctl", "hdiutil", "pkgutil",
    "system_profiler", "scutil", "ipconfig", "networksetup", "textutil", "vtool", "atos", "symbols", "derq", "SetFile",
    "GetFileInfo", "say", "afplay", "caffeinate", "diskutil", "spctl", "productbuild", "pkgbuild", "altool", "notarytool",
    "stapler", "simctl", "upload-symbols", "upload-dsym",
]

# Usages whose behaviour differs between BSD (macOS) and GNU (Linux) tools, or that test the system.
PATTERNS = {
    "sed -i '' (BSD in-place)": r"\bsed\b[^\n|;]*\s-i\s*(''|\"\")",
    "sed -i without suffix (GNU in-place)": r"\bsed\b[^\n|;]*\s-i(\s+(?!''|\"\")[-'\"]|$)",
    "sed -E": r"\bsed\b[^\n|;]*\s-E\b",
    "date -j / -v / -f (BSD)": r"\bdate\b[^\n|;]*\s-(j|v[+-]?\d|f)\b",
    "stat -f (BSD format)": r"\bstat\b[^\n|;]*\s-f\b",
    "stat -c (GNU format)": r"\bstat\b[^\n|;]*\s-c\b",
    "readlink without -f": r"\breadlink\b(?![^\n|;]*\s-[a-z]*f)",
    "readlink -f": r"\breadlink\b[^\n|;]*\s-[a-z]*f",
    "realpath": r"\brealpath\b",
    "md5 (BSD)": r"(?<![\w-])md5(?![\w-])",
    "md5sum (GNU)": r"\bmd5sum\b",
    "shasum (Perl, macOS)": r"\bshasum\b",
    "sha256sum (GNU)": r"\bsha256sum\b",
    "base64 -D (BSD decode)": r"\bbase64\b[^\n|;]*\s-D\b",
    "find -E": r"\bfind\b\s+-E\b",
    "find -depth N (BSD)": r"\bfind\b[^\n|;]*\s-depth\s+\d",
    "xargs": r"\bxargs\b",
    "cp -X / -c (BSD)": r"\bcp\b\s+-[a-zA-Z]*[Xc]",
    "grep -P": r"\bgrep\b[^\n|;]*\s-[a-zA-Z]*P",
    "mktemp -t": r"\bmktemp\b[^\n|;]*\s-t\b",
    "$OSTYPE": r"\$\{?OSTYPE\b",
    "uname": r"\buname\b",
    "sysctl": r"\bsysctl\b",
    "echo -e / -n": r"\becho\s+-[en]\b",
    "tail -r (BSD)": r"\btail\b\s+-r\b",
    "head -n -N (GNU)": r"\bhead\b[^\n|;]*-n\s*-\d",
    "/usr/libexec path": r"/usr/libexec/\w+",
    "x86_64-only prebuilt tool check (arch)": r"\barch\s+-x86_64\b",
    "Crashlytics/Firebase upload-symbols (prebuilt macOS tool)": r"upload-symbols\b",
    "bash version test ($BASH_VERSION, BASH_VERSINFO)": r"\$\{?BASH_VERSI(ON|NFO)\b",
    "$'\\u' escape (literal in bash 3.2)": r"\$'[^']*\\[uU][0-9a-fA-F]",
    "declare -p (other array format in bash 3.2)": r"\bdeclare\s+-p\b",
    "bash 4 syntax (declare -A, mapfile, ${v,,}, |&, [[ -v ]])": r"\bdeclare\s+-[a-zA-Z]*A\b|\b(mapfile|readarray)\b|\$\{\w+(,,|\^\^)\}|\|&|\[\[\s+-v\s",
    "glob in a for loop (order follows the locale)": r"\bfor\s+\w+\s+in\s+[^;\n]*\*",
}

SHEBANG = re.compile(r"^#!\s*(\S+)(?:\s+(\S+))?")
# Where a word is a command: at the start of a line, after a separator, a substitution or a
# keyword that runs one, or as the last component of a path.
COMMAND_POSITION = r"(?:^\s*|[|;&(`]\s*|\$\(\s*|\b(?:then|do|else|xcrun|exec|env|time|sudo)\s+|[\w./${}\"-]*/)"
SHELLS = ("sh", "bash", "zsh", "dash", "ksh")


def pbxproj_strings(text, key):
    """The decoded values of `key = "…";` in a project file."""
    for match in re.finditer(key + r' = "((?:[^"\\]|\\.)*)";', text):
        yield re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), match.group(1))


def projects(app):
    for folder, names, _ in os.walk(app):
        names[:] = [n for n in names if n not in SKIPPED_FOLDERS and not n.endswith((".xcframework", ".framework"))]
        for name in list(names):
            if name.endswith(".xcodeproj"):
                names.remove(name)
                yield Path(folder) / name


def resolve(path, project, app, index):
    project_dir = project.parent
    values = {"SRCROOT": project_dir, "PROJECT_DIR": project_dir, "SOURCE_ROOT": project_dir,
              "PODS_ROOT": project_dir if project.name == "Pods.xcodeproj" else project_dir / "Pods",
              "REACT_NATIVE_PATH": next((p / "node_modules/react-native" for p in [project_dir, *project_dir.parents]
                                         if (p / "node_modules/react-native").is_dir()), None)}
    def substitute(match):
        value = values.get(match.group(1) or match.group(2))
        return str(value) if value else match.group(0)
    text = re.sub(r"\$\{(\w+)\}|\$\((\w+)\)", substitute, path)
    if "$" not in text:
        candidate = Path(text) if text.startswith("/") else project_dir / text
        if candidate.is_file():
            return [candidate.resolve()]
    return [p for p in index.get(Path(text).name, [])][:5]


def file_index(app):
    found = defaultdict(list)
    for folder, names, files in os.walk(app):
        names[:] = [n for n in names if n not in {".git", "DerivedData", ".build", "build", "Build"}]
        for name in files:
            if name.endswith((".sh", ".bash")):
                found[name].append((Path(folder) / name).resolve())
    return found


def without_comments(text):
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        lines.append(re.sub(r"(^|\s)#(?![!{]).*$", "", line))
    return "\n".join(lines)


def survey(app, results, examples):
    app = Path(app).resolve()
    index = file_index(app)
    queue, seen = [], set()
    for project in projects(app):
        if not (project / "project.pbxproj").is_file():
            continue
        text = (project / "project.pbxproj").read_text(errors="replace")
        for block in re.findall(r"isa = PBXShellScriptBuildPhase;(.*?)\n\t\t\};", text, re.S):
            shell = re.search(r"shellPath = ([^;]+);", block)
            shell = shell.group(1).strip('"').split()[0] if shell else "/bin/sh"
            for script in pbxproj_strings(block, "shellScript"):
                name = next(pbxproj_strings(block, "name"), "Run Script")
                if Path(shell).name not in SHELLS:
                    results["counts"][f"phase shell {Path(shell).name} (not read)"][app.name] += 1
                    continue
                queue.append((f"{project.relative_to(app)} [{name}]", script, project))
    while queue:
        label, script, project = queue.pop()
        results["scripts"][app.name] += 1
        first = script.split("\n", 1)[0]
        shebang = SHEBANG.match(first)
        if shebang:
            interpreter = shebang.group(2) if shebang.group(1).endswith("/env") else shebang.group(1)
            results["counts"][f"shebang {interpreter}"][app.name] += 1
            if Path(interpreter).name not in SHELLS:
                continue
        body = without_comments(script)
        for number, line in enumerate(body.splitlines(), 1):
            for command in MACOS_COMMANDS:
                if re.search(COMMAND_POSITION + re.escape(command) + r"(?=[\s\"';|)`]|$)", line):
                    record(results, f"command {command}", app.name, label, number, line, examples)
            for name, pattern in PATTERNS.items():
                if re.search(pattern, line):
                    record(results, name, app.name, label, number, line, examples)
        for match in re.finditer(r'"([^"\n]+\.(?:sh|bash))"|\'([^\'\n]+\.(?:sh|bash))\'|(\S+\.(?:sh|bash))\b', body):
            for path in resolve(next(g for g in match.groups() if g), project, app, index):
                if path not in seen and path.is_file():
                    seen.add(path)
                    queue.append((str(path.relative_to(app)) if path.is_relative_to(app) else str(path),
                                  path.read_text(errors="replace"), project))


def record(results, name, app, label, number, line, examples):
    results["counts"][name][app] += 1
    results["files"][name].add((app, label))
    if len(results["examples"][name]) < examples:
        results["examples"][name].append(f"{app}: {label}:{number}: {line.strip()[:120]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("apps", nargs="+")
    parser.add_argument("--json")
    parser.add_argument("--examples", type=int, default=2)
    args = parser.parse_args()
    results = {"counts": defaultdict(lambda: defaultdict(int)), "files": defaultdict(set),
               "examples": defaultdict(list), "scripts": defaultdict(int)}
    for app in args.apps:
        if Path(app).is_dir():
            survey(app, results, args.examples)
    rows = sorted(results["counts"].items(), key=lambda item: (-len(item[1]), -sum(item[1].values())))
    print(f"{len(results['scripts'])} apps, {sum(results['scripts'].values())} scripts (phases and the scripts they call)\n")
    print("| pattern | occurrences | scripts | apps | example |")
    print("|---|---|---|---|---|")
    for name, per_app in rows:
        example = (results["examples"][name] or [""])[0].replace("|", "\\|")
        print(f"| {name} | {sum(per_app.values())} | {len(results['files'][name])} | {len(per_app)} | {example} |")
    if args.json:
        Path(args.json).write_text(json.dumps({
            "scripts": results["scripts"],
            "patterns": {name: {"apps": dict(per_app), "scripts": len(results["files"][name]), "examples": results["examples"][name]}
                         for name, per_app in rows}}, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())

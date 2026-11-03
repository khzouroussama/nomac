#!/usr/bin/env python3
"""Expo and bare React Native apps, generated from their templates, as test cases for nomac.

nomac has no React Native or Expo code: these apps exercise general rules (CocoaPods' generated
projects and script phases, Node scripts run from script phases, xcframeworks, ObjC++ and C++
compiles, privacy manifests, resource bundles). This script generates them outside the
repository, captures Xcode's references of their builds and runs `nomac verify --build` on them.

Apps (each under <root>/apps/<name>, committed into a git repository of its own at a fixed date):
  expo-default  `create-expo-app` with the default template, `expo prebuild --platform ios
                --no-install`, `pod install`
  rn-bare       `@react-native-community/cli init`, `pod install`

Every version is pinned (PINS), and npm resolves dependencies as the registry was at
PINS["npm-before"] (`npm_config_before`). CocoaPods resolves trunk pods to what the CDN has; each
app's record (<root>/apps/<id>.json) keeps the hashes of its package-lock.json and Podfile.lock,
the tools' versions and the requirements the templates themselves declare (`engines`, Gemfile).

What the projects' own documentation requires (2026-10-24):
  - Expo SDK 58 (`expo` 58.0.x, `expo-template-default` 58.0.28): Node ^22.13.0, ^24.3.0, ^26.0.0
    or >= 27.0.0 (`expo`'s `engines`); React Native 0.88.0.
  - React Native 0.88.0: Node ^22.13.0, ^24.3.0 or >= 26.0.0 (`engines`; the CLI template asks
    >= 22.11.0); its Gemfile asks Ruby >= 2.6.10, CocoaPods >= 1.13 except 1.15.0 and 1.15.1, and
    xcodeproj < 1.26.0, which CocoaPods 1.16 does not accept (it needs 1.27): rbenv's CocoaPods
    1.16.2 with xcodeproj 1.27.0 is used, as `pod install` without Bundler does.
  - Node v24.0.0, the Mac's default, is below both: the pinned Node is downloaded into <root>/node
    (nodejs.org's tarball, SHA-256 checked), at the same path the Linux build later mounts its own.

Xcode runs offline (sandbox-exec without outbound network, as signing_experiments.py), with
capture_reference.py's fixed environment; `pod install` downloads React Native's prebuilt
artifacts, so generation runs online. One exception: expo-default's `[CP-User] Build
ExpoModulesJSI xcframework` phase runs `xcodebuild` on a Swift package, and SwiftPM's manifest
sandbox cannot be applied inside a sandbox whose profile differs from its own ("sandbox_apply:
Operation not permitted"; nesting works only with an identical profile). Its builds (Xcode's and
nomac's) run without sandbox-exec, every socket the build's processes open is sampled with lsof
and written to <reference>/build/network.log (or <reference>.nomac.network.log). Archives run
unsandboxed for every app (capture_reference.py --archive: Swift macros cannot expand under
sandbox-exec either), their sockets in <reference>/archive/archive.network.log.

Usage (DEVELOPER_DIR selects the Xcode; root defaults to ~/nomac-out/wt-scratch/expo):
  expo_experiments.py generate [--root R] [app ...]
  expo_experiments.py capture [--root R] [--configuration C ...] [--archive] [app ...]
  expo_experiments.py verify --nomac <nomac> [--root R] [--configuration C ...] [--project-fixes] [app ...]
  expo_experiments.py node [--root R]          the pinned Node for this machine, in <root>/node
  expo_experiments.py triage <build.log> ...   a build log's errors by task and message
  expo_experiments.py nested [--xcodebuild X] [--keep] [app ...]   replay the phase that runs xcodebuild (B-181)
  expo_experiments.py platform-packages [app ...]   add the lockfile's Linux packages to an app generated without them
  expo_experiments.py macros <app folder> <out> <swiftc> <plugin> <iPhoneOS SDK>   Expo's macro expansions (ADR 0151)

On Linux (docs/state/react-native.md "Reproduce"), `verify` runs in a container without network, at the
Mac's paths, with <root>/node the Linux Node: the apps' .xcode.env.local names <root>/node/bin/node.

`capture` writes capture_reference.py's layout to <root>/refs/<configuration>/<id> (the PIF,
`-list` and settings once per app, the build per configuration); `verify` writes
<root>/refs/<configuration>/<id>.nomac.json and keeps nomac's derived data next to it
(<id>.nomac-DerivedData). Before each, the checkout is reset to its commit. With --project-fixes,
`verify` first makes the changes a project makes for a Linux build (`project_fixes`, ADR 0182).
"""

import argparse
import base64
import contextlib
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "corpus" / "scripts"))
import capture_reference as capture  # noqa: E402

PINS = {
    "node": "24.22.1",
    "create-expo-app": "5.0.0",
    "expo-template-default": "58.0.28",
    "@react-native-community/cli": "20.2.0",
    "react-native": "0.88.0",
    "cocoapods": "1.16.2",
    "ruby": "3.0.0",
    "npm-before": "2026-10-24T00:00:00Z",
}
NODE_SHA256 = {
    "darwin-arm64": "89c682593d76cd44233fa53b1563264e7de9cbb189cad169135c5b4fadfbc0a7",
    "linux-arm64": "33c37be234ba8bee041961047b19160f4d7d0f164e8e246f78bdd10feff148b3",
}
NESTED_SWIFTPM = {"expo-default"}
OFFLINE = ["sandbox-exec", "-p", '(version 1)(allow default)(deny network-outbound (remote ip))'
           '(deny network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))']
COMMIT_DATE = "2026-10-24T00:00:00Z"


def expo_default(apps, env):
    npx(env, apps, f"create-expo-app@{PINS['create-expo-app']}", "ExpoDefault",
        "--template", f"expo-template-default@{PINS['expo-template-default']}", "--no-agents-md")
    src = apps / "ExpoDefault"
    # Without a bundle identifier, prebuild derives one from the machine's git or Expo account.
    config = json.loads((src / "app.json").read_text())
    config["expo"]["ios"]["bundleIdentifier"] = "dev.nomac.ExpoDefault"
    (src / "app.json").write_text(json.dumps(config, indent=2) + "\n")
    npx(env, src, "expo", "prebuild", "--platform", "ios", "--no-install")
    return src, "ios/ExpoDefault.xcworkspace", "ExpoDefault"


def rn_bare(apps, env):
    npx(env, apps, f"@react-native-community/cli@{PINS['@react-native-community/cli']}", "init", "RNBare",
        "--version", PINS["react-native"], "--skip-git-init", "--install-pods", "false", "--pm", "npm")
    return apps / "RNBare", "ios/RNBare.xcworkspace", "RNBare"


APPS = {"expo-default": (expo_default, "ExpoDefault"), "rn-bare": (rn_bare, "RNBare")}


def log(message):
    print(f"[expo] {message}", flush=True)


def run(argv, cwd, env, check=True):
    log("$ " + " ".join(str(a) for a in argv))
    return subprocess.run([str(a) for a in argv], cwd=cwd, env=env, check=check)


def npx(env, cwd, *args):
    cwd.mkdir(parents=True, exist_ok=True)
    run(["npx", "-y", *args], cwd, env)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest() if Path(path).exists() else None


def node_home(root):
    """The pinned Node for this machine, downloaded into <root>/node when missing."""
    home = root / "node"
    if (home / "bin" / "node").exists():
        return home
    system = f"{'darwin' if sys.platform == 'darwin' else 'linux'}-{'arm64' if platform.machine() in ('arm64', 'aarch64') else 'x64'}"
    name = f"node-v{PINS['node']}-{system}"
    archive = root / f"{name}.tar.gz"
    if not archive.exists():
        subprocess.run(["curl", "-fsSL", "--http1.1", "-o", str(archive),
                        f"https://nodejs.org/dist/v{PINS['node']}/{name}.tar.gz"], check=True)
    if sha256(archive) != NODE_SHA256[system]:
        sys.exit(f"error: {archive} does not have the SHA-256 of Node {PINS['node']} for {system}")
    with tarfile.open(archive) as tar:
        tar.extractall(root)
    (root / name).rename(home)
    return home


def tool_environment(root):
    node = node_home(root)
    env = {"PATH": f"{node}/bin:{Path.home()}/.rbenv/shims:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(Path.home()),
           "LANG": "en_US.UTF-8", "TMPDIR": os.environ.get("TMPDIR", "/tmp/"), "RBENV_VERSION": PINS["ruby"],
           "npm_config_before": PINS["npm-before"], "CI": "1", "EXPO_NO_TELEMETRY": "1"}
    versions = {"node": output(["node", "--version"], env).lstrip("v"), "cocoapods": output(["pod", "--version"], env),
                "ruby": output(["ruby", "-e", "print RUBY_VERSION"], env)}
    for tool in ("node", "cocoapods", "ruby"):
        if versions[tool] != PINS[tool]:
            sys.exit(f"error: {tool} is {versions[tool]}, the experiment pins {PINS[tool]}")
    return env


def output(argv, env):
    return subprocess.run(argv, env=env, capture_output=True, text=True, check=True).stdout.strip()


def requirements(src):
    """What the generated app's own packages declare they need."""
    found = {}
    for package in ("expo", "react-native", "."):
        manifest = src / ("package.json" if package == "." else f"node_modules/{package}/package.json")
        if manifest.exists():
            data = json.loads(manifest.read_text())
            found[data.get("name", package)] = {"version": data.get("version"), "engines": data.get("engines")}
    gemfile = src / "Gemfile"
    if gemfile.exists():
        found["Gemfile"] = [line for line in gemfile.read_text().splitlines() if line.startswith(("ruby", "gem"))]
    return found


def platform_packages(src, env):
    """Installs the lockfile's optional packages for Linux (glibc; arm64 and x64), which npm leaves
    out on a Mac, from their tarballs with the lockfile's integrity, so that the same checkout's
    Node scripts and native modules run on Linux. Returns the folders added."""
    lock = json.loads((src / "package-lock.json").read_text()).get("packages", {})
    added = []
    with tempfile.TemporaryDirectory() as folder:
        for path, entry in sorted(lock.items()):
            if not entry.get("optional") or "linux" not in (entry.get("os") or []) or "musl" in (entry.get("libc") or []):
                continue
            if not set(entry.get("cpu") or []) & {"arm64", "x64"} or (src / path).exists():
                continue
            tarball = Path(folder) / "package.tgz"
            run(["curl", "-fsSL", "--http1.1", "-o", tarball, entry["resolved"]], src, env)
            digest = "sha512-" + base64.b64encode(hashlib.sha512(tarball.read_bytes()).digest()).decode()
            if digest != entry.get("integrity"):
                sys.exit(f"error: {entry['resolved']} does not have the lockfile's integrity")
            (src / path).mkdir(parents=True)
            subprocess.run(["tar", "-xzf", str(tarball), "-C", str(src / path), "--strip-components=1"], check=True)
            added.append(path)
    return added


def git(src, *args, env=None):
    return subprocess.run(["git", "-C", str(src), *args], check=True, capture_output=True, text=True, env=env).stdout.strip()


def commit_everything(src, message="generated", fresh=True):
    """Commits every file, node_modules and Pods included, at a fixed date: into a new repository,
    or on top of the existing one."""
    env = dict(os.environ, GIT_AUTHOR_NAME="nomac", GIT_AUTHOR_EMAIL="nomac@localhost", GIT_COMMITTER_NAME="nomac",
               GIT_COMMITTER_EMAIL="nomac@localhost", GIT_AUTHOR_DATE=COMMIT_DATE, GIT_COMMITTER_DATE=COMMIT_DATE)
    if fresh:
        shutil.rmtree(src / ".git", ignore_errors=True)
        git(src, "init", "-q")
    git(src, "-c", "core.excludesFile=/dev/null", "add", "-f", "-A", ".")
    git(src, "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", message, env=env)
    return git(src, "rev-parse", "HEAD")


def add_platform_packages(root, app_id):
    """`platform-packages`: the Linux packages for an app generated without them, as a commit on
    top; the references captured at the parent commit stay valid, a Mac build reading none of them."""
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    reset(src, record["commit"])
    record["platformPackages"] = platform_packages(src, tool_environment(root))
    record["referenceCommit"] = record.get("referenceCommit", record["commit"])
    record["commit"] = commit_everything(src, "Linux platform packages", fresh=False)
    (root / "apps" / f"{app_id}.json").write_text(json.dumps(record, indent=2) + "\n")
    log(f"{app_id}: {len(record['platformPackages'])} Linux packages at {record['commit']}")


def generate(root, app_id):
    """Generates the app where it is built, since `pod install` and codegen record absolute paths."""
    env = tool_environment(root)
    make, name = APPS[app_id]
    shutil.rmtree(root / "apps" / name, ignore_errors=True)
    src, container, scheme = make(root / "apps", env)
    run(["pod", "install"], src / "ios", env)
    record = {"id": app_id, "path": str(src), "container": container, "scheme": scheme, "pins": PINS,
              "tools": {"node": output(["node", "--version"], env), "cocoapods": output(["pod", "--version"], env),
                        "ruby": output(["ruby", "--version"], env)},
              "packageLock": sha256(src / "package-lock.json"), "podfileLock": sha256(src / "ios" / "Podfile.lock"),
              "requires": requirements(src)}
    record["platformPackages"] = platform_packages(src, env)
    record["commit"] = commit_everything(src)
    (root / "apps" / f"{app_id}.json").write_text(json.dumps(record, indent=2) + "\n")
    log(f"{app_id}: {src} at {record['commit']}")


def reset(src, commit):
    git(src, "checkout", "-q", "--detach", commit)
    git(src, "reset", "-q", "--hard", commit)
    git(src, "clean", "-q", "-fdx")


def manifest_entry(record, configuration):
    """The app as a corpus.json entry, for capture_reference.py's functions and `nomac verify`."""
    return {"id": record["id"], "repository": "", "commit": record["commit"], "container": record["container"],
            "build": {"scheme": record["scheme"], "configuration": configuration}}


def offline_run(cmd, cwd, env, out_path=None, **kwargs):
    """capture_reference.py's `run` under OFFLINE, recording the command without the sandbox, as
    `nomac verify --build` replays it."""
    if cmd[0] != "xcodebuild":
        return ORIGINAL_RUN(cmd, cwd, env, out_path, **kwargs)
    proc = ORIGINAL_RUN(OFFLINE + cmd, cwd, env, out_path, **kwargs)
    if out_path is not None:
        unwrap(Path(str(out_path) + ".cmd"))
    return proc


def unwrap(record):
    command = json.loads(record.read_text())
    if command["argv"][:2] == OFFLINE[:2]:
        command["argv"] = command["argv"][len(OFFLINE):]
        record.write_text(json.dumps(command, indent=2) + "\n")


ORIGINAL_RUN = capture.run


def capture_app(root, app_id, configurations):
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    env = capture.reference_environment(developer_dir)
    capture.run = offline_run
    host = capture.host_identity(developer_dir, env)
    shared = root / "refs" / "shared" / app_id
    if not (shared / "settings" / "index.json").exists():
        reset(src, record["commit"])
        shutil.rmtree(shared, ignore_errors=True)
        (shared / "pif").mkdir(parents=True)
        app = manifest_entry(record, configurations[0])
        capture.run(["xcodebuild", "-dumpPIF", str(shared / "pif" / "workspace.pif")] + capture.container_args(app, src),
                    cwd=src, env=env, out_path=shared / "pif" / "dumpPIF.stdout", err_path=shared / "pif" / "dumpPIF.stderr")
        capture.capture_settings(app, src, shared, env)
    for configuration in configurations:
        app = manifest_entry(record, configuration)
        out = root / "refs" / configuration / app_id
        shutil.rmtree(out, ignore_errors=True)
        shutil.copytree(shared, out)
        (out / "app.json").write_text(json.dumps(app, indent=2) + "\n")
        (out / "host.json").write_text(json.dumps(host, indent=2, sort_keys=True) + "\n")
        (out / "source.json").write_text(json.dumps({"path": str(src), "commit": record["commit"]}, indent=2) + "\n")
        capture.run(["xcodebuild", "-showsdks", "-json"], cwd=out, env=env, out_path=out / "showsdks.json",
                    err_path=out / "showsdks.stderr")
        reset(src, record["commit"])
        if app_id in NESTED_SWIFTPM:
            capture.run = ORIGINAL_RUN
            status = capture.capture_build(app, src, out, env)
            capture.run = offline_run
        else:
            status = capture.capture_build(app, src, out, env)
        summary = {"app": app_id, "commit": record["commit"], "xcodeBuild": host["xcodeBuild"],
                   "prepareExitStatus": None, "buildExitStatus": status}
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        log(json.dumps(summary))
        reset(src, record["commit"])


def capture_archives(root, app_id, configurations):
    """`capture --archive`: capture_reference.py's ad-hoc archive and `debugging` export of the build
    scheme into each configuration's reference (`archive/`): the build unsandboxed, its sockets in
    <reference>/archive/archive.network.log, the export offline."""
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    env = capture.reference_environment(developer_dir)
    capture.run = ORIGINAL_RUN
    for configuration in configurations:
        out = root / "refs" / configuration / app_id
        if not (out / "summary.json").exists():
            sys.exit(f"error: capture {app_id} {configuration} first")
        reset(src, record.get("referenceCommit", record["commit"]))
        capture.capture_archive(manifest_entry(record, configuration), src, out, env)
        for record_path in (out / "archive").glob("*.log.cmd"):
            unwrap(record_path)
        reset(src, record["commit"])


def verify_app(root, app_id, configurations, nomac, fixes=False):
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    env = capture.reference_environment(developer_dir)
    for configuration in configurations:
        out = root / "refs" / configuration / app_id
        reset(src, record["commit"])
        if fixes:
            project_fixes(src)
        on_mac = sys.platform == "darwin"
        sandbox = OFFLINE if on_mac and app_id not in NESTED_SWIFTPM else []
        with capture.NetworkLog(f"{out}.nomac.network.log") if on_mac and not sandbox else contextlib.nullcontext():
            run(sandbox + [nomac, "verify", out, "--developer-dir", developer_dir, "--build",
                           "--continue-building-after-errors", "--report", f"{out}.nomac.json"], src, env, check=False)
        build_log = Path(os.environ.get("NOMAC_HOME", Path.home() / ".nomac")) / "scratch" / f"build-{app_id}.log"
        if build_log.exists():
            shutil.copy(build_log, f"{out}.nomac-build.log")
        derived = src.parent / f"{app_id}-DerivedData"
        kept = Path(f"{out}.nomac-DerivedData")
        shutil.rmtree(kept, ignore_errors=True)
        if derived.exists():
            derived.rename(kept)
        reset(src, record["commit"])


LINUX_HERMESC = "node_modules/hermes-compiler/hermesc/linux64-bin/hermesc"
AUTOLINKING_SCAN = ("node_modules/expo-modules-autolinking/build/platforms/apple/apple.js",
                    "if (process.platform !== 'darwin') {",
                    "if (process.platform !== 'darwin' && process.platform !== 'linux') {")


def project_fixes(src):
    """--project-fixes: what `nomac check` and ADR 0182 ask of a project built on Linux, made in
    the checkout that `verify` resets afterwards. React Native's phases source ios/.xcode.env.local
    after the build settings, so it names the Linux hermesc that the same hermes-compiler package
    ships (x86_64; given the same input path, its bytecode is the macOS one's byte for byte); and
    expo-modules-autolinking scans for @ExpoModule classes on Linux too, with the Linux scanner that
    expo-modules-macros installs there."""
    applied = []
    if (src / LINUX_HERMESC).exists():
        with open(src / "ios" / ".xcode.env.local", "a") as env_file:
            env_file.write(f"export HERMES_CLI_PATH={src / LINUX_HERMESC}\n")
        applied.append("HERMES_CLI_PATH in ios/.xcode.env.local")
    path, check, linux_check = AUTOLINKING_SCAN
    if (src / path).exists() and check in (src / path).read_text():
        (src / path).write_text((src / path).read_text().replace(check, linux_check))
        applied.append(path)
    log(f"project fixes: {', '.join(applied) or 'none'}")


MACRO_STUBS = "".join(f"public protocol {name} {{}}\n" for name in ["AnyModule", "Record", "JavaScriptDecodable", "JavaScriptEncodable"]) \
    + "open class Module {}\nopen class SharedObject {}\n"


def macro_expansions(app, out, swiftc, plugin, sdk):
    """`macros`: expo-haptics' module with expo-modules-core's macro declarations, type-checked with
    -dump-macro-expansions by <swiftc> and <plugin> (ADR 0151); stand-ins for the protocols the
    declarations name. Writes <out>/expansions.out: the same bytes from Xcode's swiftc with the macOS
    plugin and swift.org's with the Linux one means the same expansions."""
    out.mkdir(parents=True, exist_ok=True)
    modules = app / "node_modules"
    (out / "stubs.swift").write_text(MACRO_STUBS)
    shutil.copy(modules / "expo-modules-core/ios/Core/ExpoModulesMacros.swift", out / "decls.swift")
    source = (modules / "expo-haptics/ios/HapticsModule.swift").read_text()
    (out / "module.swift").write_text("".join(line for line in source.splitlines(True) if line.strip() != "import ExpoModulesCore"))
    proc = subprocess.run([swiftc, "-typecheck", "-target", "arm64-apple-ios16.4", "-sdk", sdk, "-swift-version", "5",
                           "-load-plugin-executable", f"{plugin}#ExpoModulesMacros", "-Xfrontend", "-dump-macro-expansions",
                           "stubs.swift", "decls.swift", "module.swift"], cwd=out, capture_output=True)
    (out / "expansions.out").write_bytes(proc.stdout + proc.stderr)
    log(f"{(proc.stdout + proc.stderr).count(b'@__swiftmacro_')} expansions in {out / 'expansions.out'}")


NESTED_PHASES = {"expo-default": "[CP-User] Build ExpoModulesJSI xcframework"}

RECORDING_XCODEBUILD = """#!/bin/sh
# Records each call (the phase may run xcodebuild with `env -i`), then runs {xcodebuild}.
{{ printf '%s' "$PWD"; for argument in "$@"; do printf '\\0%s' "$argument"; done; printf '\\n'; }} >> '{record}'
env > '{record}.env.'$$
exec '{xcodebuild}' "$@"
"""


def phase_environment(log_path, phase):
    """The folder, command and exported environment of a script phase, from an xcodebuild log."""
    header = "PhaseScriptExecution " + phase.replace(" ", "\\ ")
    for block in Path(log_path).read_text(errors="replace").split("\n\n"):
        if block.startswith(header):
            lines = [line.strip() for line in block.splitlines()[1:]]
            unescape = lambda text: re.sub(r"\\(.)", r"\1", text)
            env = dict(unescape(line[7:]).split("=", 1) for line in lines if line.startswith("export "))
            folder = unescape(next(line[3:] for line in lines if line.startswith("cd ")))
            return folder, env
    sys.exit(f"error: no phase '{phase}' in {log_path}")


def nested(root, app_id, xcodebuild, keep=False):
    """Replays the app's phase that runs xcodebuild, with the environment Xcode's Release build
    gave it and a recording xcodebuild first on PATH; keeps the calls and the nested build's
    products and build request in <root>/refs/nested/<app>/<label>."""
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    folder, env = phase_environment(root / "refs" / "Release" / app_id / "build" / "build.log", NESTED_PHASES[app_id])
    label = "xcode" if xcodebuild == "/usr/bin/xcodebuild" else "nomac"
    out = root / "refs" / "nested" / app_id / label
    shutil.rmtree(out, ignore_errors=True)
    (out / "bin").mkdir(parents=True)
    (out / "bin" / "xcodebuild").write_text(RECORDING_XCODEBUILD.format(record=out / "calls", xcodebuild=xcodebuild))
    os.chmod(out / "bin" / "xcodebuild", 0o755)
    env["PATH"] = f"{out / 'bin'}:{env['PATH']}"
    reset(src, record["commit"])
    script = env["PODS_TARGET_SRCROOT"] + "/scripts/build-xcframework.sh"
    with (out / "phase.log").open("w") as phase_log:
        status = subprocess.run(["/bin/sh", "-c", f'"{script}"'], cwd=folder, env=env, stdout=phase_log, stderr=subprocess.STDOUT).returncode
    package = Path(env["PODS_TARGET_SRCROOT"])
    for name in ("Build/Products", ):
        if (package / ".DerivedData" / name).exists():
            shutil.copytree(package / ".DerivedData" / name, out / "Products", symlinks=True)
    for request in (package / ".DerivedData").glob("Build/Intermediates.noindex/XCBuildData/*.xcbuilddata/build-request.json"):
        shutil.copy(request, out / "build-request.json")
        shutil.copy(request.parent / "manifest.json", out / "manifest.json")
    if (package / "Products").exists():
        shutil.copytree(package / "Products", out / "xcframeworks", symlinks=True)
    calls = [line.split("\0") for line in (out / "calls").read_text().splitlines()] if (out / "calls").exists() else []
    (out / "summary.json").write_text(json.dumps({"status": status, "calls": calls}, indent=2) + "\n")
    build = next((call for call in calls if "build" in call[1:]), None)
    if label == "xcode" and build:
        reset(src, record["commit"])
        loader_captures(out, build, sorted(out.glob("calls.env.*"))[-1])
    log(f"{app_id} nested ({label}): status {status}, {len(calls)} xcodebuild calls")
    if not keep:
        reset(src, record["commit"])


def loader_captures(out, call, environment):
    """Xcode's `-list -json`, `-dumpPIF` and `-showBuildSettings` (text and JSON) for the folder
    and arguments of a recorded build call, with its environment, in capture_reference.py's
    layout (`pif/`, `settings/`), as `nomac verify` reads them."""
    folder, arguments = call[0], [argument for argument in call[1:] if argument not in ("build", "-quiet")]
    env = dict(line.split("=", 1) for line in Path(environment).read_text().splitlines() if "=" in line)
    (out / "pif").mkdir()
    (out / "settings").mkdir()
    capture.run(["xcodebuild", "-list", "-json"], cwd=folder, env=env, out_path=out / "xcodebuild-list.json",
                err_path=out / "xcodebuild-list.stderr")
    capture.run(["xcodebuild", "-dumpPIF", str(out / "pif" / "workspace.pif")], cwd=folder, env=env,
                out_path=out / "pif" / "dumpPIF.stdout", err_path=out / "pif" / "dumpPIF.stderr")
    text = capture.run(["xcodebuild", "-showBuildSettings"] + arguments, cwd=folder, env=env,
                       out_path=out / "settings" / "nested.txt", err_path=out / "settings" / "nested.stderr")
    capture.run(["xcodebuild", "-showBuildSettings", "-json"] + arguments, cwd=folder, env=env,
                out_path=out / "settings" / "nested.json", err_path=out / "settings" / "nested.json.stderr")
    (out / "settings" / "index.json").write_text(json.dumps([{"name": "nested", "arguments": arguments, "exitStatus": text.returncode}], indent=2) + "\n")


def triage(log_path):
    """The errors of an xcodebuild-format build log, grouped by the task that reported them and the
    message with its paths and numbers removed, most frequent first."""
    groups = {}
    task = "build"
    for block in Path(log_path).read_text(errors="replace").split("\n\n"):
        lines = block.splitlines()
        if lines and not lines[0].startswith((" ", "/", "error:", "warning:", "note:")):
            task = lines[0].split(" ", 1)[0]
        for line in lines:
            if "error: " not in line or line.lstrip().startswith("export "):
                continue
            message = line[line.index("error: ") + 7:]
            message = re.sub(r"(/[^\s'`:]+)+", "<path>", message)
            message = re.sub(r"\b\d+\b", "<n>", message)[:160]
            groups.setdefault((task, message), 0)
            groups[(task, message)] += 1
    for (task, message), count in sorted(groups.items(), key=lambda item: -item[1]):
        print(f"{count:5}  {task:28} {message}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["generate", "capture", "verify", "node", "triage", "nested", "platform-packages", "macros"])
    parser.add_argument("--xcodebuild", default="/usr/bin/xcodebuild")
    parser.add_argument("--keep", action="store_true", help="nested: leave the checkout as the phase left it")
    parser.add_argument("apps", nargs="*")
    parser.add_argument("--root", default=str(Path.home() / "nomac-out" / "wt-scratch" / "expo"))
    parser.add_argument("--configuration", action="append", dest="configurations")
    parser.add_argument("--nomac")
    parser.add_argument("--archive", action="store_true", help="capture: the ad-hoc archive and its export")
    parser.add_argument("--project-fixes", action="store_true", help="verify: the project's changes for Linux first")
    args = parser.parse_intermixed_args()
    root = Path(args.root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    configurations = args.configurations or ["Release", "Debug"]
    if args.command == "triage":
        for log_path in args.apps:
            triage(log_path)
        return
    if args.command == "macros":
        app, out, swiftc, plugin, sdk = args.apps
        macro_expansions(Path(app), Path(out).resolve(), swiftc, plugin, sdk)
        return
    if args.command == "node":
        log(f"Node {PINS['node']}: {node_home(root)}")
        return
    for app_id in args.apps or list(APPS):
        if args.command == "generate":
            generate(root, app_id)
        elif args.command == "platform-packages":
            add_platform_packages(root, app_id)
        elif args.command == "nested":
            if app_id in NESTED_PHASES:
                nested(root, app_id, args.xcodebuild, args.keep)
        elif args.command == "capture" and args.archive:
            capture_archives(root, app_id, configurations)
        elif args.command == "capture":
            capture_app(root, app_id, configurations)
        else:
            verify_app(root, app_id, configurations, str(Path(args.nomac or sys.exit("error: --nomac is required")).resolve()),
                       args.project_fixes)


if __name__ == "__main__":
    main()

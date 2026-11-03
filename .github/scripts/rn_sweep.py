#!/usr/bin/env python3
"""Sweep of public React Native and Expo apps: which of them nomac builds on Linux, and what stops the rest.

corpus/rn-sweep.json lists the apps (open source, each at a fixed commit) that nobody tuned nomac
for. Each app goes through these steps in order, stopping at the first failure:

  install  (Mac, online) the JavaScript packages with the package manager of the app's lockfile,
           `expo prebuild --platform ios` for an Expo app without an ios folder, `pod install`, and
           the Linux builds of the npm platform packages installed for macOS (linux_packages)
  survey   script_phase_survey.py's counts of macOS-only commands and BSD flags in the app's script
           phases (not a step that fails)
  check    (Linux, the steps below too, in a container without network) `nomac check --json`: every
           feature outside the envelope, the project requirements among them
  fixes    the project's changes for Linux: each setting that names a Mach-O tool overridden on the
           command line with the Linux build of the same tool (`build:setting=mach-o-executable`'s
           note), and ADR 0182's platform check of expo-modules-autolinking. Requirements left
           without a fix are recorded and the build is tried anyway: it decides
  build    `nomac archive` Release for generic/platform=iOS, ad-hoc signed (capture_reference.py's ADHOC),
           continuing after errors so that one run shows every independent failure (with
           --separate-build: `nomac build` without signing, then the archive from a new build folder)
  archive  the build's archive
  export   `nomac export` with capture_reference.py's `debugging` options

A failed step's errors are classified by the task that failed and the message with its paths and
numbers removed (classify): a macOS command or BSD flag in a script, a prebuilt Mach-O tool, a
storyboard or asset feature nomac refuses, a macro plugin, a compile or link error. Every output
stays under --root, outside the repository; each app's build folders are deleted after its run.

Usage (Mac):
  rn_sweep.py container [--root R]           create the Linux container (the volume's layout below)
  rn_sweep.py run [--root R] [--keep] [--keep-failed H] [--resume] [--installers N] [--builders M] [app ...]
                                             every step: N apps installing on the Mac, M building on Linux;
                                             --resume leaves out the apps that finished, except installs the
                                             network stopped
  rn_sweep.py prepare [--keep] [app ...]     the Mac steps only (install, survey), the copy deleted after
  rn_sweep.py install|survey [app ...]       one Mac step, the copy kept
  rn_sweep.py report [--root R]              tables: steps, apps, failure classes, survey, requirements
  rn_sweep.py reclassify [app ...]           the kept logs' failures classified again
In the container: rn_sweep.py linux [--root R] [--slot S] app

The volume (nomac-sweep) holds bin/current/nomac (a Linux build of nomac), devdir/Xcode_27.app (the
SDK subset with `nomac toolchain install`'s toolchain), node-linux (the pinned Node for Linux),
apps (the apps at their Mac paths) and dd (build folders). Results: <root>/results/<app>.json and
<root>/results/<app>/ (logs, check.json, survey.json).
"""

import argparse
import base64
import concurrent.futures
import contextlib
import gzip
import queue
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
MANIFEST = SCRIPTS.parents[1] / "corpus" / "rn-sweep.json"
sys.path.insert(0, str(SCRIPTS))
import expo_experiments as expo  # noqa: E402

capture = expo.capture
STEPS = ["install", "check", "fixes", "build", "archive", "export"]
VOLUME, CONTAINER, IMAGE = "nomac-sweep", "nomac-sweep-run", "nomac-linux:6.4.1-noble"
WORK = Path("/work")
NOMAC = WORK / "bin/current/nomac"
DEVELOPER_DIR = WORK / "devdir/Xcode_27.app/Contents/Developer"
MIN_FREE = 15 << 30
MIN_FREE_MAC = 10 << 30
MIN_FREE_MAC_BUILD = 25 << 30
MANIFEST_LOCK, POD_LOCK = threading.Lock(), threading.Lock()
LOCKFILES = [("bun.lock", "bun"), ("bun.lockb", "bun"), ("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"),
             ("package-lock.json", "npm")]
SKIPPED = {".git", "build", "DerivedData", ".expo"}
LINUX_CPUS = {"arm64", "x64"}
EXAMPLE_ENVIRONMENTS = [".env.example", "env.example", ".env.sample", ".env.template", ".env.dist"]
# Commands of macOS that Linux lacks, as script_phase_survey.py counts them, and BSD's md5.
MACOS_COMMANDS = {"PlistBuddy", "plutil", "sips", "osascript", "defaults", "security", "sw_vers", "xattr", "iconutil",
                  "ditto", "codesign", "xcrun", "xcodebuild", "xcode-select", "lipo", "otool", "install_name_tool",
                  "dsymutil", "dwarfdump", "actool", "ibtool", "agvtool", "mdfind", "mdls", "pbcopy", "pbpaste", "open",
                  "launchctl", "hdiutil", "pkgutil", "system_profiler", "scutil", "ipconfig", "networksetup",
                  "textutil", "vtool", "atos", "symbols", "SetFile", "GetFileInfo", "say", "caffeinate", "diskutil",
                  "spctl", "productbuild", "pkgbuild", "altool", "notarytool", "stapler", "simctl", "shasum", "md5"}
BSD_TOOLS = r"(sed|date|stat|find|base64|md5|xargs|cp|mktemp|readlink|tar|grep|ln|touch|du|head|tail|split|awk|sort|wc)"


def log(message):
    print(f"[rn-sweep] {message}", flush=True)


def manifest():
    return json.loads(MANIFEST.read_text())


def entries(names):
    apps = manifest()["apps"]
    known = {app["id"]: app for app in apps}
    missing = [name for name in names if name not in known]
    if missing:
        sys.exit(f"error: not in {MANIFEST.name}: {', '.join(missing)}")
    return [known[name] for name in names] if names else apps


def results_path(root, app_id):
    return root / "results" / f"{app_id}.json"


def load_result(root, app_id):
    path = results_path(root, app_id)
    return json.loads(path.read_text()) if path.exists() else {"id": app_id, "steps": {}}


def save_result(root, result):
    write_atomically(results_path(root, result["id"]), json.dumps(result, indent=2, sort_keys=True) + "\n")


def write_atomically(path, text):
    """Writes text to path through a rename, so that the other threads never read half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{threading.get_ident()}")
    temporary.write_text(text)
    temporary.replace(path)


def run(argv, cwd, env, log_path, timeout=None):
    """Runs a command with its output in log_path; returns the exit status (124 on timeout)."""
    log("$ " + " ".join(str(a) for a in argv))
    with open(log_path, "ab") as out:
        out.write(("$ " + " ".join(str(a) for a in argv) + "\n").encode())
        out.flush()
        try:
            return subprocess.run([str(a) for a in argv], cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT,
                                  stdin=subprocess.DEVNULL, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            out.write(f"\nerror: timed out after {timeout} seconds\n".encode())
            return 124
        except OSError as error:
            out.write(f"\nerror: {error}\n".encode())
            return 127


def step(result, name, ok, started, **details):
    result["steps"][name] = {"ok": ok, "seconds": round(time.time() - started), **details}
    log(f"{result['id']}: {name} {'passed' if ok else 'failed'}" + (f": {details.get('class')}" if not ok and details.get("class") else ""))
    return ok


def tail_error(log_path, lines=3, offset=0):
    text = Path(log_path).read_bytes()[offset:].decode(errors="replace").splitlines() if Path(log_path).exists() else []
    errors = [line for line in text if re.search(r"\b(error|ERR!|Error)\b|\[!\]", line)]
    return " | ".join(errors[:lines] if errors else text[-lines:])[:400]


def free_bytes(path):
    return shutil.disk_usage(path).free


def wait_for_space(free, where, needed=MIN_FREE, hours=6):
    """Waits until free() is at least `needed`: the disks are shared with other builds, which free theirs."""
    deadline = time.time() + hours * 3600
    if free() < needed:
        log(f"waiting for {needed >> 30} GB free {where}")
    while free() < needed:
        if time.time() > deadline:
            return False
        time.sleep(120)
    return True


# The app's folders.

def checkout(root, entry):
    """The repository folder (a whole monorepo for an app in a subfolder)."""
    return root / "apps" / entry["id"]


def app_folder(root, entry):
    return checkout(root, entry) / entry.get("path", ".") if entry.get("source") is None else checkout(root, entry)


def node_module_owners(folder, top):
    """The folders from `folder` up to `top`, whose node_modules Node searches in this order."""
    folders = [folder]
    while folders[-1] != top and folders[-1] != folders[-1].parent:
        folders.append(folders[-1].parent)
    return folders


# Install (Mac).

def mac_environment(root):
    expo.node_home(root)
    shims = root / "shims"
    env = {"PATH": f"{root}/node/bin:{shims}:{Path.home()}/.rbenv/shims:/usr/bin:/bin:/usr/sbin:/sbin",
           "HOME": str(Path.home()), "LANG": "en_US.UTF-8", "TMPDIR": os.environ.get("TMPDIR", "/tmp/"),
           "RBENV_VERSION": expo.PINS["ruby"], "CI": "1", "EXPO_NO_TELEMETRY": "1",
           "COREPACK_ENABLE_DOWNLOAD_PROMPT": "0", "npm_config_prefer_offline": "true",
           "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "http.version",
           "GIT_CONFIG_VALUE_0": "HTTP/1.1"}
    if not (shims / "yarn").exists():
        shims.mkdir(exist_ok=True)
        subprocess.run(["corepack", "enable", "--install-directory", str(shims)], env=env, check=True)
    for tool, argv in (("node", ["node", "--version"]), ("cocoapods", ["pod", "--version"])):
        version = expo.output(argv, env).lstrip("v")
        if version != expo.PINS[tool]:
            sys.exit(f"error: {tool} is {version}, the sweep pins {expo.PINS[tool]}")
    return env


def fetch(root, entry, env, log_path):
    """The app's repository at its commit, in a new folder (an example: its folder of the examples' repository)."""
    target = checkout(root, entry)
    shutil.rmtree(target, ignore_errors=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    if entry.get("source"):
        source = manifest()["sources"][entry["source"]]
        repository = root / "src" / entry["source"]
        if not (repository / ".git").exists():
            repository.mkdir(parents=True)
            git_fetch(repository, source["repository"], source["commit"], env, log_path)
        elif expo.git(repository, "rev-parse", "HEAD") != source["commit"]:
            git_fetch(repository, source["repository"], source["commit"], env, log_path)
        subprocess.run(["cp", "-cR", str(repository / entry["path"]), str(target)], check=True)
        return True
    target.mkdir(parents=True)
    if not git_fetch(target, entry["repository"], entry["commit"], env, log_path):
        return False
    if (target / ".gitmodules").exists():
        return run(["git", "submodule", "update", "--init", "--recursive", "--depth", "1"], target, env, log_path) == 0
    return True


def git_fetch(folder, url, commit, env, log_path):
    for argv in (["git", "init", "-q"], ["git", "fetch", "-q", "--depth", "1", url, commit],
                 ["git", "checkout", "-q", "--detach", "FETCH_HEAD"]):
        if run_online(argv, folder, env, log_path) != 0:
            return False
    return True


NETWORK_ERRORS = re.compile(r"ETIMEDOUT|ENOTFOUND|ECONNRESET|EAI_AGAIN|unable to access|Could not resolve host|"
                            r"Failed to connect|Connection timed out|SSL_ERROR|HTTP/2 stream|Failed to download|curl: \(\d+\)|RPC failed|early EOF|transfer closed|Connection reset")


def run_online(argv, cwd, env, log_path, timeout=3600, attempts=3):
    """run, again after a minute when the output shows a network error (the Mac's network drops)."""
    for attempt in range(attempts):
        offset = log_path.stat().st_size if log_path.exists() else 0
        status = run(argv, cwd, env, log_path, timeout=timeout)
        with open(log_path, "rb") as out:
            out.seek(offset)
            failed_online = NETWORK_ERRORS.search(out.read().decode(errors="replace"))
        if status == 0 or not failed_online or attempt + 1 == attempts:
            return status
        log(f"network error, retrying: {' '.join(str(a) for a in argv)[:80]}")
        time.sleep(60)


def package_manager(app, top):
    for folder in node_module_owners(app, top):
        for lockfile, manager in LOCKFILES:
            if (folder / lockfile).exists():
                return manager, folder, lockfile
    return "npm", app, None


def install_command(manager, folder, lockfile):
    declared = json.loads((folder / "package.json").read_text()).get("packageManager", "") if (folder / "package.json").exists() else ""
    if manager == "yarn":
        berry = declared.startswith("yarn@") and not declared.startswith("yarn@1.")
        return ["yarn", "install", "--immutable" if berry else "--frozen-lockfile"], declared or "yarn@1"
    if manager == "pnpm":
        return ["pnpm", "install", "--frozen-lockfile"], declared or "pnpm"
    if manager == "bun":
        version = declared.split("@", 1)[1] if declared.startswith("bun@") else "latest"
        return ["npx", "-y", f"bun@{version}", "install", "--frozen-lockfile"], f"bun@{version}"
    return (["npm", "ci"] if lockfile else ["npm", "install"]), declared or "npm"


def installed_version(app, top, package):
    for folder in node_module_owners(app, top):
        manifest_file = folder / "node_modules" / package / "package.json"
        if manifest_file.exists():
            return json.loads(manifest_file.read_text()).get("version")
    return None


def example_environment(app, top):
    """An app that reads its configuration from a .env file the repository leaves out ships an
    example of it; the README's setup copies the example to .env, which is done here."""
    for folder in node_module_owners(app, top):
        example = next((folder / name for name in EXAMPLE_ENVIRONMENTS if (folder / name).is_file()), None)
        if example and not (folder / ".env").exists():
            shutil.copyfile(example, folder / ".env")
            return [f"{(folder / '.env').relative_to(top)} copied from {example.name}"]
    return []


def set_bundle_identifier(app, app_id):
    """expo prebuild takes the bundle identifier from app.json, or derives one from the machine's accounts."""
    config = app / "app.json"
    if not config.exists():
        return
    data = json.loads(config.read_text())
    expo_config = data.get("expo", data)
    ios = expo_config.setdefault("ios", {})
    if "bundleIdentifier" not in ios:
        ios["bundleIdentifier"] = "dev.nomac.sweep." + re.sub(r"[^A-Za-z0-9]", "", app_id)
        config.write_text(json.dumps(data, indent=2) + "\n")


def install(root, entry, env):
    result = load_result(root, entry["id"])
    result.update({"kind": "expo-example" if entry.get("source") else "app",
                   "commit": manifest()["sources"][entry["source"]]["commit"] if entry.get("source") else entry["commit"]})
    out = root / "results" / entry["id"]
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    log_path = out / "install.log"
    started = time.time()
    if not wait_for_space(lambda: free_bytes(root), "on the Mac", MIN_FREE_MAC):
        sys.exit(f"error: less than {MIN_FREE_MAC >> 30} GB free on the Mac for 6 hours")
    if not fetch(root, entry, env, log_path):
        step(result, "install", False, started, stage="fetch", error=tail_error(log_path))
        return save_result(root, result)
    top, app = checkout(root, entry), app_folder(root, entry)
    manager, folder, lockfile = package_manager(app, top)
    argv, declared = install_command(manager, folder, lockfile)
    install_env = dict(env, npm_config_before=manifest()["sources"][entry["source"]]["npmBefore"]) \
        if entry.get("source") and not lockfile else env
    stages = [("packages", argv, folder, install_env)]
    has_expo = installed_version(app, top, "expo") is not None or "expo" in json.loads((app / "package.json").read_text()).get("dependencies", {})
    if not (app / "ios").is_dir() and has_expo:
        set_bundle_identifier(app, entry["id"])
        stages.append(("prebuild", ["npx", "expo", "prebuild", "--platform", "ios", "--no-install"], app, env))
    stages.append(("pods", ["pod", "install"], app / "ios", env))
    notes = example_environment(app, top)
    timings = {}
    for stage, argv, cwd, stage_env in stages:
        offset = log_path.stat().st_size if log_path.exists() else 0
        stage_started = time.time()
        with POD_LOCK if stage == "pods" else contextlib.nullcontext():
            status = run_online(argv, cwd, stage_env, log_path) if cwd.is_dir() else 1
        if status != 0 and stage == "packages" and argv[0] == "npm" and "ERESOLVE" in log_path.read_text(errors="replace")[-20000:]:
            notes.append("npm --legacy-peer-deps (the packages' peer dependencies conflict: ERESOLVE)")
            status = run_online(argv + ["--legacy-peer-deps"], cwd, stage_env, log_path)
        elif status != 0 and cwd.is_dir():
            notes.append(f"{stage} again after a failure")
            with POD_LOCK if stage == "pods" else contextlib.nullcontext():
                status = run_online(argv, cwd, stage_env, log_path)
        timings[stage] = round(time.time() - stage_started)
        if status != 0:
            save_versions(result, app, top, manager, declared, lockfile)
            network = bool(NETWORK_ERRORS.search(log_path.read_bytes()[offset:].decode(errors="replace")))
            step(result, "install", False, started, stage=stage, error=tail_error(log_path, offset=offset), notes=notes,
                 network=network, stages=timings)
            return save_result(root, result)
    save_versions(result, app, top, manager, declared, lockfile)
    try:
        added = linux_packages(top, log_path)
    except (OSError, ValueError) as error:
        step(result, "install", False, started, stage="linux-packages", error=str(error)[:400],
             network="could not download" in str(error), stages=timings)
        return save_result(root, result)
    step(result, "install", True, started, linuxPackages=len(added), prebuild=any(s[0] == "prebuild" for s in stages), notes=notes,
         stages=timings)
    (out / "linux-packages.txt").write_text("".join(f"{path}\n" for path in added))
    save_result(root, result)


def save_versions(result, app, top, manager, declared, lockfile):
    """Records the versions the install resolved, in the result and in the manifest's entry."""
    versions = {"react-native": installed_version(app, top, "react-native"), "expo": installed_version(app, top, "expo")}
    result["versions"] = dict(versions, packageManager=declared, lockfile=lockfile)
    with MANIFEST_LOCK:
        data = manifest()
        entry = next(e for e in data["apps"] if e["id"] == result["id"])
        entry.update({key: value for key, value in versions.items() if value})
        write_atomically(MANIFEST, json.dumps(data, indent=2) + "\n")


def package_manifests(top):
    """Every installed npm package's package.json under top (nested node_modules, scopes and pnpm's store too)."""
    for folder, dirs, files in os.walk(top):
        dirs[:] = [d for d in dirs if d not in SKIPPED]
        path = Path(folder)
        if "package.json" in files and (path.parent.name == "node_modules"
                                        or (path.parent.name.startswith("@") and path.parent.parent.name == "node_modules")):
            yield path


def resolvable(package, name, top):
    """Whether Node finds `name` from inside `package`: its own node_modules, then every node_modules above it."""
    folder = package
    while True:
        candidate = folder / name if folder.name == "node_modules" else folder / "node_modules" / name
        if candidate.exists():
            return True
        if folder == top or folder == folder.parent:
            return False
        folder = folder.parent


REGISTRY = {}


def registry_manifest(name, spec):
    """The registry's manifest of name@spec (an exact version or a range), or None."""
    key = (name, spec)
    if key in REGISTRY:
        return REGISTRY[key]
    found = None
    if re.fullmatch(r"[0-9A-Za-z.+-]+", spec):
        body = http_get(f"https://registry.npmjs.org/{name.replace('/', '%2F')}/{urllib.parse.quote(spec)}")
        found = json.loads(body) if body else None
    if found is None and not spec.startswith(("file:", "link:", "workspace:", "npm:", "git", "http")):
        view = subprocess.run(["npm", "view", f"{name}@{spec}", "version", "--json"], capture_output=True, text=True)
        versions = json.loads(view.stdout) if view.returncode == 0 and view.stdout.strip() else None
        version = versions[-1] if isinstance(versions, list) and versions else versions
        if isinstance(version, str) and version != spec:
            found = registry_manifest(name, version)
    REGISTRY[key] = found
    return found


def http_get(url):
    """The body at url, or None (curl: the system's certificates, retries, HTTP/1.1 as the other scripts fetch)."""
    proc = subprocess.run(["curl", "-fsSL", "--http1.1", "--retry", "3", "--max-time", "600", url], capture_output=True)
    return proc.stdout if proc.returncode == 0 else None


def linux_glibc(meta):
    libc = meta.get("libc") or []
    return ("linux" in (meta.get("os") or []) and bool(set(meta.get("cpu") or []) & LINUX_CPUS)
            and "musl" not in libc and "-musl" not in meta["name"])


def linux_packages(top, log_path):
    """The Linux (glibc; arm64 and x64) packages of every optional dependency that the Mac's install
    left out: npm, yarn, pnpm and bun install only the current machine's platform packages, so
    the same checkout's Node tools and native modules would not run on Linux. Each comes from
    the registry with its integrity checked, into the top node_modules folder (else beside the
    package that names it), where Node's resolution finds it. Returns the folders added."""
    added = []
    for package in list(package_manifests(top)):
        try:
            optional = json.loads((package / "package.json").read_text()).get("optionalDependencies") or {}
        except (ValueError, OSError):
            continue
        for name, spec in sorted(optional.items()):
            if resolvable(package, name, top):
                continue
            meta = registry_manifest(name, spec)
            if not meta or not linux_glibc(meta):
                continue
            target = top / "node_modules" / name
            if target.exists():
                target = package / "node_modules" / name
            if target.exists():
                continue
            download(meta["dist"], target)
            added.append(str(target.relative_to(top)))
            with open(log_path, "a") as out:
                out.write(f"linux package {name}@{meta['version']} -> {target.relative_to(top)}\n")
    return added


def download(dist, target):
    with tempfile.TemporaryDirectory() as folder:
        tarball = Path(folder) / "package.tgz"
        body = http_get(dist["tarball"])
        if body is None:
            raise ValueError(f"could not download {dist['tarball']}")
        tarball.write_bytes(body)
        algorithm, _, digest = (dist.get("integrity") or "").partition("-")
        if algorithm in ("sha512", "sha256", "sha1"):
            actual = base64.b64encode(hashlib.new(algorithm, tarball.read_bytes()).digest()).decode()
        else:
            algorithm, digest, actual = "sha1", dist.get("shasum"), hashlib.sha1(tarball.read_bytes()).hexdigest()
        if actual != digest:
            raise ValueError(f"{dist['tarball']} does not have the registry's {algorithm}")
        target.mkdir(parents=True)
        subprocess.run(["tar", "-xzf", str(tarball), "-C", str(target), "--strip-components=1"], check=True)


def survey(root, entry, script):
    result = load_result(root, entry["id"])
    out = root / "results" / entry["id"] / "survey.json"
    proc = subprocess.run([sys.executable, str(script), "--json", str(out), str(checkout(root, entry))],
                          capture_output=True, text=True)
    if proc.returncode != 0 or not out.exists():
        result["survey"] = {"error": (proc.stderr or proc.stdout)[-300:]}
    else:
        data = json.loads(out.read_text())
        result["survey"] = {"scripts": sum(data["scripts"].values()),
                            "patterns": {name: sum(p["apps"].values()) for name, p in data["patterns"].items()}}
    save_result(root, result)


# The Linux steps (in the container).

def linux_environment(root, slot):
    return {"PATH": f"{root}/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME": "/root",
            "LANG": "C.UTF-8", "TMPDIR": "/tmp", "DEVELOPER_DIR": str(DEVELOPER_DIR), "NOMAC_DEVELOPER_DIR": str(DEVELOPER_DIR),
            "NOMAC_HOME": str(WORK / f"nomac-home-{slot}"),
            "CI": "1", "EXPO_NO_TELEMETRY": "1"}


def container_of(app):
    ios = app / "ios"
    workspaces = sorted(p for p in ios.glob("*.xcworkspace"))
    projects = sorted(p for p in ios.glob("*.xcodeproj") if p.name != "Pods.xcodeproj")
    named = [w for w in workspaces if w.with_suffix(".xcodeproj").exists()]
    return (named or workspaces or projects or [None])[0]


def scheme_of(container):
    """The shared scheme named like the container, else the first one that builds an app."""
    folders = [container / "xcshareddata/xcschemes"]
    if container.suffix == ".xcworkspace":
        folders += [p / "xcshareddata/xcschemes" for p in container.parent.glob("*.xcodeproj") if p.name != "Pods.xcodeproj"]
    schemes = sorted(s for folder in folders if folder.is_dir() for s in folder.glob("*.xcscheme"))
    for scheme in schemes:
        if scheme.stem == container.stem:
            return scheme.stem
    for scheme in schemes:
        if re.search(r'BuildableName\s*=\s*"[^"]+\.app"', scheme.read_text(errors="replace")):
            return scheme.stem
    return container.stem


def linux(root, entry, slot, separate_build=False):
    """The Linux steps of one app, in the container; `slot` names its own NOMAC_HOME, as up to
    --builders builds run at once. The build is `nomac archive`, a Release build with the install
    steps after it (`nomac build`, then `nomac archive` from a new build folder, with
    separate_build: twice the time, and every archive passed whose build did: 11 of 11)."""
    result = load_result(root, entry["id"])
    out = root / "results" / entry["id"]
    top, app = checkout(root, entry), app_folder(root, entry)
    env = linux_environment(root, slot)
    container = container_of(app)
    if container is None:
        step(result, "check", False, time.time(), **{"class": "no Xcode project in ios/"})
        return save_result(root, result)
    scheme = entry.get("scheme") or scheme_of(container)
    result.update(container=str(container.relative_to(top)), scheme=scheme)

    started = time.time()
    check = subprocess.run([NOMAC, "check", container, "--json"], cwd=app, env=env, capture_output=True, text=True)
    (out / "check.json").write_text(check.stdout)
    try:
        report = json.loads(check.stdout)
    except ValueError:
        step(result, "check", False, started, **{"class": f"nomac check exited with {check.returncode}",
                                                 "error": check.stderr[-400:]})
        return save_result(root, result)
    outside = [f for f in report["features"] if f["status"] != "verified"]
    step(result, "check", True, started, outside=len(outside), unchecked=len(report.get("unchecked", [])),
         features={f["id"]: f["count"] for f in outside},
         requirements={f["id"]: [u["object"] for u in f.get("uses", [])][:20] for f in outside if f["id"].startswith("build:")})

    started = time.time()
    overrides, applied, unfixed = project_fixes(app, top, container, report)
    step(result, "fixes", True, started, applied=applied, overrides=overrides, unfixed=unfixed)
    save_result(root, result)

    scratch = WORK / "dd" / entry["id"]
    common = ["-workspace" if container.suffix == ".xcworkspace" else "-project", container, "-scheme", scheme,
              "-configuration", "Release", "-destination", "generic/platform=iOS", "-derivedDataPath", scratch / "DerivedData"]
    settings = [f"{key}={value}" for key, value in sorted(overrides.items())]
    archive = scratch / f"{scheme}.xcarchive"
    keep_going = ["-IDEBuildingContinueBuildingAfterErrors", "YES"]
    try:
        if separate_build:
            if not guarded_step(result, "build", [NOMAC, "build", *common, *keep_going, "CODE_SIGNING_ALLOWED=NO", *settings],
                                app, env, out / "build.log"):
                return
            shutil.rmtree(scratch, ignore_errors=True)
            if not guarded_step(result, "archive", [NOMAC, "archive", *common, "-archivePath", archive, *capture.ADHOC, *settings],
                                app, env, out / "archive.log"):
                return
        else:
            if not guarded_step(result, "build", [NOMAC, "archive", *common, "-archivePath", archive, *keep_going,
                                                   *capture.ADHOC, *settings], app, env, out / "build.log"):
                return
            step(result, "archive", True, time.time(), note="the build's archive (nomac archive)")
        shutil.rmtree(scratch / "DerivedData", ignore_errors=True)
        options = scratch / "ExportOptions.plist"
        options.write_text(capture.EXPORT_OPTIONS)
        guarded_step(result, "export", [NOMAC, "export", "-archivePath", archive, "-exportPath", scratch / "export",
                                        "-exportOptionsPlist", options], scratch, env, out / "export.log",
                     produced=lambda: sorted((scratch / "export").glob("*.ipa")))
    finally:
        save_result(root, result)
        shutil.rmtree(scratch, ignore_errors=True)
        shutil.rmtree(env["NOMAC_HOME"], ignore_errors=True)
        for name in ("build", "archive", "export"):
            if (out / f"{name}.log").exists():
                subprocess.run(["gzip", "-f", str(out / f"{name}.log")])


def reclassify(root, names):
    """Reads the kept logs again, after a change to classify or missing_commands."""
    for entry in entries(names):
        result = load_result(root, entry["id"])
        for name in ("build", "archive", "export"):
            s = result["steps"].get(name)
            log_path = root / "results" / entry["id"] / f"{name}.log"
            if not s or not (log_path.exists() or Path(f"{log_path}.gz").exists()):
                continue
            s["missingCommands"] = missing_commands(log_path)
            failures = [] if s["ok"] else ([{"class": KILLED, "detail": "nomac exited on SIGKILL", "task": "nomac"}]
                                           if s.get("exit") == -9 else classify(log_path))
            if failures:
                s.update(failures[0], failures=failures[:30], resource=any(f["class"] == KILLED for f in failures))
        if result["steps"]:
            save_result(root, result)


def guarded_step(result, name, argv, cwd, env, log_path, produced=None):
    if not wait_for_space(lambda: free_bytes(WORK), "in the volume"):
        return step(result, name, False, time.time(), **{"class": f"not run: less than {MIN_FREE >> 30} GB free in the volume"})
    started = time.time()
    status = run(argv, cwd, env, log_path, timeout=4 * 3600)
    outputs = produced() if produced else []
    ok = status == 0 and (produced is None or bool(outputs))
    details = {"exit": status, "missingCommands": missing_commands(log_path)}
    if outputs:
        details["ipaBytes"] = outputs[0].stat().st_size
    if not ok:
        failures = classify(log_path) if status != -9 else [{"class": KILLED, "detail": "nomac exited on SIGKILL", "task": "nomac"}]
        details.update(failures[0] if failures else {"class": f"exit {status}", "error": tail_error(log_path)})
        details["failures"] = failures[:30]
        details["resource"] = any(f["class"] == KILLED for f in failures)
    return step(result, name, ok, started, **details)


def missing_commands(log_path):
    """The commands scripts called that the build machine lacks, with the number of calls: a
    script that goes on after `command not found` builds something else than on a Mac."""
    found = {}
    for line in read_log(log_path):
        if m := re.search(r"(?:^|[\s:/])([\w.+-]+): (?:command )?not found\s*$", line):
            found[m.group(1)] = found.get(m.group(1), 0) + 1
    return found


def project_fixes(app, top, container, report):
    """The project's changes for Linux: returns the settings to override, the changes made and the
    requirements left without a fix."""
    applied, unfixed, overrides = [], [], {}
    path, test, linux_test = expo.AUTOLINKING_SCAN
    for folder in node_module_owners(app, top):
        file = folder / path
        if file.exists():
            text = file.read_text()
            if test in text:
                file.write_text(text.replace(test, linux_test))
                applied.append(str(file.relative_to(top)))
            break
    base = container.parent
    for feature in report["features"]:
        if feature["status"] == "verified":
            continue
        if feature["id"] == "build:setting=mach-o-executable":
            for use in feature.get("uses", []):
                setting, _, rest = use["object"].partition(" = ")
                value, _, linux_note = rest.partition("; Linux build: ")
                tool = linux_build(value.strip().strip("\"'"), linux_note, base, top)
                if tool and overrides.get(setting, tool) == tool:
                    overrides[setting] = tool
                elif not tool:
                    unfixed.append(use["object"][:200])
        elif feature["id"] == "build:node-module=mach-o-only":
            unfixed += [use["object"][:200] for use in feature.get("uses", [])]
    if overrides:
        applied.append("settings on the command line: " + ", ".join(sorted(overrides)))
    return overrides, applied, sorted(set(unfixed))


ELF_MACHINES = {183: "aarch64", 62: "x86_64"}


def linux_build(value, linux_note, base, top):
    """The Linux build of the Mach-O tool a setting names: the one `nomac check` lists, else the
    ELF executable of the same name nearest to it in the checkout (a package that ships its tool
    for several systems: hermes-compiler's linux64-bin/hermesc beside osx-bin/hermesc). A value
    that is more than one path (flags) is left to the project."""
    if linux_note:
        candidate = (base / linux_note.split(", ")[0]).resolve()
        return str(candidate) if candidate.exists() else None
    if not value or " " in value:
        return None
    name = Path(value).name
    written = Path(re.sub(r"\$[({](PODS_ROOT)[)}]", str(base / "Pods"), re.sub(r"\$[({](SRCROOT|PROJECT_DIR)[)}]", str(base), value)))
    written = written if written.is_absolute() else base / written
    candidates = []
    for folder, dirs, files in os.walk(top):
        dirs[:] = [d for d in dirs if d not in SKIPPED]
        if name in files:
            path = Path(folder) / name
            machine = elf_machine(path)
            if machine is not None:
                common = len(os.path.commonpath([os.path.normpath(written), str(path)]).split(os.sep))
                candidates.append((common, machine == os.uname().machine, str(path)))
    return max(candidates)[2] if candidates else None


def elf_machine(path):
    try:
        with open(path, "rb") as file:
            header = file.read(20)
    except OSError:
        return None
    if header[:4] != b"\x7fELF" or not os.access(path, os.X_OK):
        return None
    return ELF_MACHINES.get(int.from_bytes(header[18:20], "little"), "other")


# Classification of a failed step's log.

DIAGNOSTIC = re.compile(r"(^|: )(fatal )?error: ")
KILLED = "killed: the build machine ran out of memory (a process ended on SIGKILL without its diagnostics)"
GENERIC = re.compile(r"(?i)linker command failed with exit code|failed with a nonzero exit code")


def without_paths(message):
    return re.sub(r"\s+", " ", re.sub(r"(?<![\w.<>])(?:\.{0,2}/[^\s'\"`:,()]+)+", "<path>", message)).strip()


def normalize(message):
    return re.sub(r"\b0x[0-9a-fA-F]+\b|(?<!B-)\b\d+(\.\d+)*\b", "<n>", without_paths(message))[:160]


def template(message):
    return re.sub(r"'[^']*'|\"[^\"]*\"|`[^`]*`", "<q>", message)


def task_blocks(lines):
    """xcodebuild's log as {task line: output lines}: a task line is a word at column 0 followed by
    its indented command lines; the tool's output, blank lines included, runs to the next task."""
    blocks, current = {}, None
    for index, line in enumerate(lines):
        if re.match(r"[A-Z][A-Za-z0-9]+ \S", line) and index + 1 < len(lines) and lines[index + 1].startswith("    "):
            current = blocks.setdefault(line.strip(), [])
        elif current is not None and line.strip() and not line.startswith("    "):
            current.append(line)
    return blocks


def read_log(log_path):
    path = Path(log_path)
    if not path.exists() and Path(f"{log_path}.gz").exists():
        path = Path(f"{log_path}.gz")
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", errors="replace") as file:
        return file.read().splitlines()


def classify(log_path):
    """The failures of a build, archive or export log, the first first: for each failed task its
    class (coarse, for ranking), a detail (the message with paths and numbers removed) and the
    task kind. A task whose own output has no error takes the errors elsewhere in the log that
    name its input (actool's messages print under the catalog's other task)."""
    lines = read_log(log_path)
    failed = []
    if "The following build commands failed:" in lines:
        start = lines.index("The following build commands failed:") + 1
        failed = [line.strip() for line in lines[start:] if line.startswith("\t") and not re.match(r"\t\(\d+ failures?\)", line)
                  and not line.startswith("\tBuilding ")]
    crash = next((index for index, line in enumerate(lines) if line.startswith("*** Program crashed")), None)
    if crash is not None:
        cause = next((line for line in reversed(lines[:crash]) if re.search(r"Assertion|Fatal error|fatal error|precondition", line)), lines[crash])
        frame = next((re.sub(r"^\s*\d+ (\[ra\] )?0x[0-9a-f]+ ", "", line).split(" + ")[0] for line in lines[crash:crash + 40]
                      if " in nomac" in line and "ErrorOr" not in line and "assert" not in line), "")
        function = re.sub(r"\(anonymous namespace\)::|\(.*", "", frame)
        message = re.search(r"(Assertion .*|Fatal error.*|fatal error.*|precondition.*)", cause)
        return [{"class": f"nomac crashed in {function or 'nomac'}: {normalize(message.group(1) if message else cause)[:110]}",
                 "detail": frame[:160], "task": "nomac"}]
    blocks = task_blocks(lines)
    diagnostics = [index for index, line in enumerate(lines) if DIAGNOSTIC.search(line)]
    headers = {line.strip(): index for index, line in enumerate(lines) if line and not line[0].isspace()}
    used, failures = set(), []
    killed = {m.group(1) for line in lines
              if (m := re.search(r"/([^/]+)\.build/Objects-normal/[^/]+/[^/]+\.dia: warning: Could not read serialized diagnostics", line))}
    for task in failed:
        if re.fullmatch(r"[A-Za-z0-9+/=]{40,}", task):
            continue
        if m := re.fullmatch(r"Run custom shell script '(.+)'", task):
            task = next((header for header in blocks if header.startswith("SchemeAction " + m.group(1).replace(" ", "\\ "))), task)
        output = blocks.get(task) or next((out for header, out in blocks.items() if header.startswith(task[:60])), [])
        evidence = [[line for line in output if DIAGNOSTIC.search(line)]]
        if not evidence[0]:
            inputs = [path.replace("\\ ", " ") for path in re.findall(r"(/(?:[^\s\\]|\\ )+)", task)
                      if "/DerivedData/" not in path and len(path) > 12]
            chosen = [i for i in diagnostics if i not in used and any(path in lines[i] for path in inputs)][:5]
            if not chosen and (target := re.search(r"\(in target '([^']+)'", task)):
                chosen = [i for i in diagnostics if i not in used and f": {target.group(1)}: " in lines[i]][:5]
            header = headers.get(task, next((i for h, i in headers.items() if h.startswith(task[:60])), None))
            above = []
            if header is not None and task.startswith(("PhaseScriptExecution", "SchemeAction")):
                start = header
                while start > 0 and lines[start - 1].strip() and header - start < 200:
                    start -= 1
                above = lines[start:header]
                chosen = chosen or [i for i in diagnostics if start <= i < header]
            if not chosen and header is not None:
                chosen = [i for i in diagnostics if header - 3000 < i < header and i not in used][-5:][::-1]
            used.update(chosen)
            evidence = [[lines[i] for i in chosen], above]
        target = re.search(r"\(in target '([^']+)'", task)
        if target and target.group(1) in killed and not any(evidence):
            failures.append({"class": KILLED, "detail": f"{target.group(1)}'s compiler wrote no diagnostics", "task": task.split(" ", 1)[0]})
            continue
        failures.append(classify_task(task, output, evidence))
    if not failures:
        if diagnostics:
            failures.append(classify_task("nomac", [lines[i] for i in diagnostics[:5]]))
        elif lines:
            failures.append({"class": "no error message", "detail": normalize(" | ".join(lines[-3:])), "task": "nomac"})
    return failures


def classify_task(task, output, evidence=()):
    """A failed task's class from its evidence, nearest first (the errors attributed to it, the
    script output printed just above its header), then its whole output."""
    kind = task.split(" ", 1)[0]
    lines = [line for group in evidence for line in group] + output
    errors = ([line for line in lines if DIAGNOSTIC.search(line) and not GENERIC.search(line)]
              or [line for line in lines if DIAGNOSTIC.search(line)]
              or [line for line in lines if re.search(r"\b(error|Error|ERROR|ERR!)\b", line) and not GENERIC.search(line)]
              or [line for line in lines if not GENERIC.search(line)][-3:] or [task])
    detail = normalize(errors[0][errors[0].find("error:") + 6:] if "error:" in errors[0] else errors[0])
    for searched in [*("\n".join(group) for group in evidence if group), "\n".join(output)]:
        if cls := known_class(searched):
            return {"class": cls, "detail": detail, "task": kind}
    kinds = [("compile error", r"Compile(C|Swift|SwiftSources)?$|SwiftCompile|SwiftEmitModule|SwiftDriver|ProcessPCH|"
                               r"SwiftExplicitDependency\w*|ScanDependencies|PrecompileModule"),
             ("link error", r"Ld|Libtool|CreateUniversalBinary|GenerateDSYMFile"),
             ("storyboard or xib", r"CompileStoryboard|CompileXIB|LinkStoryboards"),
             ("asset catalog", r"CompileAssetCatalog\w*|GenerateAssetSymbols"),
             ("signing", r"CodeSign|ProcessProductPackaging\w*|Validate\w*"),
             ("script phase", r"PhaseScriptExecution"), ("scheme action script", r"SchemeAction")]
    label = next((label for label, pattern in kinds if re.fullmatch(pattern, kind)), kind)
    return {"class": f"{label}: {template(detail)[:100]}", "detail": detail, "task": kind}


def known_class(text):
    """The class of a failure whose messages show a known cause, else None. The attributed
    error lines are tried before the task's whole output, which holds other tasks' lines too."""
    if m := re.search(r"(\S+): cannot execute binary file|exec format error|Exec format error", text):
        return "prebuilt Mach-O tool" + (f" ({Path(m.group(1)).name})" if m.group(1) else "")
    if re.search(r"Could not read serialized diagnostics file", text) and not re.search(r"(^|: )error: ", text, re.M):
        return KILLED
    if m := re.search(r"unable to spawn process '([^']+)'", text):
        return f"nomac's developer directory lacks a tool ({m.group(1)})"
    if m := re.search(r"env: [‘'`]?([\w.+-]+)[’'`]?: No such file or directory", text):
        return f"script interpreter not installed on the build machine ({m.group(1)})"
    if m := re.search(r"(?:^|[\s:/])([\w.+-]+): (?:command )?not found", text, re.M):
        name = m.group(1)
        return f"script needs macOS command {name}" if name in MACOS_COMMANDS else f"script command not found: {name}"
    if m := re.search(BSD_TOOLS + r": (?:invalid|illegal|unrecognized|unknown) option|" + BSD_TOOLS + r": -[eE] expression|"
                      r"\bsed: can't read", text):
        return f"script uses a BSD flag of {m.group(1) or m.group(2) or 'sed'}"
    if m := re.search(r"(\S+) - error: unrecognized subcommand '([^']+)'|(\S+): error: unrecognized subcommand '([^']+)'", text):
        return f"a tool's Linux build lacks a subcommand ({m.group(1) or m.group(3)} {m.group(2) or m.group(4)})"
    if re.search(r"invalid ELF header|not a valid ELF|slice is not valid mach-o|wrong ELF class|mach-o file", text, re.I):
        return "native Node module or tool built for macOS"
    if m := re.search(r"Cannot find module '([^']+)'", text):
        return f"Node module missing ({m.group(1)})"
    if re.search(r"(?i)auth(entication)? token is required|not logged in|please run `?\S+ login", text):
        return "app: a script uploads to a service and needs credentials (fails with Xcode too)"
    if re.search(r"Unable to resolve module \S+ from", text):
        return "app: a module the JavaScript imports is not installed (Metro; fails with Xcode too)"
    if m := re.search(r"error: ([^\n]*(?:nomac does not|not supported yet|\(BACKLOG B-\d+\))[^\n]*)", text):
        return f"nomac refuses: {template(without_paths(m.group(1)))[:140]}"
    if re.search(r"/\.env[\w.]*: No such file or directory", text):
        return "app: the build reads a .env file the repository leaves out (secrets the README has you add)"
    if m := re.search(r"Can't find the '(/[^']+)' binary", text):
        return f"app: a script names a tool at a fixed path of its author's machine ({m.group(1)})"
    if re.search(r"clang frontend command failed with exit code (139|134|-?11)|PLEASE submit a bug report", text):
        return "clang crashed"
    if re.search(r"one of -create, -thin <arch_type>", text):
        return "lipo refuses a command without an operation (Swift Build's CopyAndPreserveArchs)"
    if m := re.search(r"lld: error: ([^\n]+)", text):
        return f"lld: {template(normalize(m.group(1)))[:100]}"
    if re.search(r"external macro implementation|macro plugin|-load-plugin", text):
        return "Swift macro plugin"
    return None


# Mac driver.

def docker(*argv, **kwargs):
    return subprocess.run(["docker", *argv], **kwargs)


def container_command(root, args):
    """The container for the Linux steps: the volume at /work, its apps folder and Linux Node at the
    Mac's paths, its SwiftPM cache (swift-syntax's repository for macro plugins built from their
    packages, copied from the Mac's cache: the container has no network), the results folder and
    this repository's scripts shared with the Mac."""
    (root / "results").mkdir(parents=True, exist_ok=True)
    repository = SCRIPTS.parents[1]
    argv = ["run", "-d", "--name", args.container, "--network", "none", "-v", f"{args.volume}:/work",
            "--mount", f"type=volume,src={args.volume},dst={root}/apps,volume-subpath=apps",
            "--mount", f"type=volume,src={args.volume},dst={root}/node,volume-subpath=node-linux,readonly",
            "--mount", f"type=volume,src={args.volume},dst=/root/.cache/org.swift.swiftpm,volume-subpath=swiftpm",
            "-v", f"{root}/results:{root}/results", "-v", f"{repository}:{repository}:ro", IMAGE, "sleep", "infinity"]
    docker("rm", "-f", args.container, capture_output=True)
    docker(*argv, check=True, stdout=subprocess.DEVNULL)
    log(f"container {args.container} started")


def volume_free(container):
    proc = docker("exec", container, "df", "-B1", "--output=avail", "/work", capture_output=True, text=True)
    return int(proc.stdout.split()[-1]) if proc.returncode == 0 else 0


def mac_steps(root, entry, args, env):
    purge_kept(root, args)
    install(root, entry, env)
    survey(root, entry, args.survey)


def linux_steps(root, entry, args, slot):
    """Copies the installed app into the container at its Mac path, runs the Linux steps there and
    deletes both copies."""
    app_id, top = entry["id"], checkout(root, entry)
    if load_result(root, app_id)["steps"].get("install", {}).get("ok"):
        if not (wait_for_space(lambda: free_bytes(root), "on the Mac", MIN_FREE_MAC_BUILD)
                and wait_for_space(lambda: volume_free(args.container), "in Docker", MIN_FREE)):
            sys.exit("error: not enough free space on the Mac or in Docker for 6 hours")
        log(f"{app_id}: copying into {args.container}")
        docker("exec", args.container, "rm", "-rf", str(top), check=True)
        tar = subprocess.Popen(["tar", "--no-xattrs", "--no-mac-metadata", "-C", str(top.parent), "-cf", "-", top.name],
                               stdout=subprocess.PIPE)
        docker("exec", "-i", args.container, "tar", "-xf", "-", "-C", str(top.parent), stdin=tar.stdout, check=True)
        tar.wait()
        if not args.keep:
            shutil.rmtree(top, ignore_errors=True)
        with open(root / "results" / app_id / "linux.log", "ab") as out:
            docker("exec", args.container, "python3", str(Path(__file__).resolve()), "linux", "--root", str(root),
                   "--slot", str(slot), *(["--separate-build"] if args.separate_build else []), app_id,
                   stdout=out, stderr=subprocess.STDOUT)
    elif not args.keep:
        shutil.rmtree(top, ignore_errors=True)
    result = load_result(root, app_id)
    result["finished"] = True
    first = next((s for s in STEPS if s in result["steps"] and not result["steps"][s]["ok"]), None)
    if first and first != "install" and args.keep_failed > 0:
        result["kept"] = {"path": str(top), "container": args.container, "since": time.time()}
    else:
        result.pop("kept", None)
        docker("exec", args.container, "rm", "-rf", str(top))
    save_result(root, result)
    log(f"{app_id}: " + (f"stopped at {first}: {result['steps'][first].get('class') or result['steps'][first].get('error', '')[:120]}"
                         if first else "every step passed"))


def purge_kept(root, args):
    """Deletes the checkouts kept in the container for a look at their failure: those kept more
    than --keep-failed hours, then the oldest while Docker's volume has less than 20 GB above its
    minimum."""
    kept = sorted((r["kept"]["since"], r["id"]) for path in (root / "results").glob("*.json")
                  if "kept" in (r := json.loads(path.read_text())))
    for since, app_id in kept:
        if time.time() - since > args.keep_failed * 3600 or volume_free(args.container) < MIN_FREE + (20 << 30):
            result = load_result(root, app_id)
            docker("exec", result["kept"].get("container", args.container), "rm", "-rf", result["kept"]["path"])
            result.pop("kept")
            save_result(root, result)


def run_all(root, apps, args, env):
    """Every step of each app, in the manifest's order: up to `--installers` apps install on the Mac
    (installs wait on the network; one `pod install` at a time, CocoaPods' cache being shared) while
    up to `--builders` build on Linux, each in a slot of its own. At most installers + builders
    apps are installed and not yet built, which bounds the Mac's disk."""
    if args.resume:
        apps = [entry for entry in apps if not (result := load_result(root, entry["id"])).get("finished")
                or result["steps"].get("install", {}).get("network")
                or any(s.get("resource") for s in result["steps"].values())]
    slots = queue.Queue()
    for slot in range(args.builders):
        slots.put(slot)

    def build(entry, installing):
        installing.result()
        slot = slots.get()
        try:
            linux_steps(root, entry, args, slot)
        finally:
            slots.put(slot)

    with (concurrent.futures.ThreadPoolExecutor(args.installers) as mac,
          concurrent.futures.ThreadPoolExecutor(args.builders) as linux_pool):
        builds = []
        for entry in apps:
            while sum(not b.done() for b in builds) >= args.installers + args.builders:
                concurrent.futures.wait([b for b in builds if not b.done()], return_when=concurrent.futures.FIRST_COMPLETED)
            builds.append(linux_pool.submit(build, entry, mac.submit(mac_steps, root, entry, args, env)))
        for done in builds:
            done.result()


# Report.

def report(root, names):
    results = [load_result(root, e["id"]) for e in entries(names) if results_path(root, e["id"]).exists()]
    rows = ["| step | apps that reached it | passed | pass rate |", "|---|---|---|---|"]
    for name in STEPS:
        reached = [r for r in results if name in r["steps"]]
        passed = [r for r in reached if r["steps"][name]["ok"]]
        rows.append(f"| {name} | {len(reached)} | {len(passed)} | {100 * len(passed) // max(len(reached), 1)}% |")
    built = sum(1 for r in results if r["steps"].get("build", {}).get("ok"))
    exported = sum(1 for r in results if r["steps"].get("export", {}).get("ok"))
    rows += ["", f"{len(results)} apps: {built} build on Linux ({100 * built // max(len(results), 1)}%), {exported} export an IPA.", "",
             "| app | kind | React Native | Expo | install | check: outside | fixes | build | archive | export | first failure |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    first_classes, any_classes = {}, {}
    for r in results:
        steps, versions = r["steps"], r.get("versions", {})
        first = next((s for s in STEPS if s in steps and not steps[s]["ok"]), None)
        cells = []
        for name in STEPS:
            s = steps.get(name)
            cells.append("" if s is None else ("pass" if s["ok"] else "**fail**") + (f" ({s['outside']})" if name == "check" and s["ok"] else ""))
        failure = ""
        if first:
            s = steps[first]
            failure = f"{first}: {s['class']}" if s.get("class") else f"{first} ({s.get('stage')}): {s.get('error', '')[:80]}"
            key = (first, s.get("class") or f"{first} ({s.get('stage')})")
            first_classes.setdefault(key, []).append(r["id"])
            classes = {f["class"] for f in s.get("failures", [])}
            for cls in classes:
                any_classes.setdefault((first, cls), [set(), set()])[0].add(r["id"])
                if len(classes) == 1:
                    any_classes[(first, cls)][1].add(r["id"])
        rows.append(f"| {r['id']} | {r.get('kind', '')} | {versions.get('react-native') or ''} | {versions.get('expo') or ''} | "
                    + " | ".join(cells) + f" | {failure.replace('|', '/')} |")
    kept = [r["id"] for r in results if "kept" in r]
    if kept:
        rows += ["", "Checkouts kept in the container for a look at their failure (`<root>/apps/<app>`, at its Mac path): "
                 + ", ".join(kept) + "."]
    rows += ["", "| failure class (first failure) | step | apps blocked | apps |", "|---|---|---|---|"]
    for (name, cls), apps in sorted(first_classes.items(), key=lambda item: -len(item[1])):
        rows.append(f"| {cls.replace('|', '/')} | {name} | {len(apps)} | {', '.join(apps)} |")
    rows += ["", "| failed task class (every failure of the failed step) | step | apps | apps where it is the only one |",
             "|---|---|---|---|"]
    for (name, cls), (apps, only) in sorted(any_classes.items(), key=lambda item: (-len(item[1][0]), -len(item[1][1])))[:40]:
        rows.append(f"| {cls.replace('|', '/')} | {name} | {len(apps)} | {len(only)} |")
    patterns, scripts = {}, 0
    for r in results:
        scripts += r.get("survey", {}).get("scripts", 0)
        for name, count in r.get("survey", {}).get("patterns", {}).items():
            patterns.setdefault(name, [0, 0])
            patterns[name][0] += 1
            patterns[name][1] += count
    rows += ["", f"Script phases: {scripts} scripts (phases and the scripts they call) in {len(results)} apps.", "",
             "| script pattern | apps | occurrences |", "|---|---|---|"]
    for name, (apps, count) in sorted(patterns.items(), key=lambda item: (-item[1][0], -item[1][1])):
        rows.append(f"| {name.replace('|', '/')} | {apps} | {count} |")
    features = {}
    for r in results:
        for feature in r["steps"].get("check", {}).get("features", {}):
            features.setdefault(feature, []).append(r["id"])
    missing = {}
    for r in results:
        for name in ("build", "archive"):
            for command, count in r["steps"].get(name, {}).get("missingCommands", {}).items():
                missing.setdefault(command, [set(), 0])
                missing[command][0].add(r["id"])
                missing[command][1] += count
    rows += ["", "| command not found on Linux during build or archive (fatal or not) | apps | calls |", "|---|---|---|"]
    for command, (apps, count) in sorted(missing.items(), key=lambda item: -len(item[1][0])):
        rows.append(f"| {command} | {len(apps)} | {count} |")
    rows += ["", "| nomac check: feature outside the envelope | apps |", "|---|---|"]
    for feature, apps in sorted(features.items(), key=lambda item: -len(item[1]))[:30]:
        rows.append(f"| {feature} | {len(apps)} |")
    print("\n".join(rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["container", "run", "prepare", "install", "survey", "linux", "report", "reclassify"])
    parser.add_argument("apps", nargs="*")
    parser.add_argument("--root", type=Path, default=Path.home() / "nomac-out" / "sweep")
    parser.add_argument("--volume", default=VOLUME)
    parser.add_argument("--container", default=CONTAINER)
    parser.add_argument("--survey", type=Path, default=SCRIPTS / "script_phase_survey.py",
                        help="script_phase_survey.py (default: beside this script)")
    parser.add_argument("--keep", action="store_true", help="run: keep the Mac's copy of each app")
    parser.add_argument("--resume", action="store_true", help="run: leave out the apps whose run finished")
    parser.add_argument("--installers", type=int, default=3, help="run: apps installing on the Mac at once")
    parser.add_argument("--builders", type=int, default=1, help="run: apps building on Linux at once")
    parser.add_argument("--slot", type=int, default=0, help="linux: the build's slot (its NOMAC_HOME)")
    parser.add_argument("--separate-build", action="store_true", help="run, linux: nomac build, then nomac archive anew")
    parser.add_argument("--keep-failed", type=float, default=6, metavar="HOURS",
                        help="run: keep the container's checkout of an app that fails after its install for HOURS (0: none)")
    args = parser.parse_intermixed_args()
    root = args.root.resolve() if args.command != "linux" else args.root
    if args.command == "container":
        return container_command(root, args)
    if args.command == "report":
        return report(root, args.apps)
    if args.command == "reclassify":
        return reclassify(root, args.apps)
    if args.command == "linux":
        for entry in entries(args.apps):
            linux(root, entry, args.slot, args.separate_build)
        return
    env = mac_environment(root)
    if args.command == "run":
        return run_all(root, entries(args.apps), args, env)
    for entry in entries(args.apps):
        if args.command == "prepare":
            mac_steps(root, entry, args, env)
            if not args.keep:
                shutil.rmtree(checkout(root, entry), ignore_errors=True)
        elif args.command == "install":
            install(root, entry, env)
        elif args.command == "survey":
            survey(root, entry, args.survey)


if __name__ == "__main__":
    sys.exit(main())

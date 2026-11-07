#!/usr/bin/env python3
"""How many open-source iOS projects nomac really builds, measured by building them.

The coverage survey (feature_survey.py) only reads projects. This takes a seeded sample of what the
survey read and runs each project end to end on Linux, one project after another in one container,
unchanged. A step cut by the network runs again; if it never finishes, the project is not measured
and counts nowhere. Steps:

  clone     the commit the survey read, shallow, with its submodules
  deps      the commands the project's README gives (corpus/wild-sample.json), else the ones its
            files imply: `pod install`, the JavaScript package manager of its lockfile
  check     `nomac check --json` on the resolved checkout (not a step that fails)
  archive   `nomac archive` Release for generic/platform=iOS, ad-hoc signed (capture_reference.py's ADHOC)
  export    `nomac export` with capture_reference.py's `debugging` options

The checkout and its derived data are deleted after each project; the logs stay under --root,
outside the repository. Only project names, commits, classes and counts reach corpus/.

Two frames, from the survey's `contents` records:

  clear     nothing outside the envelope in a domain that may stop a build (not loader, not signing:
            what `nomac check` reports under "May stop a build"), which needs the next frame too
  accepted  no `build:setting=deployment-target-below-minimum`: Xcode 27.0 accepts the deployment
            target as it is, whatever else the survey says

Projects are ordered by SHA-256 of "<seed>:<owner/name>" and each frame takes its first --count, so
each is a simple random sample of its frame and a project in both is built once.

A failure gets one of three verdicts:

  nomac     nomac refuses or breaks something Xcode 27.0 does: a nomac refusal, a tool or platform
            gap, or a failure that Xcode 27.0 does not have on the same checkout (the `xcode` command)
  project   the project needs something missing, such as secrets or a generated file, or Xcode 27.0
            fails the same way on the same checkout
  unknown   neither shown: nothing here says whether Xcode would fail too

Usage:
  wild_sample.py pick --survey DIR [--seed N] [--count N]   write corpus/wild-sample.json's sample
  wild_sample.py run [--root R] [--jobs N] [project ...]    (Linux, in the container; leaves out what finished)
  wild_sample.py xcode [--root R] project ...               the same checkout under Xcode 27.0 (Mac)
  wild_sample.py triage [--root R] [--all] [--lines N]      each stopped project's first errors, for the verdicts
  wild_sample.py classes [--root R]                         nomac-fault classes, ranked by projects
  wild_sample.py report [--root R] [--write]                the tables; --write puts counts in corpus/
"""

import argparse
import collections
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[1]
sys.path[:0] = [str(HERE), str(REPOSITORY / "corpus" / "scripts")]
import capture_reference as capture  # noqa: E402
import feature_survey as survey  # noqa: E402

MANIFEST = REPOSITORY / "corpus" / "wild-sample.json"
RESULTS = REPOSITORY / "corpus" / "wild-sample-results.json"
DEFAULT_ROOT = Path(os.environ.get("WILD_ROOT", Path.home() / "nomac-out" / "wild-sample"))
SEED = 20261107
COUNT = 30
XCODE_REFUSES = "build:setting=deployment-target-below-minimum"
NOT_STOPPING_DOMAINS = {"loader", "signing"}
XCODE = "/Applications/Xcode_27.app/Contents/Developer"
SHARED_HOME = Path(os.environ.get("WILD_HOME", "/work/home"))
CLONE_TIMEOUT = 600
DEPS_TIMEOUT = 1800
BUILD_TIMEOUT = 3600
EXPORT_TIMEOUT = 600
JOBS_PER_BUILD = 6
MAC_MIN_FREE_GB = 30
MAC_STOP_FREE_GB = 15
VOLUME_MAX_GB = 14
NETWORK_ATTEMPTS = 4
NETWORK_WAIT = 180
ERROR = re.compile(r"(^|\s)(error|fatal error):\s|^\s*\*\* [A-Z ]+ FAILED \*\*|^\[!\] ", re.MULTILINE)
NETWORK = re.compile(r"Could not resolve host|Temporary failure|Empty reply from server|early EOF|RPC failed|TLS handshake|SSL_ERROR|SSL connection|"
                     r"gnutls_handshake|Connection (reset|refused|timed out)|Failed to connect|Operation timed out|ETIMEDOUT|ECONNRESET|EAI_AGAIN|"
                     r"Network is unreachable|The requested URL returned error: 5\d\d|HTTP/2 stream|Failed to open TCP connection|Net::OpenTimeout")
# Build scripts of projects nobody here reviewed run on the Mac only with these, and without the network once dependencies are resolved.
SECRETS = [".ssh", ".aws", ".gnupg", ".config", ".netrc", ".npmrc", ".gem/credentials", ".claude", ".t3", ".docker", ".kube", "Library/Keychains",
           "Library/Application Support/Claude", "Library/MobileDevice", "nomac-out/private"]

print_lock = threading.Lock()
running = set()
stopping = threading.Event()


def log(message):
    with print_lock:
        print(f"{datetime.datetime.now():%H:%M:%S} {message}", flush=True)


def identifier(repository):
    return repository.replace("/", "__")


def load_manifest():
    return json.loads(MANIFEST.read_text())


def wilson(successes, total):
    return survey.wilson(successes, total) if total else (0.0, 0.0)


# ---------------------------------------------------------------------------------------------
# The sample


def may_stop(record):
    return [feature for feature, status in record["features"].items()
            if status != "verified" and record["domains"].get(feature) not in NOT_STOPPING_DOMAINS]


def frames(records):
    checked = [record for record in records if record.get("status") == "checked"]
    accepted = [record for record in checked if XCODE_REFUSES not in record["features"]]
    clear = [record for record in checked if not may_stop(record)]
    return checked, clear, accepted


def rank(repository, seed):
    return hashlib.sha256(f"{seed}:{repository}".encode()).hexdigest()


def pick(arguments):
    folder = Path(arguments.survey) / "contents"
    records = [json.loads(path.read_text()) for path in sorted(folder.glob("*.json"))]
    checked, clear, accepted = frames(records)
    order = lambda record: rank(record["repository"], arguments.seed)
    chosen = {}
    for name, frame in (("clear", clear), ("accepted", accepted)):
        for record in sorted(frame, key=order)[:arguments.count]:
            chosen.setdefault(record["repository"], {"repository": record["repository"], "commit": record["commit"],
                                                      "container": record["container"], "frames": []})["frames"].append(name)
    previous = {entry["repository"]: entry for entry in load_manifest()["projects"]} if MANIFEST.exists() else {}
    projects = []
    for entry in sorted(chosen.values(), key=lambda entry: rank(entry["repository"], arguments.seed)):
        for key in ("dependencies", "chosenContainer", "scheme", "noApp"):
            if key in previous.get(entry["repository"], {}):
                entry[key] = previous[entry["repository"]][key]
        projects.append(entry)
    manifest = {"seed": arguments.seed, "count": arguments.count, "survey": "feature_survey.py contents of 2026-11-06",
                "projects_read": len(checked), "clear": len(clear), "accepted": len(accepted), "projects": projects}
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n")
    both = sum(len(entry["frames"]) == 2 for entry in projects)
    print(f"read {len(checked)}, clear {len(clear)}, accepted {len(accepted)}; sample {len(projects)} projects, {both} in both frames")


# ---------------------------------------------------------------------------------------------
# One project


def run_logged(command, cwd, env, log_path, timeout):
    """The command's output goes to log_path; the whole process group goes on a timeout."""
    with open(log_path, "a", errors="replace") as out:
        out.write(f"$ {' '.join(str(part) for part in command)}\n")
        out.flush()
        process = subprocess.Popen([str(part) for part in command], cwd=cwd, env=env, stdout=out, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        running.add(process)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            out.write(f"\nwild_sample: timed out after {timeout} s\n")
            return "timeout"
        finally:
            running.discard(process)


def mac_sandbox(offline):
    rules = "".join(f'(deny file-read* (subpath "{Path.home() / name}"))' for name in SECRETS)
    profile = "(version 1)(allow default)" + rules
    if offline:
        profile += capture.OFFLINE[2].removeprefix("(version 1)(allow default)")
    return ["sandbox-exec", "-p", profile]


def with_network_retries(result, name, log_path, attempt):
    """A step that fails on the network says nothing about the project: it runs again, and if the
    network never lets it finish the project is not measured (`notMeasured`), counted nowhere, and
    the next run takes it again. A clone that times out is the network too."""
    for tries in range(NETWORK_ATTEMPTS):
        start = Path(log_path).stat().st_size if Path(log_path).exists() else 0
        status = attempt()
        if status == 0:
            result.pop("networkFailure", None)
            result.pop("notMeasured", None)
            return status
        with open(log_path, errors="replace") as text:
            text.seek(start)
            cut = NETWORK.search(text.read()[-200000:])
        if name == "clone" and not cut and status == "timeout":
            reason = "clone timed out"
        elif cut:
            reason = cut.group(0)
        else:
            result.pop("notMeasured", None)
            return status
        result["networkRetries"] = result.get("networkRetries", 0) + 1
        result["networkFailure"] = reason
        result["notMeasured"] = f"{name}: {reason}"
        log(f"{result['id']}: {name} cut by the network ({reason}), try {tries + 1}")
        if tries + 1 < NETWORK_ATTEMPTS:
            time.sleep(NETWORK_WAIT)
    return status


def clone(entry, top, out, env):
    log_path = out / "clone.log"
    subprocess.run(["bash", "-c", f"chmod -R u+w {top} 2>/dev/null; rm -rf {top}"], check=False)
    url = f"https://github.com/{entry['repository']}.git"
    steps = [["git", "init", "-q", top],
             ["git", "-C", top, "remote", "add", "origin", url],
             ["git", "-C", top, "fetch", "-q", "--depth", "1", "origin", entry["commit"]],
             ["git", "-C", top, "-c", "advice.detachedHead=false", "checkout", "-q", "FETCH_HEAD"]]
    for command in steps:
        status = run_logged(command, None, env, log_path, CLONE_TIMEOUT)
        if status != 0:
            return status
    if (top / ".gitmodules").exists():
        status = run_logged(["git", "-C", top, "submodule", "update", "--init", "--recursive", "--depth", "1"], None, env, log_path, CLONE_TIMEOUT)
        if status != 0:
            return status
    return 0


def implied_dependencies(top):
    """What a project's files ask for when its README gives no command: the JavaScript packages,
    then CocoaPods beside the project the survey read."""
    commands = []
    if (top / "package.json").exists():
        for lockfile, command in (("yarn.lock", "yarn install"), ("pnpm-lock.yaml", "pnpm install"), ("bun.lockb", "bun install"),
                                  ("package-lock.json", "npm ci")):
            if (top / lockfile).exists():
                commands.append({"cwd": ".", "run": command})
                break
        else:
            commands.append({"cwd": ".", "run": "npm install"})
    podfiles = [path for path in sorted(top.rglob("Podfile")) if not survey.excluded(str(path.relative_to(top)))]
    podfile = min(podfiles, key=lambda path: len(path.parts)) if podfiles else None
    if podfile and not (podfile.parent / "Pods" / "Manifest.lock").exists():
        gemfile = podfile.parent / "Gemfile"
        uses_bundler = gemfile.exists() and "cocoapods" in gemfile.read_text(errors="replace")
        commands.append({"cwd": str(podfile.parent.relative_to(top)), "run": "bundle install && bundle exec pod install" if uses_bundler else "pod install"})
    return commands


class ToolMissing(Exception):
    pass


def dependencies(entry, top, env, out):
    commands = entry["dependencies"] if "dependencies" in entry else implied_dependencies(top)
    for command in commands:
        tool = command["run"].split()[0]
        if not tool.startswith((".", "/")) and tool != "cp" and not shutil.which(tool, path=env["PATH"]):
            raise ToolMissing(tool)
    for command in commands:
        cwd = top / command.get("cwd", ".")
        status = run_logged(["bash", "-c", command["run"]], cwd, env, out / "deps.log", DEPS_TIMEOUT)
        if status != 0:
            return status, commands
    return 0, commands


def container_of(entry, top):
    chosen = entry.get("chosenContainer")
    if chosen:
        return top / chosen
    found, _ = survey.entry_container(top)
    return top / found if found else None


def application_targets(project):
    text = (project / "project.pbxproj").read_text(errors="replace") if (project / "project.pbxproj").exists() else ""
    targets = re.finditer(r'isa = PBXNativeTarget;(.*?)\n\t\t};', text, re.DOTALL)
    names = []
    for target in targets:
        body = target.group(1)
        if 'productType = "com.apple.product-type.application"' in body:
            name = re.search(r'\bname = "?([^";]+)"?;', body)
            if name:
                names.append(name.group(1))
    return names


def scheme_of(entry, container, env, out):
    """The scheme named in the manifest, else the one named like the container, else the first
    that builds an app."""
    if entry.get("scheme"):
        return entry["scheme"]
    flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
    listed = subprocess.run([NOMAC, "list", flag, str(container), "-json"], cwd=container.parent, env=env, capture_output=True,
                            text=True, timeout=600)
    (out / "list.log").write_text(listed.stdout[-20000:] + listed.stderr[-4000:])
    try:
        report = json.loads(listed.stdout)
    except ValueError:
        return None
    body = report.get("workspace") or report.get("project") or {}
    schemes = list(body.get("schemes") or [])
    if not schemes:
        return None
    projects = [container] if container.suffix == ".xcodeproj" else sorted(path for path in container.parent.glob("*.xcodeproj") if path.name != "Pods.xcodeproj")
    folders = [path / "xcshareddata" / "xcschemes" for path in [container, *projects]]
    builds_app = []
    for scheme in schemes:
        for folder in folders:
            path = folder / f"{scheme}.xcscheme"
            if path.exists() and re.search(r'BuildableName\s*=\s*"[^"]+\.app"', path.read_text(errors="replace")):
                builds_app.append(scheme)
                break
    targets = [name for project in projects for name in application_targets(project)]
    for candidate in (container.stem, *builds_app, *targets, *schemes):
        if candidate in schemes:
            return candidate
    return schemes[0]


def first_errors(log_path, limit=12):
    text = Path(log_path).read_text(errors="replace") if Path(log_path).exists() else ""
    seen, found = set(), []
    for line in text.splitlines():
        if ERROR.search(line):
            key = re.sub(r"\S*/\S*", "<path>", line)[:160]
            if key not in seen:
                seen.add(key)
                found.append(line[:400])
            if len(found) >= limit:
                break
    return found


def save(root, result):
    path = root / "results" / f"{result['id']}.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, indent=1) + "\n")
    temporary.replace(path)


def step(result, name, ok, started, **extra):
    result["steps"][name] = {"ok": ok, "seconds": round(time.time() - started), **extra}
    result["reached"] = name if ok else result.get("reached")
    if not ok:
        result["stopped"] = name


def linux_environment(run):
    """Each project has its own home, deleted with it, so that caches never outlive it; nomac and its launchers are shared."""
    home = run / "home"
    home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, **survey.GIT_ENVIRONMENT, LANG="C.UTF-8", LC_ALL="C.UTF-8", CI="1", COCOAPODS_DISABLE_STATS="1",
               HOME=str(home), NOMAC_HOME=str(SHARED_HOME / ".nomac"), TMPDIR=str(run / "tmp"), GIT_CONFIG_COUNT="3", GIT_CONFIG_KEY_0="http.version",
               GIT_CONFIG_VALUE_0="HTTP/1.1", GIT_CONFIG_KEY_1="http.lowSpeedLimit", GIT_CONFIG_VALUE_1="1000", GIT_CONFIG_KEY_2="http.lowSpeedTime",
               GIT_CONFIG_VALUE_2="180")
    env["PATH"] = f"{SHARED_HOME}/.local/bin:{env['PATH']}"
    return env


def measure(root, work, entry):
    """Every step of one project; the checkout and its derived data go whatever happens."""
    name = identifier(entry["repository"])
    out = root / "results" / name
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    run = work / "runs" / name
    shutil.rmtree(run, ignore_errors=True)
    (run / "tmp").mkdir(parents=True)
    top = run / "src"
    env = linux_environment(run)
    result = {"id": name, "repository": entry["repository"], "commit": entry["commit"], "frames": entry["frames"],
              "nomac": Path(os.path.realpath(NOMAC)).parent.name, "started": datetime.datetime.now().isoformat(timespec="seconds"), "steps": {}}
    save(root, result)
    try:
        if entry.get("noApp"):
            step(result, "scheme", False, time.time(), errors=["the repository has no app to archive"])
            return result
        started = time.time()
        status = with_network_retries(result, "clone", out / "clone.log", lambda: clone(entry, top, out, env))
        step(result, "clone", status == 0, started, status=status, errors=[] if status == 0 else first_errors(out / "clone.log"))
        if status != 0:
            return result

        started = time.time()
        commands = []

        def resolve():
            nonlocal commands
            status, commands = dependencies(entry, top, env, out)
            return status
        status = with_network_retries(result, "deps", out / "deps.log", resolve)
        step(result, "deps", status == 0, started, status=status, commands=[command["run"] for command in commands],
             fromManifest="dependencies" in entry, errors=[] if status == 0 else first_errors(out / "deps.log"))
        if status != 0:
            return result
        save(root, result)

        started = time.time()
        container = container_of(entry, top)
        if container is None or not container.exists():
            step(result, "scheme", False, started, errors=["no container"])
            return result
        result["container"] = str(container.relative_to(top))
        check = subprocess.run([NOMAC, "check", str(container), "--json"], cwd=container.parent, env=env, capture_output=True, text=True, timeout=1800)
        (out / "check.json").write_text(check.stdout)
        try:
            report = json.loads(check.stdout)
            outside = [feature for feature in report["features"] if feature["status"] != "verified"]
            stopping = sorted(feature["id"] for feature in outside if feature["domain"] not in NOT_STOPPING_DOMAINS)
            step(result, "check", True, started, outside=len(outside), mayStop=stopping, fixes=[fix.get("id") for fix in report.get("projectFixes", [])])
        except (ValueError, KeyError):
            step(result, "check", True, started, status=check.returncode, unreadable=True, error=check.stderr[-400:])
        save(root, result)

        started = time.time()
        scheme = scheme_of(entry, container, env, out)
        if scheme is None:
            step(result, "scheme", False, started, errors=[(out / "list.log").read_text(errors="replace")[-400:]])
            return result
        step(result, "scheme", True, started, scheme=scheme)
        save(root, result)

        started = time.time()
        scratch = run / "dd"
        archive = scratch / f"{scheme}.xcarchive"
        flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
        status = with_network_retries(result, "archive", out / "archive.log", lambda: run_logged(
            [NOMAC, "archive", flag, container, "-scheme", scheme, "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", scratch / "DerivedData", "-archivePath", archive, "-IDEBuildingContinueBuildingAfterErrors", "YES", *capture.ADHOC],
            container.parent, env, out / "archive.log", BUILD_TIMEOUT))
        ok = status == 0 and archive.exists()
        step(result, "archive", ok, started, status=status, errors=first_errors(out / "archive.log", 20) if not ok else [])
        if not ok:
            return result
        shutil.rmtree(scratch / "DerivedData", ignore_errors=True)
        save(root, result)

        started = time.time()
        options = scratch / "ExportOptions.plist"
        options.write_text(capture.EXPORT_OPTIONS)
        status = run_logged([NOMAC, "export", "-archivePath", archive, "-exportPath", scratch / "export", "-exportOptionsPlist", options],
                            scratch, env, out / "export.log", EXPORT_TIMEOUT)
        ipas = sorted((scratch / "export").glob("*.ipa"))
        step(result, "export", status == 0 and bool(ipas), started, status=status, ipaBytes=ipas[0].stat().st_size if ipas else 0,
             errors=first_errors(out / "export.log") if status != 0 else [])
        result["ipa"] = status == 0 and bool(ipas)
        return result
    except ToolMissing as error:
        result["notMeasured"] = f"this machine has no {error}"
        return result
    except subprocess.TimeoutExpired as error:
        step(result, "harness", False, time.time(), errors=[f"timed out: {error.cmd[:2]}"])
        return result
    finally:
        result["finished"] = datetime.datetime.now().isoformat(timespec="seconds")
        result.setdefault("ipa", False)
        if stopping.is_set():
            result["notMeasured"] = "stopped for disk space"
        save(root, result)
        subprocess.run(["bash", "-c", f"chmod -R u+w {run} 2>/dev/null; rm -rf {run}"], check=False)
        for path in out.glob("*.log"):
            subprocess.run(["gzip", "-f", str(path)], check=False)
        outcome = "IPA" if result["ipa"] else f"not measured, {result['notMeasured']}" if result.get("notMeasured") else f"stopped at {result.get('stopped')}"
        log(f"{name}: {outcome} ({sum(s['seconds'] for s in result['steps'].values())} s)")


def free_gigabytes(path):
    return shutil.disk_usage(path).free / 1e9


def wait_for_disk(root, work):
    """The Mac's disk is the real limit (bind-mounted root shows it); so is this volume's budget."""
    while True:
        mac = free_gigabytes(root)
        used = subprocess.run(["du", "-sx", "--block-size=1G", str(work)], capture_output=True, text=True).stdout.split()
        volume = int(used[0]) if used else 0
        if mac >= MAC_MIN_FREE_GB and volume < VOLUME_MAX_GB:
            return
        log(f"waiting for disk: Mac {mac:.0f} GB free, volume {volume} GB")
        time.sleep(120)


def disk_guard(root):
    """Below the floor every running step goes and the run ends: the Mac's disk is shared."""
    while not stopping.is_set():
        if free_gigabytes(root) < MAC_STOP_FREE_GB:
            log(f"stopping: the Mac has under {MAC_STOP_FREE_GB} GB free")
            stopping.set()
            for process in list(running):
                os.killpg(process.pid, signal.SIGKILL)
        time.sleep(30)


def run_all(arguments):
    root, work = Path(arguments.root), Path(arguments.work)
    (root / "results").mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    wanted = set(arguments.projects)
    pending = []
    for entry in manifest["projects"]:
        name = identifier(entry["repository"])
        if wanted and entry["repository"] not in wanted and name not in wanted:
            continue
        path = root / "results" / f"{name}.json"
        if not wanted and path.exists():
            done = json.loads(path.read_text())
            if "finished" in done and not done.get("notMeasured"):
                continue
        pending.append(entry)
    log(f"{len(pending)} projects to measure with {Path(os.path.realpath(NOMAC)).parent.name}, {arguments.jobs} at a time")

    threading.Thread(target=disk_guard, args=(root,), daemon=True).start()

    def one(entry):
        wait_for_disk(root, work)
        if not stopping.is_set():
            measure(root, work, entry)

    with concurrent.futures.ThreadPoolExecutor(max_workers=arguments.jobs) as pool:
        for future in concurrent.futures.as_completed([pool.submit(one, entry) for entry in pending]):
            future.result()


# ---------------------------------------------------------------------------------------------
# The same checkout under Xcode 27.0 (Mac)


def xcode(arguments):
    root = Path(arguments.root)
    results = root / "xcode"
    results.mkdir(parents=True, exist_ok=True)
    entries = {identifier(entry["repository"]): entry for entry in load_manifest()["projects"]}
    for name in arguments.projects:
        name = identifier(name)
        entry = entries[name]
        linux_result = json.loads((root / "results" / f"{name}.json").read_text())
        run = root / "xcode-runs" / name
        subprocess.run(["bash", "-c", f"chmod -R u+w {run} 2>/dev/null; rm -rf {run}"], check=False)
        run.mkdir(parents=True)
        top = run / "src"
        out = results / name
        shutil.rmtree(out, ignore_errors=True)
        out.mkdir()
        env = dict(os.environ, **survey.GIT_ENVIRONMENT, DEVELOPER_DIR=XCODE, TMPDIR=str(run), CI="1", COCOAPODS_DISABLE_STATS="1", LANG="en_US.UTF-8")
        result = {"id": name, "repository": entry["repository"], "started": datetime.datetime.now().isoformat(timespec="seconds"), "steps": {}}
        try:
            started = time.time()
            status = with_network_retries(result, "clone", out / "clone.log", lambda: clone(entry, top, out, env))
            step(result, "clone", status == 0, started, status=status)
            if status != 0:
                continue
            started = time.time()
            commands = entry.get("dependencies")
            if commands is None:
                commands = implied_dependencies(top)
            status = 0
            for command in commands:
                status = with_network_retries(result, "deps", out / "deps.log", lambda: run_logged(
                    [*mac_sandbox(offline=False), "bash", "-c", command["run"]], top / command.get("cwd", "."), env, out / "deps.log", DEPS_TIMEOUT))
                if status != 0:
                    break
            step(result, "deps", status == 0, started, status=status, commands=[command["run"] for command in commands],
                 errors=[] if status == 0 else first_errors(out / "deps.log"))
            if status != 0:
                continue
            container = container_of(entry, top)
            scheme = entry.get("scheme") or linux_result["steps"].get("scheme", {}).get("scheme")
            if container is None or scheme is None:
                step(result, "scheme", False, time.time(), errors=["no container or scheme from the Linux run"])
                continue
            flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
            started = time.time()
            archive = run / "dd" / f"{scheme}.xcarchive"
            with_network_retries(result, "packages", out / "resolve.log", lambda: run_logged(
                [*mac_sandbox(offline=False), "xcodebuild", "-resolvePackageDependencies", flag, container, "-scheme", scheme, "-derivedDataPath", run / "dd" / "DerivedData",
                 "-skipPackagePluginValidation", "-skipMacroValidation"], container.parent, env, out / "resolve.log", DEPS_TIMEOUT))
            status = run_logged([*mac_sandbox(offline=True), "xcodebuild", "archive", flag, container, "-scheme", scheme, "-configuration", "Release", "-destination", "generic/platform=iOS",
                                 "-derivedDataPath", run / "dd" / "DerivedData", "-archivePath", archive, "-jobs", JOBS_PER_BUILD, "-IDEBuildingContinueBuildingAfterErrors", "YES",
                                 "-skipPackagePluginValidation", "-skipMacroValidation", *capture.ADHOC], container.parent, env, out / "archive.log", BUILD_TIMEOUT)
            ok = status == 0 and archive.exists()
            step(result, "archive", ok, started, status=status, errors=[] if ok else first_errors(out / "archive.log", 20))
            result["succeeded"] = ok
        finally:
            result["finished"] = datetime.datetime.now().isoformat(timespec="seconds")
            result.setdefault("succeeded", False)
            (results / f"{name}.json").write_text(json.dumps(result, indent=1) + "\n")
            subprocess.run(["bash", "-c", f"chmod -R u+w {run} 2>/dev/null; rm -rf {run}"], check=False)
            for path in out.glob("*.log"):
                subprocess.run(["gzip", "-f", str(path)], check=False)
            print(f"{name}: Xcode {'succeeded' if result['succeeded'] else 'stopped at ' + str(result.get('stopped'))}", flush=True)


# ---------------------------------------------------------------------------------------------
# Verdicts and the report


def results_of(root):
    """Measured projects: finished, and not cut short by the network or a missing tool."""
    found = [json.loads(path.read_text()) for path in sorted((Path(root) / "results").glob("*.json"))]
    return [result for result in found if "finished" in result and not result.get("notMeasured")]


def verdicts():
    return load_manifest().get("verdicts", {})


def classes(arguments):
    """The verdicts given so far, nomac's ranked by the projects each stops."""
    finished = results_of(arguments.root)
    print(f"finished {len(finished)}; IPA {sum(result['ipa'] for result in finished)}")
    ranked = collections.defaultdict(list)
    unjudged = []
    table = verdicts()
    for result in finished:
        if result["ipa"]:
            continue
        verdict = table.get(result["repository"])
        if not verdict:
            unjudged.append(f"{result['repository']} ({result.get('stopped')})")
            continue
        ranked[(verdict["verdict"], verdict["class"])].append(result["repository"])
    for (kind, name), projects in sorted(ranked.items(), key=lambda item: (item[0][0] != "nomac", -len(item[1]), item[0][1])):
        print(f"{kind:8} {len(projects):3}  {name}")
    if unjudged:
        print("no verdict yet:", ", ".join(unjudged))


def triage(arguments):
    """Each stopped project's step and first errors, to give it a verdict by hand."""
    table = verdicts()
    for result in results_of(arguments.root):
        if result["ipa"]:
            continue
        if result["repository"] in table and not arguments.all:
            continue
        stopped = result["steps"].get(result.get("stopped"), {})
        print(f"### {result['repository']} stopped at {result.get('stopped')} ({stopped.get('seconds')} s, network: {result.get('networkFailure')})")
        for line in stopped.get("errors", [])[:arguments.lines]:
            print("  " + re.sub(r"/work/runs/[^/]+/(src/)?", "", line)[:220])


def share_line(label, successes, total):
    if not total:
        return f"{label}: 0 of 0"
    low, high = wilson(successes, total)
    return f"{label}: {successes} of {total} ({100 * successes / total:.0f}%, 95% CI {100 * low:.0f}–{100 * high:.0f}%)"


def report(arguments):
    finished = results_of(arguments.root)
    table = verdicts()
    manifest = load_manifest()
    for frame in ("clear", "accepted"):
        members = [result for result in finished if frame in result["frames"]]
        ipa = sum(result["ipa"] for result in members)
        print(share_line(f"{frame}: IPA", ipa, len(members)))
        counts = collections.Counter((table.get(result["repository"]) or {}).get("verdict", "no verdict") for result in members if not result["ipa"])
        print("  stopped:", dict(counts))
        decided = len(members) - counts["project"]
        print("  " + share_line("IPA, leaving out projects whose own failure stops them", ipa, decided))
        print("  stopped at:", dict(collections.Counter(result.get("stopped") for result in members if not result["ipa"])))
    if arguments.write:
        rows = []
        for result in finished:
            verdict = table.get(result["repository"]) or {}
            rows.append({"repository": result["repository"], "frames": result["frames"], "ipa": result["ipa"], "stoppedAt": result.get("stopped"),
                         "verdict": "ipa" if result["ipa"] else verdict.get("verdict", "no verdict"), "class": verdict.get("class"),
                         "xcode": verdict.get("xcode")})
        dates = sorted(result["started"][:10] for result in finished)
        summary = {"seed": manifest["seed"], "nomac": sorted({result["nomac"] for result in finished}), "dates": [dates[0], dates[-1]] if dates else [], "projects": rows}
        RESULTS.write_text(json.dumps(summary, indent=1) + "\n")


def main():
    global NOMAC
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("pick")
    command.add_argument("--survey", required=True)
    command.add_argument("--seed", type=int, default=SEED)
    command.add_argument("--count", type=int, default=COUNT)
    command = commands.add_parser("run")
    command.add_argument("--root", default=str(DEFAULT_ROOT))
    command.add_argument("--work", default=os.environ.get("WILD_WORK", "/work"))
    command.add_argument("--jobs", type=int, default=1)
    command.add_argument("projects", nargs="*")
    command = commands.add_parser("xcode")
    command.add_argument("--root", default=str(DEFAULT_ROOT))
    command.add_argument("projects", nargs="+")
    command = commands.add_parser("classes")
    command.add_argument("--root", default=str(DEFAULT_ROOT))
    command = commands.add_parser("triage")
    command.add_argument("--root", default=str(DEFAULT_ROOT))
    command.add_argument("--all", action="store_true")
    command.add_argument("--lines", type=int, default=8)
    command = commands.add_parser("report")
    command.add_argument("--root", default=str(DEFAULT_ROOT))
    command.add_argument("--write", action="store_true")
    arguments = parser.parse_args()
    NOMAC = shutil.which("nomac") or "nomac"
    {"pick": pick, "run": run_all, "xcode": xcode, "classes": classes, "triage": triage, "report": report}[arguments.command](arguments)


if __name__ == "__main__":
    main()

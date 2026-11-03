#!/usr/bin/env python3
"""Capture Xcode reference artifacts for one corpus app.

Runs on a macOS machine with Xcode installed (the `reference` GitHub Actions
workflow, or a contributor's Mac). For the app named on the command line it:

  1. clones the app at its pinned commit and runs its declared preparation steps;
  2. records the host identity (Xcode, macOS, user) in host.json;
  3. records `xcodebuild -list -json`;
  4. records `xcodebuild -dumpPIF` (the exact PIF Xcode hands to Swift Build);
  5. records `xcodebuild -showBuildSettings` (text and -json) for every target and
     every shared scheme, in every project configuration, under file names that are
     unique without case and listed in settings/index.json, where `nomac verify` reads them;
  6. builds the app's declared build scheme for a generic iOS device with code
     signing disabled, keeping the full log, the products, the compiled resources
     found in the intermediates (.car, nibs, .momd, compiled strings, actool's
     outputs, dependency info and asset symbols, generated string symbols, Core ML
     models' compiled folders and generated classes) and an
     unsigned IPA.

Every xcodebuild invocation runs with the fixed environment from
`reference_environment()` so the output does not depend on the runner's
environment. The exact command line of every capture is stored next to its
output in `<name>.cmd`.

Only artifacts of the corpus's own open-source apps are produced. Nothing from
Xcode itself is copied into the output (see docs/adr/0004-reference-artifacts.md).

Usage: capture_reference.py <app-id> <output-dir> [--manifest <file>] [--work <dir>] [--skip-build | --build | --archive | --clone-only
                            | --refill-string-symbols] [--reuse-checkout]

--clone-only only clones the app and runs its preparation steps, at the same path a
capture uses. The verify job uses it to recreate the checkout a reference was taken from.

--reuse-checkout captures the checkout --work already has at the app's commit, without cloning
or preparing it again (xcode_upgrade.py recaptures every app with a new Xcode so).

--refill-string-symbols adds the generated string symbols to a build capture taken before
step 6 kept them: it runs the log's GenerateStringSymbols tasks again with the same Xcode, on
the checkout at the reference's commit, and keeps their outputs as step 6 would have.

--build only adds step 6 to a reference captured with --skip-build: it builds the checkout
the reference names (source.json) and records the build's exit status in summary.json.
`nomac verify` compares the build's resource tool tasks with nomac's tools when it is there.
--build and --archive build in that checkout and then undo what the build changed in it; while
they run, the checkout is not the reference's source, so run them only when no other session
verifies the app (or capture a reference of your own under another --work).

--archive adds an ad-hoc signed archive of the build scheme to a reference (`archive/`): every
codesign step of `xcodebuild archive` recorded through a CODESIGN wrapper (its arguments,
entitlements, output and the product before and after), the `.xcarchive`, and its export with
the `debugging` method. The export runs offline (`sandbox-exec`): with an Apple account in Xcode,
exports otherwise ask Apple's developer services about the team. Builds cannot: a build that
expands Swift macros (SwiftUI's `@State` in Xcode 27's SDK) fails under `sandbox-exec`, whose
sandbox the macro plugin server cannot nest its own in, so --build and --archive run unsandboxed
and record every internet socket the build opens in `build/network.log` and
`archive/archive.network.log`.

--manifest reads the app from another manifest in corpus.json's schema (default:
corpus/corpus.json), such as a holdout set of apps kept outside the repository.
"""

import argparse
import json
import os
import platform
import pwd
import grp
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST = REPO_ROOT / "corpus" / "corpus.json"

# Compiled-resource file name suffixes copied out of the build intermediates and products.
RESOURCE_SUFFIXES = (".car", ".nib", ".storyboardc", ".momd", ".mom", ".omo", ".strings",
                     ".stringsdict", ".plist", ".cdm", ".xcmappingmodel", ".mlmodelc")
# Other intermediates `nomac verify` compares: actool's output folders (app icons beside the
# .car), its dependency info, partial Info.plists and the asset symbols it generates.
ASSET_CATALOG_OUTPUTS = ("assetcatalog_output",)
# And the classes coremlc generates (docs/formats/coreml.md).
CORE_ML_OUTPUTS = ("CoreMLGenerated",)
ASSET_CATALOG_PREFIXES = ("assetcatalog_dependencies", "assetcatalog_generated_info", "GeneratedAssetSymbols")
# And the Swift xcstringstool generate-symbols writes into DerivedSources.
STRING_SYMBOL_PREFIXES = ("GeneratedStringSymbols_",)


def log(message):
    print(f"[capture] {message}", flush=True)


def load_app(app_id, manifest_path=MANIFEST):
    manifest = json.loads(Path(manifest_path).read_text())
    for app in manifest["apps"]:
        if app["id"] == app_id:
            return manifest, app
    sys.exit(f"error: no corpus app with id '{app_id}' in {manifest_path}")


def reference_environment(developer_dir):
    """The fixed environment every xcodebuild invocation runs with."""
    home = os.environ["HOME"]
    user = pwd.getpwuid(os.getuid()).pw_name
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home,
        "USER": user,
        "LOGNAME": user,
        "SHELL": "/bin/zsh",
        "TMPDIR": os.environ.get("TMPDIR", "/tmp/"),
        "LANG": "en_US.UTF-8",
        "DEVELOPER_DIR": developer_dir,
    }


def run(cmd, cwd, env, out_path=None, err_path=None, check=False, timeout=None):
    """Runs a command, optionally saving stdout/stderr, and records the command line."""
    log("$ " + " ".join(cmd))
    started = time.time()
    proc = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    if out_path is not None:
        Path(out_path).write_bytes(proc.stdout)
        Path(str(out_path) + ".cmd").write_text(json.dumps({
            "argv": cmd, "cwd": str(cwd), "exitStatus": proc.returncode,
            "seconds": round(time.time() - started, 1)}, indent=2) + "\n")
    if err_path is not None:
        Path(err_path).write_bytes(proc.stderr)
    if check and proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode(errors="replace"))
        sys.exit(f"error: command failed with status {proc.returncode}: {' '.join(cmd)}")
    return proc


def outside_repository(path, name):
    """`path` resolved, which must not lie in this repository: a capture holds Xcode's outputs and
    the identity of the user and Mac (host.json), which the repository never holds (CLAUDE.md)."""
    resolved = Path(path).expanduser().resolve()
    if resolved == REPO_ROOT or REPO_ROOT in resolved.parents:
        sys.exit(f"error: {name} {resolved} is inside the repository; captures go outside it (~/nomac-out)")
    return resolved


def expected_xcode_build(manifest):
    """The Xcode build captures must come from: the manifest's, or the new Xcode an upgrade run of
    xcode_upgrade.py observes (NOMAC_UPGRADE_XCODE_BUILD, docs/UPGRADING.md)."""
    return os.environ.get("NOMAC_UPGRADE_XCODE_BUILD") or manifest["xcode"]["build"]


def checkout_commit(src):
    proc = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else None


def clone(app, work):
    src = work / app["id"]
    if src.exists():
        shutil.rmtree(src)
    src.mkdir(parents=True)
    git = ["git", "-C", str(src)]
    subprocess.run(git + ["init", "-q"], check=True)
    subprocess.run(git + ["remote", "add", "origin", app["repository"]], check=True)
    subprocess.run(git + ["fetch", "-q", "--depth", "1", "origin", app["commit"]], check=True)
    subprocess.run(git + ["checkout", "-q", "--detach", "FETCH_HEAD"], check=True)
    if app.get("submodules", False):
        subprocess.run(git + ["submodule", "update", "--init", "--recursive", "--depth", "1"], check=True)
    return src


def prepare(app, src, log_dir):
    """Runs the app's preparation steps; returns the first non-zero exit status, or 0.

    A failed step is recorded but does not stop the capture: the project may still load,
    and what Xcode does with an unprepared checkout is a reference too.
    """
    log_dir.mkdir(parents=True, exist_ok=True)
    for index, step in enumerate(app.get("prepare", [])):
        proc = run(["/bin/bash", "-c", step], cwd=src, env=dict(os.environ),
                   out_path=log_dir / f"step-{index}.log", err_path=log_dir / f"step-{index}.stderr",
                   timeout=CAPTURE_TIMEOUT)
        if proc.returncode != 0:
            log(f"preparation step {index} failed with status {proc.returncode}: {step}")
            return proc.returncode
    return 0


def host_identity(developer_dir, env):
    def out(cmd):
        return subprocess.run(cmd, capture_output=True, text=True, env=env).stdout.strip()
    version_lines = out(["xcodebuild", "-version"]).splitlines()
    return {
        "xcodeVersion": version_lines[0].replace("Xcode ", "") if version_lines else "",
        "xcodeBuild": version_lines[1].replace("Build version ", "") if len(version_lines) > 1 else "",
        "developerDirectory": developer_dir,
        "operatingSystemVersion": out(["sw_vers", "-productVersion"]),
        "operatingSystemBuild": out(["sw_vers", "-buildVersion"]),
        "nativeArchitecture": platform.machine(),
        "userName": pwd.getpwuid(os.getuid()).pw_name,
        "groupName": grp.getgrgid(os.getgid()).gr_name,
        "uid": os.getuid(),
        "gid": os.getgid(),
        "homeDirectory": os.environ["HOME"],
        "userCacheDirectory": out(["getconf", "DARWIN_USER_CACHE_DIR"]),
        "environment": env,
    }


def container_args(app, src):
    container = src / app["container"]
    flag = "-workspace" if app["container"].endswith(".xcworkspace") else "-project"
    return [flag, str(container)]


def safe_name(text):
    return "".join(c if c.isalnum() or c in "-_." else "_" for c in text)


def unique_name(name, used):
    """`name`, or `name-2`, `name-3`, … when another capture's name equals it without case.

    The captures share one folder, and a Mac's disk ignores case: mattermost's scheme `React`
    in `Debug` and its scheme `React-debug` would both write `scheme-React-Debug-iphoneos`,
    and the later capture would replace the earlier one. `used` holds the folded names taken.
    """
    candidate, number = name, 2
    while unicodedata.normalize("NFC", candidate).casefold() in used:
        candidate, number = f"{name}-{number}", number + 1
    used.add(unicodedata.normalize("NFC", candidate).casefold())
    return candidate


def capture_settings(app, src, out, env):
    settings_dir = out / "settings"
    settings_dir.mkdir(parents=True, exist_ok=True)
    base = ["xcodebuild"] + container_args(app, src)

    listing = run(base + ["-list", "-json"], cwd=src, env=env, out_path=out / "xcodebuild-list.json",
                  err_path=out / "xcodebuild-list.stderr")
    try:
        info = json.loads(listing.stdout)
    except json.JSONDecodeError:
        log("xcodebuild -list produced no JSON; skipping settings capture")
        return []
    body = info.get("project") or info.get("workspace") or {}
    targets = body.get("targets", [])
    schemes = body.get("schemes", [])
    configurations = body.get("configurations", [])

    captures = []
    # Default invocation: no target, scheme or configuration (xcodebuild picks them).
    captures.append(("default", []))
    for target in targets:
        for config in configurations:
            captures.append((f"target-{safe_name(target)}-{safe_name(config)}", ["-target", target, "-configuration", config]))
    # Scheme captures always name a destination: without one, xcodebuild picks the reference
    # Mac itself ("My Mac, Designed for iPad"), which has no counterpart off macOS
    # (docs/adr/0006-machine-specific-roots.md).
    for scheme in schemes:
        captures.append((f"scheme-{safe_name(scheme)}-iphoneos", ["-scheme", scheme, "-destination", "generic/platform=iOS"]))
        for config in (configurations or ["Debug", "Release"]):
            captures.append((f"scheme-{safe_name(scheme)}-{safe_name(config)}-iphoneos",
                             ["-scheme", scheme, "-configuration", config, "-destination", "generic/platform=iOS"]))

    used = set()
    captures = [(unique_name(name, used), args) for name, args in captures]
    index = []
    for name, args in captures:
        text = run(base + ["-showBuildSettings"] + args, cwd=src, env=env,
                   out_path=settings_dir / f"{name}.txt", err_path=settings_dir / f"{name}.stderr")
        run(base + ["-showBuildSettings", "-json"] + args, cwd=src, env=env,
            out_path=settings_dir / f"{name}.json", err_path=settings_dir / f"{name}.json.stderr")
        index.append({"name": name, "arguments": args, "exitStatus": text.returncode})
    (out / "settings" / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    return index


def changes(src):
    """The checkout's changed tracked paths and its untracked and ignored ones (`git status`)."""
    listing = subprocess.run(["git", "-C", str(src), "status", "--porcelain", "--ignored", "--untracked-files=all", "-z"],
                             capture_output=True, check=True).stdout
    entries = [entry for entry in listing.split(b"\0") if len(entry) > 3]
    return ({entry[3:].decode() for entry in entries if entry[:2] not in (b"??", b"!!")},
            {entry[3:].decode() for entry in entries if entry[:2] in (b"??", b"!!")})


def restore(src, changed, added):
    """Undoes what a build changed in the checkout since `changes(src)` returned `changed, added`."""
    changed_now, added_now = changes(src)
    restored = sorted(changed_now - changed)
    for path in restored:
        log(f"restoring {path}, which the build changed in the checkout")
    if restored:
        subprocess.run(["git", "--literal-pathspecs", "-C", str(src), "checkout", "--pathspec-from-file=-", "--pathspec-file-nul", "--"],
                       input="\0".join(restored).encode(), check=True)
    for name in sorted(added_now - added):
        log(f"removing {name}, which the build wrote into the checkout")
        path = src / name
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()


def capture_build(app, src, out, env):
    build = app.get("build")
    if not build:
        log("no build entry in the manifest; skipping build capture")
        return None
    build_dir = out / "build"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)
    derived = src.parent / f"{app['id']}-DerivedData"
    if derived.exists():
        shutil.rmtree(derived)
    cmd = ["xcodebuild"] + container_args(app, src) + [
        "-scheme", build["scheme"], "-configuration", build.get("configuration", "Release"),
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived)] + build.get("options", []) + [
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]
    # Overrides the corpus declares for building with the reference Xcode (for example a
    # deployment target below Xcode's minimum); nomac applies the same ones.
    cmd += [f"{key}={value}" for key, value in sorted(build.get("settings", {}).items())]
    cmd += ["build"]
    changed, added = changes(src)
    with NetworkLog(build_dir / "network.log"):
        proc = run(cmd, cwd=src, env=env, out_path=build_dir / "build.log", err_path=build_dir / "build.stderr",
                   timeout=CAPTURE_TIMEOUT)
    # A build's script phases may write into the checkout (netnewswire's SecretKey.swift, which
    # git ignores); what they change would then be part of the project nomac loads.
    restore(src, changed, added)
    products = derived / "Build" / "Products"
    if products.exists():
        shutil.copytree(products, build_dir / "Products", symlinks=True)
        apps = sorted(products.glob("*-iphoneos/*.app"))
        if apps:
            payload = build_dir / "ipa" / "Payload"
            payload.mkdir(parents=True)
            shutil.copytree(apps[0], payload / apps[0].name, symlinks=True)
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", "Payload",
                            "../unsigned.ipa"], cwd=build_dir / "ipa", check=False)
            shutil.rmtree(payload)
    intermediates = derived / "Build" / "Intermediates.noindex"
    if intermediates.exists():
        dest = build_dir / "Intermediates"
        for path in sorted(intermediates.rglob("*")):
            relative = path.relative_to(intermediates)
            if any(parent.suffix in RESOURCE_SUFFIXES for parent in relative.parents):
                continue
            if path.suffix in RESOURCE_SUFFIXES and (path.is_file() or path.is_dir()):
                pass
            elif not path.is_file() or not (any(part in ASSET_CATALOG_OUTPUTS + CORE_ML_OUTPUTS for part in relative.parts[:-1])
                                            or path.name.startswith(ASSET_CATALOG_PREFIXES + STRING_SYMBOL_PREFIXES)):
                continue
            target = dest / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.is_dir():
                shutil.copytree(path, target, symlinks=True)
            else:
                shutil.copy2(path, target)
    return proc.returncode


# How long a preparation step, a build or an archive may run: home-assistant's and pocket-casts'
# Release builds took over an hour with another capture running beside them (B-098).
CAPTURE_TIMEOUT = 3 * 60 * 60

# Ad-hoc signing for any team or signing style the project sets (the packaging experiments'
# settings, .github/scripts/signing_experiments.py, with the project's team and style cleared).
ADHOC = ["CODE_SIGN_IDENTITY=-", "AD_HOC_CODE_SIGNING_ALLOWED=YES", "PROVISIONING_PROFILE_REQUIRED=NO",
         "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER="]
OFFLINE = ["sandbox-exec", "-p", '(version 1)(allow default)(deny network-outbound (remote ip))'
           '(deny network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))']


class NetworkLog:
    """Samples the internet sockets of this process's descendants with lsof while a build runs,
    for builds that cannot run under OFFLINE (their Swift macro plugins sandbox themselves)."""

    def __init__(self, path):
        self.path, self.lines, self.stop = Path(path), set(), threading.Event()
        self.thread = threading.Thread(target=self.sample, daemon=True)

    def descendants(self):
        children = {}
        for line in subprocess.run(["ps", "-axo", "pid=,ppid="], capture_output=True, text=True).stdout.splitlines():
            pid, ppid = line.split()
            children.setdefault(ppid, []).append(pid)
        found, stack = set(), [str(os.getpid())]
        while stack:
            for child in children.get(stack.pop(), []):
                found.add(child)
                stack.append(child)
        return found

    def sample(self):
        while not self.stop.wait(1):
            pids = self.descendants()
            listing = subprocess.run(["lsof", "-nP", "-i"], capture_output=True, text=True).stdout.splitlines()
            self.lines.update(" ".join(line.split()[:2] + line.split()[7:]) for line in listing[1:] if line.split()[1] in pids)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        self.thread.join()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text("".join(line + "\n" for line in sorted(self.lines)))
        if self.lines:
            log(f"network sockets opened during the build: {self.path}")
# Records each codesign step in its own folder of {capture}: arguments, entitlements, output,
# exit status, and the product before and after.
CODESIGN_WRAPPER = """#!/bin/sh
dir=$(/usr/bin/mktemp -d "{capture}/sign.XXXXXX")
/usr/bin/perl -MTime::HiRes -e 'printf "%.6f\\n", Time::HiRes::time()' > "$dir/time"
printf '%s\\n' "$@" > "$dir/arguments"
previous=""
for argument; do
    if [ "$previous" = "--entitlements" ]; then /bin/cp "$argument" "$dir/entitlements"; fi
    previous="$argument"
done
product="$argument"
/usr/bin/ditto "$product" "$dir/before/$(/usr/bin/basename "$product")"
/usr/bin/codesign "$@" > "$dir/stdout"
status=$?
/bin/cat "$dir/stdout"
/usr/bin/ditto "$product" "$dir/after/$(/usr/bin/basename "$product")"
echo "$status" > "$dir/status"
exit "$status"
"""
# Without a team in the archive the export stops ("No Team Found in Archive"); any team lets it continue.
EXPORT_OPTIONS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>method</key>
\t<string>debugging</string>
\t<key>signingCertificate</key>
\t<string>-</string>
\t<key>signingStyle</key>
\t<string>manual</string>
\t<key>teamID</key>
\t<string>NOMAC00000</string>
</dict>
</plist>
"""


def capture_archive(app, src, out, env):
    """--archive: the build scheme archived with ad-hoc signing, its codesign steps and its export."""
    build = app.get("build")
    if not build:
        sys.exit("error: no build entry in the manifest")
    archive_dir = out / "archive"
    if archive_dir.exists():
        shutil.rmtree(archive_dir)
    (archive_dir / "codesign").mkdir(parents=True)
    wrapper = archive_dir / "codesign-wrapper.sh"
    wrapper.write_text(CODESIGN_WRAPPER.replace("{capture}", str(archive_dir / "codesign")))
    wrapper.chmod(0o755)
    derived = src.parent / f"{app['id']}-ArchiveDerivedData"
    if derived.exists():
        shutil.rmtree(derived)
    archive = archive_dir / f"{build['scheme']}.xcarchive"
    cmd = ["xcodebuild"] + container_args(app, src) + [
        "-scheme", build["scheme"], "-configuration", build.get("configuration", "Release"),
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived), "-archivePath", str(archive)
    ] + build.get("options", []) + ADHOC + [f"CODESIGN={wrapper}"]
    cmd += [f"{key}={value}" for key, value in sorted(build.get("settings", {}).items())]
    cmd += ["archive"]
    changed, added = changes(src)
    with NetworkLog(archive_dir / "archive.network.log"):
        proc = run(cmd, cwd=src, env=env, out_path=archive_dir / "archive.log", err_path=archive_dir / "archive.stderr",
                   timeout=CAPTURE_TIMEOUT)
    restore(src, changed, added)
    shutil.rmtree(derived, ignore_errors=True)
    status = {"archiveExitStatus": proc.returncode, "exportExitStatus": None}
    if proc.returncode == 0:
        options = archive_dir / "ExportOptions.plist"
        options.write_text(EXPORT_OPTIONS)
        status["exportExitStatus"] = run(OFFLINE + ["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                                                    "-exportPath", str(archive_dir / "export"), "-exportOptionsPlist", str(options)],
                                         cwd=archive_dir, env=env, out_path=archive_dir / "export.log",
                                         err_path=archive_dir / "export.stderr").returncode
    summary = json.loads((out / "summary.json").read_text())
    summary.update(status)
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    log(json.dumps(summary))


def reference_checkout(out):
    """The checkout a reference was captured from (source.json)."""
    src = Path(json.loads((out / "source.json").read_text())["path"])
    if not src.is_dir():
        sys.exit(f"error: the reference's checkout {src} is missing; recreate it with --clone-only")
    return src


def add_build(app, out, env):
    """--build: step 6 for a reference captured with --skip-build, in the checkout it names."""
    status = capture_build(app, reference_checkout(out), out, env)
    summary = json.loads((out / "summary.json").read_text())
    summary["buildExitStatus"] = status
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    log(json.dumps(summary))


def refill_string_symbols(out):
    """--refill-string-symbols: the generated string symbols of a build capture taken before the
    capture kept them. Each GenerateStringSymbols task of the log runs again, as logged, with
    its output folder in a temporary one; what it writes goes where the capture keeps it. Tasks
    whose input is gone (a package checkout in derived data that was removed) are left out."""
    build_dir = out / "build"
    command = json.loads((build_dir / "build.log.cmd").read_text())["argv"]
    derived = Path(command[command.index("-derivedDataPath") + 1])
    intermediates = derived / "Build" / "Intermediates.noindex"
    lines = (build_dir / "build.log").read_text(errors="replace").splitlines()
    refilled, skipped = 0, 0
    for index, line in enumerate(lines):
        if not line.startswith("GenerateStringSymbols "):
            continue
        directory = lines[index + 1].strip()[len("cd "):]
        arguments = shlex.split(lines[index + 2].strip())
        position = arguments.index("--output-directory") + 1
        output, source = Path(arguments[position]), Path(arguments[-1])
        if not source.exists():
            skipped += 1
            continue
        with tempfile.TemporaryDirectory() as scratch:
            arguments[position] = scratch
            subprocess.run(arguments, cwd=directory, capture_output=True, check=True)
            for written in Path(scratch).iterdir():
                target = build_dir / "Intermediates" / output.relative_to(intermediates) / written.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(written, target)
                refilled += 1
    log(f"refilled {refilled} generated string symbol files, {skipped} tasks without their input")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app_id")
    parser.add_argument("output")
    parser.add_argument("--manifest", default=str(MANIFEST))
    parser.add_argument("--work", default=os.environ.get("RUNNER_TEMP", "/tmp") + "/nomac-corpus")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--skip-build", action="store_true")
    modes.add_argument("--build", action="store_true")
    modes.add_argument("--archive", action="store_true")
    modes.add_argument("--clone-only", action="store_true")
    modes.add_argument("--refill-string-symbols", action="store_true")
    parser.add_argument("--reuse-checkout", action="store_true",
                        help="use the checkout already in --work at the app's commit, without cloning or preparing it again")
    args = parser.parse_args()
    args.output = str(outside_repository(args.output, "the output folder"))
    args.work = str(outside_repository(args.work, "--work"))

    manifest, app = load_app(args.app_id, args.manifest)
    if args.refill_string_symbols:
        refill_string_symbols(Path(args.output).resolve() / app["id"])
        return
    if args.clone_only:
        work = Path(args.work).resolve()
        work.mkdir(parents=True, exist_ok=True)
        src = clone(app, work)
        status = prepare(app, src, Path(args.output).resolve() / app["id"] / "prepare")
        log(f"checked out {app['id']} at {src} (preparation exit status {status})")
        return
    developer_dir = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
    env = reference_environment(developer_dir)
    expected = expected_xcode_build(manifest)

    out = Path(args.output).resolve() / app["id"]
    if args.build or args.archive:
        recorded = json.loads((out / "host.json").read_text())
        if recorded["xcodeBuild"] != expected or recorded["developerDirectory"] != developer_dir:
            sys.exit(f"error: the reference was captured with {recorded['developerDirectory']} ({recorded['xcodeBuild']}), "
                     f"select the same Xcode {expected}")
        if args.build:
            add_build(app, out, env)
        else:
            capture_archive(app, reference_checkout(out), out, env)
        return
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    work = Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)

    (out / "app.json").write_text(json.dumps(app, indent=2) + "\n")
    host = host_identity(developer_dir, env)
    (out / "host.json").write_text(json.dumps(host, indent=2, sort_keys=True) + "\n")
    run(["xcodebuild", "-showsdks", "-json"], cwd=out, env=env, out_path=out / "showsdks.json",
        err_path=out / "showsdks.stderr")
    if host["xcodeBuild"] != expected:
        sys.exit(f"error: reference Xcode build is {host['xcodeBuild']}, corpus expects {expected}")

    src = work / app["id"]
    if args.reuse_checkout and checkout_commit(src) == app["commit"]:
        prepare_status = None
    else:
        src = clone(app, work)
        prepare_status = prepare(app, src, out / "prepare")
    (out / "source.json").write_text(json.dumps({"path": str(src), "commit": app["commit"]}, indent=2) + "\n")

    pif_dir = out / "pif"
    pif_dir.mkdir()
    run(["xcodebuild", "-dumpPIF", str(pif_dir / "workspace.pif")] + container_args(app, src), cwd=src, env=env,
        out_path=pif_dir / "dumpPIF.stdout", err_path=pif_dir / "dumpPIF.stderr")

    capture_settings(app, src, out, env)
    status = None if args.skip_build else capture_build(app, src, out, env)
    summary = {"app": app["id"], "commit": app["commit"], "xcodeBuild": host["xcodeBuild"],
               "prepareExitStatus": prepare_status, "buildExitStatus": status}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    log(json.dumps(summary))


if __name__ == "__main__":
    main()

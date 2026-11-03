#!/usr/bin/env python3
"""Observe a new Xcode again everywhere nomac observed the current one, and report what changed.

nomac reproduces one Xcode build (docs/adr/0012-one-xcode-per-release.md). Moving to another
(docs/UPGRADING.md) means re-observing everything nomac took from the current one. `run` does it
with the Xcode of --developer-dir (default $DEVELOPER_DIR), into one folder outside the repository:

- experiments/<suite>: the 16 suites of SUITES below, run as written: every `*_experiments.py`
  of .github/scripts that observes Xcode, and sdk_version_maps.py. Not run: shell_experiments.py
  (macOS's /bin/sh, not Xcode), pif_stability.py (it clones an app, so it needs the network: run
  it by hand, docs/UPGRADING.md) and the `*_compare.py` scripts (nomac against these suites'
  observations);
- reference/<app>: every corpus app captured again (capture_reference.py --skip-build, with the
  checkouts --work already has);
- fuzz: the fuzzer's seeds 1 to --fuzz-cases (fuzz_experiments.py run --keep);
- survey: `nomac check` over the coverage survey's repositories (feature_survey.py check report,
  with the repositories of --survey);
- probe.json: each value of the Xcode profile (`nomac sdk profile`) as this Xcode answers it.

`report` compares a run with one of the current Xcode (--baseline; the corpus references default
to the baseline's, else --references) and writes REPORT.md and report.json into the candidate:
the profile values to update, the experiments whose outputs changed (the rules to observe again),
the corpus references and fuzz cases that changed, the survey's coverage, and the tests and docs
that cite each changed experiment. It exits with 1 when anything changed. Run against the current
Xcode itself, it must report no change.

Usage:
  xcode_upgrade.py run [--developer-dir DIR] [--out DIR] [--nomac PATH] [--steps LIST] [--suites LIST]
                       [--apps LIST] [--work DIR] [--fuzz-cases N] [--survey DIR] [--force]
  xcode_upgrade.py report --baseline DIR --candidate DIR [--references DIR] [--nomac PATH]

Output goes to ~/nomac-out/xcode-upgrade/<build> by default. Steps that finished are not run
again unless --force. The suites and the fuzzer run in one fixed folder, STAGE, and are moved into
the run's folder afterwards: their outputs record their own paths, and paths reach outputs that
cannot be rewritten (DerivedData folder names hash the project's path, binaries embed it), so every
run must make them at the same paths. One run at a time holds STAGE; the suites also use fixed work
folders under /tmp and DerivedData, so run this when no other experiment runs on the Mac.
"""

import argparse
import datetime
import fcntl
import hashlib
import io
import importlib.util
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS.parents[1]
DEFAULT_ROOT = Path.home() / "nomac-out" / "xcode-upgrade"
DEFAULT_NOMAC = REPO_ROOT / ".build" / "debug" / "nomac"
DEFAULT_WORK = "/tmp/nomac-corpus"
DEFAULT_SURVEY = Path.home() / "nomac-out" / "survey"
STAGE = DEFAULT_ROOT / "stage"
STEPS = ["experiments", "references", "fuzz", "survey", "probe"]
SUITE_TIMEOUT = 4 * 60 * 60

# suite: (script and arguments, the file its standard output is kept in). sdk-maps reads the
# package suite's observations, so it runs after it.
SUITES = {
    "loader": (["loader_experiments.py", "{out}"], None),
    "pif": (["pif_experiments.py", "{out}"], None),
    "package": (["package_experiments.py", "{out}"], None),
    "sdk-maps": (["sdk_version_maps.py", "{experiments}/package/observations.json"], "maps.txt"),
    "envelope": (["envelope_experiments.py", "{out}", "--nomac", "{nomac}"], None),
    "signing": (["signing_experiments.py", "{out}"], None),
    "assets": (["assets_experiments.py", "{out}", "--nomac", "{nomac}"], None),
    "nib": (["nib_experiments.py", "{out}"], None),
    "strings": (["strings_experiments.py", "{out}"], None),
    "coredata": (["coredata_experiments.py", "{out}"], None),
    "ld": (["ld_experiments.py", "{out}"], None),
    "tapi": (["tapi_experiments.py", "{out}"], None),
    "objc-link": (["objc_link_experiments.py", "{out}"], None),
    "build": (["build_experiments.py", "{out}"], None),
    "macro": (["macro_experiments.py", "preview", "{out}"], None),
    "macro-survey": (["macro_experiments.py", "survey", "{work}"], "survey.txt"),
}
# The names the docs and tests use for each suite's experiments.
SUITE_NAMES = {suite: {f"{suite}-experiments", f"{suite}_experiments"} for suite in SUITES}
SUITE_NAMES.update({"sdk-maps": {"sdk_version_maps"}, "macro-survey": {"macro_experiments"}, "macro": {"macro_experiments"},
                    "objc-link": {"objc_link_experiments", "objc-link-experiments"}})

# What is not Xcode's output, left out of every comparison: the harness's own records; the apps'
# preparation logs (package managers and the network); the projects the scripts write, with the
# git repositories some of them hold (`src`, `source`, `work`); DerivedData's build state and
# caches, which `nomac verify`'s build check leaves out too (docs/VERIFICATION.md "Build
# products"; `Build/Products` is compared), and its `info.plist` (last access); the time each
# codesign capture of signing-experiments was taken; the `Packaging.log` an export writes next to
# its IPA, a record of the export process (object addresses, rsync's transfer rates); the
# references' `showsdks.json`, the SDKs the profile section compares once.
IGNORED_PARTS = {"logs", "steps", "prepare", "work", "src", "source", ".git", "__pycache__", "Intermediates.noindex",
                 "Logs", "ModuleCache.noindex", "CompilationCache.noindex", "SDKExplicitPrecompiledModules",
                 "SDKStatCaches.noindex", "Index.noindex", "SourcePackages", "XCBuildData"}
IGNORED_FILES = {"run.json", "probe.json", "REPORT.md", "report.json", "info.plist", "time", "Packaging.log", "showsdks.json"}
# pif-experiments' observations.json records the GUIDs Xcode draws at random (ADR 0009); the PIFs
# it is read from are compared.
IGNORED_SUITE_FILES = {("pif", "observations.json")}
# Experiments whose outputs change from one run to the next with one Xcode, as the docs record:
# "order": things come in another order (compared without it: lists, the words of a value, lines);
# "choice": xcodebuild picks another target, scheme or app (not compared, listed in the report);
# "corpus": the experiment reads every file of a kind in /tmp/nomac-corpus, where other processes'
# builds add more (`<app>-DerivedData`), so its inputs change (not compared, listed);
# "build files": build files get GUIDs Xcode draws at random (numbered in order of appearance);
# "order, build files": both.
VARYING = {
    ("pif", "regions-one-folder"): ("order", "B-017"), ("pif", "hexguid-other-file"): ("order", "B-017"),
    ("pif", "hexguid-two-groups"): ("order", "B-017"),
    ("pif", "variants-order"): ("order", "B-017"), ("pif", "variants-order-fr"): ("order", "B-017"),
    ("pif", "base-variants-2"): ("order", "B-034"), ("pif", "base-variants-3"): ("order", "B-034"),
    ("pif", "libraries-nested"): ("order", "B-031"),
    **{("loader", name): ("order", "B-030") for name in (
        "regions-classic", "regions-classic-2", "regions-classic-3", "regions-classic-4", "regions-classic-5",
        "regions-case", "regions-case-2", "regions-case-3", "regions-case-4", "regions-case-5", "regions-case-6",
        "intents-codegen", "intents-codegen-fr")},
    ("loader", "lproj-groups"): ("order, build files", "B-030, ADR 0009"),
    ("loader", "variant-regions"): ("order, build files", "B-030, ADR 0009"),
    ("loader", "autocreate-three"): ("order", "B-097"),
    ("loader", "autocreate-hosts"): ("choice", "B-015"),
    ("loader", "project-reference-names"): ("choice", "VERIFICATION.md"), ("loader", "workspace-names"): ("choice", "VERIFICATION.md"),
    ("loader", "same-name-destinations"): ("choice", "VERIFICATION.md"), ("loader", "project-references"): ("choice", "VERIFICATION.md"),
    ("loader", "user-schemes-workspace"): ("choice", "B-065"), ("loader", "user-schemes-references"): ("choice", "B-065"),
    ("loader", "variant-build-files"): ("build files", "ADR 0009"),
    ("envelope", "variant-groups"): ("build files", "ADR 0009"),
    ("assets", "symbols"): ("order", "asset-catalog.md, `ties`"),
    ("strings", "xcstrings"): ("choice", "strings.md `--dry-run`, B-097"),
    ("strings", "corpus-copy"): ("corpus", "B-097"),
}
LOADER_STDERR_LIMIT = 8000
# signing-experiments' codesign captures go to `mktemp -d sign.XXXXXX` folders, named here by
# what they ran.
CAPTURE = re.compile(r"^sign\.[A-Za-z0-9]{6}$")
# Values that record when or how long, not what (the `seconds` of every capture's `.cmd`);
# whether capture_reference.py prepared the checkout, which `run` reuses prepared; and
# envelope-experiments' summaries of the captures' standard error (their first six error lines),
# which are compared in full.
IGNORED_KEYS = {"seconds", "prepareExitStatus", "xcodeError", "refusal"}
# assets-experiments' summary of `appearance-order`: the orders actool created the appearance keys
# in, six runs, which change from one run to the next (ADR 0200); the catalogs are compared.
SUITE_IGNORED_KEYS = {"assets": {"orders"}}
# Values compared by their length only: momc's `.omo` files, which differ in two bytes between two
# compiles of one model with one Xcode (UnCloudNotes v4, B-097; the format is B-256).
SUITE_LENGTH_ONLY_SUFFIXES = {"coredata": (".omo",)}


def log(message):
    print(f"[upgrade] {message}", flush=True)


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def outside_repository(path, name):
    """`path` resolved, which must not lie in this repository: runs hold Xcode's outputs and the
    identity of the user and Mac (host.json), which the repository never holds (CLAUDE.md)."""
    resolved = Path(path).expanduser().resolve()
    if resolved == REPO_ROOT or REPO_ROOT in resolved.parents:
        sys.exit(f"error: {name} {resolved} is inside the repository; runs go outside it (~/nomac-out)")
    return resolved


def xcode_identity(developer_dir):
    version = plistlib.loads((Path(developer_dir).parent / "version.plist").read_bytes())
    return {"version": version["CFBundleShortVersionString"], "build": version["ProductBuildVersion"]}


def run_command(argv, env, log_path, cwd=None, stdout_path=None, timeout=SUITE_TIMEOUT):
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.datetime.now()
    with open(log_path, "wb") as log_file:
        stdout = open(stdout_path, "wb") if stdout_path else log_file
        try:
            status = subprocess.run(argv, cwd=cwd, env=env, stdout=stdout, stderr=log_file, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            status = "timeout"
        finally:
            if stdout_path:
                stdout.close()
    return {"argv": argv, "status": status, "seconds": round((datetime.datetime.now() - started).total_seconds(), 1)}


# ---------------------------------------------------------------------------------------------
# run


class Run:
    def __init__(self, args):
        self.developer_dir = str(Path(args.developer_dir).resolve())
        self.xcode = xcode_identity(self.developer_dir)
        self.out = outside_repository(args.out or DEFAULT_ROOT / self.xcode["build"], "--out")
        self.nomac = str(Path(args.nomac).resolve())
        self.work = str(outside_repository(args.work, "--work"))
        self.survey_source = Path(args.survey).expanduser().resolve()
        self.args = args
        self.env = dict(os.environ, DEVELOPER_DIR=self.developer_dir, NOMAC_UPGRADE_XCODE_BUILD=self.xcode["build"],
                        PYTHONDONTWRITEBYTECODE="1")

    def step_record(self, name):
        return self.out / "steps" / f"{name}.json"

    def once(self, name, action):
        record = self.step_record(name)
        if record.exists() and not self.args.force:
            log(f"{name}: done in an earlier run")
            return json.loads(record.read_text())
        log(f"{name}: running")
        result = action()
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(json.dumps(result, indent=1) + "\n")
        log(f"{name}: {result.get('status')} ({result.get('seconds', 0)} s)")
        return result

    def main(self):
        self.out.mkdir(parents=True, exist_ok=True)
        STAGE.mkdir(parents=True, exist_ok=True)
        lock = open(STAGE / ".lock", "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit(f"error: another run holds {STAGE}")
        commit = subprocess.run(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        nomac_version = subprocess.run([self.nomac, "--version"], capture_output=True, text=True).stdout.strip()
        (self.out / "run.json").write_text(json.dumps({
            "out": str(self.out), "developerDirectory": self.developer_dir, "xcode": self.xcode, "nomac": self.nomac, "nomacVersion": nomac_version,
            "withBuilds": self.args.with_builds,
            "commit": commit, "work": self.work}, indent=1) + "\n")
        steps = self.args.steps.split(",") if self.args.steps else STEPS
        if "experiments" in steps:
            suites = self.args.suites.split(",") if self.args.suites else list(SUITES)
            for suite in suites:
                self.once(f"experiments-{suite}", lambda suite=suite: self.experiment_suite(suite))
        if "references" in steps:
            manifest = json.loads((REPO_ROOT / "corpus" / "corpus.json").read_text())
            apps = self.args.apps.split(",") if self.args.apps else [app["id"] for app in manifest["apps"]]
            for app in apps:
                self.once(f"reference-{app}", lambda app=app: self.reference(app))
        if "fuzz" in steps:
            self.once("fuzz", self.fuzz)
        if "survey" in steps:
            self.once("survey", self.survey)
        if "probe" in steps:
            self.once("probe", self.probe)

    def staged(self, name, make):
        """Runs `make(folder)` in STAGE/<name>, then moves the folder to the run's <name>."""
        stage, final = STAGE / name, self.out / name
        for folder in (stage, final):
            if folder.exists():
                shutil.rmtree(folder)
        stage.mkdir(parents=True)
        result = make(stage)
        final.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(stage), str(final))
        return result

    def experiment_suite(self, suite):
        arguments, stdout_name = SUITES[suite]

        def make(out):
            values = {"out": str(out), "nomac": self.nomac, "experiments": str(self.out / "experiments"), "work": self.work}
            argv = [sys.executable, str(SCRIPTS / arguments[0])] + [argument.format(**values) for argument in arguments[1:]]
            return run_command(argv, self.env, self.out / "logs" / f"experiments-{suite}.log", cwd=REPO_ROOT,
                               stdout_path=out / stdout_name if stdout_name else None)
        return self.staged(f"experiments/{suite}", make)

    def reference(self, app):
        argv = [sys.executable, str(REPO_ROOT / "corpus" / "scripts" / "capture_reference.py"), app, str(self.out / "reference"),
                "--work", self.work, "--reuse-checkout"] + ([] if self.args.with_builds else ["--skip-build"])
        return run_command(argv, self.env, self.out / "logs" / f"reference-{app}.log", cwd=REPO_ROOT)

    def fuzz(self):
        def make(out):
            argv = [sys.executable, str(SCRIPTS / "fuzz_experiments.py"), "run", "--out", str(out), "--nomac", self.nomac,
                    "--cases", str(self.args.fuzz_cases), "--start", "1", "--no-minimize", "--keep"]
            return run_command(argv, self.env, self.out / "logs" / "fuzz.log", cwd=REPO_ROOT)
        return self.staged("fuzz", make)

    def survey(self):
        survey = self.out / "survey"
        if (survey / "checks").exists():
            shutil.rmtree(survey / "checks")
        survey.mkdir(parents=True, exist_ok=True)
        source = self.survey_source
        if not (survey / "repos").exists():
            (survey / "repos").symlink_to(source / "repos")
        shutil.copyfile(source / "contents.json", survey / "contents.json")
        argv = [sys.executable, str(SCRIPTS / "feature_survey.py"), "check", "--out", str(survey), "--nomac", self.nomac, "--jobs", "4"]
        return run_command(argv, self.env, self.out / "logs" / "survey.log", cwd=REPO_ROOT)

    def probe(self):
        probe = Probe(self.developer_dir, self.env, self.out).observe()
        (self.out / "probe.json").write_text(json.dumps(probe, indent=1, sort_keys=True) + "\n")
        return {"status": 0}


class Probe:
    """Each value of the Xcode profile as the Xcode of the run answers it: from its tools, from a
    catalog actool compiles here, and from the run's experiments and references."""

    def __init__(self, developer_dir, env, out):
        self.developer_dir = developer_dir
        self.env = env
        self.out = out

    def tool(self, *argv):
        return subprocess.run(["xcrun", *argv], env=self.env, capture_output=True, text=True).stdout

    def observe(self):
        version = plistlib.loads((Path(self.developer_dir).parent / "version.plist").read_bytes())
        probe = {"xcode": {"version": version["CFBundleShortVersionString"], "build": version["ProductBuildVersion"]}}
        info_plist = self.out / "experiments/build/app-without-packages/dd-App/Build/Products/Debug-iphoneos/App.app/Info.plist"
        if info_plist.exists():
            keys = plistlib.loads(info_plist.read_bytes())
            probe["infoPlist"] = {key: value for key, value in keys.items() if key.startswith("DT") or key == "BuildMachineOSBuild"}
            probe["xcode"]["versionActual"] = keys.get("DTXcode")
        for tool in ("actool", "ibtool"):
            answer = plistlib.loads(self.tool(tool, "--version", "--output-format", "xml1").encode())[f"com.apple.{tool}.version"]
            probe[tool] = {"bundleVersion": answer["bundle-version"], "shortBundleVersion": answer["short-bundle-version"]}
        probe["assetCatalog"] = self.asset_catalog()
        sdks = {}
        for sdk in json.loads(subprocess.run(["xcodebuild", "-showsdks", "-json"], env=self.env, capture_output=True, text=True).stdout):
            entry = {"canonicalName": sdk["canonicalName"], "platform": sdk["platform"], "version": sdk["sdkVersion"]}
            if sdk.get("productBuildVersion"):
                entry["build"] = sdk["productBuildVersion"]
            sdks.setdefault(sdk["canonicalName"], entry)
        probe["sdks"] = list(sdks.values())
        hosts = sorted((self.out / "reference").glob("*/host.json"))
        host = json.loads(hosts[0].read_text()) if hosts else {
            "operatingSystemVersion": subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
            "operatingSystemBuild": subprocess.run(["sw_vers", "-buildVersion"], capture_output=True, text=True).stdout.strip(),
            "nativeArchitecture": subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()}
        probe["referenceMac"] = {key: host[key] for key in ("operatingSystemVersion", "operatingSystemBuild", "nativeArchitecture")}
        clang_job = subprocess.run(["xcrun", "clang", "-###", "-c", "-x", "c", "/dev/null", "-o", "/dev/null", "-target", "arm64-apple-ios15.0"],
                                   env=self.env, capture_output=True, text=True).stderr
        linker_version = re.search(r'"-target-linker-version" "([^"]+)"', clang_job)
        probe["xcodeTools"] = {
            "swiftCompiler": re.search(r"(Apple Swift version .*)", self.tool("swiftc", "--version")).group(1).strip(),
            "clang": self.tool("clang", "--version").splitlines()[0],
            "clangLinkerVersion": linker_version.group(1) if linker_version else None,
            "linker": json.loads(self.tool("ld", "-version_details"))["version"],
            "tapi": self.tool("tapi", "--version").splitlines()[0],
        }
        package = self.out / "experiments/package/observations.json"
        if package.exists():
            probe["manifestHostConditions"] = {"answers": json.loads(package.read_text())["conditions"]}
        object_versions = self.out / "experiments/envelope/object-versions.json"
        if object_versions.exists():
            probe["readableObjectVersions"] = sorted(json.loads(object_versions.read_text())["observations"]["readable"])
        return probe

    def asset_catalog(self):
        assets = load_script("assets_experiments")
        with tempfile.TemporaryDirectory() as folder:
            catalog = Path(folder) / "Assets.xcassets"
            (catalog / "Red.colorset").mkdir(parents=True)
            (catalog / "Contents.json").write_text(json.dumps(assets.INFO))
            (catalog / "Red.colorset" / "Contents.json").write_text(json.dumps({"colors": assets.red(), **assets.INFO}))
            out = Path(folder) / "out"
            out.mkdir()
            # The run's Xcode's actool, whatever DEVELOPER_DIR this script was started with.
            subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(out), "--export-dependency-info", str(out / "deps"),
                            "--output-partial-info-plist", str(out / "partial.plist"), *assets.ACTOOL_ARGS],
                           env=self.env, capture_output=True, check=True)
            blocks, variables = assets.bom((out / "Assets.car").read_bytes())
            named = dict(variables)
            header, metadata = blocks[named["CARHEADER"]], blocks[named["EXTENDED_METADATA"]]
            text = lambda data: data.split(b"\0", 1)[0].decode()
            dependency_info = (out / "deps").read_bytes()
            return {
                "coreUIVersion": struct.unpack_from("<I", header, 4)[0],
                "coreUIVersionString": text(header[20:148]),
                "versionString": text(header[148:404]),
                "authoringTool": text(metadata[4 + 3 * 256:4 + 4 * 256]),
                "dependencyInfoTool": text(dependency_info[1:]),
            }


# ---------------------------------------------------------------------------------------------
# report


def flatten(value, prefix=""):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            result.update(flatten(item, f"{prefix}.{key}" if prefix else key))
        return result
    if isinstance(value, list) and value and isinstance(value[0], dict) and "canonicalName" in value[0]:
        return flatten({item["canonicalName"]: item for item in value}, prefix)
    return {prefix: value}


def profile_changes(probe, profile):
    """Profile values whose observed value differs, those the run did not observe, and those no
    run observes: the pins, chosen by comparison, and the condition kinds whose unlisted
    arguments are false, a rule read from package-experiments `conditions`."""
    observed, recorded = flatten(probe), flatten(profile)
    changed, missing = [], []
    for key, value in sorted(observed.items()):
        if key == "assetCatalog.dependencyInfoTool":
            expected = f"actool-{profile['actool']['bundleVersion']}"
        elif key.startswith("manifestHostConditions.answers.") and key not in recorded:
            continue
        else:
            expected = recorded.get(key)
        if value != expected:
            changed.append({"key": key, "profile": expected, "observed": value})
    derived = lambda key: key.startswith("pins.") or key == "manifestHostConditions.closedKinds"
    missing = [key for key in sorted(recorded) if key not in observed and not derived(key)]
    return changed, missing, sorted(key for key in recorded if derived(key))


class Normalizer:
    """Rewrites what differs between two runs without saying anything about Xcode: the folders
    compared and the run's own; the Xcode's identity, which the profile section reports once (its
    build, version, `XCODE_VERSION_*` and `DTXcode`, developer directory, its SDKs' versions and
    builds, the version string of `Assets.car`); nomac's own warning that the run's Xcode is not
    its profile's, which only an upgrade's candidate run prints (envelope-experiments keep nomac's
    standard error in `verify.log` and `nomac-list.txt`); clock times, process ids, durations and result bundle names, IGNORED_KEYS,
    and xcodebuild's package preamble: the `Fetching from` lines depend on
    SwiftPM's caches, and the resolved packages come in an order that changes from one run to the
    next (icecubes, gomap), which `nomac verify` leaves out too (docs/VERIFICATION.md). In PIFs,
    two of `nomac verify`'s rewrites (`PIFComparison`): object signatures, which follow the
    project file's modification time (`PROJECT@v11_mod=<hash>`), and the GUIDs Xcode draws at
    random for a synchronized variant group with neither a development-region nor a `Base`
    variant and for its build files (ADR 0009). Synchronized GUIDs and the order of package
    projects are compared as written, so a change in how Xcode derives them shows. The devices
    and simulators of the Mac, which xcodebuild lists among a scheme's destinations (the owner's
    iPhone was connected for some corpus captures), and xcodebuild's `IDERunDestination: Supported
    platforms ... is empty` message, which one run of a command prints and another does not
    (B-097). The commits of the git repositories the experiments create (`revision`), which record
    when they were made. actool's standard error, whose messages come from several threads, and
    logs, compared as sets of lines. And what the class constants below describe."""

    SYNCHRONIZED_GUID = re.compile(r"^[A-Za-z0-9+/]{43}=$")

    TIMESTAMP = re.compile(rb"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?: ?[+-]\d{2}:?\d{2}|Z)?")
    RESULT_BUNDLE = re.compile(rb"ResultBundle_[0-9_-]+\.xcresult")
    # IDEDistribution's log bundles (`App_2026-10-22_16-52-36.404.xcdistributionlogs`).
    FILE_TIME = re.compile(rb"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?:\.\d+)?")
    DEVICE = re.compile(rb"^\s*\{ platform:[^,]+, (?:arch:[^,]+, )?id:[0-9A-F-]{25,36}, [^}]*\}[ \t]*\n?", re.MULTILINE)
    # loader-experiments keeps the last 8000 characters of standard error, which can start inside
    # one of those destinations.
    DEVICE_TAIL = re.compile(rb"\A[^{\n]*\}[ \t]*\n")
    # Two xcodebuild runs started in the same second name their result bundles alike, and one
    # fails to save its own (envelope-experiments runs four at once).
    RESULT_BUNDLE_FAILURE = re.compile(rb"^Failed saving result bundle for error: .*\n?", re.MULTILINE)
    # What xcodebuild's crash reports and logs (IDEDistribution's `Packaging.log`) record of the
    # process: object addresses, open ports and files.
    CRASH = re.compile(rb"0x[0-9a-f]{6,}|(?<=Open Mach Ports: )\d+|(?<=Open FDs: )\d+")
    # The header of the destinations above, when none is left under it.
    EMPTY_DESTINATIONS = re.compile(
        rb'(?<=\n)\n*[ \t]*(?:Destinations incompatible with|Ineligible destinations for) the "[^"\n]*" scheme:[ \t]*\n(?=\Z|[ \t]*\n)')
    # Xcode writes no value it read for a `fileEncoding` it cannot read, but whatever was in
    # memory, above 2^32 (B-081: "Xcode's value changes from dump to dump").
    UNREAD_ENCODING = re.compile(rb'("fileTextEncoding\\?" ?: ?\\?")[0-9]{11,}')
    # nomac's listing of a package the experiment created, at a commit made at run time.
    SHORT_REVISION = re.compile(rb"(/src/[^\s@]* @ [^\s()]+ \()[0-9a-f]{7}\)")
    REVISION = re.compile(rb'(revision\\?"\s*:\s*\\?")[0-9a-f]{40}')
    EMPTY_PLATFORMS = re.compile(rb"^.*\[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.\n?",
                                 re.MULTILINE)
    PROCESS = re.compile(rb"\b([A-Za-z_][\w.-]*)\[\d+:[0-9a-fx]+\]")
    DURATION = re.compile(rb"\(\d+(?:\.\d+)? (?:seconds|sec)\)|(?<=\| )\d+\.\d+ seconds")
    # Objective-C descriptions of objects in memory (`<IBNibUIView: 0x7a3a152f40>`).
    OBJECT = re.compile(rb"(<[A-Za-z_][\w.]*:? )0x[0-9a-f]+")
    NOMAC_WARNING = re.compile(rb"^warning: .* but nomac \S+ reproduces Xcode .* only; .*\n?", re.MULTILINE)
    XCODE_VERSION_KEY = re.compile(rb'(\bxcodeVersion\\?"\s*:\s*\\?")[^"\\]*')
    VERSION_SETTING = re.compile(
        rb'(\b(?:XCODE_VERSION_(?:ACTUAL|MAJOR|MINOR)|DTXcode|SDK_VERSION(?:_ACTUAL|_MAJOR|_MINOR)?|DTPlatformVersion)'
        rb'(?:\\?"\s*:\s*\\?"|\s*=\s*|</key>\s*<string>))[0-9.]+')

    def __init__(self, run, ignored_keys=IGNORED_KEYS):
        self.ignored_keys = ignored_keys
        self.length_only = ()
        self.assets = None
        version = run["xcode"]["version"].encode()
        self.replacements = [(run["out"].encode(), b"<RUN>"), (run["developerDirectory"].encode(), b"<DEVELOPER_DIR>"),
                             (run["xcode"]["build"].encode(), b"<XCODE_BUILD>")]
        self.identity = [(re.compile(rb"\bXcode " + re.escape(version) + rb"(?![\d.])"), b"Xcode <XCODE_VERSION>")]
        for sdk in run.get("sdks", []):
            platform, sdk_version = sdk["platform"].encode(), sdk["version"].encode()
            self.identity.append((re.compile(rb"\b" + re.escape(platform + sdk_version) + rb"(?![\d.])"), platform + b"<SDK_VERSION>"))
            self.identity.append((re.compile(rb"\b([A-Za-z]+)" + re.escape(sdk_version) + rb"\.sdk\b"), rb"\1<SDK_VERSION>.sdk"))
            if sdk.get("build"):
                self.identity.append((re.compile(rb"\b" + re.escape(sdk["build"].encode()) + rb"\b"), b"<SDK_BUILD>"))
        self.car_version = b"Xcode " + version + b" (" + run["xcode"]["build"].encode() + b") via AssetCatalogAgent"

    def __call__(self, path, data, root, varying=None, suite=None):
        keys, suffixes = self.ignored_keys, self.length_only
        self.ignored_keys = keys | SUITE_IGNORED_KEYS.get(suite, set())
        self.length_only = SUITE_LENGTH_ONLY_SUFFIXES.get(suite, ())
        try:
            return self.normalize(path, data, root, varying)
        finally:
            self.ignored_keys, self.length_only = keys, suffixes

    def normalize(self, path, data, root, varying):
        if data.startswith(b"bplist00"):
            # Binary property lists by their content, so the identity in them can be rewritten.
            try:
                data = plistlib.dumps(plistlib.loads(data), sort_keys=False)
            except (plistlib.InvalidFileException, ValueError, OverflowError):
                pass
        if b"\0" not in data[:4096]:
            data = data.replace(str(root).encode(), b"<ROOT>")
            for old, new in self.replacements:
                data = data.replace(old, new)
            data = self.RESULT_BUNDLE.sub(b"ResultBundle_<TIME>.xcresult", data)
            data = self.FILE_TIME.sub(b"<TIME>", data)
            data = self.OBJECT.sub(rb"\1<ADDRESS>", data)
            data = self.DEVICE.sub(b"", self.DEVICE_TAIL.sub(b"", data))
            data = self.REVISION.sub(rb"\1<REVISION>", data)
            data = self.SHORT_REVISION.sub(rb"\1<REVISION>)", data)
            data = self.RESULT_BUNDLE_FAILURE.sub(b"", data)
            data = self.EMPTY_DESTINATIONS.sub(b"", data)
            data = self.UNREAD_ENCODING.sub(rb"\1<UNREAD>", data)
            if path.suffix in (".stderr", ".log"):
                data = self.CRASH.sub(b"<PROCESS>", data)
            data = self.EMPTY_PLATFORMS.sub(b"", data)
            data = self.NOMAC_WARNING.sub(b"", data)
            data = self.XCODE_VERSION_KEY.sub(rb"\1<XCODE_VERSION>", data)
            data = self.VERSION_SETTING.sub(rb"\1<VERSION>", data)
            for pattern, replacement in self.identity:
                data = pattern.sub(replacement, data)
            data = self.TIMESTAMP.sub(b"<TIME>", data)
            data = self.PROCESS.sub(rb"\1[<PID>]", data)
            data = self.package_preamble(self.DURATION.sub(b"(<DURATION>)", data))
        kinds = set((varying or "").split(", "))
        if "order" in kinds:
            return b"\n".join(sorted(self.structured(path, data, unordered=True, build_files="build files" in kinds).split(b"\n")))
        if path.suffix == ".log" or path.name == "stderr.txt":
            return b"\n".join(sorted(self.structured(path, data).split(b"\n")))
        return self.structured(path, data, build_files="build files" in kinds)

    def structured(self, path, data, unordered=False, build_files=False):
        if path.suffix == ".ipa":
            return self.archive(data)
        if path.suffix == ".car":
            # actool creates the appearance-key blocks in an order that changes from one run to
            # the next: compared in name order, as ADR 0200 compares nomac's.
            self.assets = self.assets or load_script("assets_experiments")
            try:
                data = self.assets.canonical_car(data)
            except (AssertionError, KeyError, struct.error, UnicodeDecodeError):
                pass
            start = data.find(self.car_version)
            # CARHEADER's 256-byte version string names the Xcode.
            return data if start < 0 else data[:start] + b"<CAR_VERSION_STRING>" + data[start + 256:]
        if path.suffix == ".swiftsourceinfo":
            # Each source's hash, then its modification time (docs/VERIFICATION.md).
            return re.sub(rb"([0-9a-f]{64}).{8}", rb"\1<MTIME>", data, flags=re.DOTALL)
        if path.suffix == ".pif":
            try:
                text = self.pif(data.decode(), build_files, numbered=not unordered)
                return json.dumps(self.unordered(json.loads(text)), sort_keys=True, indent=0).encode() if unordered else text.encode()
            except ValueError:
                pass
        if path.suffix == ".json" or path.name.endswith(".cmd"):
            try:
                value = self.without_ignored_keys(json.loads(data))
            except ValueError:
                value = None
            if value is not None:
                return json.dumps(self.unordered(value) if unordered else value, sort_keys=True, indent=0).encode()
        return data

    @staticmethod
    def archive(data):
        """A zip archive's entries without the times they were written at (the DOS times and the
        `UT` and `UX` extra fields), as signing-experiments' own IPA comparison, nor the time a
        `.symbols` file records."""
        lines = []
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for info in archive.infolist():
                extra, position = b"", 0
                while position + 4 <= len(info.extra):
                    tag, size = struct.unpack_from("<HH", info.extra, position)
                    if tag not in (0x5455, 0x5855):
                        extra += info.extra[position:position + 4 + size]
                    position += 4 + size
                content, compressed = info.CRC, info.compress_size
                if info.filename.endswith(".symbols"):
                    # A `.symbols` file records its dSYM's modification time (docs/formats/symbols.md).
                    symbols = bytearray(archive.read(info))
                    symbols[40:44] = bytes(4)
                    content, compressed = zlib.crc32(symbols), None
                lines.append(f"{info.filename} {info.compress_type} {info.flag_bits} {info.create_system} {info.external_attr} "
                             f"{content} {compressed} {info.file_size} {extra.hex()}")
        return "\n".join(lines).encode()

    @classmethod
    def unordered(cls, value):
        """`value` with its lists sorted and the words of its strings sorted."""
        if isinstance(value, dict):
            return {key: cls.unordered(item) for key, item in value.items()}
        if isinstance(value, list):
            return sorted((cls.unordered(item) for item in value), key=lambda item: json.dumps(item, sort_keys=True))
        if isinstance(value, str):
            return " ".join(sorted(value.split()))
        return value

    @classmethod
    def pif(cls, text, build_files=False, numbered=True):
        objects = json.loads(text)
        replacements = [(object_["signature"], f"<{object_['type'].upper()}-{index}>") for index, object_ in enumerate(objects)]
        random = set()

        def walk(node):
            children = node.get("children", [])
            if node.get("type") == "variantGroup" and not cls.SYNCHRONIZED_GUID.match(node.get("guid", "")) and children \
                    and all(cls.SYNCHRONIZED_GUID.match(child.get("guid", "")) for child in children):
                random.add(node["guid"])
            for child in children:
                walk(child)
        contents = [object_.get("contents", {}) for object_ in objects]
        for content in contents:
            if "groupTree" in content:
                walk(content["groupTree"])
        for content in contents:
            for phase in content.get("buildPhases", []):
                random.update(file["guid"] for file in phase.get("buildFiles", []) if file.get("fileReference") in random)
        if build_files:
            random.update(file["guid"] for content in contents for phase in content.get("buildPhases", [])
                          for file in phase.get("buildFiles", []))
        order = sorted(random, key=lambda guid: text.index(f'"{guid}"'))
        replacements += [(guid, f"<RANDOM-{index}>" if numbered else "<RANDOM>") for index, guid in enumerate(order)]
        for old, new in replacements:
            text = text.replace(f'"{old}"', f'"{new}"')
        return text

    @staticmethod
    def package_preamble(data):
        lines, result, index = data.split(b"\n"), [], 0
        while index < len(lines):
            if lines[index] == b"Resolve Package Graph" and b"Resolved source packages:" in lines[index:]:
                start = lines.index(b"Resolved source packages:", index) + 1
                end = start
                while end < len(lines) and lines[end].startswith(b"  "):
                    end += 1
                result += [b"Resolved source packages:"] + sorted(lines[start:end])
                index = end
            else:
                result.append(lines[index])
                index += 1
        return b"\n".join(result)

    def without_ignored_keys(self, value):
        if isinstance(value, dict):
            return {key: f"<{len(item)} characters>" if isinstance(item, str) and key.endswith(self.length_only) and self.length_only
                    else self.without_ignored_keys(item) for key, item in value.items() if key not in self.ignored_keys}
        if isinstance(value, list):
            return [self.without_ignored_keys(item) for item in value]
        return value


def files(root):
    if not root.exists():
        return {}
    captures = capture_names(root)
    result = {}
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if path.is_file() and not path.is_symlink() and not IGNORED_PARTS.intersection(relative.parts) \
                and relative.name not in IGNORED_FILES and relative.name != ".DS_Store":
            folders = [root.joinpath(*relative.parts[:index + 1]) for index in range(len(relative.parts))]
            result[str(Path(*(captures.get(folder, folder.name) for folder in folders)))] = path
    return result


def capture_names(root):
    """Each codesign capture folder under `root`, named by the command line it captured and, for
    the same command line run again, by the order it ran in."""
    by_arguments = {}
    for folder in root.rglob("sign.*"):
        if folder.is_dir() and CAPTURE.match(folder.name) and (folder / "arguments").exists():
            key = (folder.parent, hashlib.sha256((folder / "arguments").read_bytes()).hexdigest()[:16])
            started = float((folder / "time").read_text()) if (folder / "time").exists() else 0
            by_arguments.setdefault(key, []).append((started, folder))
    names = {}
    for (_, digest), folders in by_arguments.items():
        for index, (_, folder) in enumerate(sorted(folders, key=lambda item: item[0])):
            names[folder] = f"sign.{digest}-{index}"
    return names


def compare_trees(baseline, candidate, normalize_baseline, normalize_candidate, suite=None):
    """(changed, only in baseline, only in candidate) relative paths."""
    old, new = files(baseline), files(candidate)
    for tree in (old, new):
        for name in [name for name in tree if (suite, name) in IGNORED_SUITE_FILES]:
            del tree[name]
    changed = []
    for name in sorted(old.keys() & new.keys()):
        varying = VARYING.get((suite, unit(name)), (None, None))[0]
        a = normalize_baseline(old[name], old[name].read_bytes(), baseline, varying, suite)
        b = normalize_candidate(new[name], new[name].read_bytes(), candidate, varying, suite)
        # loader-experiments keeps the last 8000 characters of standard error: where one side was
        # cut, it must be the end of the other.
        truncated = suite == "loader" and name.endswith(".stderr") and LOADER_STDERR_LIMIT in (
            len(old[name].read_text(errors="replace")), len(new[name].read_text(errors="replace")))
        if a != b and not (truncated and (a.endswith(b) or b.endswith(a))) and not input_times_only(a, b):
            changed.append(name)
    return changed, sorted(old.keys() - new.keys()), sorted(new.keys() - old.keys())


def input_times_only(a, b):
    """Whether two binaries differ only right before the path of an input an experiment wrote at
    run time (in its `src` or `source` folder): what Swift records of such an input, its bridging
    header for one, in a binary module and in a dSYM's copy of it (signing-experiments
    `symbols`, two runs with Xcode 27.0)."""
    if len(a) != len(b) or b"\0" not in a[:4096]:
        return False
    positions = [index for index in range(len(a)) if a[index] != b[index]]
    if not positions or len(positions) > 64:
        return False
    for position in positions:
        following = a[position:position + 24]
        start = following.find(b"/")
        if start < 0 or not re.match(rb"/[^\0]*/(src|source)/", a[position + start:position + start + 512]):
            return False
    return True


def capture_stem(path):
    """The capture a file of capture_reference.py's layout belongs to (`<stem>.json.cmd` → `<stem>`)."""
    name = re.sub(r"(\.json)?(\.txt)?(\.cmd|\.stderr)?$", "", path)
    return name


def scheme_refused_once(baseline, candidate, changed):
    """The scheme captures xcodebuild answered in one run and refused with 64 in the other: an
    extension's autocreated scheme, as B-015 and docs/VERIFICATION.md record for the loader's experiments
    (fuzz case 10's `Stickers`, B-097)."""
    refused = set()
    for path in changed:
        if path.endswith(".cmd") and path.startswith("settings/scheme-"):
            statuses = {json.loads((root / path).read_text()).get("exitStatus") for root in (baseline, candidate)}
            if statuses == {0, 64}:
                refused.add(capture_stem(path))
    return refused


def unit(path):
    """The experiment, app or case a relative path belongs to."""
    first = Path(path).parts[0]
    for suffix in (".dumpPIF.log", ".pif", ".json", ".txt"):
        if first.endswith(suffix):
            return first[: -len(suffix)]
    return first


def citations(suite, names):
    """For each experiment name, the lines of Tests, docs and Sources that cite it with its suite."""
    markers = SUITE_NAMES.get(suite, set())
    found = {name: [] for name in names}
    for folder in ("Tests", "docs", "Sources"):
        for path in sorted((REPO_ROOT / folder).rglob("*")):
            if path.suffix not in (".swift", ".md") or not path.is_file():
                continue
            lines = path.read_text(errors="replace").splitlines()
            for number, line in enumerate(lines):
                window = " ".join(lines[max(0, number - 2):number + 3])
                if not any(marker in window for marker in markers):
                    continue
                for name in names:
                    if f"`{name}`" in line or f'"{name}"' in line:
                        found[name].append(f"{path.relative_to(REPO_ROOT)}:{number + 1}")
    return found


def report(args):
    baseline, candidate = Path(args.baseline).expanduser(), Path(args.candidate).expanduser()
    runs = {side: json.loads((root / "run.json").read_text()) for side, root in (("baseline", baseline), ("candidate", candidate))}
    for side, root in (("baseline", baseline), ("candidate", candidate)):
        if (root / "probe.json").exists():
            runs[side]["sdks"] = json.loads((root / "probe.json").read_text()).get("sdks", [])
    normalize = {side: Normalizer(run) for side, run in runs.items()}
    nomac = args.nomac or runs["candidate"]["nomac"]
    profile = json.loads(subprocess.run([nomac, "sdk", "profile"], capture_output=True, text=True, check=True).stdout)
    probe = json.loads((candidate / "probe.json").read_text()) if (candidate / "probe.json").exists() else {}
    changed_profile, missing, unobserved = profile_changes(probe, profile)

    result = {"baseline": runs["baseline"], "candidate": runs["candidate"], "profile": changed_profile, "notObserved": missing, "rederive": unobserved,
              "experiments": {}, "varying": [], "references": {}, "fuzz": {}, "survey": {}, "failedSteps": []}
    for root in (baseline, candidate):
        for record in sorted((root / "steps").glob("*.json")):
            status = json.loads(record.read_text()).get("status")
            if status not in (0, None):
                result["failedSteps"].append(f"{root.name}/{record.stem}: {status}")

    for suite in SUITES:
        changed, removed, added = compare_trees(baseline / "experiments" / suite, candidate / "experiments" / suite,
                                                normalize["baseline"], normalize["candidate"], suite)
        listed = ("choice", "corpus")
        for name in sorted({unit(path) for path in changed if VARYING.get((suite, unit(path)), ("",))[0] in listed}):
            result["varying"].append(f"{suite} `{name}` ({VARYING[(suite, name)][1]})")
        changed = [path for path in changed if VARYING.get((suite, unit(path)), ("",))[0] not in listed]
        if changed or removed or added:
            units = sorted({unit(path) for path in changed + removed + added})
            result["experiments"][suite] = {"changed": changed, "onlyInBaseline": removed, "onlyInCandidate": added,
                                            "experiments": units, "citedBy": citations(suite, units)}

    references_baseline = baseline / "reference" if (baseline / "reference").exists() else Path(args.references).expanduser()
    apps = sorted({path.name for path in (candidate / "reference").glob("*") if path.is_dir()})
    with_builds = runs["candidate"].get("withBuilds")
    keys = IGNORED_KEYS if with_builds else IGNORED_KEYS | {"buildExitStatus", "archiveExitStatus", "exportExitStatus"}
    reference_normalize = {side: Normalizer(run, keys) for side, run in runs.items()}
    for app in apps:
        changed, removed, added = compare_trees(references_baseline / app, candidate / "reference" / app,
                                                reference_normalize["baseline"], reference_normalize["candidate"])
        if not with_builds:
            removed = [path for path in removed if Path(path).parts[0] not in ("build", "archive")]
        if changed or removed or added:
            result["references"][app] = {"changed": changed, "onlyInBaseline": removed, "onlyInCandidate": added}

    # The fuzzer keeps the captures of one case per class of difference with nomac, so the cases
    # both runs kept are compared.
    kept = lambda root: {path.parent.name for path in (root / "fuzz" / "cases").glob("*/ref")}
    for case in sorted(kept(baseline) & kept(candidate)):
        changed, removed, added = compare_trees(baseline / "fuzz" / "cases" / case / "ref", candidate / "fuzz" / "cases" / case / "ref",
                                                normalize["baseline"], normalize["candidate"])
        refused = scheme_refused_once(baseline / "fuzz" / "cases" / case / "ref", candidate / "fuzz" / "cases" / case / "ref", changed)
        for stem in sorted(refused):
            result["varying"].append(f"fuzz `{case}` `{stem}` (B-097)")
        changed = [path for path in changed if capture_stem(path) not in refused]
        if changed or removed or added:
            result["fuzz"][case] = {"changed": changed, "onlyInBaseline": removed, "onlyInCandidate": added}
    for side, root in (("baseline", baseline), ("candidate", candidate)):
        results = [json.loads(path.read_text()) for path in (root / "fuzz" / "cases").glob("*/result.json")]
        result["fuzz"].setdefault("identical", {})[side] = sum(1 for item in results if item.get("status") == "identical")
        summary = root / "survey" / "summary.json"
        if summary.exists():
            numbers = json.loads(summary.read_text())
            result["survey"][side] = {key: numbers.get(key) for key in ("projects", "inside", "coverage", "coverage95")}
    if result["fuzz"]["identical"]["baseline"] == result["fuzz"]["identical"]["candidate"]:
        del result["fuzz"]["identical"]
    if result["survey"].get("baseline") == result["survey"].get("candidate"):
        result["survey"] = {}

    result["noChange"] = not (result["profile"] or result["notObserved"] or result["experiments"] or result["references"] or result["fuzz"]
                              or result["survey"] or result["failedSteps"])
    (candidate / "report.json").write_text(json.dumps(result, indent=1, sort_keys=True) + "\n")
    (candidate / "REPORT.md").write_text(markdown(result))
    log(f"{'no change' if result['noChange'] else 'changes'}: {candidate / 'REPORT.md'}")
    return 0 if result["noChange"] else 1


def listing(paths, limit=12):
    shown = [f"`{path}`" for path in paths[:limit]]
    return ", ".join(shown) + (f" and {len(paths) - limit} more" if len(paths) > limit else "")


def markdown(result):
    old, new = result["baseline"], result["candidate"]
    lines = [f"# Xcode upgrade report: {old['xcode']['version']} ({old['xcode']['build']}) to {new['xcode']['version']} ({new['xcode']['build']})",
             "", f"Baseline `{old['developerDirectory']}` (nomac `{old['commit'][:12]}`), candidate `{new['developerDirectory']}` "
             f"(nomac `{new['commit'][:12]}`).", "", "**No change.**" if result["noChange"] else "**Changes found.**", ""]
    if result["failedSteps"]:
        lines += ["## Steps that failed", ""] + [f"- {step}" for step in result["failedSteps"]] + [""]
    lines += ["## Profile values to update (`Sources/NomacCore/XcodeProfile.swift`)", ""]
    if result["profile"]:
        lines += ["| Key | Profile | Observed |", "|---|---|---|"]
        lines += [f"| `{item['key']}` | `{item['profile']}` | `{item['observed']}` |" for item in result["profile"]]
    else:
        lines.append("None: every observed value is the profile's.")
    if result["notObserved"]:
        lines += ["", "Not observed by this run (its suite did not run, or the probe found nothing): "
                  + listing([key for key in result["notObserved"]], 20) + "."]
    lines += ["", "Derived, not observed: the pins by comparison (ADR 0005, ADR 0010, ADR 0100, ADR 0102), the closed condition kinds from package-experiments `conditions`: "
              + ", ".join(f"`{key}`" for key in result["rederive"]) + ".", "", "## Experiments whose outputs changed", ""]
    if not result["experiments"]:
        lines.append("None.")
    for suite, changes in sorted(result["experiments"].items()):
        lines += [f"### {suite}", ""]
        for name in changes["experiments"]:
            cited = changes["citedBy"].get(name) or []
            lines.append(f"- `{name}`" + (f": re-derive {listing(cited, 8)}" if cited else ": cited nowhere"))
        for label, key in (("Changed", "changed"), ("Only in the baseline", "onlyInBaseline"), ("Only in the candidate", "onlyInCandidate")):
            if changes[key]:
                lines.append(f"- {label}: {listing(changes[key])}")
        lines.append("")
    if result["varying"]:
        lines += ["", "Different again, as from one run to the next with one Xcode (not compared): "
                  + ", ".join(result["varying"]) + ".", ""]
    lines += ["", "## Corpus references that changed", ""]
    if not result["references"]:
        lines.append("None.")
    for app, changes in sorted(result["references"].items()):
        lines.append(f"- {app}: " + "; ".join(f"{label} {listing(changes[key])}" for label, key in
                                              (("changed", "changed"), ("only in the baseline", "onlyInBaseline"), ("only in the candidate", "onlyInCandidate"))
                                              if changes[key]))
    lines += ["", "## Fuzz cases whose Xcode outputs changed", ""]
    if not result["fuzz"]:
        lines.append("None.")
    for case, changes in sorted(result["fuzz"].items()):
        lines.append(f"- {case}: {json.dumps(changes)}" if case == "identical" else f"- {case}: {listing(changes['changed'] + changes['onlyInBaseline'] + changes['onlyInCandidate'])}")
    lines += ["", "## Coverage survey", "", f"Changed: `{json.dumps(result['survey'])}`." if result["survey"] else "Unchanged.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run")
    run.add_argument("--developer-dir", default=os.environ.get("DEVELOPER_DIR"))
    run.add_argument("--out")
    run.add_argument("--nomac", default=str(DEFAULT_NOMAC))
    run.add_argument("--steps", help=f"comma-separated, of {','.join(STEPS)}")
    run.add_argument("--suites", help=f"comma-separated, of {','.join(SUITES)}")
    run.add_argument("--apps", help="comma-separated corpus app ids (default: every app of corpus/corpus.json)")
    run.add_argument("--work", default=DEFAULT_WORK, help="the corpus checkouts (capture_reference.py --work)")
    run.add_argument("--with-builds", action="store_true", help="capture the references with their builds")
    run.add_argument("--fuzz-cases", type=int, default=100)
    run.add_argument("--survey", default=str(DEFAULT_SURVEY), help="a feature_survey.py folder whose repositories to check")
    run.add_argument("--force", action="store_true", help="run steps an earlier run finished again")
    compare = commands.add_parser("report")
    compare.add_argument("--baseline", required=True)
    compare.add_argument("--candidate", required=True)
    compare.add_argument("--references", default=str(Path.home() / "nomac-out" / "reference"),
                         help="the current Xcode's corpus references, when the baseline run has none")
    compare.add_argument("--nomac", help="the nomac whose profile to compare (default: the candidate run's)")
    args = parser.parse_args()
    if args.command == "run":
        if not args.developer_dir:
            parser.error("give --developer-dir or set DEVELOPER_DIR")
        Run(args).main()
        return 0
    return report(args)


if __name__ == "__main__":
    sys.exit(main())

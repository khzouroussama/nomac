#!/usr/bin/env python3
"""Every asset catalog of the corpus, the holdout and the React Native and Expo sweep, compiled by
actool and by nomac on the same command line, ranked by what stops or changes the most apps.

The command lines are the ones Xcode ran where a build log exists: the corpus's reference builds
(`~/nomac-out/reference/<app>/build/build.log`) and the sweep's Linux builds
(`~/nomac-out/sweep/results/<app>/build.log.gz`). signal, the holdout and the sweep's apps that never
reached a build have no build log: each of their catalogs is compiled alone, with the app icon,
accent color, widget background color and deployment target their captured build settings give, or
their project files when none was captured. Catalogs of tvOS targets, by their path, are left out:
nomac builds iOS apps (BACKLOG B-206). Catalogs `expo prebuild` writes, and those of the Expo
packages, come from one shared install under <root>/expo (the sweep's npm date).

  catalog_sweep.py fetch <root>                  the catalogs of the sweep and the sample, from the apps' repositories
  catalog_sweep.py tasks <root>                  writes <root>/tasks.json
  catalog_sweep.py run <root> --nomac <nomac>    [--set S] [--app A] [--only refused,different] [--jobs N]
  catalog_sweep.py recompare <root>              compares the kept outputs again
  catalog_sweep.py report <root>                 the counts, the refusals and the causes of differences

The set `sample` is the coverage survey's repeatable sample of open-source projects
(`feature_survey.py catalogs --sample 60`, its results in <survey>/catalogs), each catalog compiled
alone on that step's command line, as a build for iOS 15. Its count is the projects whose catalogs
all compile.

actool's outputs are kept in <root>/actool, keyed by the command line, and reused; nomac's stay in
<root>/nomac for catalogs that do not match. Outputs stay outside the repository.
"""

import argparse
import collections
import concurrent.futures
import gzip
import hashlib
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

import assets_experiments as ae
import pdf_experiments as pe

HOME = Path.home()
CORPUS = Path("/tmp/nomac-corpus")
HOLDOUT = Path("/tmp/nomac-holdout")
REFERENCE = HOME / "nomac-out/reference"
HOLDOUT_REFERENCE = HOME / "nomac-out/holdout/reference"
SWEEP_RESULTS = HOME / "nomac-out/sweep/results"
SURVEY = HOME / "nomac-out/survey-20261106"
SWEEP_PREFIX = re.compile(r"^.*?/sweep/apps/")
CHECKOUTS = re.compile(r"/SourcePackages/checkouts/")
NODE_MODULE = re.compile(r"^.*?/node_modules/")
TV_TARGET = re.compile(r"tvOS|[ /_-]TV\b|appletv", re.I)
PACKAGE_COPY = re.compile(r"/packages/([^/]+)/")
MANIFEST = Path(__file__).resolve().parents[2] / "corpus/rn-sweep.json"
OUTPUTS = {"--compile", "--export-dependency-info", "--output-partial-info-plist",
           "--generate-swift-asset-symbols", "--generate-objc-asset-symbols", "--generate-asset-symbol-index"}
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer"))


def actool_lines(text):
    for line in text.splitlines():
        if line.startswith("    ") and "/usr/bin/actool " in line:
            args = shlex.split(line.strip())[1:]
            if "--compile" in args or any(a.startswith("--generate-") for a in args):
                yield args


def without_outputs(args):
    kept, skip = [], False
    for arg in args:
        if not skip and arg not in OUTPUTS:
            kept.append(arg)
        skip = not skip and arg in OUTPUTS
    return kept


def task(app_set, app, args, kind=None):
    stripped = without_outputs(args)
    outputs = [a for a in args if a in OUTPUTS]
    return {"set": app_set, "app": app, "args": stripped, "outputs": outputs,
            "kind": kind or ("compile" if "--compile" in outputs else "symbols"),
            "catalogs": [a for a in stripped if a.endswith((".xcassets", ".icon"))],
            "key": hashlib.sha256(json.dumps([stripped, outputs]).encode()).hexdigest()[:16]}


def logged_tasks(app_set, app, text, rewrite=lambda a: a):
    seen = {}
    for args in actool_lines(text):
        made = task(app_set, app, [rewrite(a) for a in args])
        seen.setdefault(made["key"], made)
    return list(seen.values())


def setting_values(pbxproj, name):
    return re.findall(rf'{name} = "?([^";]+)"?;', pbxproj)


def captured_settings(app):
    """Each target's build settings from the holdout's capture, as (settings, ...)."""
    found = []
    for path in (HOLDOUT_REFERENCE / app / "settings").glob("*.json"):
        try:
            found += [t.get("buildSettings", {}) for t in json.loads(path.read_text())]
        except (ValueError, AttributeError):
            pass
    return found


def alone_tasks(app_set, app, top):
    settings = captured_settings(app)
    pbxprojs = "".join(p.read_text(errors="replace") for p in top.glob("**/*.xcodeproj/project.pbxproj")
                       if "/Pods/" not in str(p))

    def values(name):
        got = [s[name] for s in settings if s.get(name)]
        return got or setting_values(pbxprojs, name)

    targets = [v for v in values("IPHONEOS_DEPLOYMENT_TARGET") if re.fullmatch(r"[\d.]+", v)]
    deployment = collections.Counter(targets).most_common(1)[0][0] if targets else "16.0"
    tasks = []
    for catalog in sorted(top.glob("**/*.xcassets")):
        if any(part in ("DerivedData", "node_modules", "build") for part in catalog.parts) or not (catalog / "Contents.json").exists():
            continue
        if TV_TARGET.search(str(catalog.relative_to(top))):
            continue
        members = {p.name for p in catalog.glob("**/*") if p.is_dir()}
        watch = re.search(r"watch", str(catalog.relative_to(top)), re.I)
        args = [str(catalog), "--output-format", "human-readable-text", "--notices", "--warnings", "--compress-pngs",
                "--enable-on-demand-resources", "YES", "--development-region", "en"]
        if watch:
            args += ["--target-device", "watch", "--minimum-deployment-target", "10.0", "--platform", "watchos"]
        else:
            args += ["--target-device", "iphone", "--target-device", "ipad", "--minimum-deployment-target", deployment, "--platform", "iphoneos"]
        for option, setting, suffix in (("--app-icon", "ASSETCATALOG_COMPILER_APPICON_NAME", ".appiconset"),
                                        ("--accent-color", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", ".colorset"),
                                        ("--widget-background-color", "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME", ".colorset")):
            for name in sorted(set(values(setting))):
                if name + suffix in members:
                    args += [option, name]
                    break
        if any(s == "YES" for s in values("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS")) and "--app-icon" in args:
            args.append("--include-all-app-icons")
        tasks.append(task(app_set, app, args + ["--compile", "OUT", "--export-dependency-info", "OUT",
                                                "--output-partial-info-plist", "OUT"]))
    return tasks


def sparse_checkout(target, repository, commit):
    target.mkdir(parents=True, exist_ok=True)
    git = ["git", "-C", str(target), "-c", "http.version=HTTP/1.1"]
    steps = (["init", "-q"], ["remote", "add", "origin", repository],
             ["sparse-checkout", "set", "--no-cone", "*.xcassets/"],
             ["fetch", "-q", "--depth=1", "--filter=blob:none", "origin", commit],
             ["checkout", "-q", "--detach", "FETCH_HEAD"])
    for step in steps:
        done = subprocess.run(git + step, capture_output=True, text=True, timeout=900)
        if done.returncode and step[0] != "remote":
            shutil.rmtree(target, ignore_errors=True)
            return False
    return True


def resolved_pins(top):
    """{checkout name: (repository, revision)} of a checkout's Package.resolved files."""
    pins = {}
    for path in top.glob("**/Package.resolved"):
        try:
            data = json.loads(path.read_text())
        except ValueError:
            continue
        for pin in data.get("pins") or data.get("object", {}).get("pins", []):
            location = pin.get("location") or pin.get("repositoryURL")
            revision = pin.get("state", {}).get("revision")
            if location and revision:
                pins[location.rstrip("/").removesuffix(".git").rsplit("/", 1)[-1].lower()] = (location, revision)
    return pins


def fetch(root):
    """Sparse checkouts holding only the catalogs: the sweep's apps at the manifest's commits and
    the packages whose catalogs the corpus's logs name, at their pins."""
    manifest = json.loads(MANIFEST.read_text())
    apps = root / "sweep-apps"
    missing = []
    for entry in manifest["apps"]:
        target = apps / entry["id"]
        if entry.get("source") or (target / ".git").exists():
            continue
        if sparse_checkout(target, entry["repository"], entry["commit"]):
            print(entry["id"], sum(1 for _ in target.glob("**/*.xcassets")), flush=True)
        else:
            missing.append(entry["id"])
    for result in sorted((SURVEY / "catalogs").glob("*.json")):
        target = root / "sample" / result.stem
        repository = SURVEY / "repos" / result.stem
        if (target / ".git").exists():
            continue
        url = subprocess.run(["git", "-C", str(repository), "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
        commit = subprocess.run(["git", "-C", str(repository), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if not sparse_checkout(target, url, commit):
            missing.append(result.stem)
    for made in json.loads((root / "tasks.json").read_text()):
        for catalog in made["catalogs"]:
            found = PACKAGE_COPY.search(catalog)
            if made["set"] != "corpus" or Path(catalog).exists() or not found:
                continue
            target = root / "packages" / found.group(1)
            if (target / ".git").exists():
                continue
            pin = resolved_pins(CORPUS / made["app"]).get(found.group(1).lower())
            if not pin or not sparse_checkout(target, *pin):
                missing.append(found.group(1))
    print("not fetched:", missing)


def make_tasks(root):
    tasks = []
    def package_copy(arg):
        if CHECKOUTS.search(arg) and not Path(arg).exists():
            return str(root / "packages" / CHECKOUTS.split(arg, maxsplit=1)[1])
        return arg

    for log in sorted(REFERENCE.glob("*/build/build.log")):
        tasks += logged_tasks("corpus", log.parents[1].name, log.read_text(errors="replace"), package_copy)
    for app in sorted(p.name for p in REFERENCE.iterdir()):
        if not (REFERENCE / app / "build/build.log").exists() and (CORPUS / app).is_dir():
            tasks += alone_tasks("corpus", app, CORPUS / app)
    for top in sorted(p for p in HOLDOUT.iterdir() if p.is_dir()):
        tasks += alone_tasks("holdout", top.name, top)
    apps = root / "sweep-apps"

    def installed_package(arg):
        shared = root / "expo" / NODE_MODULE.sub("node_modules/", arg)
        return str(shared) if NODE_MODULE.search(arg) and shared.exists() else arg

    for log in sorted(SWEEP_RESULTS.glob("*/build.log.gz")):
        app = log.parent.name
        text = gzip.open(log, "rt", errors="replace").read()
        tasks += logged_tasks("sweep", app, text, lambda a: installed_package(SWEEP_PREFIX.sub(str(apps) + "/", a)))
    logged = {t["app"] for t in tasks if t["set"] == "sweep"}
    for top in sorted(p for p in apps.iterdir() if p.is_dir() and p.name not in logged):
        tasks += alone_tasks("sweep", top.name, top)
    for result in sorted((SURVEY / "catalogs").glob("*.json")):
        for relative in sorted(json.loads(result.read_text())["catalogs"]):
            catalog = root / "sample" / result.stem / relative
            args = [str(catalog), "--platform", "iphoneos", "--minimum-deployment-target", "15.0", "--target-device", "iphone",
                    "--target-device", "ipad", "--compress-pngs", "--output-format", "human-readable-text"]
            if (catalog / "AppIcon.appiconset").is_dir():
                args += ["--app-icon", "AppIcon"]
            tasks.append(task("sample", result.stem, args + ["--compile", "OUT", "--output-partial-info-plist", "OUT"]))
    for task_ in tasks:
        task_["present"] = all(Path(c).exists() for c in task_["catalogs"]) and bool(task_["catalogs"])
    ae.write_json(root / "tasks.json", tasks)
    counts = collections.Counter((t["set"], t["kind"], t["present"]) for t in tasks)
    for key, count in sorted(counts.items()):
        print(key, count)


def run_tool(tool, made, out, env=None):
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    started = time.monotonic()
    names = {"--compile": "", "--export-dependency-info": "deps", "--output-partial-info-plist": "partial.plist",
             "--generate-swift-asset-symbols": "symbols.swift", "--generate-objc-asset-symbols": "symbols.h",
             "--generate-asset-symbol-index": "symbols.plist"}
    outputs = []
    for option in made["outputs"]:
        outputs += [option, str(out / names[option]) if names[option] else str(out)]
    try:
        done = subprocess.run(tool + made["args"] + outputs, capture_output=True, text=True, env=env, timeout=3600)
        status, stdout, stderr = done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired:
        status, stdout, stderr = 124, "", "timed out"
    (out / "stdout.txt").write_text(stdout)
    (out / "stderr.txt").write_text(stderr)
    (out / "status").write_text(str(status))
    (out / "seconds").write_text(f"{time.monotonic() - started:.1f}")
    return out


def rendition_kind(block):
    return block[24:28].decode("latin-1").strip() or "?"


def rendition_name(block):
    return block[40:168].rstrip(b"\0").decode("utf-8", "replace")


def car_causes(x, y, converted):
    """What keeps the two files from matching under ADR 0204, with a few rendition names."""
    x, y, _ = pe.with_alike_pdfs(x, y)
    a, va = ae.bom(x)
    b, vb = ae.bom(y)
    if dict(va).keys() != dict(vb).keys():
        return ["tables " + ",".join(sorted(dict(va).keys() ^ dict(vb).keys()))], []
    blocks = ae.pixel_car_blocks(x, y, converted)
    if blocks is None:
        return [f"layout: {len(a)} and {len(b)} blocks"], []
    names = {index: name for name, index in va}
    causes, samples = collections.Counter(), []
    for index in blocks[1]:
        p, q = a[index], b[index]
        if p[:4] != b"ISTC":
            causes[names.get(index, "other block")] += 1
            continue
        kind = rendition_kind(p)
        if p[:168] != q[:168]:
            part = "header"
        elif p[168:180] != q[168:180] or len(p) < 184 or p[184:184 + struct.unpack_from("<I", p, 168)[0]] != q[184:184 + struct.unpack_from("<I", q, 168)[0]]:
            part = "properties"
        else:
            part = "payload"
        causes[f"{kind} {part}"] += 1
        if len(samples) < 12:
            samples.append(f"{kind} {part} {rendition_name(p)}")
    return [f"{name} x{count}" for name, count in causes.most_common()], samples


def car_verdict(x, y, converted):
    if x == y:
        return "identical", [], []
    try:
        if b"iconstack" in x and ae.compare_icon_car(x, y) != "different":
            return ae.compare_icon_car(x, y), [], []
        verdict = pe.compare_car(x, y, converted)
        return (verdict, *(([], []) if verdict != "different" else car_causes(x, y, converted)))
    except (AssertionError, struct.error, KeyError, ValueError, IndexError) as error:
        return "different", [f"unreadable car: {type(error).__name__}"], []


def single_size_icon(args, catalogs):
    """Whether `--app-icon` names a set of one 1,024-point image, whose PNGs actool resizes (ADR 0204)."""
    if "--app-icon" not in args:
        return False
    name = args[args.index("--app-icon") + 1]
    for catalog in catalogs:
        for contents in Path(catalog).glob(f"**/{name}.appiconset/Contents.json"):
            sizes = {e.get("size") for e in json.loads(contents.read_text()).get("images", []) if e.get("filename")}
            return sizes == {"1024x1024"}
    return False


def compare(actool, nomac, args, catalogs):
    verdicts = {}
    causes, samples = [], []
    converted = ae.converted_files(c for c in catalogs if c.endswith(".xcassets"))
    names = {p.relative_to(d).as_posix() for d in (actool, nomac) for p in d.glob("**/*")
             if p.is_file() and p.name not in ("stderr.txt", "status", "seconds")}
    car = (actool / "Assets.car").read_bytes() if (actool / "Assets.car").exists() else b""
    resized = single_size_icon(args, catalogs)
    for name in sorted(names):
        a, n = actool / name, nomac / name
        if not a.exists() or not n.exists():
            verdicts[name] = "only in " + ("nomac" if not a.exists() else "actool")
            causes.append(f"{Path(name).suffix or name}: {verdicts[name]}")
            continue
        x, y = a.read_bytes(), n.read_bytes()
        if name == "Assets.car":
            verdicts[name], found, samples = car_verdict(x, y, converted)
            causes += found
            continue
        if name in ("deps", "stdout.txt", "partial.plist"):
            x = ae.sorted_document_warnings(x.replace(str(actool).encode(), b"OUT"))
            y = ae.sorted_document_warnings(y.replace(str(nomac).encode(), b"OUT"))
        if x == y:
            verdicts[name] = "identical"
        elif name.endswith(".png") and (converted or resized or b"iconstack" in car or b"RGBW" in car) and ae.png_chunks(x) == ae.png_chunks(y):
            verdicts[name] = "equivalent"
        elif name.endswith((".swift", ".h", ".plist")) and name.startswith("symbols") and sorted(x.splitlines()) == sorted(y.splitlines()):
            verdicts[name] = "equivalent"
        else:
            verdicts[name] = "different"
            causes.append(f"{Path(name).suffix or name} differs")
    values = set(verdicts.values())
    if "different" in values or any(v.startswith("only") for v in values):
        return "different", causes, samples
    return ("equivalent" if "equivalent" in values else "identical"), [], []


def refusal(nomac):
    lines = (nomac / "stderr.txt").read_text(errors="replace").strip().splitlines()
    errors = [line for line in lines if "error:" in line]
    return errors[-1] if errors else (lines[-1] if lines else "no message")


def normalized(message):
    message = re.sub(r"^.*?error: ", "", message)
    return re.sub(r"/\S+/", "", message)[:160]


def measure(root, nomac, made):
    if not made["present"]:
        return {**made, "status": "input missing"}
    actool = root / "actool" / made["key"]
    if not (actool / "status").exists():
        run_tool(["xcrun", "actool"], made, actool, ENV)
    mine = root / "nomac" / made["key"]
    run_tool([nomac, "actool"], made, mine)
    tool_status = int((actool / "status").read_text())
    nomac_status = int((mine / "status").read_text())
    result = {**made, "actool": tool_status, "nomac": nomac_status, "seconds": float((mine / "seconds").read_text())}
    if nomac_status == 124:
        result["status"], result["message"] = "refused", "timed out"
    elif nomac_status and not tool_status:
        result["status"], result["message"] = "refused", refusal(mine)
    elif tool_status and not nomac_status:
        result["status"], result["causes"] = "different", ["actool stopped, nomac did not"]
    elif tool_status:
        result["status"] = "both stop"
    else:
        result["status"], result["causes"], result["samples"] = compare(actool, mine, made["args"], made["catalogs"])
    if result["status"] in ("identical", "equivalent", "both stop"):
        shutil.rmtree(mine, ignore_errors=True)
    return result


def recompare(root):
    """The comparison again on the outputs kept, after a change of its rules."""
    path = root / "results.json"
    results = json.loads(path.read_text())
    for result in results.values():
        mine = root / "nomac" / result["key"]
        if result["status"] == "different" and mine.exists():
            result["status"], result["causes"], result["samples"] = compare(root / "actool" / result["key"], mine, result["args"], result["catalogs"])
    ae.write_json(path, results)
    report(root)


def run(root, nomac, sets, apps, only, jobs):
    tasks = json.loads((root / "tasks.json").read_text())
    results_path = root / "results.json"
    results = json.loads(results_path.read_text()) if results_path.exists() else {}
    todo = [t for t in tasks
            if (not sets or t["set"] in sets) and (not apps or t["app"] in apps)
            and (t["key"] not in results if not only else results.get(t["key"], {}).get("status") in only)]
    print(len(todo), "tasks", flush=True)
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        for count, result in enumerate(pool.map(lambda t: measure(root, nomac, t), todo), 1):
            results[result["key"]] = result
            if count % 20 == 0:
                ae.write_json(results_path, results)
                print(count, flush=True)
    ae.write_json(results_path, results)
    report(root)


def report(root):
    results = list(json.loads((root / "results.json").read_text()).values())
    for app_set in ("corpus", "holdout", "sweep", "sample"):
        members = [r for r in results if r["set"] == app_set]
        counts = collections.Counter(r["status"] for r in members)
        apps = {r["app"] for r in members}
        refused = {r["app"] for r in members if r["status"] == "refused"}
        different = {r["app"] for r in members if r["status"] == "different"}
        print(f"{app_set}: {len(members)} tasks in {len(apps)} apps, {dict(sorted(counts.items()))}; "
              f"{len(apps - refused)} apps compile all, {len(apps - refused - different)} match actool")
    slowest = sorted((r for r in results if "seconds" in r), key=lambda r: -r["seconds"])[:5]
    print("slowest:", ", ".join(f"{r['app']} {r['seconds']:.0f} s" for r in slowest))
    for status, describe in (("refused", lambda r: normalized(r.get("message", ""))),
                             ("different", lambda r: "; ".join(r.get("causes", []))[:160])):
        groups = collections.defaultdict(list)
        for result in results:
            if result["status"] == status:
                groups[describe(result)].append(result)
        print(f"\n{status}:")
        for cause, members in sorted(groups.items(), key=lambda kv: (-len({r["app"] for r in kv[1]}), -len(kv[1]))):
            print(f"{len({r['app'] for r in members}):3d} apps {len(members):3d} tasks  {cause}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("fetch", "tasks", "run", "recompare", "report"))
    parser.add_argument("root", type=Path)
    parser.add_argument("--nomac")
    parser.add_argument("--set", action="append", default=[])
    parser.add_argument("--app", action="append", default=[])
    parser.add_argument("--only", default="")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    if args.command == "fetch":
        fetch(args.root)
    elif args.command == "tasks":
        make_tasks(args.root)
    elif args.command == "run":
        run(args.root, args.nomac, args.set, args.app, set(filter(None, args.only.split(","))), args.jobs)
    elif args.command == "recompare":
        recompare(args.root)
    else:
        report(args.root)


if __name__ == "__main__":
    sys.exit(main())

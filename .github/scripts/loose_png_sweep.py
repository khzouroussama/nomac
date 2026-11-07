#!/usr/bin/env python3
"""Loose PNGs that build phases copy, in the corpus, the holdout and the coverage survey's sample of
60 projects: Xcode's copypng and nomac's on Xcode's command line (`copypng -compress
-strip-PNG-text`), compared byte for byte. A file is taken as copied when a project's Resources phase
names it (`<name> in Resources`) and it does not lie in an asset catalog; synchronized folders are
not looked at.

  loose_png_sweep.py files <root>                   lists them, fetching the sample's from GitHub
  loose_png_sweep.py run <root> --nomac <nomac>     [--tag T] [--jobs 2]
  loose_png_sweep.py report <root>                  [--tag T]
"""

import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

HOME = Path.home()
SURVEY = HOME / "nomac-out/survey-20261106"
ENV = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode_27.app/Contents/Developer")
NAMED = re.compile(r"/\* ([^*\n]+?\.png) in Resources \*/", re.I)
OPTIONS = ["-compress", "-strip-PNG-text"]


def named_in_projects(top):
    names = set()
    for path in top.glob("**/*.xcodeproj/project.pbxproj"):
        names.update(NAMED.findall(path.read_text(errors="replace")))
    return names


def wanted(relative, names):
    return Path(relative).name in names and ".xcassets/" not in relative and "/.git/" not in relative


def tree_files(top):
    return [str(p.relative_to(top)) for p in top.glob("**/*") if p.suffix.lower() == ".png" and p.is_file()]


def fetch_sample(root, name, names):
    target = root / "sample" / name
    listing = subprocess.run(["git", "-C", str(target), "ls-tree", "-r", "--name-only", "-z", "HEAD"], capture_output=True, text=True)
    paths = [p for p in listing.stdout.split("\0") if p and wanted(p, names)]
    if not paths:
        return [], True
    patterns = ["*.xcassets/"] + ["/" + re.sub(r"([\\*?\[\]!# ])", r"\\\1", p) for p in paths]
    done = subprocess.run(["git", "-C", str(target), "-c", "http.version=HTTP/1.1", "sparse-checkout", "set", "--no-cone", "--stdin"],
                          input="\n".join(patterns) + "\n", capture_output=True, text=True, timeout=1200)
    return [p for p in paths if (target / p).is_file()], done.returncode == 0


def files(root):
    found, unfetched = [], []
    for app_set, parent in (("corpus", Path("/tmp/nomac-corpus")), ("holdout", Path("/tmp/nomac-holdout"))):
        for top in sorted(p for p in parent.iterdir() if p.is_dir() and not p.name.endswith("-DerivedData")):
            names = named_in_projects(top)
            found += [{"set": app_set, "app": top.name, "path": str(top / p)} for p in tree_files(top) if wanted(p, names)]
    for result in sorted((SURVEY / "catalogs").glob("*.json")):
        names = named_in_projects(SURVEY / "repos" / result.stem)
        if not names:
            continue
        paths, ok = fetch_sample(root, result.stem, names)
        if not ok:
            unfetched.append(result.stem)
        found += [{"set": "sample", "app": result.stem, "path": str(root / "sample" / result.stem / p)} for p in paths]
        print(result.stem, len(paths), flush=True)
    (root / "loose-pngs.json").write_text(json.dumps(found, indent=1))
    counts = collections.Counter(f["set"] for f in found)
    print(dict(counts), {s: len({f["app"] for f in found if f["set"] == s}) for s in counts}, "not fetched:", unfetched)


def chunks(data):
    out, o = [], 8
    while data[:4] == b"\x89PNG" and o + 8 <= len(data):
        n, t = struct.unpack_from(">I4s", data, o)
        out.append((t.decode("latin-1"), data[o + 8:o + 8 + n]))
        o += 12 + n
    return out


def form(data):
    """Depth, color type and interlacing of a PNG, for naming a family."""
    if data[:4] != b"\x89PNG" or len(data) < 33:
        return "not a PNG"
    return f"depth {data[24]} type {data[25]}{' interlaced' if data[28] else ''}"


def cause(input_data, x, y):
    a, b = chunks(x), chunks(y)
    ta, tb = [t for t, _ in a], [t for t, _ in b]
    if ta != tb:
        return f"chunks: {','.join(ta)[:50]} / {','.join(tb)[:50]}"
    different = sorted({t for (t, p), (_, q) in zip(a, b) if p != q})
    return "bytes of " + ",".join(different) if different else "bytes outside chunks"


def measure(item, nomac, cache):
    data = Path(item["path"]).read_bytes()
    key = hashlib.sha256(data).hexdigest()[:24]
    known = cache / (key + ".png")
    with tempfile.TemporaryDirectory(dir=cache) as work:
        if not (cache / (key + ".done")).exists():
            run = subprocess.run(["xcrun", "copypng", *OPTIONS, item["path"], work + "/x.png"], capture_output=True, text=True, env=ENV)
            if Path(work + "/x.png").exists():
                shutil.copy(work + "/x.png", known)
            (cache / (key + ".done")).write_text(f"{run.returncode}\n{run.stdout[:400]}")
        apple_status = int((cache / (key + ".done")).read_text().split("\n")[0])
        apple = known.read_bytes() if known.exists() else None
        run = subprocess.run([nomac, "copypng", *OPTIONS, item["path"], work + "/n.png"], capture_output=True, text=True)
        mine = Path(work + "/n.png").read_bytes() if Path(work + "/n.png").exists() else None
    result = {**item, "form": form(data), "size": len(data)}
    if run.returncode:
        message = (run.stderr.strip().splitlines() or ["?"])[-1]
        result.update(status="refused", cause=re.sub(r"^.*?error: ", "", message)[:110], apple=apple_status)
    elif mine == apple:
        result["status"] = "identical"
    elif apple is None or mine is None:
        result.update(status="different", cause="file only from " + ("nomac" if apple is None else "copypng"))
    else:
        result.update(status="different", cause=cause(data, apple, mine))
    return result


def run_all(root, nomac, tag, jobs):
    items = json.loads((root / "loose-pngs.json").read_text())
    cache = root / "copypng-cache"
    cache.mkdir(exist_ok=True)
    out = []
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        for count, result in enumerate(pool.map(lambda i: measure(i, nomac, cache), items), 1):
            out.append(result)
            if count % 500 == 0:
                print(count, flush=True)
                (root / f"loose-results-{tag}.json").write_text(json.dumps(out))
    (root / f"loose-results-{tag}.json").write_text(json.dumps(out))
    report(root, tag)


def report(root, tag):
    results = json.loads((root / f"loose-results-{tag}.json").read_text())
    for app_set in ("corpus", "holdout", "sample"):
        members = [r for r in results if r["set"] == app_set]
        apps = {r["app"] for r in members}
        refused = {r["app"] for r in members if r["status"] == "refused"}
        different = {r["app"] for r in members if r["status"] == "different"}
        counts = collections.Counter(r["status"] for r in members)
        print(f"{app_set}: {len(members)} PNGs in {len(apps)} apps, {dict(counts)}; {len(refused)} apps stopped, {len(different - refused)} more differ")
    for status in ("refused", "different"):
        groups = collections.defaultdict(list)
        for r in results:
            if r["status"] == status:
                groups[(r.get("cause", ""), r["form"] if status == "different" else "")].append(r)
        print(f"\n{status}:")
        for (name, shape), members in sorted(groups.items(), key=lambda kv: (-len({m["app"] for m in kv[1]}), -len(kv[1])))[:24]:
            print(f"{len({m['app'] for m in members}):3d} apps {len(members):5d} files  {shape}  {name}"[:170])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("files", "run", "report"))
    parser.add_argument("root", type=Path)
    parser.add_argument("--nomac")
    parser.add_argument("--tag", default="now")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.command == "files":
        files(args.root)
    elif args.command == "run":
        run_all(args.root, args.nomac, args.tag, args.jobs)
    else:
        report(args.root, args.tag)


if __name__ == "__main__":
    main()

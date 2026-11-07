#!/usr/bin/env python3
"""Measure `nomac momc` on the Core Data models of a checkout tree, against Xcode 27.0's momc.

The models come from the repositories of the coverage survey (feature_survey.py, docs/PROGRESS.md),
sparse-checked out at the survey's commits under one directory. Nothing read or written here enters
the repository: observations stay outside it.

    coredata_survey.py features <repositories>                  what the versions use, B-257's list
    coredata_survey.py observe <repositories> <observations>    momc's outputs for every model (Mac)
    coredata_survey.py compare <repositories> <observations> <nomac> [substring]

`observe` runs the three commands a build runs (compile, dry run, generate, at the paths the models
are at, since momc's order of versions depends on them) and keeps one JSON per model. `compare` runs
nomac's momc on each and sorts the models: identical or equivalent as coredata_compare.py defines
it, refused (by nomac's message without names), different (nomac wrote something else), or failing
in momc too. Refusing a model momc compiles is the safe failure; "different" is the one that matters.
"""

import base64
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coredata_compare as compare  # noqa: E402
import coredata_experiments as experiments  # noqa: E402

ARGUMENTS = ["--iphoneos-deployment-target", "27.0", "--module", "T"]
GENERATE = ["--action", "generate", "--swift-version", "5.0"]


def models(root):
    """Each repository's .xcdatamodeld, and its .xcdatamodel outside one, in path order."""
    found = []

    def walk(directory):
        for child in sorted(directory.iterdir(), key=lambda p: p.name):
            if not child.is_dir() or child.name == ".git":
                continue
            if child.suffix in (".xcdatamodeld", ".xcdatamodel"):
                found.append(child)
            else:
                walk(child)
    for repository in sorted(p for p in root.iterdir() if p.is_dir()):
        walk(repository)
    return found


def key(path):
    return hashlib.sha1(str(path).encode()).hexdigest()


def run(command, out):
    out.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(command, capture_output=True, timeout=300)
    files = {str(p.relative_to(out)): base64.b64encode(p.read_bytes()).decode() for p in sorted(out.rglob("*")) if p.is_file()}
    return {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"), "stderr": proc.stderr.decode(errors="replace"), "files": files}


def outputs(tool, path, sdk):
    """What a build's three commands make of the model, each in a new directory."""
    with tempfile.TemporaryDirectory() as temporary:
        out = Path(temporary)
        common = [*tool, "--sdkroot", sdk, *ARGUMENTS]
        return {
            "compile": run([*common, str(path), str(out / "compile")], out / "compile"),
            "dry-run": run([*tool, "--dry-run", *GENERATE, "--sdkroot", sdk, *ARGUMENTS, str(path), "/out"], out / "dry-run"),
            "generate": run([*tool, *GENERATE, "--sdkroot", sdk, *ARGUMENTS, str(path), str(out / "generate")], out / "generate"),
        }


def observe(root, observations):
    observations.mkdir(parents=True, exist_ok=True)
    sdk = experiments.sdk()
    momc = subprocess.run(["xcrun", "--find", "momc"], capture_output=True, text=True, check=True).stdout.strip()
    pending = [path for path in models(root) if not (observations / f"{key(path)}.json").exists()]

    def one(path):
        record = {"path": str(path), **outputs([momc], path, sdk)}
        (observations / f"{key(path)}.json").write_text(json.dumps(record))
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(one, pending))
    print(f"{len(pending)} models observed")


CREATED = re.compile(rb"^//  Created by .* on \d+/\d+/\d+\.$", re.M)


def message(stderr):
    """nomac's refusal without the model's own names, so that equal reasons count together."""
    text = stderr.strip().split("error: ")[-1].splitlines()[-1] if stderr.strip() else ""
    text = re.sub(r"^.*\.xcdatamodeld?(/[^:]*)?: ", "", text)
    text = re.sub(r"<attribute> without attributeType in .*", "<attribute> without attributeType", text)
    text = re.sub(r"nomac does not compile (.*) in Core Data models yet.*", r"\1", text)
    text = re.sub(r"\b(entity|attribute|relationship|names?|request|class) [\w.+-]+( and [\w.+-]+)?", r"\1 _", text)
    return text[:110]


def same_file(name, ours, theirs):
    if ours == theirs:
        return True
    if name.endswith(".omo"):
        try:
            return compare.canonical(ours) == compare.canonical(theirs) is not None
        except Exception:
            return False
    if name.endswith("VersionInfo.plist"):
        return compare.same_values(ours, theirs)
    return False


def different_files(ours, theirs, generated=False):
    def read(result, file):
        data = base64.b64decode(result["files"][file])
        return CREATED.sub(b"//  Created by", data) if generated else data
    different = [f for f in sorted(ours["files"].keys() & theirs["files"].keys()) if not same_file(f, read(ours, f), read(theirs, f))]
    return different + sorted(ours["files"].keys() ^ theirs["files"].keys())


def judge(path, nomac, observations):
    theirs = json.loads((observations / f"{key(path)}.json").read_text())
    ours = outputs([nomac, "momc"], path, "/SDK")
    if theirs["compile"]["status"] != 0:
        return ("momc fails", "", path) if ours["compile"]["status"] != 0 else ("momc fails, nomac does not", "", path)
    for step in ("compile", "dry-run", "generate"):
        if theirs[step]["status"] == 0 and ours[step]["status"] != 0:
            return ("refused", f"{step}: {message(ours[step]['stderr'])}", path)
    different = different_files(ours["compile"], theirs["compile"])
    if different:
        return ("different", "compile: " + ", ".join(Path(f).name for f in different[:3]), path)
    if compare.diagnostics(ours["compile"]["stderr"]) != compare.diagnostics(theirs["compile"]["stderr"]):
        return ("different", "messages", path)
    if theirs["dry-run"]["status"] == 0 and ours["dry-run"]["stdout"] != theirs["dry-run"]["stdout"]:
        return ("different", "dry run", path)
    if theirs["generate"]["status"] == 0:
        different = different_files(ours["generate"], theirs["generate"], generated=True)
        if different:
            return ("different", "generate: " + ", ".join(Path(f).name for f in different[:3]), path)
    return ("same", "", path)


def run_compare(root, observations, nomac, only):
    selected = [path for path in models(root) if only in str(path) and (observations / f"{key(path)}.json").exists()]
    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(lambda path: judge(path, nomac, observations), selected))
    counts = Counter(result[0] for result in results)
    repositories = defaultdict(set)
    for kind, _, path in results:
        repositories[kind].add(path.relative_to(root).parts[0])
    print(" ".join(f"{kind}={counts[kind]} models, {len(repositories[kind])} repositories;" for kind in sorted(counts)))
    reasons = defaultdict(list)
    for kind, reason, path in results:
        if kind not in ("same", "momc fails"):
            reasons[(kind, reason)].append(path)
    for (kind, reason), paths in sorted(reasons.items(), key=lambda item: (item[0][0], -len(item[1]))):
        print(f"{len(paths):5} {len({p.relative_to(root).parts[0] for p in paths}):4}  {kind}: {reason}  e.g. {paths[0].relative_to(root)}")
    (observations / "compare.json").parent.mkdir(exist_ok=True)
    (observations.parent / "compare.json").write_text(json.dumps([[k, r, str(p)] for k, r, p in results], indent=0))


def version_features(contents):
    """B-257's features a version file uses, each named once."""
    root = ET.fromstring(contents)
    used = set()
    if root.get("userDefinedModelVersionIdentifier"):
        used.add("userDefinedModelVersionIdentifier")
    tools = root.get("minimumToolsVersion", "Automatic")
    major = None if tools == "Automatic" else int(re.sub(r"\D.*", "", tools.replace("Xcode ", "") or "0") or 0)
    for child in root:
        if child.tag == "configuration":
            used.add("configuration")
        elif child.tag == "fetchRequest":
            extra = sorted(set(child.attrib) - {"name", "entity"})
            used.update(f"fetchRequest@{name}" for name in extra)
            used.update(f"fetchRequest<{item.tag}>" for item in child)
    names = []
    for entity in root.iter("entity"):
        names.append(entity.get("name", ""))
        if entity.get("representedClassName") is None:
            used.add("entity without representedClassName")
        if major and not entity.get("syncable") == "YES":
            used.add(f"entity not syncable under Xcode {'10-13' if 10 <= major <= 13 else 'other'}")
        compound = entity.find("compoundIndexes")
        if compound is not None and len(compound) > 1:
            used.add("several compoundIndexes")
        indexes = entity.findall("fetchIndex")
        indexed = [a for a in entity.findall("attribute") if a.get("indexed") == "YES"]
        if indexes and (indexed or compound is not None and len(compound)):
            used.add("fetchIndex with indexed attributes or compoundIndexes")
        if major and major < 9 and compound is not None and len(compound):
            used.add("compoundIndexes under an old minimumToolsVersion")
        for member in entity:
            names.append(member.get("name", ""))
            if member.tag == "fetchedProperty":
                used.add("fetchedProperty")
            elif member.tag == "attribute":
                kind = member.get("attributeType")
                if member.get("defaultValueString") is not None and kind not in ("Integer 16", "Integer 32", "Integer 64", "Double", "Float", "Boolean", "String"):
                    used.add(f"default value of {kind}")
                if member.get("versionHashModifier"):
                    used.add("attribute versionHashModifier")
                if member.get("renamingIdentifier"):
                    used.add("renamingIdentifier")
                bounded = member.get("minValueString") or member.get("maxValueString")
                if bounded and kind not in ("Integer 16", "Integer 32", "Integer 64", "Double", "Float", "String"):
                    used.add(f"validation of {kind}")
                if member.get("minDateTimeInterval") or member.get("maxDateTimeInterval"):
                    used.add("validation of Date intervals")
                if member.find("userInfo") is not None and (bounded or member.get("minDateTimeInterval")):
                    used.add("user info with validation")
                if major and member.get("syncable") != "YES" and 10 <= major <= 13:
                    used.add("attribute not syncable under Xcode 10-13")
                if kind == "Undefined":
                    used.add("attribute type Undefined")
                used.update(f"attribute@{name}" for name in member.attrib if name not in KNOWN_ATTRIBUTE)
            elif member.tag == "relationship":
                if member.get("transient") == "YES":
                    used.add("transient relationship")
                if member.find("userInfo") is not None:
                    used.add("relationship user info")
                if member.get("versionHashModifier"):
                    used.add("relationship versionHashModifier")
                if major and member.get("syncable") != "YES":
                    used.add(f"relationship not syncable under Xcode {'10-13' if 10 <= major <= 13 else 'other'}")
                used.update(f"relationship@{name}" for name in member.attrib if name not in KNOWN_RELATIONSHIP)
            elif member.tag not in ("uniquenessConstraints", "compoundIndexes", "fetchIndex", "userInfo"):
                used.add(f"entity<{member.tag}>")
        used.update(f"entity@{name}" for name in entity.attrib if name not in KNOWN_ENTITY)
    if any(re.search(r"[^A-Za-z0-9_]", name) for name in names):
        used.add("names of other characters")
    return used


KNOWN_ENTITY = {"name", "representedClassName", "parentEntity", "isAbstract", "versionHashModifier", "elementID", "codeGenerationType", "syncable"}
KNOWN_ATTRIBUTE = {"name", "optional", "transient", "attributeType", "defaultValueString", "defaultDateTimeInterval", "usesScalarValueType",
                   "minValueString", "maxValueString", "indexed", "valueTransformerName", "customClassName", "elementID",
                   "allowsExternalBinaryDataStorage", "syncable", "versionHashModifier", "renamingIdentifier"}
KNOWN_RELATIONSHIP = {"name", "optional", "transient", "toMany", "ordered", "minCount", "maxCount", "deletionRule", "destinationEntity",
                      "inverseName", "inverseEntity", "elementID", "syncable", "versionHashModifier"}


def features(root):
    versions, by_repository, by_model = Counter(), defaultdict(set), defaultdict(set)
    total = 0
    for model in models(root):
        repository = model.relative_to(root).parts[0]
        for version in ([model] if model.suffix == ".xcdatamodel" else sorted(model.glob("*.xcdatamodel"))):
            total += 1
            contents = version / "contents"
            try:
                used = version_features(contents.read_bytes()) if contents.exists() else {"no contents file"}
            except ET.ParseError:
                used = {"contents not well-formed"}
            for feature in used:
                versions[feature] += 1
                by_repository[feature].add(repository)
                by_model[feature].add(model)
    print(f"{total} versions, {len(models(root))} models, {len({m.relative_to(root).parts[0] for m in models(root)})} repositories")
    print("repositories models versions feature")
    for feature in sorted(versions, key=lambda f: (-len(by_repository[f]), f)):
        print(f"{len(by_repository[feature]):5} {len(by_model[feature]):5} {versions[feature]:5}  {feature}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    command, root = sys.argv[1], Path(sys.argv[2]).resolve()
    if command == "features":
        features(root)
    elif command == "observe":
        observe(root, Path(sys.argv[3]).resolve())
    elif command == "compare":
        run_compare(root, Path(sys.argv[3]).resolve(), str(Path(sys.argv[4]).resolve()), sys.argv[5] if len(sys.argv) > 5 else "")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compare nomac's compiled nibs with ibtool's, from nib_experiments.py observations.

Runs anywhere nomac runs. Each experiment's document is written again from nib_experiments.py
and compiled with `nomac ibtool` and the build's options (a storyboard into a compilation
directory, then linked); the nib or the .storyboardc, the linked copy, the partial Info.plist and
what ibtool printed must be identical; where ibtool failed, nomac must fail too. Nibs identical but for the order of
an NSSet's elements count as equivalent (ADR 0252), as `nomac verify` judges them. Experiments nomac refuses with an
error naming a BACKLOG item are listed apart; any other failure fails the comparison.

With `corpus`, the observations of nib_experiments.py's `corpus` experiment instead: each corpus
document compiled where it is checked out (/tmp/nomac-corpus).

Usage: nib_compare.py <observations-dir> <nomac> [experiment ...]
       nib_compare.py <corpus-observations-dir> <nomac> corpus
"""

import base64
import json
import struct
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nib_experiments as experiments  # noqa: E402


def sorting_sets(data):
    """The NIBArchive with each NSSet's and NSMutableSet's object references in ascending order, nested archives
    too (NibSetComparison.swift), or None when it is not one."""
    data = bytearray(data)

    def sort(start, end):
        if end - start < 50 or data[start:start + 10] != b"NIBArchive":
            return False

        def varint(p):
            value = shift = 0
            while p < end:
                byte = data[p]
                p += 1
                value |= (byte & 0x7F) << shift
                shift += 7
                if byte & 0x80:
                    return value, p
            raise ValueError

        _, _, objects, objects_at, key_count, keys_at, value_count, values_at, class_count, classes_at = struct.unpack_from("<10I", data, start + 10)
        try:
            keys, p = [], start + keys_at
            for _ in range(key_count):
                n, p = varint(p)
                keys.append(bytes(data[p:p + n]))
                p += n
            classes, p = [], start + classes_at
            for _ in range(class_count):
                n, p = varint(p)
                fallbacks, p = varint(p)
                p += 4 * fallbacks
                classes.append(bytes(data[p:p + n]).rstrip(b"\0"))
                p += n
            sizes = {0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4}
            values, p = [], start + values_at
            for _ in range(value_count):
                key, p = varint(p)
                kind = data[p]
                p += 1
                n, p = varint(p) if kind == 8 else (sizes[kind], p)
                values.append((keys[key], kind, p, p + n))
                p += n
            for _, kind, low, high in values:
                if kind == 8 and data[low:low + 10] == b"NIBArchive" and not sort(low, high):
                    return False
            p = start + objects_at
            for _ in range(objects):
                index, p = varint(p)
                first, p = varint(p)
                count, p = varint(p)
                if classes[index] in (b"NSSet", b"NSMutableSet"):
                    elements = [v for v in values[first:first + count] if v[1] == 10 and v[0].startswith(b"NS.object.")]
                    references = sorted(struct.unpack_from("<I", data, v[2])[0] for v in elements)
                    for element, reference in zip(elements, references):
                        struct.pack_into("<I", data, element[2], reference)
        except (ValueError, IndexError, KeyError, struct.error):
            return False
        return True

    return bytes(data) if sort(0, len(data)) else None


def same(mine, theirs):
    """Whether the files are identical, equivalent (nibs differing only in their sets' order) or neither (None)."""
    if mine == theirs:
        return "identical"
    if mine.keys() != theirs.keys():
        return None
    for name in mine:
        if mine[name] != theirs[name] and (sorting_sets(mine[name]) is None or sorting_sets(mine[name]) != sorting_sets(theirs[name])):
            return None
    return "equivalent"


def files_under(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in sorted(directory.rglob("*")) if p.is_file()} if directory.exists() else {}


def compare_storyboard(name, observed, nomac, work, identical, equivalent, different, refused, failed):
    source = work / ("Base.lproj/Main.storyboard" if name in experiments.LPROJ_STORYBOARDS else "Main.storyboard")
    source.parent.mkdir(parents=True)
    source.write_text(experiments.STORYBOARDS[name])
    module, deployment, devices = experiments.options(name)
    common = ["--errors", "--warnings", "--notices", "--module", module, *[a for d in devices for a in ("--target-device", d)],
              "--minimum-deployment-target", deployment, "--output-format", "human-readable-text"]
    compiled = subprocess.run([nomac, "ibtool", *common, "--output-partial-info-plist", str(work / "SBPartialInfo.plist"),
                               "--auto-activate-custom-fonts", str(source), "--compilation-directory", str(work / "compiled")],
                              capture_output=True, text=True)
    message = compiled.stdout.strip().splitlines()[-1] if compiled.stdout.strip() else compiled.stderr.strip()
    if compiled.returncode != 0:
        (refused if "(BACKLOG B-" in message else failed).append(f"{name}: {message}")
        return
    linked = subprocess.run([nomac, "ibtool", *common, "--link", str(work / "linked"), str(work / "compiled/Main.storyboardc")],
                            capture_output=True, text=True)
    theirs = {k: base64.b64decode(v) for k, v in observed["compile"]["files"].items()}
    theirs_linked = {k: base64.b64decode(v) for k, v in observed["link"]["files"].items()}
    partial = (work / "SBPartialInfo.plist").read_text() if (work / "SBPartialInfo.plist").exists() else None
    kinds = {same(files_under(work / "compiled"), theirs), same(files_under(work / "linked"), theirs_linked)}
    stdout = observed["compile"]["stdout"].replace(f"/tmp/nomac-nib-experiments/{name}/{source.relative_to(work)}", str(source))
    ok = linked.returncode == 0 and partial == observed["partial Info.plist"] and compiled.stdout == stdout
    (different if not ok or None in kinds else equivalent if "equivalent" in kinds else identical).append(name)


def compare_link(observed, nomac, work, identical, different):
    work.mkdir(parents=True)
    source = work / "Main.storyboard"
    source.write_text(experiments.STORYBOARD)
    common = ["--module", "T", "--target-device", "iphone", "--minimum-deployment-target", "27.0", "--output-format", "human-readable-text"]
    folders = ["Base.lproj", "fr.lproj", "plain"]
    for folder in folders:
        subprocess.run([nomac, "ibtool", *common, str(source), "--compilation-directory", str(work / "compiled" / folder)], capture_output=True)
    proc = subprocess.run([nomac, "ibtool", *common, "--link", str(work / "app"),
                           *[str(work / "compiled" / folder / "Main.storyboardc") for folder in folders]], capture_output=True, text=True)
    theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
    same = proc.returncode == observed["status"] and proc.stdout == observed["stdout"] and files_under(work / "app") == theirs
    (identical if same else different).append("link-lproj")


def compare_corpus(observations, nomac, work, identical, equivalent, different, refused, failed):
    common = ["--errors", "--warnings", "--notices", "--module", "T", "--auto-activate-custom-fonts", "--target-device", "iphone",
              "--minimum-deployment-target", "27.0", "--output-format", "human-readable-text"]
    for index, (name, observed) in enumerate(observations.items()):
        path = Path(name[len("corpus:"):])
        if not path.exists():
            continue
        out = work / f"{index:04}"
        out.mkdir(parents=True)
        if path.suffix == ".storyboard":
            proc = subprocess.run([nomac, "ibtool", *common, "--output-partial-info-plist", str(out / "P.plist"), str(path),
                                   "--compilation-directory", str(out / "compiled")], capture_output=True, text=True)
            mine = files_under(out / "compiled")
        else:
            proc = subprocess.run([nomac, "ibtool", *common, "--output-partial-info-plist", str(out / "P.plist"),
                                   "--compile", str(out / (path.stem + ".nib")), str(path)], capture_output=True, text=True)
            mine = {k: v for k, v in files_under(out).items() if k.endswith(".nib") or "/" in k}
        message = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else proc.stderr.strip()
        if proc.returncode != 0:
            if observed["status"] != 0 and proc.stdout == observed["stdout"]:
                identical.append(name)
            else:
                (refused if "(BACKLOG B-" in message else failed).append(f"{name}: {message}")
            continue
        theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
        kind = same(mine, theirs) if observed["status"] == 0 and proc.stdout == observed["stdout"] else None
        (equivalent if kind == "equivalent" else identical if kind else different).append(name)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    observations = json.loads((Path(sys.argv[1]) / "observations.json").read_text())
    nomac = sys.argv[2]
    selected = sys.argv[3:] or [name for name in [*experiments.EXPERIMENTS, *experiments.STORYBOARDS] if name in observations]
    work = Path(tempfile.mkdtemp(prefix="nomac-nib-compare-"))
    identical, equivalent, different, refused, failed = [], [], [], [], []
    try:
        if selected == ["corpus"]:
            compare_corpus({k: v for k, v in observations.items() if k.startswith("corpus:")}, nomac, work, identical, equivalent, different, refused, failed)
            selected = []
        for name in selected:
            if name in experiments.STORYBOARDS:
                compare_storyboard(name, observations[name], nomac, work / name, identical, equivalent, different, refused, failed)
                continue
            source = work / name / ("Base.lproj/View.xib" if name in experiments.LPROJ_XIBS else "View.xib")
            source.parent.mkdir(parents=True)
            source.write_text(experiments.EXPERIMENTS[name])
            out = work / name / "out"
            module, deployment, devices = experiments.options(name)
            proc = subprocess.run([nomac, "ibtool", "--errors", "--warnings", "--notices", "--module", module,
                                   "--output-partial-info-plist", str(out / "PartialInfo.plist"), "--auto-activate-custom-fonts",
                                   *[argument for device in devices for argument in ("--target-device", device)],
                                   "--minimum-deployment-target", deployment,
                                   "--output-format", "human-readable-text", "--compile", str(out / "View.nib"), str(source)],
                                  capture_output=True, text=True)
            observed = observations[name]
            message = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else proc.stderr.strip()
            if proc.returncode != 0:
                expected = observed["stdout"].replace(f"/tmp/nomac-nib-experiments/{name}/{source.relative_to(work / name)}", str(source))
                if observed["status"] != 0 and proc.stdout == expected:
                    identical.append(name)
                elif "(BACKLOG B-" in message:
                    refused.append(f"{name}: {message}")
                else:
                    failed.append(f"{name}: {message}")
                continue
            mine = {p.name: p.read_bytes() for p in out.iterdir()}
            theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
            kind = same(mine, theirs) if observed["status"] == 0 else None
            (equivalent if kind == "equivalent" else identical if kind else different).append(name)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if "link-lproj" in observations:
        compare_link(observations["link-lproj"], nomac, work / "link-lproj", identical, different)
    if "missing-file" in observations:
        missing = work / "missing-file" / "Missing.xib"
        proc = subprocess.run([nomac, "ibtool", "--module", "T", "--minimum-deployment-target", "27.0", "--target-device", "iphone",
                               "--compile", str(work / "missing.nib"), str(missing)], capture_output=True, text=True)
        expected = observations["missing-file"]["stdout"].replace("/tmp/nomac-nib-experiments/missing-file/Missing.xib", str(missing))
        (identical if proc.stdout == expected and proc.returncode == observations["missing-file"]["status"] else different).append("missing-file")
    print(f"identical {len(identical)}, equivalent {len(equivalent)}, different {len(different)}, refused {len(refused)}, failed {len(failed)}")
    for name in equivalent:
        print(f"    equivalent: {name}")
    for name in different:
        print(f"    different: {name}")
    for line in failed:
        print(f"    failed: {line}")
    for line in refused:
        print(f"    refused: {line}")
    sys.exit(1 if different or failed else 0)


if __name__ == "__main__":
    main()

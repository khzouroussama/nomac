#!/usr/bin/env python3
"""Compare nomac's compiled nibs with ibtool's, from nib_experiments.py observations.

Runs anywhere nomac runs. Each experiment's document is written again from nib_experiments.py
and compiled with `nomac ibtool` and the build's options (a storyboard into a compilation
directory, then linked); the nib or the .storyboardc, the linked copy, the partial Info.plist and
what ibtool printed must be identical; where ibtool failed, nomac must fail too. Nibs identical but for the order of
an NSSet's elements (ADR 0252), or of outlet collections of several sources (ADR 0260), count as equivalent, as
`nomac verify` judges them, and so do warnings that differ only in their order, which changes from run to run in
ibtool when objects' ids collide (ADR 0254). Experiments nomac refuses with an
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


def canonical_connections(data):
    """The NIBArchive as a text walking its objects from the root, each object numbered where the walk
    first reaches it, the root's outlet collection connections sorted by label and source
    (NibConnectionComparison.swift, ADR 0260), or None when it is not one."""
    sizes = {0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4}
    try:
        if data[:10] != b"NIBArchive":
            return None
        _, _, object_count, objects_at, key_count, keys_at, value_count, values_at, class_count, classes_at = struct.unpack_from("<10I", data, 10)

        def varint(p):
            value = shift = 0
            while True:
                byte = data[p]
                p += 1
                value |= (byte & 0x7F) << shift
                shift += 7
                if byte & 0x80:
                    return value, p

        keys, p = [], keys_at
        for _ in range(key_count):
            n, p = varint(p)
            keys.append(bytes(data[p:p + n]).decode())
            p += n
        values, p = [], values_at
        for _ in range(value_count):
            key, p = varint(p)
            kind = data[p]
            p += 1
            if kind == 8:
                n, p = varint(p)
            else:
                n = sizes[kind]
            payload = bytes(data[p:p + n])
            p += n
            values.append((keys[key], kind, struct.unpack("<I", payload)[0] if kind == 10 else payload))
        classes, p = [], classes_at
        for _ in range(class_count):
            n, p = varint(p)
            fallbacks, p = varint(p)
            p += 4 * fallbacks
            classes.append(bytes(data[p:p + n]).rstrip(b"\0").decode())
            p += n
        objects, p = [], objects_at
        for _ in range(object_count):
            index, p = varint(p)
            first, p = varint(p)
            count, p = varint(p)
            objects.append((classes[index], values[first:first + count]))
    except (struct.error, IndexError, KeyError, UnicodeDecodeError):
        return None
    root_values = {key: value for key, kind, value in objects[0][1] if kind == 10}
    connections = root_values.get("UINibConnectionsKey")
    numbering, lines = {}, []

    def text_of(index):
        return next((value for key, kind, value in objects[index][1] if key == "NS.bytes"), b"")

    def walk(start):
        stack = [start]
        while stack:
            index = stack.pop()
            if index in numbering:
                continue
            numbering[index] = len(numbering)
            name, items = objects[index]
            references = [value for key, kind, value in items if kind == 10]
            if index == connections:
                run = [r for r in references if objects[r][0] == "UIRuntimeOutletCollectionConnection"]
                for reference in run:
                    for key, kind, value in objects[reference][1]:
                        if key == "UISource" and kind == 10:
                            walk(value)
                order = {}
                for reference in run:
                    fields = {key: value for key, kind, value in objects[reference][1] if kind == 10}
                    order[reference] = (text_of(fields.get("UILabel", 0)), numbering.get(fields.get("UISource"), -1))
                run.sort(key=order.get)
                references = run + [r for r in references if objects[r][0] != "UIRuntimeOutletCollectionConnection"]
                items = [(key, kind, value) for key, kind, value in items if kind != 10] + [("", 10, r) for r in references]
            lines.append((index, name, items))
            stack.extend(reversed([value for key, kind, value in items if kind == 10]))

    walk(0)
    return "\n".join(f"{numbering[index]} {name} " + ", ".join(f"{key}=#{numbering[value]}" if kind == 10 else f"{key}={kind}:{value.hex()}"
                                                         for key, kind, value in items)
                     for index, name, items in sorted(lines, key=lambda line: numbering[line[0]]))


def tie_canonical(data):
    """The NIBArchive as a graph renumbered depth first from the root, the constraints of each
    settled tie (ADR 0253: one item's required constraints by the same attributes to several views,
    all satisfied by the archive's frames) in one canonical order, every set's elements sorted, nested
    archives likewise (NibTieComparison.swift), or None when it is not one."""
    data = bytes(data)
    if data[:10] != b"NIBArchive" or len(data) < 50:
        return None

    def varint(p):
        value = shift = 0
        while True:
            byte = data[p]
            p += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte & 0x80:
                return value, p

    try:
        _, _, count, objects_at, key_count, keys_at, value_count, values_at, class_count, classes_at = struct.unpack_from("<10I", data, 10)
        keys, p = [], keys_at
        for _ in range(key_count):
            n, p = varint(p)
            keys.append(data[p:p + n].decode())
            p += n
        classes, p = [], classes_at
        for _ in range(class_count):
            n, p = varint(p)
            fallbacks, p = varint(p)
            p += 4 * fallbacks
            classes.append(data[p:p + n].rstrip(b"\0").decode())
            p += n
        sizes = {0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4}
        values, p = [], values_at
        for _ in range(value_count):
            key, p = varint(p)
            kind = data[p]
            p += 1
            n, p = varint(p) if kind == 8 else (sizes[kind], p)
            raw = data[p:p + n]
            payload = struct.unpack("<I", raw)[0] if kind == 10 else raw
            values.append([keys[key], kind, payload])
            p += n
        objects, p = [], objects_at
        for _ in range(count):
            index, p = varint(p)
            first, p = varint(p)
            n, p = varint(p)
            objects.append([classes[index], values[first:first + n]])
    except (IndexError, KeyError, struct.error, UnicodeDecodeError):
        return None

    def fields(i):
        return {k: v for k, t, v in objects[i][1]}

    def refs(i):
        return [v for k, t, v in objects[i][1] if t == 10 and (k == "UINibEncoderEmptyKey" or k.startswith("NS.object."))]

    def number(raw, kind):
        return {0: "<b", 1: "<h", 2: "<i", 3: "<q", 6: "<f", 7: "<d"}.get(kind) and struct.unpack({0: "<b", 1: "<h", 2: "<i", 3: "<q", 6: "<f", 7: "<d"}[kind], raw)[0]

    def scalar(i, key, default=None):
        for k, t, v in objects[i][1]:
            if k == key:
                return number(v, t) if t not in (8, 9, 10, 4, 5) else (True if t == 5 else False if t == 4 else v)
        return default

    parents, frames = {}, {}
    for i, (name, vals) in enumerate(objects):
        f = fields(i)
        if "UISubviews" in f:
            for child in refs(f["UISubviews"]):
                parents[child] = i
        if "UICenter" in f and "UIBounds" in f:
            cx, cy = struct.unpack("<2d", f["UICenter"][1:17])
            w, h = struct.unpack("<4d", f["UIBounds"][1:33])[2:]
            frames[i] = (cx - w / 2, cy - h / 2, w, h)

    root = fields(0)
    paths = {}
    if "UINibTopLevelObjectsKey" in root:
        queue = [(top, (n,)) for n, top in enumerate(refs(root["UINibTopLevelObjectsKey"]))]
        while queue:
            item, path = queue.pop(0)
            if item in paths:
                continue
            paths[item] = path
            f = fields(item)
            if "UISubviews" in f:
                queue += [(child, path + (n,)) for n, child in enumerate(refs(f["UISubviews"]))]

    def in_owner(item, owner):
        if item == owner:
            frame = frames.get(owner)
            return (0, 0, frame[2], frame[3]) if frame else None
        if item not in frames:
            return None
        x, y, w, h = frames[item]
        current = parents.get(item)
        while current is not None and current != owner:
            if current not in frames:
                return None
            x += frames[current][0]
            y += frames[current][1]
            current = parents.get(current)
        return (x, y, w, h) if current == owner else None

    def value(item, attribute, owner):
        if objects[item][0] == "UILayoutGuide" and scalar(item, "UILayoutGuideOwningView") == owner and attribute in (1, 2, 5, 6, 7, 9):
            frame = in_owner(owner, owner)
        else:
            frame = in_owner(item, owner)
        if frame is None:
            return None
        x, y, w, h = frame
        return {1: x, 5: x, 2: x + w, 6: x + w, 3: y, 4: y + h, 7: w, 8: h, 9: x + w / 2, 10: y + h / 2}.get(attribute)

    def satisfied(c, owner):
        first = value(scalar(c, "NSFirstItem"), scalar(c, "NSFirstAttributeV2"), owner)
        second = value(scalar(c, "NSSecondItem"), scalar(c, "NSSecondAttributeV2"), owner)
        if first is None or second is None:
            return False
        difference = first - (second * scalar(c, "NSMultiplier", 1) + scalar(c, "NSConstantV2", 0))
        relation = scalar(c, "NSRelation", 0)
        return difference <= 0.01 if relation == -1 else difference >= -0.01 if relation == 1 else abs(difference) <= 0.01

    def signature(c):
        return tuple(scalar(c, k) for k in ("NSFirstItem", "NSFirstAttributeV2", "NSSecondAttributeV2", "NSRelation", "NSMultiplier"))

    runs = []
    for owner in range(len(objects)):
        f = fields(owner)
        if "UIViewAutolayoutConstraints" not in f:
            continue
        listed = refs(f["UIViewAutolayoutConstraints"])
        start = 0
        while start < len(listed):
            end = start + 1
            while end < len(listed) and signature(listed[end]) == signature(listed[start]):
                end += 1
            run = listed[start:end]
            seconds = {scalar(c, "NSSecondItem") for c in run}
            if (len(seconds) > 1 and None not in seconds and all(scalar(c, "NSPriority") is None and satisfied(c, owner) for c in run)
                    and all(s in paths for s in seconds)):
                runs.append(sorted(run, key=lambda c: (paths[scalar(c, "NSSecondItem")], scalar(c, "NSConstantV2", 0), scalar(c, "NSSecondAttributeV2"))))
            start = end
    for run in runs:
        members = set(run)
        for name, vals in objects:
            if name not in ("NSArray", "NSMutableArray", "NSOrderedSet"):
                continue
            slots = [n for n, v in enumerate(vals) if v[1] == 10 and v[2] in members]
            if len(slots) == len(run):
                for slot, member in zip(slots, run):
                    vals[slot][2] = member

    order, stack = {}, [0]
    while stack:
        item = stack.pop()
        if item in order:
            continue
        order[item] = len(order)
        stack += [v for k, t, v in reversed(objects[item][1]) if t == 10]
    canonical = []
    for item in sorted(order, key=order.get):
        name, vals = objects[item]
        out = []
        for k, t, v in vals:
            if t == 10:
                v = order[v]
            elif t == 8 and v[:10] == b"NIBArchive":
                v = tie_canonical(v)
            out.append((k, t, v))
        if name in ("NSSet", "NSMutableSet"):
            elements = sorted(v for k, t, v in out if t == 10 and k.startswith("NS.object."))
            out = [(k, t, elements.pop(0)) if t == 10 and k.startswith("NS.object.") else (k, t, v) for k, t, v in out]
        canonical.append((name, tuple(out)))
    return tuple(canonical)


def judged(mine, theirs, printed, expected, status):
    """How `same` judges the files once ibtool succeeded and printed the same lines, in any order."""
    if status != 0 or sorted(printed.splitlines()) != sorted(expected.splitlines()):
        return None
    kind = same(mine, theirs)
    return "equivalent" if kind and printed != expected else kind


def same(mine, theirs):
    """Whether the files are identical, equivalent (nibs differing only in their sets' order, their outlet collections'
    order, ADR 0260, or their settled ties' order, ADR 0253) or neither (None)."""
    if mine == theirs:
        return "identical"
    if mine.keys() != theirs.keys():
        return None
    for name in mine:
        if mine[name] == theirs[name]:
            continue
        mine_sorted, theirs_sorted = sorting_sets(mine[name]), sorting_sets(theirs[name])
        if mine_sorted is not None and theirs_sorted is not None:
            if mine_sorted == theirs_sorted:
                continue
            mine_text = canonical_connections(mine_sorted)
            if mine_text is not None and mine_text == canonical_connections(theirs_sorted):
                continue
        mine_ties = tie_canonical(mine[name])
        if mine_ties is None or mine_ties != tie_canonical(theirs[name]):
            return None
    return "equivalent"


def files_under(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in sorted(directory.rglob("*")) if p.is_file()} if directory.exists() else {}


def compare_storyboard(name, observed, nomac, work, identical, equivalent, different, refused, failed):
    source = work / (f"{experiments.OTHER_LPROJ[name]}.lproj/Main.storyboard" if name in experiments.OTHER_LPROJ
                     else "Base.lproj/Main.storyboard" if name in experiments.LPROJ_STORYBOARDS else "Main.storyboard")
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
        kind = judged(mine, theirs, proc.stdout, observed["stdout"], observed["status"])
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
            source = work / name / (f"{experiments.OTHER_LPROJ[name]}.lproj/View.xib" if name in experiments.OTHER_LPROJ
                                    else "Base.lproj/View.xib" if name in experiments.LPROJ_XIBS else "View.xib")
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
            printed = observed["stdout"].replace(f"/tmp/nomac-nib-experiments/{name}/{source.relative_to(work / name)}", str(source))
            kind = judged(mine, theirs, proc.stdout, printed, observed["status"])
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

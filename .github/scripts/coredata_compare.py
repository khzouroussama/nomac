#!/usr/bin/env python3
"""Compare `nomac momc` with what Xcode 27.0's momc wrote (coredata_experiments.py's observations).

Each experiment model is written again where coredata_experiments.py compiled it
(/tmp/nomac-coredata-experiments/<name>), because momc's order of versions depends on their paths;
corpus models are read from their checkouts at the observed paths. Every file momc wrote, and its
notes on standard error, are compared with nomac's; an .omo identical once momc's SQL column-name
lists and its entities' families are sorted (ADR 0230, ADR 0232) and its lookup tables reduced to
their keys (ADR 0231) is equivalent, and
so is a VersionInfo.plist of the same values (B-235). Models nomac refuses are counted apart with nomac's
message; when only their .omo is refused, each version's .mom is compared on its own.
Mapping models (`mapping:<path>`) are compiled with `nomac mapc` and their .cdm compared; generated
classes are compared without the line naming their author and day.

Usage: coredata_compare.py <observations-dir> <nomac> [name ...]
"""

import base64
import json
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coredata_experiments as experiments  # noqa: E402

WORK = Path("/tmp/nomac-coredata-experiments")


def source(name):
    """The model momc compiled for observation `name`, written again for experiments."""
    if name.startswith("corpus:"):
        return Path(name[len("corpus:"):])
    if name in experiments.VERSIONED:
        path = WORK / name / "Model.xcdatamodeld"
        shutil.rmtree(path, ignore_errors=True)
        for version, contents in experiments.VERSIONED[name].items():
            (path / f"{version}.xcdatamodel").mkdir(parents=True)
            (path / f"{version}.xcdatamodel" / "contents").write_text(contents)
        experiments.write_current_version(path, name)
        return path
    path = WORK / name / "Model.xcdatamodel"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    (path / "contents").write_text(experiments.EXPERIMENTS[name])
    return path


def diagnostics(stderr):
    return [line for line in stderr.splitlines() if ": note: " in line or ": warning: " in line]


def sorting_column_lists(data):
    """The .omo with each SQL entity's column-name list sorted by name: what ADR 0230 compares."""
    data = bytearray(data)

    def u32(offset):
        return struct.unpack(">I", data[offset:offset + 4])[0]
    offset = (u32(64 + 64) + 3) // 4 * 4
    count = u32(offset)
    offset += 4
    names = []
    for _ in range(count):
        offset = (offset + 7) // 8 * 8
        length = u32(offset + 12)
        names.append(bytes(data[offset + 24:offset + 24 + length]))
        offset += 24 + length + 1
    offset = (u32(64) + 3) // 4 * 4
    requests = u32(offset + 8)
    offset += 12
    if requests:
        offset = (offset + 7) // 8 * 8 + 8 * requests
    configurations = u32(offset)
    offset += 4
    for _ in range(configurations):
        offset = (offset + 4 + 7) // 8 * 8 + 16
        members = u32(offset + 4)
        offset = (offset + 8 + 7) // 8 * 8 + 8 * members
    entities = u32((u32(64) + 3) // 4 * 4 + 4)
    offset += 32
    offset = (offset + 7) // 8 * 8 + 8 * entities if entities else offset
    for _ in range(entities):
        offset += 20
        count = u32(offset)
        offset = (offset + 4 + 7) // 8 * 8
        words = sorted((bytes(data[offset + 8 * i:offset + 8 * i + 8]) for i in range(count)),
                       key=lambda word: names[struct.unpack(">Q", word)[0]])
        data[offset:offset + 8 * count] = b"".join(words)
        offset += 8 * count
    return bytes(data)


def sorting_families(data):
    """The .omo with each entity record's list of itself and its subentities sorted: momc writes
    it in an order that changes from run to run (ADR 0232)."""
    data = bytearray(data)

    def u32(offset):
        return struct.unpack(">I", data[offset:offset + 4])[0]
    offset = (u32(64 + 4) + 3) // 4 * 4
    count = u32(offset)
    offset += 4
    for _ in range(count):
        end = offset + u32(offset + 4)
        tail = end - 12
        # The list follows its count, written twice six words apart (and a padding word when the
        # list is aligned after it).
        for size in range(1, count + 1):
            start = tail - 8 * size
            label = start - 4 if u32(start - 4) else start - 8
            words = [struct.unpack(">Q", data[start + 8 * i:start + 8 * i + 8])[0] for i in range(size)]
            if u32(label) == size == u32(label - 24) and all(word < count for word in words) and len(set(words)) == size:
                data[start:tail] = b"".join(struct.pack(">Q", word) for word in sorted(words))
                break
        offset = end + 4
    return bytes(data)


def canonical(data):
    """The .omo with its column-name lists and its entities' families sorted (ADR 0230, ADR 0232),
    its section offsets cleared and each lookup table reduced to its keys (ADR 0231), or None when
    a table does not lead every key to its slot."""
    data = sorting_families(sorting_column_lists(data))

    def u32(offset):
        return struct.unpack(">I", data[offset:offset + 4])[0]

    def u16(offset):
        return struct.unpack(">H", data[offset:offset + 2])[0]
    offset = (u32(64 + 64) + 3) // 4 * 4
    count = u32(offset)
    offset += 4
    names = []
    for _ in range(count):
        offset = (offset + 7) // 8 * 8
        length = u32(offset + 12)
        names.append(data[offset + 24:offset + 24 + length])
        offset += 24 + length + 1
    tables_at, properties_at = u32(64 + 40), u32(64 + 12)
    header = bytearray(data[:156])
    for index in (0, 1, 3, 10, 12, 14, 16, 18):
        header[64 + 4 * index:68 + 4 * index] = bytes(4)
    out = bytes(header) + data[156:tables_at]
    offset = (tables_at + 3) // 4 * 4 + 4
    for _ in range(u32((tables_at + 3) // 4 * 4)):
        offset = (offset + 7) // 8 * 8 + 40
        key_count, node_count = u32(offset), u32(offset + 4)
        offset += 8 + 8 * node_count
        nodes = []
        for _ in range(node_count - 1):
            low, high = u16(offset + 8), u16(offset + 12)
            size = max(high - low + 1, 0)
            nodes.append((u32(offset), low, u16(offset + 10), high, u16(offset + 14), [u16(offset + 16 + 2 * i) for i in range(size)]))
            offset += 16 + 2 * (size + (4 - size % 4) % 4)
        keys = [names[struct.unpack(">Q", data[offset + 8 * i:offset + 8 * i + 8])[0]] for i in range(key_count)]
        for slot, key in enumerate(keys):
            index, found = 0, False
            for _ in nodes:
                kind, low, below, high, above, table = nodes[index]
                value = len(key.decode()) if index == 0 else (key[kind >> 13] if kind >> 13 < len(key) else None)
                if value == low - 1:
                    reference = below
                elif value == high + 1:
                    reference = above
                elif value is not None and low <= value <= high:
                    reference = table[value - low]
                else:
                    return None
                if not reference & 0x8000:
                    found = reference == slot
                    break
                index = 0x10000 - reference
                if index >= len(nodes):
                    return None
            if nodes and not found:
                return None
        out += str(key_count).encode() + b"\0" + data[offset:offset + 8 * key_count]
        offset += 8 * key_count
    return out + data[properties_at:]


def same_values(left, right):
    """A .momd's VersionInfo.plist: the same values, entity names shared otherwise (B-235)."""
    return plistlib.loads(left) == plistlib.loads(right)


def compare_versions(nomac, name, expected, counts):
    """The .mom of each version of a model nomac refuses for its .omo, each version compiled alone."""
    for file, contents in sorted(expected["files"].items()):
        if not file.endswith(".mom"):
            continue
        version = source(name) / (Path(file).stem + ".xcdatamodel")
        with tempfile.TemporaryDirectory() as out:
            proc = subprocess.run([nomac, "momc", "--sdkroot", "/SDK", "--iphoneos-deployment-target", "27.0", "--module", "T",
                                   str(version), out], capture_output=True)
            written = Path(out) / (Path(file).stem + ".mom")
            if proc.returncode == 0 and written.read_bytes() == base64.b64decode(contents):
                counts["identical versions of refused models"] += 1
            else:
                counts["different versions of refused models"] += 1
                print(f"{name}: version {Path(file).stem} {'differs' if proc.returncode == 0 else 'refused'}")


def compare_dry_run(nomac, name, expected, counts):
    """`momc --dry-run --action generate`'s list of generated files."""
    proc = subprocess.run([nomac, "momc", "--dry-run", "--action", "generate", "--swift-version", "5.0", "--sdkroot", "/SDK",
                           "--iphoneos-deployment-target", "27.0", "--module", "T", str(source(name)), str(WORK / "dry-run-out")],
                          capture_output=True, text=True)
    if proc.returncode == 0 and proc.stdout == expected["stdout"]:
        counts["identical dry runs"] += 1
    else:
        counts["different dry runs" if proc.returncode == 0 else "refused dry runs"] += 1
        print(f"{name}: dry run {'differs' if proc.returncode == 0 else 'refused: ' + proc.stderr.strip()[-160:]}")


CREATED = re.compile(rb"^//  Created by .* on \d+/\d+/\d+\.$", re.M)


def compare_generated(nomac, name, expected, counts, shown):
    """`momc --action generate`'s files, the line naming their author and day aside."""
    with tempfile.TemporaryDirectory() as out:
        proc = subprocess.run([nomac, "momc", "--action", "generate", "--swift-version", "5.0", "--sdkroot", "/SDK",
                               "--iphoneos-deployment-target", "27.0", "--module", "T", str(source(name)), out], capture_output=True, text=True)
        if proc.returncode != 0:
            counts["refused generations"] += 1
            if shown["refused"] < 5:
                shown["refused"] += 1
                print(f"refused generation {name}: {proc.stderr.strip().split('error: ')[-1][:160]}")
            return
        written = {p.name: CREATED.sub(b"//  Created by", p.read_bytes()) for p in Path(out).iterdir()}
    wanted = {Path(f).name: CREATED.sub(b"//  Created by", base64.b64decode(d)) for f, d in expected["files"].items()}
    different = sorted(f for f in wanted.keys() | written.keys() if wanted.get(f) != written.get(f))
    counts["identical generations" if not different else "different generations"] += 1
    if different and shown["different"] < 8:
        shown["different"] += 1
        print(f"{name}: generated {', '.join(different[:4])} differ")


def compare_mapping(nomac, name, expected, counts):
    """`nomac mapc` against mapc's .cdm, for observations `mapping:<path>`."""
    source_path = Path(name[len("mapping:"):])
    with tempfile.TemporaryDirectory() as out:
        target = Path(out) / (source_path.stem + ".cdm")
        proc = subprocess.run([nomac, "mapc", "--sdkroot", "/SDK", "--iphoneos-deployment-target", "27.0", "--module", "T",
                               str(source_path), str(target)], capture_output=True, text=True)
        if proc.returncode != 0:
            counts["refused mapping models"] += 1
            print(f"refused {name}: {proc.stderr.strip().split('error: ')[-1][:200]}")
            return
        identical = target.read_bytes() == base64.b64decode(expected["files"][target.name])
    counts["identical mapping models" if identical else "different mapping models"] += 1
    if not identical:
        print(f"{name}: differs {target.name}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    observations = json.loads((Path(sys.argv[1]) / "observations.json").read_text())
    nomac = str(Path(sys.argv[2]).resolve())
    selected = sys.argv[3:] or [name for name, record in observations.items() if "compile" in record]
    counts = Counter()
    shown = Counter()
    for name in selected:
        expected = observations[name]["compile"]
        if expected["status"] != 0:
            continue
        if name.startswith("mapping:"):
            compare_mapping(nomac, name, expected, counts)
            continue
        if "dry-run" in observations[name]:
            compare_dry_run(nomac, name, observations[name]["dry-run"], counts)
        generated = observations[name].get("generate", {})
        if generated.get("status") == 0 and generated.get("files"):
            compare_generated(nomac, name, generated, counts, shown)
        with tempfile.TemporaryDirectory() as out:
            proc = subprocess.run([nomac, "momc", "--sdkroot", "/SDK", "--iphoneos-deployment-target", "27.0", "--module", "T",
                                   str(source(name)), out], capture_output=True, text=True)
            if proc.returncode != 0:
                counts["refused"] += 1
                print(f"refused {name}: {proc.stderr.strip().split('error: ')[-1][:200]}")
                if "B-256" in proc.stderr:
                    compare_versions(nomac, name, expected, counts)
                continue
            written = {str(p.relative_to(out)): p.read_bytes() for p in Path(out).rglob("*") if p.is_file()}
        differences = []
        for file, contents in sorted(expected["files"].items()):
            if file not in written:
                differences.append(f"missing {file}")
            elif written[file] != base64.b64decode(contents):
                if file.endswith(".omo") and canonical(written[file]) == canonical(base64.b64decode(contents)) is not None:
                    counts["equivalent files (.omo column order, lookup positions, families: ADR 0230-0232)"] += 1
                elif file.endswith(".momd/VersionInfo.plist") and same_values(written[file], base64.b64decode(contents)):
                    counts["equivalent files (VersionInfo.plist name sharing, B-235)"] += 1
                else:
                    differences.append(f"differs {file}")
            else:
                counts["identical files"] += 1
        differences += [f"extra {file}" for file in sorted(set(written) - set(expected["files"]))]
        if diagnostics(proc.stderr) != diagnostics(expected["stderr"]):
            differences.append("diagnostics differ: " + " | ".join(set(diagnostics(proc.stderr)) ^ set(diagnostics(expected["stderr"])))[:300])
        counts["models identical" if not differences else "models different"] += 1
        counts["different files"] += sum(d.startswith("differs") for d in differences)
        for difference in differences:
            print(f"{name}: {difference}")
    print(dict(counts))
    sys.exit(0 if counts["models different"] == 0 and counts["different mapping models"] == 0 else 1)


if __name__ == "__main__":
    main()

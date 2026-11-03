#!/usr/bin/env python3
"""Check the order of Foundation's dictionaries against every observed .mom.

Reads coredata_experiments.py's observations.json and, for each compiled .mom, compares the
NS.keys order of every entities and properties dictionary with the rules of
docs/formats/foundation-collections.md ("Placement", "Growth", "Immutable copies", "What uses
which"): properties are a copy of a mutable dictionary built in the model file's order, entities
the same twice. Corpus models are read from their checkouts at the observed paths.

Usage: coredata_dictionaries.py <observations-dir>
"""

import base64
import json
import os
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coredata_experiments as experiments  # noqa: E402

# 127 buckets: threshold-71-54 and threshold-71-55 grow to it; how many keys it holds is not
# observed (86 follows the rule of the smaller tables) and no observed dictionary reaches it.
BUCKETS = [3, 7, 13, 23, 41, 71, 127]
HELD = [3, 7, 12, 20, 33, 53, 86]
COPY_CAPACITIES = [3, 6, 11, 19, 32, 52, 85]
MASK = (1 << 64) - 1


def nshash(string):
    """NSString's hash, as NomacCore's FoundationStringHash computes it."""
    data = string.encode("utf-16-be")
    units = [data[i] << 8 | data[i + 1] for i in range(0, len(data), 2)]
    length = len(units)
    result = length

    def four(i):
        nonlocal result
        result = (result * 67503105 + units[i] * 16974593 + units[i + 1] * 66049 + units[i + 2] * 257 + units[i + 3]) & MASK

    if length <= 96:
        i = 0
        while i + 4 <= length:
            four(i)
            i += 4
        while i < length:
            result = (result * 257 + units[i]) & MASK
            i += 1
    else:
        for start in [0, length // 2 - 16, length - 32]:
            for i in range(start, start + 32, 4):
                four(i)
    return (result + (result << (length & 31))) & MASK


def place(buckets, key):
    index = nshash(key) % len(buckets)
    while buckets[index] is not None:
        index = (index + 1) % len(buckets)
    buckets[index] = key


def mutable(keys):
    buckets, count = [], 0
    for key in keys:
        held = HELD[BUCKETS.index(len(buckets))] if buckets else 0
        if count + 1 > held:
            old = [k for k in buckets if k is not None]
            buckets = [None] * next(b for b, h in zip(BUCKETS, HELD) if b > len(buckets) and h >= count + 1)
            for k in old:
                place(buckets, k)
        place(buckets, key)
        count += 1
    return buckets


def copied(buckets):
    keys = [k for k in buckets if k is not None]
    size = next(b for b, c in zip(BUCKETS, COPY_CAPACITIES) if c >= len(keys))
    if size == len(buckets):
        return keys
    new = [None] * size
    for key in keys:
        place(new, key)
    return [k for k in new if k is not None]


def archive_objects(data):
    """The $objects of a binary keyed archive: strings, dictionaries as (key, value) lists."""
    trailer = data[-32:]
    offset_size, reference_size = trailer[6], trailer[7]
    count, top, table = struct.unpack(">QQQ", trailer[8:])
    offsets = [int.from_bytes(data[table + i * offset_size:table + (i + 1) * offset_size], "big") for i in range(count)]

    def read(index):
        position = offsets[index]
        marker = data[position]
        high, low = marker >> 4, marker & 0xF

        def length():
            if low != 0xF:
                return low, position + 1
            size = 1 << (data[position + 1] & 0xF)
            return int.from_bytes(data[position + 2:position + 2 + size], "big"), position + 2 + size

        if high == 5:
            n, start = length()
            return data[start:start + n].decode()
        if high == 6:
            n, start = length()
            return data[start:start + 2 * n].decode("utf-16-be")
        if high == 8:
            return ("uid", int.from_bytes(data[position + 1:position + 2 + low], "big"))
        if high in (0xA, 0xD):
            n, start = length()
            references = [int.from_bytes(data[start + k * reference_size:start + (k + 1) * reference_size], "big")
                          for k in range(n * (2 if high == 0xD else 1))]
            if high == 0xA:
                return [read(r) for r in references]
            return [(read(k), read(v)) for k, v in zip(references[:n], references[n:])]
        return None

    return dict(read(top))["$objects"]


def check(model_root, mom):
    objects = archive_objects(mom)
    entities = [e.get("name") for e in model_root.findall("entity")]
    properties = {e.get("name"): [p.get("name") for p in e if p.tag in ("attribute", "relationship", "fetchedProperty")]
                  for e in model_root.findall("entity")}

    def keys(dictionary):
        return [objects[uid] for _, uid in dict(dictionary)["NS.keys"]]

    results = [keys(objects[dict(objects[1])["NSEntities"][1]]) == (copied(mutable(copied(mutable(entities)))) if entities else [])]
    property_results = []
    for item in objects:
        if isinstance(item, list) and item and isinstance(item[0], tuple) and "NSProperties" in dict(item):
            name = objects[dict(item)["NSEntityName"][1]]
            names = properties[name]
            property_results.append(keys(objects[dict(item)["NSProperties"][1]]) == (copied(mutable(names)) if names else []))
    return results, property_results


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    observations = json.loads((Path(sys.argv[1]) / "observations.json").read_text())
    entity_counts, property_counts, files, skipped = [0, 0], [0, 0], 0, 0
    for name, record in observations.items():
        if "compile" not in record:
            continue
        for file, contents in record["compile"]["files"].items():
            if not file.endswith(".mom"):
                continue
            version = os.path.basename(file)[:-4]
            if name.startswith("corpus:"):
                source = name[len("corpus:"):]
                path = os.path.join(source, version + ".xcdatamodel", "contents") if source.endswith(".xcdatamodeld") else os.path.join(source, "contents")
                root = ET.parse(path).getroot()
            else:
                text = experiments.EXPERIMENTS.get(name) or experiments.VERSIONED[name][version]
                root = ET.fromstring(text)
            if len(root.findall("entity")) > HELD[-1]:
                skipped += 1
                continue
            entities, properties = check(root, base64.b64decode(contents))
            files += 1
            entity_counts[0] += sum(entities)
            entity_counts[1] += len(entities)
            property_counts[0] += sum(properties)
            property_counts[1] += len(properties)
    print(f"{files} .mom files: entities {entity_counts[0]} / {entity_counts[1]} properties {property_counts[0]} / {property_counts[1]}"
          f" ({skipped} with more entities than a known table holds)")
    sys.exit(0 if entity_counts[0] == entity_counts[1] and property_counts[0] == property_counts[1] else 1)


if __name__ == "__main__":
    main()

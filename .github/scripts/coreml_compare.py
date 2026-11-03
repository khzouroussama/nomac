#!/usr/bin/env python3
"""Compile every model coreml_experiments.py observed with `nomac coremlc` and compare the files
with coremlc's.

For each model of the `tools` (the iOS 18.0 compile), `metadata`, `types` and `validation`
observations, the input is written to a scratch folder under its observed name, `nomac coremlc
compile` runs on it, and each file of the `.mlmodelc` and the partial Info.plist is compared byte
for byte, but for the order of user metadata entries, which Xcode itself changes from run to run. Prints one line per model that is not identical (refused: nomac's first error line;
different: the first different file) and the totals; then the same for every class generation observed (`coremlc generate --language
Swift`), against the generated files.

Usage: coreml_compare.py <observations.json> <nomac executable>
"""

import base64
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def varint(data, offset):
    value, shift = 0, 0
    while True:
        byte = data[offset]
        value |= (byte & 0x7F) << shift
        offset += 1
        if byte < 0x80:
            return value, offset
        shift += 7


def fields(data):
    """(number, raw field bytes, payload) of each field of a protocol buffer message."""
    offset, found = 0, []
    while offset < len(data):
        start = offset
        key, offset = varint(data, offset)
        if key & 7 == 2:
            length, offset = varint(data, offset)
            payload = data[offset:offset + length]
            offset += length
        elif key & 7 == 0:
            _, offset = varint(data, offset)
            payload = None
        else:
            offset += 8 if key & 7 == 1 else 4
            payload = None
        found.append((key >> 3, data[start:offset], payload))
    return found


def unordered_metadata(description):
    """A ModelDescription with its user metadata entries sorted: Xcode's own order changes from
    run to run (docs/formats/coreml.md)."""
    out = b""
    for number, raw, payload in fields(description):
        if number == 100:
            inner = fields(payload)
            body = b"".join(r for n, r, _ in inner if n != 100) + b"".join(sorted(r for n, r, _ in inner if n == 100))
            out += raw[:len(raw) - len(payload)] + body
        else:
            out += raw
    return out


def equivalent(path, ours, theirs):
    """Equal, or equal but for the order of user metadata entries."""
    if ours == theirs:
        return True
    if path == "metadata.json":
        load = lambda data: json.loads(data, object_pairs_hook=lambda pairs: [(k, sorted(v) if k == "userDefinedMetadata" else v) for k, v in pairs])
        return load(ours) == load(theirs)
    if path == "coremldata.bin" and ours[:0x24] == theirs[:0x24]:
        if ours[0x24:0x2b] == b"generic" and len(ours) == len(theirs):
            length = int.from_bytes(ours[0x4b:0x53], "little")
            return (ours[:0x53] == theirs[:0x53] and ours[0x53 + length:] == theirs[0x53 + length:]
                    and unordered_metadata(ours[0x53:0x53 + length]) == unordered_metadata(theirs[0x53:0x53 + length]))
        if ours[0x24:0x28] == b"spec" and len(ours) == len(theirs):
            body = lambda data: b"".join(unordered_metadata(p) if n == 2 else r for n, r, p in fields(data[0x48:]))
            return ours[:0x48] == theirs[:0x48] and body(ours) == body(theirs)
    return False


def generated(observations):
    """(name, input files, generate options, expected files) of each class generation observed."""
    for name, entry in observations.get("tools", {}).items():
        inputs = {f"{name}.mlpackage/{path}": data for path, data in entry["input"].items()} if isinstance(entry["input"], dict) \
            else {f"{name}.mlmodel": entry["input"]}
        for key, options in [("generate Swift --swift-version 6", ["--swift-version", "6"]),
                             ("generate Swift --swift-version 5 --public-access", ["--swift-version", "5", "--public-access"])]:
            if not entry["runs"][key]["status"]:
                yield name, inputs, options, entry["runs"][key]["files"]
    for section in ["metadata", "types", "validation", "names", "programs", "opsets", "program-validation"]:
        for name, entry in observations.get(section, {}).items():
            inputs = {f"{name}.mlpackage/{path}": data for path, data in entry["input"].items()} if isinstance(entry["input"], dict) \
                else {f"{name}.mlmodel": entry["input"]}
            for variant, run in entry.get("generated", {}).items():
                if not run["status"] and variant != "Objective-C":
                    yield name, inputs, variant.split(), run["files"]


def compare_generated(observations, nomac, scratch, totals):
    for name, inputs, options, expected in generated(observations):
        case = Path(scratch) / f"generate-{name}"
        for path, data in inputs.items():
            (case / path).parent.mkdir(parents=True, exist_ok=True)
            (case / path).write_bytes(base64.b64decode(data))
        model = case / next(iter(inputs)).split("/")[0]
        out = case / "out"
        run = subprocess.run([nomac, "coremlc", "generate", str(model), str(out), "--language", "Swift", *options], capture_output=True, text=True)
        label = f"{name} generate {' '.join(options)}"
        if run.returncode:
            totals["refused"] += 1
            print(f"{label}: refused: {(run.stderr.strip().splitlines() or [''])[0]}")
        else:
            for file, data in expected.items():
                ours = (out / file).read_text() if (out / file).exists() else ""
                theirs = base64.b64decode(data).decode()
                if ours != theirs:
                    totals["different"] += 1
                    line = next((index for index, (a, b) in enumerate(zip(ours.splitlines(), theirs.splitlines())) if a != b),
                                min(len(ours.splitlines()), len(theirs.splitlines())))
                    print(f"{label}: different from line {line + 1}: {theirs.splitlines()[line] if line < len(theirs.splitlines()) else '<end>'!r}")
                    break
            else:
                totals["identical"] += 1
        shutil.rmtree(case)


def cases(observations):
    """(name, input files by relative path, expected files by relative path) of each model."""
    for name, entry in observations.get("tools", {}).items():
        run = entry["runs"]["compile 18.0"]
        if run["status"]:
            continue
        expected = {path[len(name) + len(".mlmodelc/"):]: data for path, data in run["files"].items() if path.startswith(name + ".mlmodelc/")}
        expected["partial.plist"] = run["files"][f"{name}-CoreMLPartialInfo.plist"]
        if isinstance(entry["input"], dict):
            yield name, {f"{name}.mlpackage/{path}": data for path, data in entry["input"].items()}, expected
        else:
            yield name, {f"{name}.mlmodel": entry["input"]}, expected
    for section in ["metadata", "types", "validation", "names", "programs", "opsets", "program-validation"]:
        for name, entry in observations.get(section, {}).items():
            if entry["status"]:
                continue
            inputs = {f"{name}.mlpackage/{path}": data for path, data in entry["input"].items()} if isinstance(entry["input"], dict) \
                else {f"{name}.mlmodel": entry["input"]}
            yield name, inputs, dict(entry["files"])


def main():
    observations = json.loads(Path(sys.argv[1]).read_text())
    nomac = sys.argv[2]
    totals = {"identical": 0, "different": 0, "refused": 0}
    with tempfile.TemporaryDirectory() as scratch:
        for name, inputs, expected in cases(observations):
            case = Path(scratch) / name
            for path, data in inputs.items():
                (case / path).parent.mkdir(parents=True, exist_ok=True)
                (case / path).write_bytes(base64.b64decode(data))
            model = case / next(iter(inputs)).split("/")[0]
            out = case / "out"
            run = subprocess.run([nomac, "coremlc", "compile", str(model), f"{out}/", "--output-partial-info-plist", str(out / "partial.plist")],
                                 capture_output=True, text=True)
            if run.returncode:
                totals["refused"] += 1
                print(f"{name}: refused: {(run.stderr.strip().splitlines() or [''])[0]}")
                continue
            produced = {str(path.relative_to(out / f"{name}.mlmodelc")): path for path in (out / f"{name}.mlmodelc").rglob("*") if path.is_file()}
            if "partial.plist" in expected:
                produced["partial.plist"] = out / "partial.plist"
            different = sorted(path for path in set(expected) | set(produced)
                               if path not in produced or path not in expected
                               or not equivalent(path, produced[path].read_bytes(), base64.b64decode(expected[path])))
            if different:
                totals["different"] += 1
                print(f"{name}: different: {', '.join(different)}")
            else:
                totals["identical"] += 1
            shutil.rmtree(case)
        print("compile: " + " ".join(f"{key} {value}" for key, value in totals.items()))
        totals = {"identical": 0, "different": 0, "refused": 0}
        compare_generated(observations, nomac, scratch, totals)
    print("generate: " + " ".join(f"{key} {value}" for key, value in totals.items()))


if __name__ == "__main__":
    main()

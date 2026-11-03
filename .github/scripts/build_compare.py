#!/usr/bin/env python3
"""Xcode's builds and nomac's, side by side (docs/state/build-driver.md, ADR 0101, ADR 0102).

Usage:
  build_compare.py reference <checkout> <derived-data> <container> <scheme> <configuration> [SETTING=VALUE ...]
      xcodebuild build for generic/platform=iOS with code signing off and the fixed environment
      of corpus/scripts/capture_reference.py; the log goes to <derived-data>.log
  build_compare.py files <reference-derived-data> <other-derived-data>
      every file of Build/ (XCBuildData aside): identical, different, missing, extra
  build_compare.py request <reference-derived-data> <other-derived-data>
      the build-request.json Swift Build recorded, key by key
  build_compare.py sections <reference-mach-o> <other-mach-o>
      a thin 64-bit Mach-O file's sections, byte for byte, and its relocations

Reference outputs are Xcode's and stay outside the repository (CLAUDE.md, legal line).
"""

import filecmp
import glob
import json
import os
import shutil
import struct
import subprocess
import sys


def reference(checkout, derived, container, scheme, configuration, *settings):
    shutil.rmtree(derived, ignore_errors=True)
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "USER": os.environ["USER"],
                   "LOGNAME": os.environ["USER"], "SHELL": "/bin/zsh", "TMPDIR": os.environ.get("TMPDIR", "/tmp/"),
                   "LANG": "en_US.UTF-8",
                   "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")}
    command = ["xcodebuild", "-project", container, "-scheme", scheme, "-configuration", configuration,
               "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
               "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", *settings, "build"]
    with open(derived.rstrip("/") + ".log", "w") as log:
        status = subprocess.run(command, cwd=checkout, env=environment, stdout=log, stderr=subprocess.STDOUT).returncode
    print(f"exit {status}")
    return status


def files(reference_root, other_root):
    def listed(root):
        result = set()
        for directory, _, names in os.walk(os.path.join(root, "Build")):
            for name in names:
                path = os.path.relpath(os.path.join(directory, name), root)
                if "/XCBuildData/" not in path:
                    result.add(path)
        return result
    a, b = listed(reference_root), listed(other_root)
    same = sorted(p for p in a & b if filecmp.cmp(os.path.join(reference_root, p), os.path.join(other_root, p), shallow=False))
    different = sorted((a & b) - set(same))
    print(f"identical {len(same)}, different {len(different)}, only in reference {len(a - b)}, only in other {len(b - a)}")
    for path in different:
        print("DIFF", path)
    for path in sorted(a - b):
        print("MISSING", path)
    for path in sorted(b - a):
        print("EXTRA", path)
    return 0


def request(reference_root, other_root):
    def load(root):
        found = glob.glob(root + "/Build/Intermediates.noindex/XCBuildData/*.xcbuilddata/build-request.json")
        if len(found) != 1:
            sys.exit(f"error: expected one build-request.json under {root}, found {len(found)}")
        return json.load(open(found[0]))

    def flat(value, path=""):
        if isinstance(value, dict):
            for key, item in value.items():
                yield from flat(item, f"{path}/{key}")
        elif isinstance(value, list) and value and isinstance(value[0], dict):
            for index, item in enumerate(value):
                yield from flat(item, f"{path}[{index}]")
        else:
            yield path, value
    a, b = dict(flat(load(reference_root))), dict(flat(load(other_root)))
    differences = [key for key in sorted(set(a) | set(b)) if a.get(key) != b.get(key)]
    for key in differences:
        print(key, "| reference:", json.dumps(a.get(key)), "| other:", json.dumps(b.get(key)))
    print("build requests identical" if not differences else f"{len(differences)} differences")
    return 0


def sections(reference_file, other_file):
    def read(path):
        data = open(path, "rb").read()
        if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
            sys.exit(f"error: {path} is not a thin 64-bit Mach-O file")
        count = struct.unpack_from("<I", data, 16)[0]
        offset, found = 32, {}
        for _ in range(count):
            command, size = struct.unpack_from("<II", data, offset)
            if command == 0x19:
                for index in range(struct.unpack_from("<I", data, offset + 64)[0]):
                    header = offset + 72 + index * 80
                    name = data[header:header + 16].rstrip(b"\0").decode()
                    segment = data[header + 16:header + 32].rstrip(b"\0").decode()
                    _, length, start, _, relocations, relocation_count, _ = struct.unpack_from("<QQIIIII", data, header + 32)
                    body = data[start:start + length] if start else b""
                    found[f"{segment},{name}"] = (body, data[relocations:relocations + 8 * relocation_count])
            offset += size
        return data, found
    a, sa = read(reference_file)
    b, sb = read(other_file)
    print(f"file identical: {a == b}; sizes {len(a)} {len(b)}")
    print("same:", " ".join(k for k in sa if k in sb and sa[k][0] == sb[k][0]))
    for key in (k for k in sa if k in sb and sa[k][0] != sb[k][0]):
        x, y = sa[key][0], sb[key][0]
        first = next((i for i in range(min(len(x), len(y))) if x[i] != y[i]), min(len(x), len(y)))
        print(f"DIFF {key}: sizes {len(x)} {len(y)}, first byte differing at {first}, relocations same: {sa[key][1] == sb[key][1]}")
    for key in (k for k in sa if k not in sb):
        print("only in reference:", key)
    for key in (k for k in sb if k not in sa):
        print("only in other:", key)
    return 0


COMMANDS = {"reference": reference, "files": files, "request": request, "sections": sections}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    sys.exit(COMMANDS[sys.argv[1]](*sys.argv[2:]))

#!/usr/bin/env python3
"""Observe what Xcode makes of .strings, .stringsdict and .xcstrings files.

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR). Every input is written here from scratch:

- `copy`: one iOS app whose synchronized folder holds one en.lproj/<case>.strings or
  .stringsdict per case below, built with xcodebuild once per STRINGS_FILE_OUTPUT_ENCODING
  (the iOS default, binary, then UTF-16 and UTF-8). Records each compiled file and the notes
  builtin-copyStrings printed for it.
- `xcstrings`: `xcstringstool compile` (and `--dry-run`) run directly on each catalog below with
  the options Xcode's build passes (`--output-directory <dir> <file>`), plus `-l` and
  `--serialization-format binary` variants. Records every output file and the dry-run list.
- `generate-symbols`: `xcstringstool generate-symbols` in each language on the same catalogs, the
  extraction-state matrices, the `symbols-*` catalogs (names, escapes, specifiers, arguments,
  comments, tables, collisions; each written as `<table>.xcstrings`) and the corpus's catalogs.
  Records every output file and the diagnostics.
- `xcstrings-build`: one app with a few of the catalogs, built with xcodebuild, to record which
  tasks the build runs on xcstringstool's outputs.

Outputs go to <output-dir>/<experiment>/: observations.json (base64 file contents) and the
build logs. Nothing here is Xcode's own content: only its outputs for these inputs.

Usage: strings_experiments.py <output-dir> [experiment ...]
"""

import base64
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pif_experiments import write_project  # noqa: E402

PLIST_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
              '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n')


def plist(body):
    return (PLIST_HEAD + body + "</plist>\n").encode()


def many(count, prefix="k"):
    return "".join(f'"{prefix}{i:04}" = "value {i}";\n' for i in range(count)).encode()


STRINGS = {
    "simple": b'"key" = "value";\n',
    "empty": b"",
    "whitespace": b"\n  \n",
    "comments": b'/* a comment */\n// another\n',
    "two": b'"b" = "2";\n"a" = "1";\n',
    "unsorted": b'"zeta" = "z";\n"Alpha" = "A";\n"alpha" = "a";\n"_x" = "u";\n"10" = "ten";\n"9" = "nine";\n',
    "same-values": b'"a" = "same";\n"b" = "same";\n"c" = "other";\n',
    "key-is-value": b'"a" = "b";\n"b" = "a";\n',
    "shorthand": b'"key";\n',
    "unquoted": b'key = value;\nother = "x y";\n',
    "escapes": b'"k1" = "line\\nnext";\n"k2" = "tab\\tq\\"b\\\\";\n"k3" = "\\U00e9\\U2603";\n"k4" = "\\101\\102";\n',
    "unicode": '"café" = "naïve ☃ \U0001F600";\n"ascii" = "plain";\n'.encode(),
    "utf8-bom": b"\xef\xbb\xbf" + b'"key" = "value";\n',
    "utf16le-bom": "﻿\"key\" = \"value\";\n\"é\" = \"è\";\n".encode("utf-16-le"),
    "utf16be-bom": "﻿\"key\" = \"value\";\n".encode("utf-16-be"),
    "long-14": b'"k" = "12345678901234";\n',
    "long-15": b'"k" = "123456789012345";\n',
    "long-300": b'"k" = "' + b"x" * 300 + b'";\n',
    "long-70000": b'"k" = "' + b"y" * 70000 + b'";\n',
    "unicode-long": ('"k" = "' + "é" * 20 + '";\n').encode(),
    "many-20": many(20),
    "many-200": many(200),
    "many-300": many(300),
    "nested": b'"array" = ("a", "b");\n"dict" = { "x" = "1"; };\n',
    "data": b'"d" = <0fbd77>;\n',
    "xml-format": plist("<dict>\n\t<key>k</key>\n\t<string>v</string>\n</dict>\n"),
    "xml-typed": plist("<dict>\n\t<key>i</key>\n\t<integer>7</integer>\n\t<key>b</key>\n\t<true/>\n"
                       "\t<key>r</key>\n\t<real>1.5</real>\n</dict>\n"),
    "duplicate-keys": b'"k" = "first";\n"k" = "second";\n',
    "empty-value": b'"k" = "";\n',
    "no-trailing-newline": b'"key" = "value";',
    "crlf": b'"a" = "1";\r\n"b" = "2";\r\n',
    # Round 2: which equal values the binary writer stores once.
    "xml-duplicates": plist("<dict>\n\t<key>a</key>\n\t<integer>1</integer>\n\t<key>b</key>\n\t<integer>1</integer>\n"
                            "\t<key>c</key>\n\t<real>1</real>\n\t<key>d</key>\n\t<true/>\n\t<key>e</key>\n\t<true/>\n"
                            "\t<key>f</key>\n\t<data>AAE=</data>\n\t<key>g</key>\n\t<data>AAE=</data>\n"
                            "\t<key>h</key>\n\t<real>2.5</real>\n\t<key>i</key>\n\t<real>2.5</real>\n"
                            "\t<key>j</key>\n\t<integer>-1</integer>\n\t<key>k</key>\n\t<integer>300</integer>\n"
                            "\t<key>l</key>\n\t<integer>70000</integer>\n\t<key>m</key>\n\t<integer>5000000000</integer>\n"
                            "\t<key>n</key>\n\t<false/>\n\t<key>o</key>\n\t<date>2001-01-01T00:00:00Z</date>\n"
                            "\t<key>p</key>\n\t<string>1</string>\n</dict>\n"),
    "container-duplicates": b'"a" = { "x" = "1"; };\n"b" = { "x" = "1"; };\n"c" = ("1", "1");\n"d" = ("1", "1");\n"e" = ();\n"f" = ();\n"g" = {};\n',
    # Round 3: the sizes of offsets and object references at their boundaries. With one key,
    # the offset table starts at 16 + the value's length (15 to 255 characters).
    "table-at-255": b'"k" = "' + b"t" * 239 + b'";\n',
    "table-at-256": b'"k" = "' + b"t" * 240 + b'";\n',
    "objects-255": "".join(f'"k{i:03}" = "v{min(i, 125):03}";\n' for i in range(127)).encode(),
    "objects-256": "".join(f'"k{i:03}" = "v{min(i, 126):03}";\n' for i in range(128)).encode(),
    "objects-257": "".join(f'"k{i:03}" = "v{i:03}";\n' for i in range(128)).encode(),
    "key-order-unicode": '"\uff01" = "1";\n"\U0001F600" = "2";\n"\u00e9" = "3";\n"e\u0301x" = "4";\n"z" = "5";\n'.encode(),
    # U+FEFF at the start, inside and at the end of values and keys (nextcloud's NextcloudKitUI kn.lproj)
    "xml-bom-values": plist("<dict>\n\t<key>k</key>\n\t<string>\ufeffv</string>\n\t<key>m</key>\n\t<string>a\ufeffb</string>\n"
                            "\t<key>e</key>\n\t<string>v\ufeff</string>\n\t<key>o</key>\n\t<string>\ufeff</string>\n"
                            "\t<key>t</key>\n\t<string>\ufeff\ufeffx</string>\n\t<key>r</key>\n\t<string>&#xFEFF;v</string>\n"
                            "\t<key>s</key>\n\t<string> \ufeffv</string>\n</dict>\n"),
    "xml-bom-keys": plist("<dict>\n\t<key>\ufeffk</key>\n\t<string>v</string>\n\t<key>a\ufeffb</key>\n\t<string>w</string>\n</dict>\n"),
    "text-bom-values": '"k" = "\ufeffv";\n"m" = "a\ufeffb";\n"\ufeffkey" = "w";\n"u" = "\\UFEFFv";\n'.encode(),
}

STRINGSDICT = {
    "plural": plist("""<dict>
\t<key>%d items</key>
\t<dict>
\t\t<key>NSStringLocalizedFormatKey</key>
\t\t<string>%#@items@</string>
\t\t<key>items</key>
\t\t<dict>
\t\t\t<key>NSStringFormatSpecTypeKey</key>
\t\t\t<string>NSStringPluralRuleType</string>
\t\t\t<key>NSStringFormatValueTypeKey</key>
\t\t\t<string>d</string>
\t\t\t<key>one</key>
\t\t\t<string>%d item</string>
\t\t\t<key>other</key>
\t\t\t<string>%d items</string>
\t\t</dict>
\t</dict>
</dict>
"""),
    "two-entries": plist("""<dict>
\t<key>b</key>
\t<dict>
\t\t<key>NSStringLocalizedFormatKey</key>
\t\t<string>%#@n@</string>
\t\t<key>n</key>
\t\t<dict>
\t\t\t<key>NSStringFormatSpecTypeKey</key>
\t\t\t<string>NSStringPluralRuleType</string>
\t\t\t<key>NSStringFormatValueTypeKey</key>
\t\t\t<string>d</string>
\t\t\t<key>other</key>
\t\t\t<string>%d b</string>
\t\t</dict>
\t</dict>
\t<key>a</key>
\t<dict>
\t\t<key>NSStringLocalizedFormatKey</key>
\t\t<string>%#@n@</string>
\t\t<key>n</key>
\t\t<dict>
\t\t\t<key>NSStringFormatSpecTypeKey</key>
\t\t\t<string>NSStringPluralRuleType</string>
\t\t\t<key>NSStringFormatValueTypeKey</key>
\t\t\t<string>d</string>
\t\t\t<key>other</key>
\t\t\t<string>%d a</string>
\t\t</dict>
\t</dict>
</dict>
"""),
    "variable-width": plist("""<dict>
\t<key>Title</key>
\t<dict>
\t\t<key>NSStringVariableWidthRuleType</key>
\t\t<dict>
\t\t\t<key>1</key>
\t\t\t<string>T</string>
\t\t\t<key>20</key>
\t\t\t<string>Title</string>
\t\t</dict>
\t</dict>
</dict>
"""),
    "empty-dict": plist("<dict/>\n"),
    "bom-forms": plist("""<dict>
\t<key>\ufeff%d items</key>
\t<dict>
\t\t<key>NSStringLocalizedFormatKey</key>
\t\t<string>\ufeff%#@items@</string>
\t\t<key>items</key>
\t\t<dict>
\t\t\t<key>NSStringFormatSpecTypeKey</key>
\t\t\t<string>NSStringPluralRuleType</string>
\t\t\t<key>NSStringFormatValueTypeKey</key>
\t\t\t<string>d</string>
\t\t\t<key>one</key>
\t\t\t<string>\ufeff%d item</string>
\t\t\t<key>other</key>
\t\t\t<string>%d \ufeffitems</string>
\t\t</dict>
\t</dict>
</dict>
"""),
    "openstep": b'{ "k" = { "NSStringLocalizedFormatKey" = "%#@n@"; }; }\n',
}

ENCODINGS = [None, "UTF-16", "UTF-8"]


def run(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True)


def b64(data):
    return base64.b64encode(data).decode()


def copy_experiment(out):
    work = Path("/tmp/nomac-strings-experiments/copy")
    shutil.rmtree(work, ignore_errors=True)
    files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n"}
    project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
    for name, data in STRINGS.items():
        (work / "Src/en.lproj").mkdir(parents=True, exist_ok=True)
        (work / f"Src/en.lproj/{name}.strings").write_bytes(data)
    for name, data in STRINGSDICT.items():
        (work / f"Src/en.lproj/{name}.stringsdict").write_bytes(data)
    observations = {}
    for encoding in ENCODINGS:
        label = encoding or "default"
        build = work / f"build-{label}"
        args = ["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                f"SYMROOT={build}/products", f"OBJROOT={build}/intermediates", "build"]
        if encoding:
            args.append(f"STRINGS_FILE_OUTPUT_ENCODING={encoding}")
        proc = run(args, cwd=work)
        log = proc.stdout.decode(errors="replace") + proc.stderr.decode(errors="replace")
        (out / f"build-{label}.log").write_text(log)
        app = build / "products/Debug-iphoneos/T.app/en.lproj"
        results = {}
        for name in list(STRINGS) + list(STRINGSDICT):
            file_name = f"{name}.strings" if name in STRINGS else f"{name}.stringsdict"
            output = app / file_name
            notes = sorted(set(re.findall(rf"/en\.lproj/{re.escape(file_name)}:[0-9:]* (\w+: .*?) \(in target", log)))
            results[file_name] = {"output": b64(output.read_bytes()) if output.exists() else None, "notes": notes}
        observations[label] = {"status": proc.returncode, "files": results}
        print(f"[copy {label}] status {proc.returncode}, {sum(r['output'] is not None for r in results.values())} outputs", flush=True)
    return observations


# `copy-escapes`: \U escapes that are UTF-16 surrogates, each file in a build of its own (a file
# Xcode rejects fails its build).
ESCAPES = {
    "surrogate-pair": b'"k" = "\\UD83D\\UDE00";\n',
    "lone-high": b'"k" = "\\UD83D";\n',
    "lone-low": b'"k" = "\\UDE00";\n',
    "high-then-other": b'"k" = "\\UD83Dx";\n',
    "pair-in-key": b'"\\UD83D\\UDE00" = "v";\n',
    "high-then-escape": b'"k" = "\\UD83D\\U0041";\n',
    "two-highs-then-low": b'"k" = "\\UD83D\\UD83D\\UDE00";\n',
    "low-then-high": b'"k" = "\\UDE00\\UD83D";\n',
}


def copy_escapes_experiment(out):
    observations = {}
    for name, data in ESCAPES.items():
        work = Path("/tmp/nomac-strings-experiments/copy-escapes") / name
        shutil.rmtree(work, ignore_errors=True)
        files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n"}
        project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
        (work / "Src/en.lproj").mkdir(parents=True)
        (work / "Src/en.lproj/Escape.strings").write_bytes(data)
        build = work / "build"
        proc = run(["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                    "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                    f"SYMROOT={build}/products", f"OBJROOT={build}/intermediates", "build"], cwd=work)
        log = proc.stdout.decode(errors="replace") + proc.stderr.decode(errors="replace")
        output = build / "products/Debug-iphoneos/T.app/en.lproj/Escape.strings"
        messages = sorted(set(re.findall(r"Escape\.strings[:0-9]* ((?:error|warning|note): .*?) \(in target", log)))
        observations[name] = {"status": proc.returncode, "output": b64(output.read_bytes()) if output.exists() else None,
                              "messages": messages}
        print(f"[copy-escapes {name}] status {proc.returncode} {messages}", flush=True)
    return observations


def catalog(strings, source="en", version="1.0", extra=None):
    document = {"sourceLanguage": source, "strings": strings, "version": version}
    document.update(extra or {})
    return json.dumps(document, indent=2, ensure_ascii=False).encode() + b"\n"


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def plural(**forms):
    return {"variations": {"plural": {form: unit(value) for form, value in forms.items()}}}


def manual(**fields):
    return {"extractionState": "manual", **fields}


def substituted(value, substitutions):
    return {"stringUnit": {"state": "translated", "value": value}, "substitutions": substitutions}


def substitution(specifier, arg_num=None, **forms):
    entry = {"variations": {"plural": {form: unit(value) for form, value in (forms or {"other": "%arg"}).items()}}}
    if specifier is not None:
        entry["formatSpecifier"] = specifier
    if arg_num is not None:
        entry["argNum"] = arg_num
    return entry


CATALOGS = {
    "empty": catalog({}),
    "one-key-no-localizations": catalog({"Hello": {}}),
    "source-only": catalog({"Hello": {"localizations": {"en": unit("Hello there")}}}),
    "source-same-as-key": catalog({"Hello": {"localizations": {"en": unit("Hello")}}}),
    "translated": catalog({"Hello": {"localizations": {"fr": unit("Bonjour"), "de": unit("Hallo")}}}),
    "states": catalog({"a": {"localizations": {"fr": unit("A-fr", "new")}},
                       "b": {"localizations": {"fr": unit("B-fr", "needs_review")}},
                       "c": {"localizations": {"fr": unit("C-fr", "translated")}},
                       "d": {"localizations": {"fr": unit("D-fr", "stale")}}}),
    "should-not-translate": catalog({"Brand": {"shouldTranslate": False}, "Hello": {"localizations": {"fr": unit("Bonjour")}}}),
    "extraction-states": catalog({"a": {"extractionState": "manual", "localizations": {"fr": unit("A")}},
                                  "b": {"extractionState": "stale", "localizations": {"fr": unit("B")}},
                                  "c": {"extractionState": "extracted_with_value", "localizations": {"en": unit("C-en", "new")}}}),
    "comment": catalog({"Hello": {"comment": "A greeting", "localizations": {"fr": unit("Bonjour")}}}),
    "plural-source": catalog({"%lld apples": {"localizations": {"en": plural(one="%lld apple", other="%lld apples")}}}),
    "plural-translated": catalog({"%lld apples": {"localizations": {
        "en": plural(one="%lld apple", other="%lld apples"),
        "fr": plural(one="%lld pomme", other="%lld pommes"),
        "ru": plural(one="%lld a", few="%lld b", many="%lld c", other="%lld d")}}}),
    "plural-formats": catalog({
        "%d d": {"localizations": {"en": plural(one="%d x", other="%d xs")}},
        "%@ at": {"localizations": {"en": plural(one="%@ x", other="%@ xs")}},
        "%u u": {"localizations": {"en": plural(one="%u x", other="%u xs")}},
        "%ld ld": {"localizations": {"en": plural(one="%ld x", other="%ld xs")}},
        "%f f": {"localizations": {"en": plural(one="%f x", other="%f xs")}},
        "%1$lld pos": {"localizations": {"en": plural(one="%1$lld x", other="%1$lld xs")}},
        "zero %lld": {"localizations": {"en": plural(zero="none", one="%lld x", other="%lld xs")}},
        "no format": {"localizations": {"en": plural(one="one", other="many")}}}),
    "substitutions": catalog({"%lld files in %lld folders": {"localizations": {"en": {
        "stringUnit": {"state": "translated", "value": "%#@files@ in %#@folders@"},
        "substitutions": {
            "files": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {
                "one": unit("%arg file"), "other": unit("%arg files")}}},
            "folders": {"argNum": 2, "formatSpecifier": "lld", "variations": {"plural": {
                "one": unit("%arg folder"), "other": unit("%arg folders")}}}}}}}}),
    "device": catalog({"Tap": {"localizations": {"en": {"variations": {"device": {
        "iphone": unit("Tap"), "mac": unit("Click"), "other": unit("Select")}}}}}}),
    "device-plural": catalog({"%lld taps": {"localizations": {"en": {"variations": {"device": {
        "iphone": plural(one="%lld tap", other="%lld taps"), "other": plural(one="%lld click", other="%lld clicks")}}}}}}),
    "width": catalog({"Title": {"localizations": {"en": {"variations": {"width": {
        "1": unit("T"), "20": unit("Title")}}}}}}),
    "many-languages": catalog({"Hi": {"localizations": {lang: unit(f"Hi-{lang}") for lang in
                                                        ["zh-Hans", "pt-BR", "fr", "de", "ja", "en-GB", "es-419", "ar"]}}}),
    "non-ascii": catalog({"café": {"localizations": {"fr": unit("café ☃ \U0001F600"), "en": unit("coffee")}}}),
    "escapes": catalog({"quote\"back\\slash\nnl": {"localizations": {"fr": unit("a\"b\\c\nd\te<f>&g")}}}),
    "mixed": catalog({"Hello": {"localizations": {"fr": unit("Bonjour")}},
                      "%lld apples": {"localizations": {"fr": plural(one="%lld pomme", other="%lld pommes")}}}),
    "source-fr": catalog({"Bonjour": {"localizations": {"en": unit("Hello")}}}, source="fr"),
    "unsorted-keys": catalog({"zeta": {"localizations": {"fr": unit("z")}}, "Alpha": {"localizations": {"fr": unit("A")}},
                              "alpha": {"localizations": {"fr": unit("a")}}, "10": {"localizations": {"fr": unit("t")}},
                              "9": {"localizations": {"fr": unit("n")}}}),
    "version-1.1": catalog({"Hello": {"localizations": {"fr": unit("Bonjour")}}}, version="1.1"),
    "empty-value": catalog({"Hello": {"localizations": {"fr": unit("")}}}),
}

# Round 2: which keys the source language gets, by extraction state and source unit, with
# and without another language; format specifiers in plurals; variations inside variations;
# the order of keys that UTF-16 and scalar order sort differently.
SOURCE_UNITS = {"none": None, "same": ("translated", None), "differs": ("translated", "Other"),
                "new": ("new", "Other"), "new-same": ("new", None), "review": ("needs_review", "Other")}
EXTRACTION_STATES = {"absent": None, "manual": "manual", "stale": "stale", "with-value": "extracted_with_value",
                     "migrated": "migrated"}


def source_matrix(with_other):
    strings = {}
    for state_name, state in EXTRACTION_STATES.items():
        for unit_name, source in SOURCE_UNITS.items():
            key = f"{state_name}-{unit_name}"
            entry = {}
            if state:
                entry["extractionState"] = state
            localizations = {}
            if source:
                localizations["en"] = unit(source[1] or key, source[0])
            if with_other:
                localizations["fr"] = unit(key + "-fr")
            if localizations:
                entry["localizations"] = localizations
            strings[key] = entry
    return catalog(strings)


def plural_format(spec):
    return {"localizations": {"en": plural(one=f"%{spec} x", other=f"%{spec} xs")}}


CATALOGS.update({
    "source-matrix": source_matrix(True),
    "source-matrix-alone": source_matrix(False),
    "plural-specifiers": catalog({f"{spec} {name}": plural_format(spec) for name, spec in [
        ("d", "d"), ("i", "i"), ("u", "u"), ("ld", "ld"), ("lu", "lu"), ("li", "li"), ("lld", "lld"),
        ("llu", "llu"), ("at", "@"), ("f", "f"), ("lf", "lf"), ("g", "g"), ("x", "x"), ("pos1", "1$lld"),
        ("zd", "zd"), ("hd", "hd"), ("e", "e")]}),
    "plural-forms": catalog({
        "%lld only-other": {"localizations": {"en": plural(other="%lld things")}},
        "%lld zero": {"localizations": {"en": plural(zero="no things", one="%lld thing", other="%lld things")}},
        "%lld two": {"localizations": {"en": plural(one="%lld", two="%lld two", few="%lld few", other="%lld o")}},
        "%lld one-no-number": {"localizations": {"en": plural(one="a thing", other="%lld things")}}}),
    "plural-two-args": catalog({
        "%@ has %lld apples": {"localizations": {"en": plural(one="%1$@ has %2$lld apple", other="%1$@ has %2$lld apples")}},
        "%lld apples for %@": {"localizations": {"en": plural(one="%lld apple for %@", other="%lld apples for %@")}}}),
    "plural-other-language": catalog({
        "Plain": {"localizations": {"en": unit("Plain"), "fr": plural(one="%lld un", other="%lld des")}},
        "%lld n": {"localizations": {"en": plural(one="%lld n", other="%lld ns"), "fr": unit("%lld fr")}}}),
    "device-all": catalog({"Tap": {"localizations": {"en": {"variations": {"device": {
        name: unit(f"Tap-{name}") for name in ["iphone", "ipad", "ipod", "mac", "applewatch", "appletv", "applevision", "other"]}}}}}}),
    "device-no-other": catalog({"Tap": {"localizations": {"en": {"variations": {"device": {
        "iphone": unit("Tap"), "mac": unit("Click")}}}}}}),
    "device-nested-plural": catalog({"%lld taps": {"localizations": {"en": {"variations": {"device": {
        "iphone": plural(one="%lld tap", other="%lld taps"), "other": unit("%lld clicks")}}}}}}),
    "width-plural": catalog({"%lld w": {"localizations": {"en": {"variations": {"width": {
        "1": plural(one="%lld", other="%lld"), "20": plural(one="%lld w", other="%lld ws")}}}}}}),
    "substitution-device": catalog({"%lld in %lld": {"localizations": {"en": {
        "stringUnit": {"state": "translated", "value": "%#@a@ in %#@b@"},
        "substitutions": {
            "a": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {"one": unit("%arg a"), "other": unit("%arg as")}}},
            "b": {"argNum": 2, "formatSpecifier": "lld", "variations": {"plural": {"one": unit("%arg b"), "other": unit("%arg bs")}}}}}}}}),
    "substitution-plural-outer": catalog({"%lld of %lld": {"localizations": {"en": {
        "variations": {"plural": {
            "one": {"stringUnit": {"state": "translated", "value": "%lld of %#@total@"}},
            "other": {"stringUnit": {"state": "translated", "value": "%lld of %#@total@"}}}},
        "substitutions": {
            "total": {"argNum": 2, "formatSpecifier": "lld", "variations": {"plural": {"one": unit("%arg t"), "other": unit("%arg ts")}}}}}}}}),
    "percent-literal": catalog({"100%% done": {"localizations": {"fr": unit("100%% fait")}}}),
    "key-order": catalog({k: {"localizations": {"fr": unit(k)}} for k in
                          ["\uff01", "\U0001F600", "z", "Z", "_", "\u00e9", "e", "a b", "a", "aa", "A"]}),
    "empty-source-value": catalog({"Hello": {"localizations": {"en": unit(""), "fr": unit("Bonjour")}}}),
    "string-set": catalog({"Phrase": {"localizations": {"en": {"stringSet": {"state": "translated", "values": ["a", "b"]}}}}}),
})

# Round 3 (corpus differences): languages without a unit for manual and migrated strings; named
# arguments; the language codes of the lproj folders; key order in .stringsdict files.
# Two identifiers with one folder (iw and he) give a folder whose contents change from one run
# to the next, so each identifier here has a folder of its own.
LANGUAGES = ["en", "fr", "kmr", "kmr-TR", "ckb", "ckb-IR", "iw", "in", "ji", "no", "nb-NO", "tl", "mo", "sh", "zh-CN",
             "zh-TW", "zh-HK", "zh-Hans", "zh-Hant", "EN-gb", "pt-PT", "pt-BR", "sr-Latn", "sr-Cyrl", "yue", "yue-Hant",
             "es-419", "es-MX", "ars", "arc", "ber", "sgn", "und", "mul", "zxx", "en-US-POSIX", "de-CH-1996", "x-test",
             "art-lojban", "i-klingon", "nn", "sv-FI", "az-Arab", "uz-Cyrl", "mn-Mong", "pa-Arab", "ms-Arab", "Base",
             "en_AU", "pt_PT", "uz_Latn", "az_Cyrl", "fr_CA", "zh_Hans_SG", "es_419", "DE", "de-at", "es-us", "PT-ao"]
CATALOGS.update({
    "unlocalized-languages": catalog({
        "manual-en-plain": {"extractionState": "manual", "localizations": {"en": unit("Plain")}},
        "manual-en-plural %lld": {"extractionState": "manual", "localizations": {"en": plural(one="%lld x", other="%lld xs")}},
        "manual-none": {"extractionState": "manual"},
        "migrated-en-plain": {"extractionState": "migrated", "localizations": {"en": unit("Plain")}},
        "absent-en-plain": {"localizations": {"en": unit("Plain")}},
        "stale-en-plain": {"extractionState": "stale", "localizations": {"en": unit("Plain")}},
        "manual-no-translate": {"extractionState": "manual", "shouldTranslate": False, "localizations": {"en": unit("Plain")}},
        "absent-no-translate": {"shouldTranslate": False, "localizations": {"en": unit("Plain")}},
        "manual-fr-only": {"extractionState": "manual", "localizations": {"fr": unit("Fr")}},
        "other": {"localizations": {"fr": unit("autre"), "de": unit("andere")}}}),
    "named-arguments": catalog({
        "plain %(count)lld": {"localizations": {"fr": unit("%(count)lld et %(name)@")}},
        "plural %(count)lld": {"localizations": {"fr": plural(one="%(count)lld x", other="%(count)lld xs %(name)@")}},
        "second %(count)lld": {"localizations": {"fr": plural(one="%(name)@ %(count)lld x", other="%(name)@ %(count)lld xs")}},
        "sub": {"localizations": {"fr": {
            "stringUnit": {"state": "translated", "value": "%#@a@ %(name)@"},
            "substitutions": {"a": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {
                "one": unit("%arg a"), "other": unit("%arg as")}}}}}}}}),
    "language-codes": catalog({"Hi": {"localizations": {language: unit(f"Hi-{language}") for language in LANGUAGES}}}),
    "stringsdict-key-order": catalog({k: {"localizations": {"fr": plural(other=f"%lld {k}")}} for k in
                                      ["\uff01", "\U0001F600", "z", "Z", "_", "\u00e9", "e", "a b", "a", "aa", "A"]}),
    "substitution-precision": catalog({"%.1f m": {"localizations": {"fr": {
        "stringUnit": {"state": "translated", "value": "%#@m@ %#@n@"},
        "substitutions": {
            "m": {"argNum": 1, "formatSpecifier": ".1f", "variations": {"plural": {"one": unit("%arg m"), "other": unit("%arg ms")}}},
            "n": {"formatSpecifier": "-3ld", "variations": {"plural": {"one": unit("%arg n"), "other": unit("%arg ns")}}}}}}}}),
})

# Round 4: which strings with no unit in a language get their key there (icecubes' manual
# plurals do, `unlocalized-languages` `manual-en-plain` does not).
SOURCE_ONLY = {
    "plural": plural(one="%lld x", other="%lld xs"),
    "plain": unit("Plain"),
    "device": {"variations": {"device": {"iphone": unit("Tap"), "other": unit("Select")}}},
    "device-no-other": {"variations": {"device": {"iphone": unit("Tap")}}},
    "substitution": {"stringUnit": {"state": "translated", "value": "%#@a@"}, "substitutions": {"a": {
        "argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {"one": unit("%arg a"), "other": unit("%arg as")}}}}},
    "width": {"variations": {"width": {"1": unit("T"), "20": unit("Title")}}},
    "string-set": {"stringSet": {"state": "translated", "values": ["a", "b"]}},
}
CATALOGS.update({
    "unlocalized-variations": catalog({
        **{f"{state_name}-{kind} %lld": ({"extractionState": state} if state else {}) | {"localizations": {"en": localization}}
           for state_name, state in EXTRACTION_STATES.items() for kind, localization in SOURCE_ONLY.items()},
        "manual-plural-fr-plain %lld": {"extractionState": "manual", "localizations": {
            "en": plural(one="%lld x", other="%lld xs"), "fr": unit("fr")}},
        "manual-plural-new %lld": {"extractionState": "manual", "localizations": {"en": {"variations": {"plural": {
            "one": unit("%lld x", "new"), "other": unit("%lld xs", "new")}}}}},
        "other": {"localizations": {"fr": unit("autre"), "de": unit("andere")}}}),
    # Which manual strings other languages fill with their key: those whose generated symbol takes arguments.
    "unlocalized-specifiers": catalog({
        **{f"s{index:02}": manual(localizations={"en": unit(value)}) for index, value in enumerate([
            "a %@", "%1$@ and %2$lld", "%lld", "%(n)lld", "%% done", "100%", "%#@x@", "%d", "%i", "%u", "%f", "%g", "%e",
            "%x", "%ld", "%lu", "%lf", "%c", "%p", "%llu", "%lli", "%S", "%5.2f", "%-d", "%1$s", "%@ %s", "%s %@", "%hd",
            "%n", "%1$@ %3$@", "%1$@ %1$lld", "%2$@", "%(n)lld %(n)lld"])},
        "%@ key": manual(localizations={"en": unit("plain")}),
        "new": manual(localizations={"en": unit("%@", "new")}),
        "no-type": manual(localizations={"en": unit("%@"), "de": unit("%s")}),
        "other-language": manual(localizations={"en": unit("x"), "de": unit("%@")}),
        "other-inconsistent": manual(localizations={"en": unit("%@"), "de": unit("%1$@ %1$lld")}),
        "key-only %@": manual(),
        "key-only %s": manual(),
        "self %@": manual(localizations={"en": unit("%@")}),
        "not-manual": {"localizations": {"en": unit("%@ x")}},
        "migrated": {"extractionState": "migrated", "localizations": {"en": unit("%@ x")}},
        "untranslatable": manual(shouldTranslate=False, localizations={"en": unit("%@ x")}),
        "plural": manual(localizations={"en": plural(one="%lld a", other="%lld b")}),
        "plural-no-type": manual(localizations={"en": plural(one="one", other="%lld %s")}),
        "plural-inconsistent": manual(localizations={"en": plural(one="%1$lld", other="%1$@")}),
        "substitution": manual(localizations={"en": substituted("%#@x@", {"x": substitution("lld")})}),
        "substitution-no-type": manual(localizations={"en": substituted("%#@x@", {"x": substitution("s")})}),
        "substitution-skipped": manual(localizations={"en": substituted("%#@x@ %3$@", {"x": substitution("lld")})}),
        "other": manual(localizations={"en": unit("other"), "fr": unit("autre")})}),
    "unlocalized-source-fr": catalog({
        "manual-plural %lld": {"extractionState": "manual", "localizations": {"fr": plural(one="%lld x", other="%lld xs")}},
        "other": {"localizations": {"en": unit("other"), "de": unit("andere")}}}, source="fr"),
})

# Round 5: the format specifier grammar, one catalog per candidate and probe (a plural can only
# take a number, so `a-` shows whether the candidate is a number, `b-` whether it is a specifier
# at all by the position of the number after it, `p-` whether a plain string loses its argument
# name), how a plural finds its number, and the diagnostics.
SPECIFIER_CANDIDATES = ["% d", "%-d", "%+d", "%#x", "%0d", "%'d", "%jd", "%td", "%zd", "%a", "%A", "%Lf", "%hhd", "%qd", "%C",
                        "%S", "%c", "%s", "%p", "%n", "%F", "%G", "%5.2f", "%*d", "%.*f", "%k", "%(x) d", "%(x)ja", "%(x)",
                        "%ld", "%lu", "%hu", "%lx", "%llx", "%lf", "%e", "%E", "%g", "%i", "%o", "%X", "%u", "%D", "%U", "%O",
                        "%ls", "%hs", "%lc", "%@", "%2$@", "%2$d", "%(x)@", "%l@", "%-5@", "%.3@", "%z@", "%%", "%1", "%1 d",
                        "%Ld", "%I", "%m", "%ll@", "%hhx", "%1$(x)d", "%(x)1$d", "% 5d", "%+.2f", "%#@x@", "%5$d"]
for index, candidate in enumerate(SPECIFIER_CANDIDATES):
    manual_entry = {"extractionState": "manual"}
    CATALOGS[f"specifier-{index:02}-a"] = catalog({"k": manual_entry | {"localizations": {"en": plural(other=f"%(a)@ {candidate}")}}})
    CATALOGS[f"specifier-{index:02}-b"] = catalog({"k": manual_entry | {"localizations": {"en": plural(other=f"%(a)@ {candidate} %(n)lld")}}})
    CATALOGS[f"specifier-{index:02}-p"] = catalog({"k": manual_entry | {"localizations": {"en": unit(f"[%(a)@ {candidate}]")}}})
CATALOGS.update({
    "plural-inference-own-differs": catalog({"k": {"localizations": {"en": plural(one="%lld x", other="%lld xs"),
                                                                     "fr": plural(one="%@ %d y", other="%@ %d ys")}}}),
    "plural-inference-own-none": catalog({"k": {"localizations": {"en": plural(one="%@ %lld x", other="%@ %lld xs"),
                                                                  "fr": plural(one="y", other="ys")}}}),
    "plural-inference-source-plain": catalog({"k": {"localizations": {"en": unit("%lld x"), "fr": plural(one="y", other="ys")}}}),
    "plural-inference-one-type-twice": catalog({"k": {"localizations": {"en": plural(one="%lld x", other="%lld xs"),
                                                                        "fr": plural(one="%d %d y", other="%d ys")}}}),
    "plural-inference-source-none": catalog({"k": {"localizations": {"en": plural(one="x", other="xs"),
                                                                     "fr": plural(one="%d y", other="%d ys")}}}),
    "plural-inference-other-first": catalog({"k": {"localizations": {"en": plural(one="%lld x", other="%lld xs"),
                                                                     "fr": plural(one="%d y", other="%lld ys")}}}),
    "plural-inference-named": catalog({"k": {"localizations": {"en": plural(one="%(n)lld x", other="%(n)lld xs"),
                                                               "fr": plural(one="%(n)lld y", other="%(n) ys")}}}),
    "diagnostic-two-positions": catalog({"two numbers": {"localizations": {"en": plural(one="%lld of %lld", other="%lld of %lld s")}}}),
    "diagnostic-two-types": catalog({"k": {"localizations": {"en": plural(other="%(a)@ %-d %(n)lld")}}}),
    "diagnostic-warning-and-error": catalog({"two numbers": {"localizations": {"en": plural(one="%lld of %lld", other="%lld of %lld s")}},
                                             "at": {"localizations": {"en": plural(one="%@ x", other="%@ xs")}}}),
    "diagnostic-variable-in-plural": catalog({"k": {"localizations": {"en": plural(other="%#@x@ %lld")}}}),
})


def labeled(label, specifier="lld"):
    return substituted(f"%#@{label}@", {label: substitution(specifier)})


def symbol_keys(keys):
    return catalog({key: manual() for key in keys})


SYMBOL_IDENTIFIERS = [
    "hello world", "Hello World", "HELLO world", "hello_world", "hello-world", "hello.world", "helloWorld",
    "HelloWorld", "URL loader", "the URL", "API key", "myURLLoader", "URLLoader", "MyURL", "the myURL", "x URLLoader",
    "x aBC", "x iOS", "ABcDef", "a ABcDef", "1 apple", "123", "12ab", "a 12ab", "ab12cd", "ab12CD", "a1b2", "x 2nd",
    "1ABC def", "ABC1DEF x", "v2.0", "", " ", "-a", "a_", "x__y", "_under", "__double", "_1", "__", "_A", "_URL",
    "_hello world", "__COLUMN__", "$money", "a$b", "a·b", "a²b", "a´b", "café au lait", "Éclair", "ÉCLAIR x",
    "x éclair", "İstanbul", "x ǆemal", "aǅb", "Ωmega", "x ωmega", "ß", "日本語", "a日b", "か b", "٣ arabic", "a٣b",
    "ⅷ x", "x ⅷ", "aªb", "aʰb", "aˆb", "aͅb", "aⓐb", "a𝐀b", "emoji 😀 face", "🙂 a", "a 🙂b", "x_🙂",
    "a‍b", "x́y", "it's", "don't stop", "a'b'c", "a’b", "a‘b", "a`b", "a''b", "a'1", "1'a", "’leading",
    "trailing’", "aʼb", "a＇b", "a/b", "x%@y", "per%%cent", "two\nlines", "tab\there", 'quote"s', "back\\slash",
    "class", "Class", "default", "init", "INIT", "Init", "self", "SELF", "Self", "Type", "TYPE", "Protocol", "Any",
    "_", "#if", "package", "actor", "nonisolated", "some", "description", "_self", "Self x",
]

SYMBOL_ESCAPES = [chr(c) for c in [*range(0x21), 0x27, 0x60, 0x7F, 0x80, 0x85, 0x9F, 0xA0, 0xAD, 0x200B, 0x200E,
                                   0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xE000, 0x301]]

SYMBOL_SPECIFIERS = ["@", "d", "i", "u", "o", "x", "c", "s", "f", "F", "e", "g", "a", "p", "n", "D", "ld", "li", "lu",
                     "lf", "le", "lg", "lld", "llu", "llx", "qd", "hd", "hhd", "zd", "td", "jd", "Lf", "lc", "ls",
                     "#x", "-d", " d", "+d", "0d", "'d", "*d", ".*f", "1$d", "5.2lf", ".2f", "05.1f", ".3s", "10@",
                     "-10@", "#@x@", "%"]

# Each catalog is written as <file>.xcstrings: the file name is the table name.
SYMBOL_CATALOGS = {
    "symbols-identifiers": ("Localizable", symbol_keys(SYMBOL_IDENTIFIERS)),
    "symbols-escapes": ("Localizable", symbol_keys(f"k{index:03} x{c}y" for index, c in enumerate(SYMBOL_ESCAPES))),
    "symbols-order": ("Localizable", symbol_keys(["！ a", "\U0001F600 b", "z", "é", "éx", "ea", "B", "a"])),
    "symbols-specifiers": ("Localizable", catalog({f"s{index:02}": manual(localizations={"en": unit(f"v %{specifier} w")})
                                                    for index, specifier in enumerate(SYMBOL_SPECIFIERS)})),
    "symbols-comments": ("Localizable", catalog({
        "c1": manual(comment="A simple comment"), "c2": manual(comment="line one\nline two\n\nline four"),
        "c3": manual(comment="has */ end and /* start /*/"), "c4": manual(comment="  padded  "), "c5": manual(comment=""),
        "c6": manual(comment='quote “x” "y" \\ back'), "c7": manual(comment="trailing newline\n"),
        "c8": manual(comment="tab\there", isCommentAutoGenerated=True), "c9": manual(comment="\n")})),
    "symbols-arguments": ("Localizable", catalog({
        "k1": manual(localizations={"en": unit("Hello %@")}),
        "k2 %@": manual(),
        "k3 %lld": manual(localizations={"en": unit("no arguments")}),
        "k4": manual(localizations={"en": unit("%lld items and %@")}),
        "k5": manual(localizations={"en": unit("%2$@ then %1$lld")}),
        "k6": manual(localizations={"en": unit("100%% sure %@")}),
        "k7": manual(localizations={"en": unit("%.2f and %5d and %-3@ and %+d and %05.1f")}),
        "k8": manual(localizations={"fr": unit("Bonjour %@")}),
        "k9": manual(localizations={"en": unit("%3$@")}),
        "k10": manual(localizations={"en": unit("%1$@ %1$@")}),
        "k11": manual(localizations={"en": unit("%1$@ %1$lld")}),
        "k12": manual(localizations={"en": unit("%(used)lld of %(limit)lld")}),
        "k13": manual(localizations={"en": {"stringUnit": {"state": "new", "value": "%@"}}}),
        "k14": manual(shouldTranslate=False, localizations={"en": unit("%@")}),
        "p1": manual(localizations={"en": plural(one="%lld apple", other="%lld apples")}),
        "p2": manual(localizations={"en": plural(one="%@", other="%lld")}),
        "p3": manual(localizations={"en": {"variations": {"device": {"iphone": unit("phone %@"), "other": unit("other %@")}}}}),
        "p4": manual(localizations={"en": {"variations": {"device": {"iphone": plural(other="%lld %@"), "other": unit("%lld")}}}}),
        "s1": manual(localizations={"en": substituted("%#@apples@", {"apples": substitution("lld", one="%arg apple", other="%arg apples")})}),
        "s2": manual(localizations={"en": substituted("%@ has %#@apples@", {"apples": substitution("lld", 2)})}),
        "s3": manual(localizations={"en": substituted("%#@a_b@ %#@cD@", {"a_b": substitution("lld", 1), "cD": substitution("ld", 2)})}),
        "s4": manual(localizations={"en": substituted("%#@x y@", {"x y": substitution("lld")})}),
        "s5": manual(localizations={"en": substituted("%#@n@", {"n": substitution("lld", other="%arg %@")})}),
        "s6": manual(localizations={"en": substituted("%#@n@", {"n": substitution("lld", other="%@ %arg")})}),
        "s7": manual(localizations={"en": substituted("%#@n@", {"n": substitution("lld", other="%arg %arg")})}),
        "s8": manual(localizations={"en": substituted("%#@n@", {"n": substitution(None)})}),
        "s9": manual(localizations={"en": substituted("%#@missing@ %@", {})}),
        "s10": manual(localizations={"en": substituted("%2$#@x@ %1$@", {"x": substitution("lld")})}),
        "s11": manual(localizations={"en": substituted("%#@x@ %@", {"x": substitution("lld", 2)})}),
        "s12": manual(localizations={"en": substituted("%#@x@ %@", {"x": substitution("lld", 1)})}),
        "s13": manual(localizations={"en": substituted("%#@x@ %#@y@", {"x": substitution("lld", 2), "y": substitution("@")})}),
        "s14": manual(localizations={"en": substituted("%#@x@ %#@y@", {"x": substitution("lld"), "y": substitution("@", 1)})}),
        "s15": manual(localizations={"en": substituted("%#@x@ %%#@y@", {"x": substitution("lld"), "y": substitution("@")})}),
        "s16": manual(localizations={"en": substituted("text", {"x": substitution("lld")})}),
        "s17": manual(localizations={"en": substituted("%1$#@x@", {"x": substitution("lld", 2)})}),
        "s18": manual(localizations={"en": substituted("%#@x@", {"x": substitution("s")})}),
        "s19": manual(localizations={"en": substituted("%#@x@", {"x": substitution("1$lld")})}),
        "s20": manual(localizations={"en": substituted("%#@x@", {"x": substitution("lld", 3)})}),
        "s21": manual(localizations={"en": {"variations": {"device": {"iphone": substituted("%#@x@", {"x": substitution("lld")}),
                                                                      "other": unit("%lld")}}}}),
        "l1": manual(localizations={"en": labeled("class")}),
        "l2": manual(localizations={"en": labeled("self")}),
        "l3": manual(localizations={"en": labeled("Type")}),
        "l4": manual(localizations={"en": labeled("1abc")}),
        "l5": manual(localizations={"en": labeled("URL count")}),
        "l6": manual(localizations={"en": substituted("%#@arg2@ %2$@", {"arg2": substitution("lld", 1)})}),
        "l7": manual(localizations={"en": substituted("%#@a_b@ %#@aB@", {"a_b": substitution("lld", 1), "aB": substitution("lld", 2)})}),
        "m1": manual(localizations={"en": unit("%@"), "fr": unit("%lld")}),
        "m2": manual(localizations={"en": unit("%@"), "fr": unit("%@ %@")}),
        "m3": manual(localizations={"en": unit("x"), "de": labeled("del"), "fr": unit("%2$@")}),
        "m4": manual(localizations={"fr": unit("%@"), "de": unit("%lld")}),
        "m5": manual(localizations={"fr": labeled("frl"), "de": labeled("del")}),
        "m6": manual(localizations={"de": labeled("count"), "en": unit("%lld")}),
        "m7": manual(localizations={"en": unit("starred"), "de": labeled("count")}),
        "m8": manual(localizations={"de": labeled("aa"), "fr": labeled("bb"), "ja": unit("%lld")}),
        "m9": manual(localizations={"Base": unit("%@"), "ar": unit("%lld")}),
        "m10": manual(localizations={"pt-BR": unit("%@"), "pt": unit("%lld"), "pt-PT": unit("%f")}),
        "m11": manual(localizations={"ZZ": labeled("upper"), "aa": labeled("lower")}),
    })),
    "symbols-table-spaces": ("My Strings", symbol_keys(["k", "a %@"])),
    "symbols-table-quote": ("a\"b", symbol_keys(["k"])),
    "symbols-table-lowercase": ("localizable", symbol_keys(["k"])),
    "symbols-table-digit": ("1abc", symbol_keys(["k"])),
    "symbols-table-keyword": ("class", symbol_keys(["k"])),
    "symbols-table-any": ("Any", symbol_keys(["k"])),
    "symbols-table-type": ("Type", symbol_keys(["k", "self"])),
    "symbols-table-self": ("self", symbol_keys(["k"])),
    "symbols-table-words": ("x URL ABC def", symbol_keys(["k"])),
    "symbols-table-uppercase": ("LOCALIZABLE", symbol_keys(["k"])),
    "symbols-table-underscore": ("__x", symbol_keys(["k"])),
    "symbols-table-dollar": ("$x", symbol_keys(["k"])),
    "symbols-only-errors": ("Localizable", symbol_keys(["self", "Type"])),
    "symbols-separators": ("Localizable", symbol_keys(
        f"{prefix}{index:02} {head}{chr(c)}y" for index, c in enumerate(
            [0xAD, 0x200B, 0x200C, 0x200D, 0x202A, 0x202E, 0x203F, 0x2054, 0x2060, 0x206F, 0xFEFF, 0x180E, 0x34F,
             0xFE0F, 0x2028, 0x3000, 0x3005, 0xFFFD, 0x1F3FB, 0xE0001, 0x2070])
        for prefix, head in [("a", "x"), ("b", "")])),
    "symbols-case": ("Localizable", symbol_keys(["x ꜰZ", "x ꜰZZa", "ꜰZ y", "ꜰZZa y", "x ZꜰZ", "x ǅZ", "ǅZ y", "x ßZ", "x ŉZ",
                                                 "x ʰZ", "x ªZ", "x ǰZ", "x ﬁZ", "x ⓐZ", "x ⅷZ", "x ꭰZ", "x ᴀZ", "²\u200b%lldꜰZ"])),
    "symbols-key-specifiers": ("Localizable", symbol_keys(["a%#@x@b", "%1$@%#@x@b", "%@%#@x@b", "%%%#@x@b", "a%2$#@x@b",
                                                           "%#@x@%#@y@b", "a %lld %#@x@b", "%@ %2$#@x@ q", "%1$@ %1$lld q",
                                                           "%1$@%dq", "%(n)lld %(m)@ q", "%(n)lld %(n)lld q", "%3$@ q",
                                                           "%1$#@x@b", "%1$@%lld%#@x@c", "%1$@ %#@x@ %#@y@b", "%2$@%lld%#@x@d",
                                                           "%1$@%lld%#@x@_\n"])),
    "symbols-numbering": ("Localizable", catalog({
        **{f"n{index:02}": manual(localizations={"en": unit(value)}) for index, value in enumerate([
            "%2$@ %lld", "%2$lld %@", "%2$lld %.2f %lld", "%1$@ %lld", "%3$@ %lld %f", "%(n)lld %g %(n)lld", "%(n)lld %(n)lld",
            "%(n)lld %(m)@", "%(n)lld %(n)@", "%(n)lld %2$@", "%2$(n)lld %@", "%@ %(n)lld", "%(a b)@ %2$lld", "%@ %2$lld %@",
            "%2$lld %.2f %(name)lld"])},
        **{f"r{index:02}": manual(localizations={"en": substituted(value, {"x": substitution("lld"), "y": substitution("lld")})})
           for index, value in enumerate(["%#@x@ %#@x@", "%#@x@ %@ %#@x@", "%#@x@ %1$lld", "%#@x@ %(x)lld", "%#@x@ %2$(x)lld"])},
        "p1": manual(localizations={"en": plural(one="%(n)lld", other="%(m)lld")}),
        "p2": manual(localizations={"en": plural(one="%(n)lld", other="%lld")}),
        "p3": manual(localizations={"en": unit("%(n)lld"), "de": unit("%(m)lld")}),
        **{f"f{index:02}": manual(localizations={"en": substituted(token, {"x": substitution("lld", arg_num, other=form)})})
           for index, (form, arg_num, token) in enumerate([
               ("%arg %@", None, "%#@x@"), ("%arg %@", 2, "%#@x@"), ("%arg %@", None, "%2$#@x@"), ("%2$lld %@", None, "%#@x@"),
               ("%@ %3$lld %@", None, "%#@x@"), ("%@ %arg", 2, "%#@x@"), ("%@ %@", None, "%#@x@"), ("%@ %@", 3, "%#@x@"),
               ("%3$@ %@", None, "%#@x@")])},
    })),
    "symbols-warnings": ("Localizable", catalog({
        "w1": manual(localizations={"en": unit("%lld"), "de": labeled("self")}),
        "w2": manual(localizations={"en": labeled("self"), "de": labeled("self"), "Base": labeled("self"), "zh-Hans": labeled("self")}),
        "w3": manual(localizations={"en": labeled("self"), "de": unit("%s")}),
        "w4": manual(localizations={"en": labeled("self"), "de": unit("%1$@ %1$lld")}),
        "w5": manual(localizations={"en": labeled("Type"), "de": unit("%2$@")}),
        "w6": manual(localizations={"en": labeled("self"), "es": unit("%s text")}),
        "w7": manual(localizations={"Base": labeled("self", "f"), "en": unit("%llu %s text")}),
        "w8": manual(localizations={"Base": labeled("self", "f"), "en": unit("%llu %s text"), "fr": unit("%1$@ %1$lld")}),
        "w9": manual(localizations={"es": labeled("self", "f"), "pt-BR": unit("%3$@")}),
        "w10": manual(localizations={"es": labeled("self", "s")}),
    })),
    "symbols-collisions": ("Localizable", catalog({
        "a": manual(), "a %@": manual(), "b %@": manual(), "b-%@": manual(), "c %@": manual(), "c %lld": manual(),
        "d": manual(localizations={"en": labeled("x")}), "d.": manual(localizations={"en": labeled("y")}),
        "e": manual(localizations={"en": labeled("x")}), "e.": manual(localizations={"en": labeled("x", "@")}),
        "f %s": manual(), "f": manual(), "h %@ %@": manual(), "h %@": manual()})),
}


def files_under(directory):
    return {str(p.relative_to(directory)): b64(p.read_bytes()) for p in sorted(directory.rglob("*")) if p.is_file()}


def xcstrings_experiment(out, corpus):
    work = Path("/tmp/nomac-strings-experiments/xcstrings")
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    inputs = {}
    for name, data in CATALOGS.items():
        path = work / "in" / name / "Catalog.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_bytes(data)
        inputs[name] = path
    for path in corpus:
        inputs["corpus:" + str(path)] = Path(path)
    variants = {"build": [], "languages-fr": ["-l", "fr"], "binary": ["--serialization-format", "binary"],
                "stringsdict-only": ["--format", "stringsdictOnly"]}
    observations = {}
    for name, path in inputs.items():
        record = {}
        for variant, extra in variants.items():
            if name.startswith("corpus:") and variant != "build":
                continue
            output = work / "out" / name.replace("/", "_") / variant
            dry = run(["xcrun", "xcstringstool", "compile", "--dry-run", "--output-directory", str(output), *extra, str(path)])
            proc = run(["xcrun", "xcstringstool", "compile", "--output-directory", str(output), *extra, str(path)])
            record[variant] = {
                "status": proc.returncode, "stderr": proc.stderr.decode(errors="replace"),
                "stdout": proc.stdout.decode(errors="replace"),
                "dryRun": dry.stdout.decode(errors="replace").replace(str(output), "<OUT>"),
                "dryRunStatus": dry.returncode,
                "files": files_under(output) if output.exists() else {}}
        observations[name] = record
        print(f"[xcstrings {name}] " + ", ".join(f"{v}: {len(r['files'])} files" for v, r in record.items()), flush=True)
    return observations


def generate_symbols_experiment(out, corpus):
    """`xcstringstool generate-symbols` (the GenerateStringSymbols task) on every catalog above, the
    extraction-state matrices and the corpus's catalogs, in each language, with the options Xcode's
    build passes (`--language <l> --output-directory <dir> <file>`). Records the status, the
    output and each written file, and the keys whose extractionState is `manual`."""
    work = Path("/tmp/nomac-strings-experiments/generate-symbols")
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    inputs = {}
    catalogs = {**CATALOGS, "states-alone": source_matrix(False), "states-with-other": source_matrix(True)}
    files = {name: ("Catalog", data) for name, data in catalogs.items()} | SYMBOL_CATALOGS
    for name, (table, data) in files.items():
        path = work / "in" / name / f"{table}.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_bytes(data)
        inputs[name] = path
    for path in corpus:
        inputs["corpus:" + str(path)] = Path(path)
    observations = {}
    for name, path in inputs.items():
        try:
            manual = sorted(key for key, entry in json.loads(path.read_bytes()).get("strings", {}).items()
                            if entry.get("extractionState") == "manual")
        except ValueError:
            manual = None
        record = {"manual": manual}
        for language in ("swift", "objc"):
            output = work / "out" / name.replace("/", "_") / language
            output.mkdir(parents=True)
            proc = run(["xcrun", "xcstringstool", "generate-symbols", "--language", language, "--output-directory", str(output), str(path)])
            record[language] = {"status": proc.returncode, "stderr": proc.stderr.decode(errors="replace"),
                                "stdout": proc.stdout.decode(errors="replace"), "files": files_under(output)}
        observations[name] = record
        sizes = {language: [len(base64.b64decode(v)) for v in record[language]["files"].values()] for language in ("swift", "objc")}
        print(f"[generate-symbols {name}] manual {len(manual) if manual is not None else '?'}, sizes {sizes}", flush=True)
    return observations


def xcstrings_build_experiment(out):
    work = Path("/tmp/nomac-strings-experiments/xcstrings-build")
    shutil.rmtree(work, ignore_errors=True)
    files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n"}
    project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
    for name in ["mixed", "source-only", "substitutions", "device"]:
        (work / f"Src/{name}.xcstrings").write_bytes(CATALOGS[name])
    build = work / "build"
    proc = run(["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                f"SYMROOT={build}/products", f"OBJROOT={build}/intermediates", "build"], cwd=work)
    log = proc.stdout.decode(errors="replace") + proc.stderr.decode(errors="replace")
    (out / "build.log").write_text(log)
    app = build / "products/Debug-iphoneos/T.app"
    return {"status": proc.returncode,
            "products": {k: v for k, v in files_under(app).items() if ".lproj/" in k},
            "intermediates": {k: v for k, v in files_under(build / "intermediates").items() if ".lproj/" in k}}


def corpus_copy_experiment(out, corpus):
    """The corpus checkouts' .strings and .stringsdict files, copied by one build of an app
    that holds them all under numbered names (their contents are the apps' own)."""
    work = Path("/tmp/nomac-strings-experiments/corpus-copy")
    shutil.rmtree(work, ignore_errors=True)
    files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n"}
    project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
    names = {}
    for index, path in enumerate(corpus):
        name = f"f{index:05}{Path(path).suffix}"
        names[name] = path
        target = work / "Src/en.lproj" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    build = work / "build"
    proc = run(["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                f"SYMROOT={build}/products", f"OBJROOT={build}/intermediates", "build"], cwd=work)
    (out / "build.log").write_bytes(proc.stdout + proc.stderr)
    app = build / "products/Debug-iphoneos/T.app/en.lproj"
    return {"status": proc.returncode,
            "files": {path: b64((app / name).read_bytes()) if (app / name).exists() else None for name, path in names.items()}}


def main():
    out = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or ["copy", "copy-escapes", "xcstrings", "xcstrings-build", "corpus-copy"]
    corpus = sorted(str(p) for p in Path("/tmp/nomac-corpus").glob("*/**/*.xcstrings")) if Path("/tmp/nomac-corpus").exists() else []
    for name in selected:
        directory = out / name
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        if name == "copy":
            observations = copy_experiment(directory)
        elif name == "copy-escapes":
            observations = copy_escapes_experiment(directory)
        elif name == "xcstrings":
            observations = xcstrings_experiment(directory, corpus)
        elif name == "generate-symbols":
            observations = generate_symbols_experiment(directory, corpus)
        elif name == "xcstrings-build":
            observations = xcstrings_build_experiment(directory)
        elif name == "corpus-copy":
            observations = corpus_copy_experiment(directory, sorted(
                str(p) for pattern in ["*/**/*.strings", "*/**/*.stringsdict"] for p in Path("/tmp/nomac-corpus").glob(pattern)))
        else:
            sys.exit(f"unknown experiment {name}")
        (directory / "observations.json").write_text(json.dumps(observations, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

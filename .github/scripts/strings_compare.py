#!/usr/bin/env python3
"""Compare nomac's strings outputs with Xcode's, from strings_experiments.py observations.

Runs anywhere nomac runs. For `copy`, each self-written strings file is copied with `nomac
builtin-copyStrings` in the three output encodings; for `copy-escapes`, each file of `\\U`
surrogate escapes is copied as binary; for `xcstrings`, each catalog is compiled
with `nomac xcstringstool compile` in the variants the experiment ran (the corpus catalogs need
the checkouts at the paths they were observed at); for `corpus-copy`, each corpus strings file
is copied as binary; for `generate-symbols`, each catalog's symbols are generated with `nomac
xcstringstool generate-symbols` in both languages. Files, notes and diagnostics (on the same
stream) must be identical; where xcstringstool failed, nomac must fail too.

Usage: strings_compare.py <observations-dir> <nomac> [copy] [copy-escapes] [xcstrings] [generate-symbols] [corpus-copy]
"""

import base64
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import strings_experiments as experiments  # noqa: E402

VARIANTS = {"build": [], "languages-fr": ["-l", "fr"], "stringsdict-only": ["--format", "stringsdictOnly"]}


def copy_strings(nomac, source, encoding, outdir, name):
    proc = subprocess.run([nomac, "builtin-copyStrings", "--validate", "--outputencoding", encoding, "--outdir", str(outdir),
                           "--outfilename", name, "--", str(source)], capture_output=True, text=True)
    output = outdir / name
    notes = sorted({line.split(": ", 1)[1] for line in proc.stderr.splitlines() if ": note: " in line})
    return (output.read_bytes() if output.exists() else None), notes


def compare_copy(observations, nomac, work):
    cases = {f"{k}.strings": v for k, v in experiments.STRINGS.items()} | {f"{k}.stringsdict": v for k, v in experiments.STRINGSDICT.items()}
    differences = []
    for label, encoding in [("default", "binary"), ("UTF-16", "UTF-16"), ("UTF-8", "UTF-8")]:
        for name, data in cases.items():
            source = work / "copy-in" / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(data)
            mine, notes = copy_strings(nomac, source, encoding, work / f"copy-{label}", name)
            observed = observations[label]["files"][name]
            theirs = base64.b64decode(observed["output"]) if observed["output"] is not None else None
            if mine != theirs or (label == "default" and notes != sorted(observed["notes"])):
                differences.append(f"copy {label} {name}")
    return len(cases) * 3, differences


def compare_copy_escapes(observations, nomac, work):
    differences = []
    for name, data in experiments.ESCAPES.items():
        source = work / "copy-escapes-in" / name / "Escape.strings"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_bytes(data)
        mine, notes = copy_strings(nomac, source, "binary", work / "copy-escapes" / name, "Escape.strings")
        observed = observations[name]
        theirs = base64.b64decode(observed["output"]) if observed["output"] is not None else None
        if mine != theirs or notes != observed["messages"]:
            differences.append(f"copy-escapes {name}")
    return len(experiments.ESCAPES), differences


def diagnostics(stderr):
    """The diagnostics without the catalog path, in any order (Xcode's changes from run to run)."""
    lines = [line for line in stderr.splitlines() if ": error: " in line or ": warning: " in line]
    return sorted(line[line.index(": ") + 2:] for line in lines)


def compare_xcstrings(observations, nomac, work):
    count, differences = 0, []
    for name, record in observations.items():
        if name.startswith("corpus:"):
            path = Path(name[len("corpus:"):])
            if not path.exists():
                continue
        else:
            path = work / "catalogs" / name / "Catalog.xcstrings"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(experiments.CATALOGS[name])
        for variant, extra in VARIANTS.items():
            if variant not in record:
                continue
            count += 1
            observed = record[variant]
            out = work / "xcstrings" / name.replace("/", "_") / variant
            proc = subprocess.run([nomac, "xcstringstool", "compile", "--output-directory", str(out), *extra, str(path)],
                                  capture_output=True, text=True)
            if (proc.returncode != 0) != (observed["status"] != 0):
                differences.append(f"xcstrings {name} [{variant}]: status {proc.returncode}, Xcode {observed['status']}")
                continue
            for stream, mine, theirs in [("stdout", proc.stdout, observed["stdout"]), ("stderr", proc.stderr, observed["stderr"])]:
                if diagnostics(mine) != diagnostics(theirs):
                    differences.append(f"xcstrings {name} [{variant}] {stream}: {diagnostics(mine)}, Xcode {diagnostics(theirs)}")
            if observed["status"] != 0:
                continue
            mine = {str(f.relative_to(out)): f.read_bytes() for f in out.rglob("*") if f.is_file()} if out.exists() else {}
            theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
            for file in sorted(set(mine) | set(theirs)):
                if mine.get(file) != theirs.get(file):
                    differences.append(f"xcstrings {name} [{variant}] {file}")
    return count, differences


def compare_generate_symbols(observations, nomac, work):
    files = {name: ("Catalog", data) for name, data in experiments.CATALOGS.items()} | {
        "states-alone": ("Catalog", experiments.source_matrix(False)),
        "states-with-other": ("Catalog", experiments.source_matrix(True))} | experiments.SYMBOL_CATALOGS
    count, differences = 0, []
    for name, record in observations.items():
        if name.startswith("corpus:"):
            path = Path(name[len("corpus:"):])
            if not path.exists():
                continue
        elif name in files:
            table, data = files[name]
            path = work / "generate-symbols-in" / name / f"{table}.xcstrings"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        else:
            continue
        for language in ("swift", "objc"):
            count += 1
            observed = record[language]
            out = work / "generate-symbols" / name.replace("/", "_") / language
            out.mkdir(parents=True)
            proc = subprocess.run([nomac, "xcstringstool", "generate-symbols", "--language", language, "--output-directory", str(out), str(path)],
                                  capture_output=True, text=True)
            label = f"generate-symbols {name} [{language}]"
            if (proc.returncode != 0) != (observed["status"] != 0):
                differences.append(f"{label}: status {proc.returncode}, Xcode {observed['status']}")
                continue
            for stream, mine, theirs in [("stdout", proc.stdout, observed["stdout"]), ("stderr", proc.stderr, observed["stderr"])]:
                if diagnostics(mine) != diagnostics(theirs):
                    differences.append(f"{label} {stream}: {diagnostics(mine)}, Xcode {diagnostics(theirs)}")
            mine = {str(f.relative_to(out)): f.read_bytes() for f in out.rglob("*") if f.is_file()}
            theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
            for file in sorted(set(mine) | set(theirs)):
                if mine.get(file) != theirs.get(file):
                    differences.append(f"{label} {file}")
    return count, differences


def compare_corpus_copy(observations, nomac, work):
    differences = []
    for index, (path, output) in enumerate(observations["files"].items()):
        mine, _ = copy_strings(nomac, path, "binary", work / "corpus-copy", f"{index:05}")
        if mine != base64.b64decode(output):
            differences.append(f"corpus-copy {path}")
    return len(observations["files"]), differences


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    directory, nomac = Path(sys.argv[1]), sys.argv[2]
    selected = sys.argv[3:] or ["copy", "copy-escapes", "xcstrings", "generate-symbols", "corpus-copy"]
    comparisons = {"copy": compare_copy, "copy-escapes": compare_copy_escapes, "xcstrings": compare_xcstrings,
                   "generate-symbols": compare_generate_symbols, "corpus-copy": compare_corpus_copy}
    work = Path(tempfile.mkdtemp(prefix="nomac-strings-compare-"))
    failed = False
    try:
        for name in selected:
            recorded = directory / name / "observations.json"
            if not recorded.exists():
                print(f"[{name}] no observations")
                continue
            count, differences = comparisons[name](json.loads(recorded.read_text()), nomac, work)
            print(f"[{name}] {count - len(differences)} of {count} identical")
            for difference in differences:
                print("    " + difference)
            failed = failed or bool(differences)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

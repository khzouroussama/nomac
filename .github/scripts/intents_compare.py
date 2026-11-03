#!/usr/bin/env python3
"""Compare nomac's intentbuilderc with Xcode's, from intents_experiments.py observations.

Runs anywhere nomac runs (the corpus's and holdout's definitions at the paths they were observed
at). Each definition is generated with `nomac intentbuilderc generate` in every variant the
experiment ran, with and without `-dryRun`: the status, the paths a dry run prints and every
generated file must be identical.

Usage: intents_compare.py <observations-dir> <nomac> [-v]
"""

import base64
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import intents_experiments as experiments  # noqa: E402


def files_under(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in sorted(directory.rglob("*")) if p.is_file()} if directory.exists() else {}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    observations = json.loads((Path(sys.argv[1]) / "intents" / "observations.json").read_text())
    nomac, verbose = sys.argv[2], "-v" in sys.argv[3:]
    work = Path(tempfile.mkdtemp(prefix="nomac-intents-compare-"))
    count, differences = 0, []
    try:
        for name, record in observations.items():
            if name.startswith("corpus:"):
                path = Path(name[len("corpus:"):])
                if not path.exists():
                    continue
            else:
                path = work / "in" / name / "Probe.intentdefinition"
                path.parent.mkdir(parents=True)
                path.write_bytes(experiments.plistlib.dumps(experiments.DEFINITIONS[name]))
            for variant, observed in record["generate"].items():
                count += 1
                out = work / "out" / name.replace("/", "_") / variant / path.stem
                options = experiments.VARIANTS[variant]
                dry = subprocess.run([nomac, "intentbuilderc", "generate", "-dryRun", "-input", str(path), "-output", str(out)] + options,
                                     capture_output=True, text=True)
                real = subprocess.run([nomac, "intentbuilderc", "generate", "-input", str(path), "-output", str(out)] + options,
                                      capture_output=True, text=True)
                label = f"{name} [{variant}]"
                problems = []
                if (dry.returncode != 0) != (observed["dryRunStatus"] != 0) or (real.returncode != 0) != (observed["status"] != 0):
                    problems.append(f"status {dry.returncode}/{real.returncode}, Xcode {observed['dryRunStatus']}/{observed['status']}"
                                    + (f": {(dry.stderr + real.stderr).strip()[:300]}" if verbose else ""))
                elif dry.stdout.replace(str(out), "<OUT>") != observed["dryRun"]:
                    problems.append("dry-run paths")
                mine = files_under(out)
                theirs = {k: base64.b64decode(v) for k, v in observed["files"].items()}
                problems += [f"file {f}" for f in sorted(set(mine) | set(theirs)) if mine.get(f) != theirs.get(f)]
                if problems:
                    differences.append(f"{label}: {', '.join(problems)}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"[intents] {count - len(differences)} of {count} identical")
    for difference in differences:
        print("    " + difference)
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()

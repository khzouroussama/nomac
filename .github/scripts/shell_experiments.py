#!/usr/bin/env python3
"""What shell script phases see as `/bin/sh`, on macOS and with Linux candidates.

Swift Build runs every script phase as `/bin/sh -c <script>`, and the script starts with
`#!/bin/sh` (SWBTaskConstruction `ShellScriptTaskProducer`). On macOS `/bin/sh` runs
`/private/var/select/sh`, bash 3.2 by default; Ubuntu's is dash. Scripts written for Xcode use
what macOS's `sh` accepts (tofu's `${GIT_RELEASE_VERSION/-0-/-}` fails under dash). This runs
constructs common in script phases under a shell and records each one's output and exit status.

With --nested each snippet is instead a `#!/bin/sh` script file that the shell runs by path
(`<shell> -c <file>`), as CocoaPods' `[CP]` phases run their scripts: the kernel then runs it with
the interpreter its `#!` line names (docs/adr/0180-scripts-run-by-path.md).

Usage:
  shell_experiments.py [--nested] <output.json>                       macOS: /bin/sh
  shell_experiments.py [--nested] <output.json> <shell> [args ...]    any shell, run as <shell> [args] -c <snippet>
  shell_experiments.py compare <reference.json> <other.json> ...
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SNIPPETS = {
    "echo-escapes": 'echo "a\\nb\\tc"',
    "echo-n": "echo -n x; echo y",
    "echo-e": 'echo -e "a\\tb"',
    "pattern-substitution": "v=1-0-2; echo ${v/-0-/-}; echo ${v//-/+}",
    "substring": "v=abcdef; echo ${v:1:2} ${#v}",
    "double-brackets": "[[ -n x && x == x* ]] && echo yes",
    "test-double-equals": "[ a == a ] && echo yes",
    "arrays": "a=(1 2 3); echo ${a[1]} ${#a[@]}",
    "ansi-c-quoting": "printf '%s|' $'a\\tb'; echo",
    "function-keyword": "function f { echo f; }; f",
    "source": "source /dev/null && echo sourced",
    "ampersand-redirect": "echo x &>/dev/null; echo done",
    "brace-expansion": "echo {a,b}c",
    "let": "let i=1+2; echo $i",
    "here-string": 'read -r v <<< "abc"; echo $v',
    "pipefail": "set -o pipefail; false | true; echo $?",
    "process-substitution": "cat <(echo p)",
    "local-outside-function": "local x=1 2>/dev/null; echo $?",
    "dollar-zero": "echo $0",
    "posix-mode": 'case "$SHELLOPTS" in *posix*) echo posix;; *) echo not-posix;; esac',
}


def run(shell, nested=False):
    results = {}
    with tempfile.TemporaryDirectory() as folder:
        for name, snippet in SNIPPETS.items():
            command = snippet
            if nested:
                command = f"{folder}/{name}.sh"
                Path(command).write_text(f"#!/bin/sh\n{snippet}\n")
                os.chmod(command, 0o755)
            proc = subprocess.run(shell + ["-c", command], capture_output=True, text=True, env={"PATH": "/usr/bin:/bin"})
            stdout = proc.stdout.replace(command, "<script>") if nested else proc.stdout
            results[name] = {"status": proc.returncode, "stdout": stdout}
    return results


def main():
    if sys.argv[1] == "compare":
        reference = json.load(open(sys.argv[2]))
        for path in sys.argv[3:]:
            other = json.load(open(path))
            differing = [name for name in reference["results"] if reference["results"][name] != other["results"].get(name)]
            print(f"{other['shell']}: {len(SNIPPETS) - len(differing)}/{len(SNIPPETS)} like {reference['shell']}")
            for name in differing:
                print(f"    {name}: {json.dumps(reference['results'][name])} | {json.dumps(other['results'].get(name))}")
        return
    arguments = sys.argv[1:]
    nested = arguments[0] == "--nested"
    arguments = arguments[1:] if nested else arguments
    shell = arguments[1:] or ["/bin/sh"]
    json.dump({"shell": " ".join(shell) + (" (nested)" if nested else ""), "results": run(shell, nested)},
              open(arguments[0], "w"), indent=2)


if __name__ == "__main__":
    main()

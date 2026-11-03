#!/usr/bin/env python3
"""What `#!/bin/bash` scripts get from macOS's bash 3.2 and from another bash.

script_phase_survey.py finds `#!/bin/bash` or `#!/usr/bin/env bash` in the scripts of 21 of 45
test apps' phases. On macOS they run bash 3.2.57; on Linux the machine's bash (5.x), which
ADR 0180's interposer leaves alone (it handles `/bin/sh` only). This runs snippets as such a script
runs them, `<bash> -c <snippet>` (not POSIX mode), and records each one's standard output and exit
status: the differences a script written for macOS could meet, the bash 4 syntax a script that
works on macOS cannot use, and constructs common in phase scripts.

Usage:
  bash_experiments.py <output.json> [<bash>]     default /bin/bash
  bash_experiments.py compare <reference.json> <other.json>
"""

import json
import subprocess
import sys

SNIPPETS = {
    "version-major": "echo ${BASH_VERSINFO[0]}",
    "empty-array-with-set-u": 'set -u; a=(); echo "${a[@]}" x',
    "unset-array-element-count-with-set-u": "set -u; a=(); echo ${#a[@]}",
    "unicode-escape": "printf '%s\\n' $'\\u00e9'",
    "printf-q": "printf '%q|' '' 'a b' \"it's\" $'tab\\there'; echo",
    "declare-p": "x=1; a=(p q); declare -p x a",
    "set-e-in-substitution": "set -e; x=$(false; echo after); echo \"[$x]\"",
    "set-e-function-in-condition": "set -e; f(){ false; echo inside; }; if f; then echo ok; fi",
    "regex-capture": "[[ abc123 =~ ^[a-z]+([0-9]+)$ ]] && echo ${BASH_REMATCH[1]}",
    "regex-quoted-pattern": "[[ a.c =~ \"a.c\" ]] && echo literal; [[ abc =~ \"a.c\" ]] || echo no-wildcard",
    "read-into-array": "read -ra a <<< 'x y z'; echo ${#a[@]} ${a[2]}",
    "printf-v": "printf -v x '%03d' 7; echo $x",
    "arithmetic": "echo $(( 2**10 )) $(( 7/2 )) $(( -7/2 ))",
    "negative-substring": "v=abcdef; echo ${v: -2}",
    "heredoc-in-substitution": "x=$(cat <<EOF\nhi\nEOF\n); echo $x",
    "case-in-substitution": "x=$(case a in a) echo m;; esac); echo $x",
    "echo-backslashes": "echo \"a\\tb\"",
    "echo-e": "echo -e 'a\\tb'",
    "glob-order": "d=$(mktemp -d); cd \"$d\" && touch B a C b _x 10 9 && echo *; rm -rf \"$d\"",
    "sort-of-brackets": "[[ B < a ]] && echo B-first || echo a-first",
    "pipefail-and-pipestatus": "set -o pipefail; false | true; echo $? ${PIPESTATUS[@]}",
    "command-not-found-status": "nonexistent-command-xyz 2>/dev/null; echo $?",
    "local-in-function": "f(){ local v=in; echo $v; }; v=out; f; echo $v",
    "trap-err": "trap 'echo trapped' ERR; false; echo after",
    "string-replace-anchors": "v=a-b-a; echo ${v/#a/X} ${v/%a/Y}",
    "indirect-expansion": "name=v; v=7; echo ${!name}",
    "bash4-associative-array": "declare -A m 2>/dev/null && { m[k]=v; echo ${m[k]}; } || echo unsupported",
    "bash4-case-conversion": "v=AbC; eval 'echo ${v,,}' 2>/dev/null || echo unsupported",
    "bash4-mapfile": "mapfile -t l < <(printf 'a\\nb\\n') 2>/dev/null && echo ${#l[@]} || echo unsupported",
    "bash4-test-v": "x=1; [[ -v x ]] 2>/dev/null && echo set || echo unsupported",
    "bash4-brace-step": "echo {1..9..3}",
    "bash4-pipe-stderr": "eval 'echo x |& cat' 2>/dev/null || echo unsupported",
}


def run(shell):
    results = {}
    for name, snippet in SNIPPETS.items():
        proc = subprocess.run([shell, "-c", snippet], capture_output=True, text=True, timeout=30,
                              env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "HOME": "/tmp"})
        results[name] = {"status": proc.returncode, "stdout": proc.stdout}
    return results


def main():
    if sys.argv[1] == "compare":
        reference, other = (json.load(open(path)) for path in sys.argv[2:4])
        same = [name for name in SNIPPETS if reference.get(name) == other.get(name)]
        print(f"{len(same)} of {len(SNIPPETS)} snippets alike")
        for name in SNIPPETS:
            if name not in same:
                print(f"    {name}: {reference.get(name)} vs {other.get(name)}")
        return
    shell = sys.argv[2] if len(sys.argv) > 2 else "/bin/bash"
    version = subprocess.run([shell, "-c", "echo $BASH_VERSION"], capture_output=True, text=True).stdout.strip()
    json.dump({"bash": version, **run(shell)}, open(sys.argv[1], "w"), indent=2)


if __name__ == "__main__":
    main()

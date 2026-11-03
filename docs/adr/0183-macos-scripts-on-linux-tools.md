# ADR 0183: What macOS scripts get on Linux: bash 3.2 versus the machine's bash, BSD versus GNU tools

- Status: accepted (the Expo workstream, 2026-11-02)
- Date: 2026-11-02

## Context

Run-script phases and the scripts they call are written for macOS. `.github/scripts/script_phase_survey.py`
reads them in 45 test apps (the corpus, the holdout, expo-default, rn-bare and the RN holdout's
three): 734 scripts in 36 apps. ADR 0103 and ADR 0180 give `/bin/sh` scripts a macOS-like shell;
`#!/bin/bash` and `#!/usr/bin/env bash` scripts, in 21 apps, run the machine's bash, 5.2 on Ubuntu
24.04, where macOS has 3.2.57. The scripts also call tools whose BSD and GNU versions differ.

Observed:

1. **bash** (`.github/scripts/bash_experiments.py`, 32 snippets run as `bash -c`, macOS 3.2.57 and
   Ubuntu's 5.2.21): 20 alike, `set -e` in substitutions and conditions, regular expressions and
   their captures, `printf %q`, `pipefail` and `PIPESTATUS`, `trap ERR`, `local`, indirect
   expansion, here-documents among them. Different: bash 4 syntax that 3.2 rejects (associative
   arrays, `${v,,}`, `mapfile`, `[[ -v ]]`, stepped brace ranges, `|&`), `case` inside `$(…)` and
   `"${a[@]}"` of an empty array under `set -u`, which 3.2 refuses and 5.2 runs; `BASH_VERSINFO`;
   `$'\u…'`, literal in 3.2; `declare -p`'s array form. The survey finds none of the constructs whose
   output differs in the 734 scripts (no version test, no `$'\u…'`, no `declare -p`, no bash 4
   syntax): a script that works on macOS meets only what 5.2 accepts as well.
2. **Glob order** follows the locale. Xcode gives phases `LANG=en_US.UTF-8`, and macOS sorts `*`
   by its collation (`_x 10 9 a B C`); a machine without that locale sorts by bytes. 19 loops over
   globs in 4 apps, none whose result depends on the order (dSYM and xcframework slices; one pipes
   through `LC_ALL=C sort`).
3. **xargs**: macOS's does not run the command on empty input, GNU's runs it once. In the 33
   uses, the empty case either gives the same result (`$(… | xargs -0)` of nothing) or is guarded
   (CocoaPods' resources script runs `actool` only with catalogs).
4. **otool**: all 18 uses are CocoaPods' frameworks script's `xcrun otool -LX`, in a branch for
   Xcode before 7.
5. **sed -i ''** (BSD in-place without a suffix), which GNU sed reads as a script and fails: one
   phase in one app (mullvad's WireGuard project, "Strip Trailing Whitespace").

## Options

- **A. bash 3.2 for `#!/bin/bash` scripts** (GNU bash 3.2.57, built by `nomac toolchain install`
  and placed where the interposer could send them). Identical semantics, at the cost of an old
  shell to build and keep, for differences no surveyed script meets.
- **B. The machine's bash, with nothing changed.** Every difference found needs a construct that
  macOS's bash rejects or that no surveyed script uses.
- **C. BSD tools on the phases' `PATH`** (sed, xargs, …): would cover `sed -i ''` and empty-input
  `xargs`, but replace well-tested GNU tools for one script, and their other behaviour would then
  have to be proven like macOS's too.

## Decision

B for bash. For the tools, a stand-in only where the survey finds a result that differs and a
project cannot easily avoid it: `PlistBuddy` (9 apps, `nomac PlistBuddy`), `lipo` and `derq`
already, and `file` (CocoaPods' frameworks script in 11 of the RN sweep's 11 apps, `nomac file`,
which words Mach-O files, `ar` archives, empty files and folders as macOS's `file` does), and BSD `md5`
(Bugsnag's `md5 -qs "$CONFIGURATION_BUILD_DIR"` in 2 of the sweep's apps, `nomac md5`), and Xcode's
`dwarfdump --uuid` (expo-modules-autolinking's dSYM source maps, which a Linux build otherwise skips,
`nomac dwarfdump`). `sed -i ''`, the macOS-only commands without a stand-in and the scripts that test the
machine (`uname -m`) are named by `nomac check` with what to change, rather than masked.

BSD `cp -X` (2026-11-03, the RN sweep's full run): React Native 0.81's codegen phase (`[CP-User]
Generate Specs`, `scripts/react_native_pods_utils/script_phases.sh`) runs `/bin/cp -R -X`, which
GNU cp refuses ("invalid option -- 'X'"), in 2 of the sweep's 3 apps on 0.81 (graysky,
obytes-template; 0.86 and 0.88 no longer use it). macOS's cp copies extended attributes unless
given `-X` (`-R`, `-a`: kept; `-R -X`, `-RX`, `-pR -X`, `-a -X`, `-aX`: none); GNU cp keeps them
only under `-a`. The exec interposer runs the machine's cp, by `/bin/cp` or found on `PATH`, with
the `X` left out of each option cluster, and with `--no-preserve=xattr` under `-a`; a cp without
`-X` runs as asked.

## Consequences

- The survey is rerun on new apps (the owner's apps and public React Native apps, by the agents
  that have them); a construct from item 1, a glob loop whose output depends on order or another
  BSD-only usage reopens this ADR with counts.
- Glob order stays the machine's until an app shows a difference; the locale is the environment's
  (`LANG` as Xcode sets it), not nomac's to change.

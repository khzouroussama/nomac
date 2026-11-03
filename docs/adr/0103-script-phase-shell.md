# ADR 0103: Script phases on Linux run under a shell like macOS's /bin/sh

- Status: accepted (2026-10-22)
- Date: 2026-10-22

## Context

Swift Build runs every shell script phase as `/bin/sh -c <script>`, and writes the script with
`#!<shellPath>` first, the phase's `shellPath` from the PIF, `/bin/sh` unless the project says
otherwise (SWBTaskConstruction `ShellScriptTaskProducer`). The command line is fixed; `/bin/sh -c`
only executes the script file, and the kernel runs it with the interpreter its `#!` line names.

On macOS, `/bin/sh` runs `/private/var/select/sh`, `/bin/bash` by default: bash 3.2.57 as `sh`,
so in POSIX mode, and with `echo` interpreting backslash escapes and taking no options. On Ubuntu
it is dash. Scripts written for Xcode use what macOS's `sh` accepts: tofu's "Generate Version
Headers" phase uses `${GIT_RELEASE_VERSION/-0-/-}`, and fails under dash with "Bad substitution".

`.github/scripts/shell_experiments.py` runs 20 constructs common in script phases (echo forms,
pattern substitution, substrings, `[[ ]]`, arrays, `$'…'`, `function`, `source`, `&>`, brace
expansion, here-strings, `pipefail`, process substitution, …). Against macOS's `/bin/sh`:

| Shell on Linux | Like macOS's `/bin/sh` |
|---|---|
| dash (Ubuntu's `/bin/sh`) | 4 of 20 |
| bash 5.2 run as `sh` | 15 (`echo` takes options and no escapes) |
| bash 5.2 run as `sh` with `-O xpg_echo` | 19 (bash 5 also accepts process substitution in POSIX mode; macOS's rejects it) |

## Options

- **A. Require a macOS-like `/bin/sh` on the build machine.** It is the user's machine (and CI's
  container) to change, for one tool.
- **B. nomac ships the shell and its build points script phases at it.** `nomac toolchain
  install` writes `usr/libexec/nomac/sh` into the developer directory: `#!/bin/bash` and
  `exec -a /bin/sh /bin/bash -O xpg_echo "$@"` (bash in POSIX mode because it runs as `sh`). Off
  macOS, `nomac build` gives the PIF it builds the shell's path for every script phase whose
  `shellPath` is `/bin/sh`.
- **C. Keep dash.** Scripts that use bash features fail, and some that pass write other output.

## Decision

B. The PIF `nomac pif` prints and the settings `nomac inspect` evaluates are unchanged; only the
PIF handed to Swift Build for a build differs, and its changed objects (the targets with such a
phase, the projects that list them, the workspace) get a suffix on their signatures so that each
stays unique. If the developer directory has no shell, or its path has white space (`#!` cannot
name it), `nomac build` runs the phases with the machine's `/bin/sh` and warns when that
`/bin/sh` does not answer a probe as macOS's does.

## Consequences

- The build's command lines are Xcode's: the log shows `/bin/sh -c <script>`. Only the script
  file in the intermediates (`Script-<id>.sh`) has another first line, `#!<developer
  directory>/usr/libexec/nomac/sh`.
- tofu on Linux with dash as `/bin/sh`: the phase runs, and its `include/TofuVersions.h` and the
  `Preprocessed-Info.plist` built from it are Xcode's, byte for byte; the installed shell is like
  macOS's in 19 of the 20 constructs.
- Phases with another `shellPath` (`/bin/bash`, `/bin/zsh`, `/usr/bin/env python3`) run what the
  machine has at that path; bash 5 differs from macOS's bash 3.2 in what the 20 constructs do not
  cover. Each difference a corpus app shows is a finding for `shell_experiments.py`.
- Linux runs nested interpreter scripts (the phase's script names the shell, which is itself a
  script); macOS does not, but nomac does not redirect on macOS.
- Scripts that run tools through `xcrun` reach `nomac xcrun`, whose launcher
  `nomac toolchain install` writes in the developer directory's `usr/bin`; it answers as Xcode's
  xcrun does (docs/formats/build.md "xcrun"). A script's `xcrun --sdk macosx swift <script>` runs
  the script on the build machine, which off macOS is Linux: the toolchain's `swift` then gets no
  `SDKROOT`, since macOS's SDK cannot build for Linux, and the script runs with swift.org's
  Foundation. Whether its output is a Mac's is a finding of the app that runs it.
- Scripts a phase runs by path keep their own `#!` line; ADR 0180 gives those that name
  `/bin/sh` nomac's shell too (CocoaPods' `[CP]` scripts).

## Addendum: user script sandboxing (2026-10-31)

With `ENABLE_USER_SCRIPT_SANDBOXING = YES`, Xcode's default for new projects, Swift Build runs a
script phase as `/usr/bin/sandbox-exec -D … -f <profile> /bin/sh -c <script>`, its profile
allowing writes to the phase's declared outputs only. `.github/scripts/script_sandbox_experiments.py`
(a self-written app, sandboxing on): Xcode 27.0 builds a script that copies its declared input to
its declared output, and fails one that also writes an undeclared file ("deny"). Linux has no
`sandbox-exec`, and Swift Build starts it itself, in nomac's process, where the exec interposer
(ADR 0180) does not reach; both builds failed ("unable to spawn process '/usr/bin/sandbox-exec'").

Decision (the integrator's): off macOS the script runs as the plain command. `nomac build`
synthesizes `DISABLE_TASK_SANDBOXING = YES` (`TaskSandbox`), which drops only the wrapper and its
profile; the planning, which follows `ENABLE_USER_SCRIPT_SANDBOXING`, is unchanged. A script that
keeps to its declared inputs and outputs writes the same outputs as on the Mac. The sandbox's
enforcement is not reproduced: a script writing an undeclared file succeeds on Linux where Xcode
fails it. Enforcing it with Linux's own mechanisms is B-132.

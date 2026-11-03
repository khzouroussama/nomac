# ADR 0180: Scripts that script phases run by path get the macOS-like shell too

- Status: accepted (the Expo workstream, 2026-10-24; extends ADR 0103)
- Date: 2026-10-24

## Context

ADR 0103 runs each script phase's own script under nomac's shell (bash as `sh`, `xpg_echo`). A
phase that runs another script by path does not reach it: the kernel runs that script with the
interpreter its `#!` line names, `/bin/sh`, which is dash on Ubuntu. On macOS it is bash 3.2 in
POSIX mode.

CocoaPods' `[CP]` phases are each one such line, `"${PODS_ROOT}/Target Support Files/<target>/<target>-xcframeworks.sh"`
(or `-frameworks.sh`, `-resources.sh`), and those scripts start `#!/bin/sh` and use
`set -o pipefail`, arrays and `[[ ]]`. In the Linux builds of expo-default and rn-bare, 13
distinct scripts failed so (`set: Illegal option -o pipefail`); no xcframework was copied, and
every target that includes React Native's headers failed after them. All 13 are direct children
of the phase's script.

`.github/scripts/shell_experiments.py --nested` runs ADR 0103's 20 constructs as `#!/bin/sh`
scripts that the phase's shell runs by path. On macOS they behave as `/bin/sh -c` does, `$0`
aside. On Linux:

| Shell for nested scripts | Like macOS |
|---|---|
| dash (the kernel's choice) | 4 of 20 |
| nomac's shell, through the interposer below | 19 of 20 (process substitution, as in ADR 0103) |

## Options

- **A. An exec interposer that nomac's shell preloads.** nomac's shell sets `LD_PRELOAD` to a
  small library, compiled by `nomac toolchain install` with the installed `clang`. In the
  processes of a phase it wraps `execve`, `execv`, `execvp`, `execvpe`, `posix_spawn` and
  `posix_spawnp`: a script whose `#!` line names `/bin/sh` starts nomac's shell with the
  arguments the kernel would give `/bin/sh` (the `#!` line's argument, the script, its
  arguments), and so does `/bin/sh` itself, by that path or found as `sh` on `PATH` (`sh -c` from
  node, `env sh`). It needs no privilege. It does not reach programs started without the
  environment (`env -i`), statically linked programs, or `system()` and `popen()`, which glibc
  starts without the wrapped functions.
- **B. A private mount namespace** where `/bin/sh` is nomac's shell (`unshare --user --mount`,
  bind mount), entered by `nomac build`. Root in the container can; a non-root user in the same
  container gets a namespace but `mount(2)` fails with `EPERM`. On Ubuntu 24.04, also under WSL2,
  AppArmor restricts unprivileged user namespaces by default
  (`kernel.apparmor_restrict_unprivileged_userns=1`), so a normal user cannot either. The Docker
  Desktop kernel used here (`6.10.14-linuxkit`) has no AppArmor, so that setting could not be
  measured; the non-root failure already rules B out as the only mechanism.
- **C. An AppArmor profile** allowing user namespaces for nomac, installed once with sudo by
  `nomac toolchain install`: a system change for one tool, only where AppArmor runs, and B's
  non-root `EPERM` remains where it does not.

## Decision

A. `ExecInterposer` (`NomacBuild`) holds the library's source; `nomac toolchain install`
compiles it into `usr/libexec/nomac/libnomac-exec.so` next to nomac's shell, which preloads it
when it is there. B and C are not used: A works for every user, and B and C would only add a
second mechanism that has to agree with it.

## Consequences

- All the nested `#!/bin/sh` scripts measured, and `/bin/sh -c` or `sh -c` started inside a phase,
  run under nomac's shell, like macOS's `/bin/sh` in 19 of 20 constructs.
- Every process of a phase loads the library (`LD_PRELOAD`). A program for another architecture
  (an x86_64 tool run by emulation) cannot load it, and its loader prints that it ignored it.
- `system()`, `popen()`, static binaries and `env -i` children still get the machine's `/bin/sh`;
  each case a project shows is a finding for `shell_experiments.py`.
- On macOS nothing changes: neither the shell nor the library is installed there.
- Addendum (2026-10-30, build driver): the library also runs the developer directory's tool for a
  program started by a macOS path of one nomac installs that the machine lacks
  (`/usr/bin/codesign`, `/usr/bin/ditto`, `/usr/bin/xcodebuild`, `/usr/bin/xcrun`;
  `ExecInterposer.toolPaths`): CocoaPods' frameworks script signs the embedded frameworks of an
  install build with `/usr/bin/codesign`, and rn-bare's archive failed there on Linux
  ("/usr/bin/codesign: No such file or directory").

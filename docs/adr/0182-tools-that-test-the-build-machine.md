# ADR 0182: A project's tools that test the build machine's system are the project's to change

- Status: decision superseded by ADR 0184 (the owner's requirement, 2026-11-04); the observations
  below still hold. Accepted by the Expo workstream, 2026-10-30.
- Date: 2026-10-30

## Context

expo-default's `[Expo] Configure project` phase runs `expo-modules-autolinking
generate-modules-provider` with the project's Node. It writes `ExpoModulesProvider.swift`, the
list of module classes the app target compiles, from each package's `expo-module.config.json`
and from a scan of the packages' Swift sources for `@ExpoModule` classes. The scan runs
`expo-modules-macros`' scanner, which is also the pods' Swift macro plugin. On Linux the phase
fails:

    error: Scanning for @ExpoModule classes didn't complete (see the warnings above), so the module
    classes of these packages are missing from the modules provider: expo-modules-core. ...

Observed (expo-modules-autolinking and expo-modules-macros 0.22.0 as installed in expo-default):

1. **The check is Node's system.** `scanNativeModulesAsync` returns before running the scanner
   when `process.platform !== 'darwin'` ("The scanner is a macOS binary."). The command then
   sets exit status 1 when a package has `@ExpoModule` annotations and declares no modules. Node
   documents `process.platform` as the operating system its binary was compiled for; no
   environment variable, file or command that Xcode's environment provides changes it.
2. **The scanner exists for Linux.** `expo-modules-macros` lists `@expo/modules-macros-linux-arm64`
   and `-linux-x64` (glibc) as optional dependencies; on Linux those packages hold an ELF
   `ExpoModulesMacros`, which `getScannerBinaryPath` picks there. npm installs them only on Linux
   (`expo_experiments.py` adds the lockfile's Linux packages to the generated checkout).
3. **The provider does not depend on the scan in this app.** The phase's command, run by hand
   with the phase's arguments (outside the repository, `~/nomac-out/wt-scratch/expo/scan`), on the
   Mac (Node 24.22.1, darwin-arm64), on Linux as installed (no scan, exit 1) and on Linux with the
   check allowing `linux` (the Linux scanner, exit 0), writes the same `ExpoModulesProvider.swift`
   byte for byte, which is also the file `pod install` wrote: its 22 module classes come from the
   packages' `expo-module.config.json`. The only scanned class, expo-modules-core's `CoreModule`,
   is internal and left out on both systems with the same warning.

## Options

- **A. nomac makes Node report `darwin`** (a preloaded script or a wrapper `node` that sets
  `process.platform`). Every Node program of every phase would then believe it runs on macOS:
  the JS bundler would load `lightningcss.darwin-arm64.node` and fail, npm's platform packages
  would resolve to macOS binaries, and Expo's own `getScannerBinaryPath` would pick the Mach-O
  scanner. A rule for one tool's check that breaks the others, and a misreport no Xcode
  environment makes.
- **B. nomac ignores the phase's failure.** Xcode fails a script phase that exits non-zero; so
  must nomac.
- **C. The project changes its tool.** Like a Mach-O `hermesc`, the test is the project's own:
  the project either declares the classes in the packages' `expo-module.config.json` (the
  phase's own advice) or lets its autolinking scan on Linux, where the scanner exists (a
  one-line change of the platform check, kept with the project's patches). nomac provides the
  build machine as it is.

## Decision

C. nomac does not make a tool believe it runs on macOS, and adds nothing for one tool. `nomac
check` reports what a project's files show of the same tools (ADR 0011 domains): a Swift macro
plugin or a script phase's tool that is a Mach-O executable (`build:setting=mach-o-executable`,
with the setting to override on the command line), and native Node modules installed only for
macOS (`build:node-module=mach-o-only`, with the Linux packages the lockfile lists). A check
inside a tool's JavaScript is not visible in the project's files; the build fails with the
tool's own message, which names the change.

For the test apps, `expo_experiments.py verify --project-fixes` makes the project's changes on
the checkout it resets afterwards: the platform check allows `linux`, and `ios/.xcode.env.local`
names the Linux `hermesc` that `hermes-compiler` ships.

## Consequences

- expo-default's provider on Linux is the Mac's byte for byte, from the Linux scanner.
- A project whose packages have public `@ExpoModule` classes without a declaration depends on
  the scan; with the check left as installed, its Linux build fails at this phase rather than
  linking an app without those modules, which is the tool's own safeguard.
- The same reasoning applies to any tool a phase runs that tests `uname`, `process.platform` or
  similar: nomac reports what is visible and leaves the tool's choice to the project.

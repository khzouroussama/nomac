# ADR 0184: A fresh app builds with no change by its user

- Status: accepted (the Expo workstream, 2026-11-04). Supersedes ADR 0182's decision.
- Date: 2026-11-04

## Context

ADR 0182 left two things to the project, so a fresh Expo or React Native app needed a user's
change on Linux: a one-line edit in `node_modules` for Expo's platform check, and
`HERMES_CLI_PATH=<the Linux hermesc>` on every command line, for both kinds of app. The owner's
requirement replaces that decision: "I don't like that the user needs to change things to run his
app." After `npm install` and `pod install`, plain `nomac build` and `nomac archive` have to work,
with no edit to `node_modules`, no override and no other project-specific flag.

ADR 0182's observations still hold, and they are why this is safe:

1. `expo-modules-autolinking`'s `scanNativeModulesAsync` starts with `if (process.platform !==
   'darwin') { return null; }` ("The scanner is a macOS binary."), still there in 58.0.17, the
   latest on npm on 2026-11-04. `expo-modules-macros` installs a Linux scanner, which works.
2. Node reporting `darwin` to every program stays rejected: the bundler would load
   `lightningcss.darwin-arm64.node`, and Expo's own `getScannerBinaryPath` would pick the Mach-O
   scanner.
3. Failing to fail a phase stays rejected: Xcode fails a script phase that exits non-zero.

## Decision

Off macOS, `nomac build` and `nomac archive` handle these themselves, and never touch the user's
files. On a Mac they do none of it. Everything nomac changes about how a project's tools run follows
the owner's second requirement: separate, documented and highlighted, because nomac is a global
runner and not an Expo or React Native tool, and some users will still have to edit their own
projects.

**Separate.** All of it lives in `Sources/NomacBuild/ProjectFixes/`, with a table of `ProjectFix`
entries as data: the tool, the exact change or the rule, why, when to drop it, and any upstream issue.
The build code has one entry point, `ProjectFixRun`, and nothing else in it knows a tool. The table has
three entries.

| Fix | Change |
|---|---|
| `expo-autolinking-scan` | In memory, in `expo-modules-autolinking/build/platforms/apple/apple.js`: `if (process.platform !== 'darwin') {` is read as `if (process.platform !== 'darwin' && process.platform !== 'linux') {` |
| `mach-o-tool-linux-build` | A rule for any setting whose value is a Mach-O executable: the one fitting ELF executable of the same name, in a sibling of its folder |
| `macro-plugin-from-package` | ADR 0151's rule, moved under the same reporting: a Mach-O macro plugin is built from the Swift package beside it |

**Documented.** docs/PROJECT-COMPATIBILITY.md says what each fix does in plain words and how to turn
it off, and what a project may have to change itself, with which of those `nomac check` reports. A test
holds the document to the table and to the features `nomac check` knows.

**Highlighted.** Each fix prints a `note:` when it applies, and the end of the build repeats them in a
short summary naming the document, also under `-quiet`. `nomac check` lists the fixes that would apply in a
section of its own, apart from the features outside the envelope and without changing its exit status.
`--no-project-fixes` turns them all off for a build, which then stops with the original error.

### The in-memory edit

The first entry is deliberate tool-specific code, in a project that otherwise has none, because the
owner asked that users change nothing. nomac adds `--require <preload>` to script phases' `NODE_OPTIONS`,
after any value the environment, the project or the command line gives. The preload is written to
nomac's scratch folder. It wraps `Module.prototype._compile`: for a file whose path ends in the entry's
suffix and whose source contains the exact old text, it compiles the replaced text, prints its `note:`
to standard error and appends the fix's id to the file `NOMAC_PROJECT_FIXES_RECORD` names, which the
end of the build reads. That path is the same from build to build, so that the environment does not make
phases run again. Every other file compiles as it was, and `process.platform` still says `linux`
everywhere.

Without the exact text the entry does nothing, so an Expo release that fixes this makes it inert. **Drop
the entry when Expo ships the fix.** Add an entry only for a check that refuses Linux although the tool
works there, with the observation that shows it.

### The general rule for Mach-O tools

For a setting whose value is a Mach-O executable, nomac looks in the sibling folders of the executable's
folder for ELF executables with the same file name. If exactly one fits this machine, its own
architecture first and otherwise one the kernel accepts through user-mode emulation, nomac sets it as an
override. A value on the command line always wins, and shell code a phase sources afterwards
(`ios/.xcode.env.local`) still can.

- Several that fit: no override, and a warning asks for one on the command line.
- Only other machines' builds, which this one cannot run: the override is a stand-in script that stops
  the build with an error naming `qemu-user-static` instead of "Exec format error", if the build comes to
  run the tool. A failure at the start would be wrong: Debug bundling never runs `hermesc`, and a setting
  may name a tool nothing runs.

`nomac check` reports the same choice. A setting with a build that fits is
`build:setting=mach-o-executable-linux-build`, verified. Otherwise it stays
`build:setting=mach-o-executable`, the project's requirement, naming the builds.

## Options not taken

- **Editing `node_modules`** in the build: nomac does not change the user's files, and a checksum or
  a later `npm ci` would see or undo it.
- **Scanning the build's output for the summary**: under `-quiet` there is no output to scan, and a
  file the preload appends to also works when a phase captures its tool's output.
- **Node reporting `darwin`**, ADR 0182's option A, for the reasons above.
- **The shell of script phases** setting `NODE_OPTIONS` (`usr/libexec/nomac/sh`, ADR 0103): it needs a
  reinstalled developer directory and covers only phases whose `shellPath` is `/bin/sh`. A build
  setting reaches every phase, because Swift Build exports overrides to their environment.

## Consequences

- A fresh app builds unchanged; the results are in docs/DEMO.md.
- A project's own requirements stay its own, and docs/PROJECT-COMPATIBILITY.md lists them. This ADR
  does not make nomac responsible for every tool's test of the system.
- A phase that assigns `NODE_OPTIONS` itself, without keeping the value it had, drops the preload,
  and the build fails with Expo's own message.
- `expo_experiments.py verify --project-fixes` and `rn_holdout_experiments.py`'s are gone, and so is
  the sweep's edit of `apple.js`: nomac now does what they did.
- ADR 0182's rule still stands for everything outside the table: a tool's other tests of the system
  are the project's, and the build fails with the tool's own message.

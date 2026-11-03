# ADR 0004: Reference artifacts and the comparison contract

- Status: accepted
- Date: 2026-10-21

## Context

nomac is "done" for a file type only when its output matches Xcode's. That needs real
Xcode output for real projects, plus a precise statement of what "match" means when some
values depend on the machine (user name, home directory, checkout path).

## Decision

1. **Where references come from.** The `reference` workflow runs on GitHub-hosted macOS
   runners (`xcode-27` image, Xcode 27.0 build 27A266a, matching the pinned Swift Build). For each
   corpus app it captures `xcodebuild -dumpPIF`, `xcodebuild -list -json`,
   `-showBuildSettings` (text and JSON) for every target and shared scheme, the build log,
   products, compiled resources and an unsigned IPA (`corpus/scripts/capture_reference.py`).
2. **What is stored.** Artifacts are uploaded as workflow artifacts named
   `reference-<app>-xcode-<build>` and kept for the maximum retention. They contain only
   output derived from the corpus's own open-source apps. They never contain Xcode
   itself, SDK files or Apple binaries, and they are never committed to this repository.
3. **Fixed environment.** Every `xcodebuild` invocation runs with a fixed, minimal
   environment (`PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `TMPDIR`, `LANG`,
   `DEVELOPER_DIR`), recorded with the host identity in `host.json`, so the runner's
   environment does not leak into the reference.
4. **Comparison contract.** `nomac inspect` can present the host identity from a reference's
   `host.json` (user, group, ids, home directory, OS version and build, architecture,
   environment) to Swift Build. A comparison then rewrites exactly three kinds of
   machine-specific absolute paths on *both* sides to symbolic roots: the developer directory
   (`<DEVELOPER_DIR>`), the app's checkout directory (`<SOURCE_ROOT>`) and the derived-data
   root (`<DERIVED_DATA>`). After that rewrite the outputs must be byte-identical. No other
   normalization is allowed. Any additional rule needs a new ADR that says why the value
   cannot be reproduced.
5. **Where comparisons run.** The project loader is pure data transformation, so it runs and
   is compared on the macOS runner against the installed Xcode. This is the only place
   CI may legally have a complete Xcode. Linux CI runs the full test suite against a
   self-authored synthetic developer directory. A Linux run against the real SDK needs
   the user's own Xcode (`nomac sdk install`) and is documented in docs/VERIFICATION.md.

## Consequences

- References expire after 90 days and are re-captured by re-running the workflow. Each
  capture is tagged with the Xcode build, so captures from different Xcode builds are
  never compared with each other.
- Point 5 means Linux CI cannot prove SDK-dependent behavior (compiling and linking) until
  the project owner decides how CI may obtain an iOS SDK on Linux. That decision is recorded
  in docs/STATE.md under "Decisions needed".

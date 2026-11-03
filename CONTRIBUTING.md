# Contributing to nomac

Thank you for helping. nomac reproduces what Xcode does, so most work is finding out exactly what
Xcode does in one case, then making nomac do the same and proving it. This page explains how.
AI coding agents follow the same rules, written for them in AGENTS.md.

## Setup

On Linux, where nomac runs: Ubuntu 24.04 with Swift 6.4.1, as in docs/INSTALL.md "Building
from source", then:

```sh
swift build --build-tests && swift test --skip-build
.build/debug/nomac --help
```

A Mac with Xcode 27.0 (27A266a) is needed only to observe Xcode: running the experiments and
capturing references of corpus apps (docs/VERIFICATION.md "Without CI"). Install that Xcode at
`/Applications/Xcode_27.app` and build with
`DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer swift build --build-tests`. Leave
the system's selected Xcode alone.

## The rules, briefly

- Match Xcode by observation. Every behavior nomac reproduces comes from an experiment on a
  self-written project or from a corpus app's Xcode output, and the code comment or the format
  doc in `docs/formats/` names which. If you do not know what Xcode does in a case, find out with
  an experiment; do not guess. A difference nobody can explain is a bug.
- The legal line. Never commit Apple binaries, SDK files, anything from an Xcode `.xip`, or
  files Xcode produced. Tests keep observed facts (values, SHA-256 digests), not Xcode's files;
  experiment outputs stay outside the repository. Never decompile, disassemble or patch Apple's
  tools: watch what they output. docs/LEGAL.md has the details.
- No stubs, TODOs or mocks in merged code. Unfinished work goes to `docs/BACKLOG.md` with
  why it waits and the plan.
- Keep the docs true in the same pull request: the state file of the area you work in
  (`docs/state/`), `docs/formats/`, ADRs (`docs/adr/`), `docs/ARCHITECTURE.md`,
  `docs/BACKLOG.md`, docs/PROGRESS.md.
- Small conventional commits : `feat(scope):`, `fix(scope):`, `test(scope):`, `ci:`, `docs:`,
  each saying what changed and why, with the test output that shows it works.
- Swift for nomac; Python only for CI, experiment and capture scripts.

## Picking work

- `docs/STATE.md` lists the workstreams and each one's state file in `docs/state/`, whose "Next
  actions" are ready to take.
- `docs/BACKLOG.md` lists deferred items with their reason and plan.
- Things `nomac check` reports for your own project are good first issues: open one with the
  report (it contains no source code).

Before starting something large, open an issue so that nobody does it twice.

## Adding an experiment

1. In the suite for the area (`.github/scripts/<area>_experiments.py`), add a case that writes a
   minimal project varying one thing.
2. Run the suite on the Mac with Xcode 27.0; outputs go to a folder outside the repository
   (`~/nomac-out/<suite>` by convention).
3. Write the rule you observed in `docs/formats/<area>.md`, naming the case.
4. Implement it in nomac and add a test with the observed values.
5. Run the suite's comparison against nomac when it has one (`--nomac .build/debug/nomac`).

## Checking with `nomac verify`

`nomac verify` compares nomac's output for an app with a reference Xcode built, file by file, and
reports every difference (docs/VERIFICATION.md). With a reference captured by
`corpus/scripts/capture_reference.py`:

```sh
.build/debug/nomac verify ~/nomac-out/reference/<app> --source <checkout> \
    --developer-dir /Applications/Xcode_27.app/Contents/Developer
```

A change that touches behavior shows its before and after numbers in the pull request.

## Pull requests

1. Branch from `main`; one topic per branch.
2. Run the suite (Linux, and the Mac when you touched Mac-only behavior) and `nomac verify` on
   the apps your change affects.
3. Open the pull request with what changed, why, the experiment or reference behind it, and the
   test output. CI runs the Linux suite on x86_64 and arm64.
4. Keep BACKLOG and ADR numbers in your area's range (AGENTS.md) and unique in the history.

By contributing you agree that your contribution is licensed under the Apache License 2.0.

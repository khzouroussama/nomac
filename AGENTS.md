# nomac for AI coding agents

nomac builds iOS apps from `.xcodeproj`/`.xcworkspace` on Linux, with the user's own Xcode
download and no Mac: the goal is the IPA Xcode would produce, byte for byte where Xcode is
deterministic, plus device install, tests and TestFlight upload. Progress is measured on real
apps: the corpus (`corpus/`), the holdout and the React Native and Expo sweep (docs/PROGRESS.md).

## Picking up

1. Read `docs/STATE.md` (current step, workstreams, next actions, how to reproduce), then
   `docs/ARCHITECTURE.md`, then your workstream's `docs/state/<workstream>.md`. Those files are
   written so that you can continue without any other context.
2. Pick the next action there, or a `docs/BACKLOG.md` item in your workstream: each says why it
   was deferred and the plan.
3. Find the rule with an experiment before writing code (below), implement it, and encode the
   observed facts in tests.
4. Verify (below), update your state file and the docs the change touches, commit, and hand the
   branch over.

## Rules

- Match Xcode exactly. Every behavior nomac reproduces comes from observation: a corpus
  reference (`docs/VERIFICATION.md`) or an experiment on self-written projects
  (`.github/scripts/*_experiments.py`). Say which in the code comment or the format doc
  (`docs/formats/`). When a rule is not known yet, find it with an experiment; do not guess.
  An unexplained difference is a bug, not noise. Where nomac does not know Xcode's behavior, it
  stops with a message (`nomac check` reports it) instead of guessing.
- Legal line. No Apple binaries, SDK files, `.xip` contents or Xcode-derived artifacts are
  ever committed or published. Reference artifacts from the macOS CI are stored only for the
  corpus's own open-source apps. Everything reimplemented is written from observing outputs
  and public documentation, never from decompiling, disassembling or patching Apple's tools.
  Experiment and capture outputs stay outside the repository; tests encode the observed facts
  (values, digests), not Xcode's files. See docs/LEGAL.md.
- Swift for nomac itself; Python only for CI, experiment and capture scripts.
- No stubs, TODOs or mocks in merged code. Deferred work goes to `docs/BACKLOG.md` with the
  reason and the plan.
- Keep the docs true in the same change: docs/PROGRESS.md, `docs/STATE.md` or the
  workstream's state file, `docs/ARCHITECTURE.md`, ADRs (`docs/adr/`), `docs/formats/`,
  `docs/BACKLOG.md`, and the README when what it says changes.
- Small conventional commits (`feat(scope):`, `fix(scope):`, `test(scope):`, `ci:`, `docs:`)
  whose message says what changed and why, with the test output that shows it works pasted in.
  Commits are authored by the git identity of the person you work for and end with a
  `Co-Authored-By:` trailer naming the model that wrote them. No session lines or links to
  agent sessions in commits, pull requests or docs.
- Milestone tags only when CI is green, through `.github/tags` (ADR 0007).
- Ask the maintainers only for decisions that are theirs (money, visibility, accounts, scope).

## Finding a rule with an experiment

Experiments run on a Mac with Xcode 27.0 (27A266a) at `/Applications/Xcode_27.app`. Each suite
in `.github/scripts/*_experiments.py` writes small self-written projects, runs Xcode's tools on
them, and records the outputs outside the repository (`~/nomac-out` by convention,
docs/VERIFICATION.md "Without CI"). Add a case that isolates the behavior (vary one thing at a
time), record it, write the rule down in `docs/formats/` with the experiment's name, then make
nomac produce the same output and add a test with the observed values.

## Verifying

```sh
swift build --build-tests && swift test --skip-build      # Linux, Swift 6.4.1
DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer swift build --build-tests && swift test --skip-build   # Mac
.build/debug/nomac verify <reference-app-dir> --source <checkout> --developer-dir <Xcode>/Contents/Developer
```

`nomac verify` compares nomac's output for a corpus app with Xcode's reference, file by file
(docs/VERIFICATION.md). Anything that needs Xcode's own output runs on a Mac; the macOS
workflows are manual-only (billed at 10x).

## Working in parallel

Several agents may work at once, one workstream each:

- One branch per workstream, from `main`, merged through a pull request. Rebase or merge
  `main` in before opening it; never rewrite another workstream's branch.
- Stay inside your workstream's modules (`Sources/<Module>`, `Tests/<Module>Tests`). Changes
  to shared code (`NomacCore`, `Package.swift`, CI) are kept small and called out in the PR.
- Keep your state in `docs/state/<workstream>.md` (current step, just finished, next
  actions). `docs/STATE.md` lists the workstreams; only the integrating session edits its
  other sections and docs/PROGRESS.md's generated section.
- Number new BACKLOG items and ADRs in your workstream's range, so parallel branches never
  collide, and only with a number that appears nowhere in the history
  (`git log --all -S 'B-0NN'` is empty):

  | Workstream | BACKLOG | ADRs |
  |---|---|---|
  | Project loader, SDK, verification harness | B-001–B-099 | 0011–0099 |
  | Build driver (Swift Build builds, toolchains, SwiftPM, CocoaPods, xcframeworks) | B-100–B-199 | 0100–0199 |
  | Resources (asset catalogs, storyboards and xibs, strings, Core Data, rare types, Metal, Core ML) | B-200–B-299 | 0200–0299 |
  | Packaging and signing (IPA, entitlements, dSYM, extensions) | B-300–B-399 | 0300–0399 |
  | Device and distribution (install, launch, tests on device, TestFlight) | B-400–B-499 | 0400–0499 |

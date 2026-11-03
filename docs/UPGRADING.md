# Moving nomac to another Xcode

Each nomac release reproduces one Xcode build (docs/adr/0012-one-xcode-per-release.md), and
everything nomac takes from that Xcode is in one file, `Sources/NomacCore/XcodeProfile.swift`.
Moving to another Xcode is observing it again everywhere nomac observed the current one,
then changing the profile, the pins the tests point to, and the rules whose observations changed.
`.github/scripts/xcode_upgrade.py` does the observing and writes the list of what changed.

It runs on a Mac with both Xcodes installed side by side (`/Applications/Xcode_27.app` and, say,
`/Applications/Xcode_27.1.app`), each selected per command with `DEVELOPER_DIR`; never with
`xcode-select`. Outputs stay outside the repository, in `~/nomac-out/xcode-upgrade/<build>`.

## 1. Record the current Xcode

Once per Xcode, with the nomac release that reproduces it, before the new one is looked at:

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
swift build -j 4                                  # the nomac whose profile is the current one
python3 .github/scripts/xcode_upgrade.py run --steps experiments,fuzz,survey,probe
```

This writes `~/nomac-out/xcode-upgrade/27A266a`: the 16 experiment suites that observe Xcode
(`SUITES` in the script: every `*_experiments.py` of `.github/scripts` but shell_experiments.py,
which observes macOS's `/bin/sh`, and sdk_version_maps.py), the fuzzer's seeds 1 to 100
(`--fuzz-cases`), `nomac check` over the coverage survey's
repositories (`--survey`, default `~/nomac-out/survey`) and `probe.json`. The corpus references
of the current Xcode are those of docs/VERIFICATION.md (`~/nomac-out/reference`), so the
baseline does not capture them again. A step that finished is not run again (`--force` reruns
it), so an interrupted run continues where it stopped. `--out` and `--work` must lie outside the
repository: the runs hold Xcode's outputs and the user's and Mac's identity (`host.json`), and
both scripts refuse a folder inside it.

pif_stability.py clones an app at each run, so the harness does not run it: with each Xcode, run
`python3 .github/scripts/pif_stability.py netnewswire <folder>` by hand and compare the two
`summary.json`.

The suites and the fuzzer run in one fixed folder, `~/nomac-out/xcode-upgrade/stage`, and are
moved into the run's folder when they finish: their outputs record the paths they were made at,
and some of those cannot be rewritten afterwards (DerivedData folder names hash a project's path,
binaries and debug information embed it), so every run makes them at the same paths, as
verification does (ADR 0006). One run at a time holds the folder. The suites also use fixed work
folders under `/tmp` (`/tmp/nomac-pif-experiments`, `-nib-`, `-strings-`, `-coredata-`) and
DerivedData: run the harness when no other experiment runs on the Mac.

A first run against the current Xcode itself checks the harness: run the same command with
`--out ~/nomac-out/xcode-upgrade/27A266a-rerun` and all steps, then the report below with that
folder as the candidate. It must say **No change**.

## 2. Observe the new Xcode

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer
python3 .github/scripts/xcode_upgrade.py run
python3 .github/scripts/xcode_upgrade.py report --baseline ~/nomac-out/xcode-upgrade/27A266a \
    --candidate ~/nomac-out/xcode-upgrade/27A9275
```

`run` sets `NOMAC_UPGRADE_XCODE_BUILD` for the scripts, which otherwise refuse an Xcode other than
`corpus/corpus.json`'s. The corpus references are captured again from the checkouts in `--work`
(default `/tmp/nomac-corpus`, where `capture_reference.py` puts them) without cloning them again
(`--reuse-checkout`); `--with-builds` also captures each app's build. The nomac it runs is the
current release: the fuzzer's and the survey's verdicts are its own against the new Xcode.

`report` writes `REPORT.md` and `report.json` into the candidate folder and exits with 1 when
anything changed:

- **Profile values to update**: each value of `nomac sdk profile` the new Xcode answers otherwise
  (`probe.json`): its version and build, actool's and ibtool's versions, the `Assets.car` strings
  (from a color set the probe compiles), the SDKs, the Mac, the `DT*` keys (from build-experiments
  `app-without-packages`), Xcode's own tools, the Mac's answers to manifest conditions
  (package-experiments `conditions`) and the `objectVersion`s it reads (envelope-experiments
  `object-versions`).
- **Experiments whose outputs changed**, by suite and experiment, with the lines of `Tests`,
  `docs` and `Sources` that cite each one: the rules to observe again and the tests to derive
  again.
- **Corpus references** and **fuzz cases** whose Xcode outputs changed, the fuzzer's count of
  identical cases, and the survey's coverage.

What is compared is Xcode's outputs and, where a suite records them, nomac's verdicts against
them (envelope-experiments' `verify.log` and `nomac-list.txt`, assets-experiments' comparisons,
the fuzzer's count of identical cases); not the projects the scripts write (`src`, `source`, `work`,
with their git repositories), DerivedData's build state and caches (everything but
`Build/Products`, as `nomac verify`'s build check), the apps' preparation logs, an export's
`Packaging.log`, or a reference's build and archive when the run captured none. Before comparing,
both sides are rewritten for what says nothing about Xcode, each rule observed in runs against
Xcode 27.0 itself (`Normalizer` and the tables above it in the script):

- the folders compared and the runs' own; the Xcode's identity, which the profile section reports
  once: its build, version, `XCODE_VERSION_*` and `DTXcode`, developer directory, its SDKs'
  versions and builds (`showsdks.json` is left out), and `Assets.car`'s version string, with
  binary property lists compared by their content; nomac's own warning that the run's Xcode is
  not its profile's, which only an upgrade's candidate run prints;
- clock times, process ids, durations, object addresses, result bundle and log bundle names; the
  `seconds` of the scripts' records and whether a checkout was prepared; the time and the
  `mktemp` name of each codesign capture (named by its command line instead); the commits of the
  git repositories the experiments create;
- the devices and simulators of the Mac, which xcodebuild lists among a scheme's destinations;
- the times things record of their inputs: the entries of a zip (as signing-experiments compares
  IPAs), a `.symbols` file's dSYM time, `.swiftsourceinfo`'s source times, and the bridging
  header's time in a Swift module (docs/VERIFICATION.md lists the last two for builds);
- xcodebuild's package preamble
  (fetch lines and the resolved packages' order), which `nomac verify` leaves out too;
- in PIFs, `nomac verify`'s object signatures and the GUIDs Xcode draws at random (ADR 0009);
  synchronized GUIDs and the order of package projects stay compared, so a change in how Xcode
  derives them shows; `.car` files with their appearance keys in name order (ADR 0200);
- logs and actool's standard error, compared as sets of lines (xcodebuild runs independent tasks
  at once);
- the experiments whose docs record an output that changes from one run to the next (`VARYING`
  in the script, each with its BACKLOG item: B-015, B-017, B-030, B-031, B-034, B-065, B-097,
  or the rule docs/VERIFICATION.md gives for schemes of one name): compared without their order, or, where xcodebuild picks another target, scheme or app,
  listed in the report but not compared.

Every other difference is listed. A new one found against the current Xcode itself is an
observation: record it (BACKLOG B-097) before adding a rule. `python3
.github/scripts/xcode_upgrade_test.py` checks the rules on a simulated candidate of another build
(27.1, 27A9275): its outputs, which differ only by that Xcode's identity, must compare identical,
and a changed setting must not.

## 3. Change nomac

On a branch of its own, in this order:

1. **The profile.** Every value of the report's first table, in `XcodeProfile.swift`, with where
   it was observed.
2. **The pins**, re-derived by comparison, since no tool reports them (ADR 0005, ADR 0010,
   ADR 0100, ADR 0102): the Swift Build revision whose settings match the new Xcode's references,
   the SwiftPM revision and the tag the package PIF builder is vendored from
   (`Sources/VendoredPackagePIFBuilder/UPSTREAM.md`), the swift.org release paired with the Xcode
   and the llvm-project tag the lld patches apply to. `XcodeProfileTests` fails until
   `Package.swift`, `Package.resolved`, `UPSTREAM.md`, `build-llvm-tools.sh` and `build-swift-frontend.sh`
   agree with the profile; `.github/swift`'s patches are made again for the new tag's swiftlang/swift.
3. **The corpus's Xcode.** `corpus/corpus.json`'s `xcode` block (also checked by
   `XcodeProfileTests`); the `xcode-27` runner label and the Xcode path in `.github/workflows`
   and in the scripts' defaults (`/Applications/Xcode_27.app`), and `docs/VERIFICATION.md`'s.
4. **The rules.** For each changed experiment, the format document's observation and the code,
   with the tests the report lists; each difference is either explained by a change in Xcode and
   reproduced, or a BACKLOG item. Unchanged experiments carry over: their envelope entries
   (ADR 0011) are evidence for the new build too.
5. **The references.** The new captures replace the old ones (`~/nomac-out/reference`), and
   `nomac verify` runs over every corpus app, as in docs/VERIFICATION.md.
6. **The version.** The release counter in `NomacVersion.current` goes back to 1 when the Xcode's
   major or minor version changed (`27.1.1`), and up by one otherwise.

The record of step 1 for the new Xcode is then the baseline of the next upgrade.

# Verification harness: check kinds and progress

Part of the loader, SDK and verification workstream (BACKLOG B-001–B-099, ADRs 0011–0099).
Branch `loader/verify-kinds`. How a comparison works is in docs/VERIFICATION.md ("Tool checks",
"Signing and export checks", "Progress"); this file is where the work stands.

## Current step

`nomac verify` compares, beside the loader's `pif`, `list` and `settings`: every resource tool
task of a reference's Xcode build (`strings`, `nib`, `assets`, `coredata`, `ToolVerification`),
every codesign step and the export of an ad-hoc archive (`signing`, `export`,
`ArchiveVerification`), and with `--build` the build products (`build`, the build driver's).
Each report records where it ran (`host`). `nomac corpus results` measures each README line as
corpus.json's `progress` says; the build driver's line and "apps build" read Linux reports only.

## Just finished

- Numbers of 2026-10-24 (main e33efac): 20 Mac reports and retro-rampage's Linux report, in
  `~/nomac-out/wt-scratch/verifykinds/reports-v8`; corpus/RESULTS.md and the README rendered
  from them.
- Reference captures on the owner's Mac (outside the repository):
  - `~/nomac-out/reference/<app>/build`: Xcode builds of 17 apps (`capture_reference.py --build`),
    of which cwa, pocket-casts, signal and mattermost stop before any tool task (B-098);
  - `archive/` for retro-rampage, tofu, flappy-fly-bird and uncloudnotes (`--archive`);
  - references of their own for those four, from clones under a scratch root, for
    `--build`: `~/nomac-out/wt-scratch/verifykinds/refs`, clones in `…/corpus`.

## Next actions

1. Linux reports for more apps' builds (tofu, flappy-fly-bird, uncloudnotes) once the build
   driver says they build on Linux (docs/state/build-driver.md); `linux_verify.sh <app>` below.
2. B-093 (tool messages), B-098 (corpus builds that fail under Xcode 27.0), B-099 (package
   inputs without the capture's derived data).
3. home-assistant's build capture was stopped at the time limit; capture it again on a
   reference of its own (a long build: give it its own background job).
4. Findings for other workstreams, not fixed here: the export adds an empty `embeddedBinaries`
   where Xcode leaves it out (packaging); Xcode's `builtin-copyStrings` drops a leading U+FEFF in
   a value (strings, nextcloud's `kn`); on the Mac, Xcode's momc writes uncloudnotes' `.omo`
   differently each run, so the `build` check differs by it (build comparison).

## How to reproduce

Scripts in `~/nomac-out/wt-scratch/verifykinds` (outside the repository; Mac, Xcode 27.0):

```sh
V=~/nomac-out/wt-scratch/verifykinds
$V/snapshot.sh <label>                       # copy the worktree's debug nomac to $V/bin/<label>
$V/capture_builds.sh <apps…>                 # --build into ~/nomac-out/reference, two at a time
$V/capture_archives.sh <apps…>               # --archive into ~/nomac-out/reference
$V/own_refs.sh <apps…>                       # full capture and archive under $V/refs, $V/corpus
$V/verify.sh <label> <reports> <apps…>       # nomac verify of ~/nomac-out/reference/<app>
VERIFY_FLAGS=--build $V/verify_own.sh <label> <reports> <apps…>   # of $V/refs/<app>, with --build
$V/linux_verify.sh <app>                     # --build on Linux: see below
.build/debug/nomac corpus results --reports <reports> --output corpus/RESULTS.md \
    --update docs/PROGRESS.md --update docs/STATE.md --source "<where the reports came from>"
```

Never run `--build` against `~/nomac-out/reference`: its checkouts are the shared
`/tmp/nomac-corpus/<app>` (docs/VERIFICATION.md "Tool checks"). `linux_verify.sh` runs in a
container on the `nomac-verifykinds` volume: this branch's Linux nomac at `/work/bin/current`
(built there with `swift build --skip-update`, the Mac's `.build/checkouts` copied in, and the
`.bundle` folders beside the binary), the build workstream's installed developer directory
`nomac-build:xcode-640-ld/Xcode_27.app` mounted read-only at `/Applications/Xcode_27.app` (its
tool launchers run `/work/bin/current/nomac`), the reference mounted read-only at its path and
the clone copied into the container at its own. Remove the volume when done.

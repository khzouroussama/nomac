# Linux corpus: state

Workstream: the corpus apps built fully on Linux with nomac (Docker), measured by
`nomac verify --build` against their Xcode references, and the Linux reports the README's
progress reads (docs/VERIFICATION.md "Progress": the build line and "apps build" count reports
with `"host": "Linux"` only). Build-driver rules found on the way are fixed here; resource,
packaging and clang findings go to their workstreams. Branch `build/linux-corpus`, based on
`build/driver`. BACKLOG B-171–B-179, ADRs 0130–0149.

## Current step

Batch 4 (2026-11-02): main `0b15e3e8` (lld with patches 1 to 13, cctools with 1 to 6, the patched
clang with 0001 to 0026 and its `clang.cfg` defaults) against the references the B-098 swap
captured again: 17 of 20 now have a successful Xcode build. Every corpus app was verified on the
Mac; on Linux the 17 apps one at a time under `nice`, 16 measured (nextcloud stopped by the disk
watchdog at 3 GB free). README progress from these reports (`~/nomac-out/linux-corpus/results-final`):
overall 63%, 2 / 20 apps build on Linux, build driver 929 / 1198 checks in 16 apps.

Build products identical or equivalent on Linux: retro-rampage 8/8, flappy-fly-bird 4/4, swiftfin
135/138, netnewswire 63/68, cwa 62/66, kickstarter 157/168, mastodon 96/117, icecubes 75/86,
pocket-casts 167/245, home-assistant 122/219, wikipedia 28/42, gomap 6/12, moonlight 3/7, tofu 2/5,
uncloudnotes 1/4, flutter-platform-channels 0/9. What stops them, by class:

- Resources (nibs, assets, intents) in every app but retro-rampage and flappy-fly-bird.
- macOS's case-insensitive file system: cwa's project names `PDFGeneration`, the folder is
  `PdfGeneration`; moonlight's `#include <openssl/evp.h>` finds the binary package's
  `OpenSSL.framework` only case-insensitively.
- watchOS targets (home-assistant, pocket-casts): the SDK subset gives no `Swift` module or
  `Foundation/Foundation.h` for watchOS.
- App Intents metadata (B-107): gomap's `LiveActivityIntent` and constant values, icecubes'
  `ProvidesDialog & ShowsSnippetView`.
- `tapi stubify` refuses Objective-C ivar symbols (B-106, mastodon's MastodonSDKDynamic).
- A script phase running SwiftPM on a local build-tools package (home-assistant's SwiftGen and
  SwiftLint): the manifest does not compile in the phase's environment.
- Binary artifacts' framework binaries that Swift Build cannot open (kickstarter's
  facebook-ios-sdk and braze xcframeworks).
- swiftfin's linked images: Objective-C references in `__DATA` where Xcode's `ld` puts them in
  `__DATA_CONST`, an export's weak-definition flag, an export only in Xcode's.
- nomac's debug build asserts in Swift Build's `SwiftPackageCopyFilesTaskProducer` (a binary
  target's build file with platform filters; kickstarter, pocket-casts), which Xcode's release
  Swift Build compiles out: these runs use nomac built with `-assert-config Release`.

## Just finished

- B-173: cctools' `ld64 -r` leaves a Swift object's `__LLVM,__swift_modhash` out, as Xcode's `ld`
  (cctools' sixth patch; `relocatable_experiments.py`: 6 of 6 cases as Xcode's, 4 of 5 before).
- B-175: `nomac build` and `nomac archive` run scheme pre-actions and post-actions as xcodebuild
  does (docs/formats/build.md "Scheme actions"); the full settings environment of an environment
  buildable and unobserved cases remain (B-175).
- cctools' fifth patch: `ld64 -r` leaves empty sections out, as Xcode's `ld`
  (`relocatable_experiments.py` `empty-*`; netnewswire's `RSCoreObjC.o`).
- `-derivedDataPath` and build-log paths under `/private/tmp` are spelled `/tmp`, as xcodebuild
  (`FileSystem.xcodebuildSpelling`), in nomac and in `verify`'s tool checks.
- `swift_conformsToProtocol2` from iOS 17.0 is a documented compiler difference.
- netnewswire's prepare step runs `buildscripts/updateSecrets.sh` (no secrets needed).

## Next actions

1. nextcloud on Linux once the Docker disk has 20 GB free.
2. B-175's remainder: Xcode's settings environment for an environment buildable.
3. Rerun the eight apps on Linux as the nib, asset and clang fixes land, and the twelve others
   once their references build.

## How to reproduce

In Docker, `nomac-linux-corpus` volume: nomac built from this branch at `/work/src`
(`swift build --scratch-path /work/build -debug-info-format none`), lld rebuilt with
`.github/scripts/build-llvm-tools.sh` (WORK=/work/lld-work, the build agent's tree copied for an
incremental build), the SDK subset and toolchain at `/work/devdir/Xcode_27.app`
(`nomac toolchain install … --llvm-tools /work/llvm-tools`, a fresh subset each time). The
verify container mounts that developer directory at `/Applications/Xcode_27.app`, the corpus
checkouts read-only, the references at their Mac paths and the Mac's SwiftPM repository cache
read-only at `/mac-swiftpm` (each app's packages are copied from it, so resolution only fetches
updates); `~/nomac-out/linux-corpus/scripts/verify.sh
<app> …` copies each checkout to `/private/tmp/nomac-corpus/<app>` (`/tmp` a relative link to
`private/tmp`), runs `nomac verify <reference> --build --continue-building-after-errors` from
inside the copy and writes `<app>-linux.json`. Run from inside the checkout: corelibs Foundation
standardizes a path that does not exist (`project.xcworkspace` of a lone project) through the
link only from some directories, and the PIF's project GUIDs then differ.

```sh
python3 .github/scripts/ld_weak_experiments.py <out>                   # Mac, Xcode's ld
python3 .github/scripts/ld_weak_experiments.py <out> --lld <lld>       # Linux, the same objects
python3 .github/scripts/relocatable_experiments.py inputs <out>        # Mac
python3 .github/scripts/relocatable_experiments.py run <out> <developer-dir>   # Linux
python3 .github/scripts/swift_codegen_experiments.py <out> <developer-dir> xcode|nomac
```

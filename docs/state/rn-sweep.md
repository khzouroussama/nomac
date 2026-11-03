# React Native and Expo sweep: state

Workstream: how many React Native and Expo apps that nobody tuned nomac for build on Linux, and
what stops the rest, ranked by the number of apps each failure class blocks, so that other
workstreams fix the largest classes with general rules. It measures "builds on Linux", not byte
identity: no Xcode references. Nothing here is fixed in nomac; each class goes to the workstream
that owns it. Branch `corpus/rn-sweep`. BACKLOG B-043–B-049, ADRs 0030–0039.

## Current step

Batch 1 (10 of Expo's examples, 5 apps) done on main `b225fc0c` and routed (Results, Classes).
Running: all 106 apps of the manifest on main `c2ad7afd` (`results-batch1-b225fc0c/` keeps batch
1's records). Next: its table, B-043.

## The apps

`corpus/rn-sweep.json`: Expo's examples (github.com/expo/examples at a fixed commit, one entry per
folder; no lockfile, so npm resolves as of the commit's date, `npmBefore`) and open-source apps at
fixed commits, picked for the variety of their native dependencies. `rn_sweep.py install` records
the React Native and Expo versions each install resolved in the entry.

## How it runs

`.github/scripts/rn_sweep.py` (its docstring has every step). On the Mac, online: the app's
packages with its lockfile's package manager (npm, yarn, pnpm, bun; through corepack), `expo
prebuild --platform ios --no-install` for an Expo app without an `ios` folder, `pod install`
(CocoaPods 1.16.2 under rbenv's Ruby 3.0.0, Node 24.22.1: expo_experiments.py's pins), then the
Linux builds (glibc, arm64 and x64) of every npm platform package the Mac's install left out,
from the registry with their integrity checked (`linux_packages`: one rule for every package
manager, where expo_experiments.py's reads `package-lock.json`). `script_phase_survey.py` counts
the macOS-only commands and BSD flags of the app's script phases. In a container without network
(`nomac-sweep-run`, the `nomac-sweep` volume; the app at its Mac path, the Linux Node at the Mac
Node's path): `nomac check --json`, the project's changes for Linux (each setting that names a
Mach-O tool overridden on the command line with the Linux build of the same tool, the one `nomac
check` lists or else the nearest ELF executable of that name in the checkout; ADR 0182's platform
check of expo-modules-autolinking), `nomac build` Release continuing after errors, then `nomac
archive` (ad hoc) and `nomac export` (`debugging`). Each failed step's failed tasks are classified
from the log (`classify`): the task in xcodebuild's failure summary and its errors, the errors that
name its input when its own output has none (actool's messages print under the catalog's other
task), and for a script phase the errors left in tasks that succeeded (nomac streams a script's
output as it runs, between other tasks' output). Classes starting `app:` fail with Xcode too (a
JavaScript import of a package the app does not install). Up to 3 apps install on the Mac
(`--installers`; one `pod install` at a time, CocoaPods' cache being shared) while up to 3 build on
Linux (`--builders`, each with a NOMAC_HOME of its own; one at a time while Docker's disk was small):
an install waits on the network for minutes to an hour, a build takes 2 to 7 minutes; each app's Mac copy is deleted once copied into the container, the
container's copy and build folders after its run, the logs gzipped; results stay in
`~/nomac-out/sweep/results` (`reclassify` reads the kept logs again). The Mac checkout of an app
that fails after its install is kept for 6 hours (`--keep-failed`), for other agents to look at,
then deleted (sooner when the Mac runs short of space); its result names it. Builds wait for 10 GB free on
the Mac and 15 GB in Docker (agent-common.md, after the VM filled up on 2026-11-02).

The container has no network, so what a build would download is provided: the Linux Node, and
the SwiftPM cache's swift-syntax repository (copied from the Mac's), which `nomac build` fetches to
build Expo's macro plugin from the package beside it (ADR 0151). nomac takes the developer
directory from `NOMAC_DEVELOPER_DIR`.

## Results

Batch 1, main `b225fc0c` (Swift Build fork `01811544`), 2026-11-02:

| step | apps that reached it | passed |
|---|---|---|
| install (Mac) | 15 | 13: expo-with-stripe's own pods fail on the Mac (`[Reanimated] Failed to validate worklets version`), bluesky's fetch was cut by the network |
| check | 13 | 13 |
| fixes | 13 | 13 (`HERMES_CLI_PATH` overridden with hermes-compiler's `linux64-bin/hermesc` in 13; the Linux packages of lightningcss, sentry-cli, ... installed) |
| build (Linux) | 13 | 5: expo-blank, expo-with-router, expo-with-reanimated, expo-with-skia, expo-with-sqlite |
| archive, export | 5 | 5 (ad-hoc signed IPAs, 7 MB for expo-blank) |

5 of 15 apps build, archive and export on Linux (33%); 2 more fail only for reasons of their own
(expo-with-camera, inaturalist), so 5 of the 11 that a Mac would build do (45%).

| app | React Native, Expo | first failure on Linux |
|---|---|---|
| expo-with-camera | 0.86.0, 57.0.31 | `app:` Metro: `Unable to resolve module @expo/vector-icons/AntDesign from <app>/App.tsx: @expo/vector-icons/AntDesign could not be found within the project` (the example imports a package its package.json does not list) |
| expo-with-maps | 0.86.0, 57.0.31 | nomac crashed: llbuild's `DirectoryContentsTask::getContents` dereferences an unchecked `ErrorOr<basic_file_status>` (`*it->status()`); a debug build asserts |
| expo-with-sentry | 0.86.0, 57.0.31 | `sentry-cli - error: unrecognized subcommand 'xcode'`: the Linux build of sentry-cli has no `react-native xcode`, which Sentry's bundle phase calls |
| expo-with-widgets | 0.86.0, 57.0.31 | App Intents `isDiscoverable` (B-107); lld `TODO: support aliasing to symbols of kind 3` linking the widget's `.debug.dylib` in Release; `unable to spawn process 'embeddedBinaryValidationUtility'` |
| bluewallet | 0.88.1 | `lipo <MessagesApplicationExtensionStub> -output <Stickers.appex/Stickers>` (CopyAndPreserveArchs) refused without an operation; App Intents intent without a constant `title` (B-107); an app icon entry outside B-202's sizes; Ruby script phases (`/usr/bin/env: 'ruby'`); BSD `md5` |
| rocketchat | 0.86.3, 57.0.23 | watchOS asset catalogs (B-206) and Core Data generation for watchOS; clang segfault on expo-modules-core's `SwiftUIVirtualViewObjC.mm` (`<eof> parser at end of file`); a scene without one view controller (B-261); PDF images (B-200); `app:` its bundle phase sets `NODE_BINARY=/opt/homebrew/bin/node` |
| inaturalist | 0.83.10 | `app:` the scheme's pre-action sources `../.env` (secrets) and needs model files the repository leaves out |
| zeus | 0.87.1 | Yoga (built from source, `-Werror`): `argument unused during compilation: '-fmodules-cache-path=…' [-Werror,-Wunused-command-line-argument]` from swift.org's clang |

Every build also ran CocoaPods' `[CP] Embed Pods Frameworks` without `file` (`file: command not
found`, 11 of 11 apps, 246 calls in builds and archives): the script then neither strips
architectures nor copies the frameworks' dSYMs, silently. Script phases (script_phase_survey.py,
793 scripts in 15 apps): `ditto` in 12 apps (274 calls), `xcrun` 13, `ipconfig` 14, `realpath` 13,
`shasum` 10, BSD `md5` 2, `sed -i ''` 2, `PlistBuddy` 2, `defaults` and `open` 1.

## Classes

Each class goes to the workstream that owns it; none is fixed here.

| class | apps (batch 1) | owner |
|---|---|---|
| `file` missing on the Linux machine (CocoaPods' frameworks script goes on without it) | 11 | build driver (toolchain install) |
| App Intents metadata nomac does not write (`isDiscoverable`, an intent without a constant `title`; B-107) | 2 | build driver |
| a script phase's tool or interpreter the Linux machine lacks (`ruby`, BSD `md5`, `nc`, `open`) | 2 | build driver |
| a tool's Linux build lacks a macOS-only subcommand (`sentry-cli react-native xcode`) | 1 | project requirement: `nomac check` (loader) |
| asset catalogs: watchOS (B-206), PDF images (B-200), app icon entries outside B-202 | 2 | resources (asset catalogs) |
| storyboard scene without one view controller (B-261) | 1 | resources (nibs) |
| Core Data generation for a watchOS target | 1 | resources (Core Data) |
| swift.org clang: segfault on Objective-C++, `-Wunused-command-line-argument` for `-fmodules-cache-path` | 2 | clang |
| lld: aliases to symbols of kind 3 (a `.debug.dylib` in Release) | 1 | build driver (B-183) |
| `lipo` refuses CopyAndPreserveArchs' copy (a sticker pack's stub) | 1 | build driver |
| `embeddedBinaryValidationUtility` missing (apps with extensions) | 1 | packaging and signing |
| llbuild crash on an unreadable directory entry | 1 | build driver |
| `app:` failures (fail with Xcode too; B-043) | 3 | the apps |

Reruns on the same nomac: expo-with-maps built, archived and exported (the llbuild crash did not
come back: it depends on timing); bluesky (React Native 0.88.0, Expo 58.0.19, pnpm) builds Yoga from
source and fails as zeus does (`-Wunused-command-line-argument` under `-Werror`), and refuses
expo-dev-launcher's image sets with `appearances` (B-200).

## Reproduce

```sh
# once: a Linux build of nomac and a developer directory in the nomac-sweep volume
docker run -d --name nomac-sweep -v nomac-sweep:/work -v nomac-build:/ref:ro nomac-linux:6.4.1-noble sleep infinity
#   copy the sources and .build/checkouts into /work/src, then in the container:
#   swift build --skip-update; copy .build/debug/{nomac,SwiftBuild_*.bundle,nomac_NomacMacros.bundle} to /work/bin/<commit>,
#   link /work/bin/current; cp -a /ref/xcode/Xcode_27.app /work/devdir/;
#   nomac toolchain install /ref/toolchains/swift-6.4.0-RELEASE-ubuntu24.04-aarch64/usr --llvm-tools /ref/llvm-tools \
#     --developer-dir /work/devdir/Xcode_27.app/Contents/Developer; the Linux Node 24.22.1 in /work/node-linux
#   (--llvm-tools: a build whose lld.patches.sha256 and cctools.patches.sha256 are LinuxToolchain.builtPatches;
#   nomac-build's /ref/llvm-tools may be ahead of main)
python3 .github/scripts/rn_sweep.py container           # the run container, without network
python3 .github/scripts/rn_sweep.py run [app ...]       # Mac: every step, app by app
python3 .github/scripts/rn_sweep.py report              # the tables below
```

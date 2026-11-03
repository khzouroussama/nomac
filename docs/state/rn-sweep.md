# React Native and Expo sweep: state

Workstream: how many React Native and Expo apps that nobody tuned nomac for build on Linux, and
what stops the rest, ranked by the number of apps each failure class blocks, so that other
workstreams fix the largest classes with general rules. It measures "builds on Linux", not byte
identity: no Xcode references. Nothing here is fixed in nomac; each class goes to the workstream
that owns it. Branch `corpus/rn-sweep`. BACKLOG B-043–B-049, ADRs 0030–0039.

## Current step

Paused on 2026-11-03 (the owner saves usage): round 2 is partial, 61 of the manifest's 106 apps
finished (Round 2 below), the driver stopped with nothing in flight, the volume back to its base
(3.1 GB: nomac `ad202e5b` at /work/bin/current, its developer directory, the Linux Node, the
SwiftPM cache) and no checkout kept. Batch 1 (b225fc0c) is in Results and Classes.

Next actions:

1. Resume round 2 on the same nomac (`ad202e5b`; never move /work/bin/nomac-ad202e5b, the developer
   directory's launchers name it), once the Mac has 30 GB free:

   ```sh
   docker start nomac-sweep-run
   cd ~/nomac-out/wt/sweep && nohup python3 .github/scripts/rn_sweep.py run --resume --builders 2 \
       --installers 3 --keep-failed 6 > ~/nomac-out/sweep/run-round2-resume.log 2>&1 &
   ```

   `--resume` runs the 45 apps without a finished result; then `rn_sweep.py report` gives the table.
2. The round's classes routed to their workstreams (Classes), the report pasted here.
3. A next round on a newer main (its own nomac and developer directory, from /ref/llvm-tools at
   main's stamps) for the 47 results that came from `a9b571ab`, so that one build produces them all.
4. B-043.

The manifest records what an app asks of a build machine (`env`, `{checkout}` standing for its
checkout: bluesky's `SENTRY_XCFRAMEWORK_CACHE_DIR`, inside the checkout so that the container sees
the Sentry.xcframework that @sentry/react-native's podspec downloads at `pod install` and names by
its absolute path) and failures observed with Xcode 27.0 too (`failsWithXcode`: graysky's
RevenueCat 5.50.1, which the owner found does not compile with Xcode 27), reported as `app:`.

## The apps

`corpus/rn-sweep.json`: Expo's examples (github.com/expo/examples at a fixed commit, one entry per
folder; no lockfile, so npm resolves as of the commit's date, `npmBefore`) and open-source apps at
fixed commits, picked for the variety of their native dependencies. `rn_sweep.py install` records
the React Native and Expo versions each install resolved in the entry.

## How it runs

`.github/scripts/rn_sweep.py` (its docstring has every step). On the Mac, online: the app's
packages with its lockfile's package manager (npm, yarn, pnpm, bun; through corepack), for an Expo
example (no lockfile) `npx expo install --fix`, as Expo recommends, so that its packages are the
SDK's versions (an open range had pulled expo-web-browser 58.0.7 into the Expo 57 expo-with-clerk,
whose `SceneGeometry.anchorPopover` is Expo 58's: Xcode fails the same way, the macros agent found;
the examples that passed before 2026-11-03 were installed without it), `expo prebuild --platform
ios --no-install` for an Expo app without an `ios` folder, `pod install`
(CocoaPods 1.16.2 under rbenv's Ruby 3.0.0, Node 24.22.1: expo_experiments.py's pins), then the
Linux builds (glibc, arm64 and x64) of every npm platform package the Mac's install left out,
from the registry with their integrity checked (`linux_packages`: one rule for every package
manager, where expo_experiments.py's reads `package-lock.json`). `script_phase_survey.py` counts
the macOS-only commands and BSD flags of the app's script phases. In a container without network
(`nomac-sweep-run`, the `nomac-sweep` volume; the app at its Mac path, the Linux Node at the Mac
Node's path): `nomac check --json`, the project's changes for Linux (each setting that names a
Mach-O tool overridden on the command line with the Linux build of the same tool, the one `nomac
check` lists or else the nearest ELF executable of that name in the checkout; ADR 0182's platform
check of expo-modules-autolinking), the build: `nomac archive` Release (ad hoc) continuing after
errors (until 2026-11-03, `nomac build` and then `nomac archive` from a new build folder: twice the
Linux time, and every archive passed whose build had, 11 of 11; `--separate-build`), then `nomac
export` (`debugging`). Each failed step's failed tasks are classified
from the log (`classify`): the task in xcodebuild's failure summary and its errors, the errors that
name its input when its own output has none (actool's messages print under the catalog's other
task), and for a script phase the errors left in tasks that succeeded (nomac streams a script's
output as it runs, between other tasks' output). Classes starting `app:` fail with Xcode too (a
JavaScript import of a package the app does not install). Up to 3 apps install on the Mac
(`--installers`; one `pod install` at a time, CocoaPods' cache being shared) while up to 3 build on
Linux (`--builders`, each with a NOMAC_HOME of its own; one at a time while Docker's disk was small):
an install waits on the network for minutes to an hour, a build takes 2 to 7 minutes; each app's Mac copy is deleted once copied into the container, the
container's copy and build folders after its run, the logs gzipped; results stay in
`~/nomac-out/sweep/results` (`reclassify` reads the kept logs again). The Mac copy of an app goes as
soon as it is in the container; the container's copy of an app that fails after its install stays
6 hours (`--keep-failed`) at its Mac path in `nomac-sweep-run`, for other agents to look at (sooner
gone when the Mac has less than 30 GB free: Docker's disk is on the Mac's, and 15 kept checkouts
took 22 GB on 2026-11-03); its result names it. Installs wait for 30 GB free on
the Mac (installed apps waiting for a build slot would otherwise take the builds' margin); builds start only with 25 GB free on the Mac, whose disk holds Docker's, and 15 GB in the
volume (agent-common.md, after the VM filled up on 2026-11-02 and the Mac on 2026-11-03); each build's
NOMAC_HOME goes with its derived data (4.7 GB a slot after 20 apps, mostly macro plugins).

The container has no network, so what a build would download is provided: the Linux Node, and
the SwiftPM cache's swift-syntax repository (copied from the Mac's), which `nomac build` fetches to
build Expo's macro plugin from the package beside it (ADR 0151). nomac takes the developer
directory from `NOMAC_DEVELOPER_DIR`.

## Round 2 (partial, 2026-11-03)

The 46 apps that passed every step on main `a9b571ab` kept that result; the others ran on the gate's
build of main `ad202e5b`. Each row names the nomac build that produced it.

61 of 106 apps finished, 49 build, archive and export on Linux (80% of the finished); results by nomac build: a9b571ab 47, ad202e5b 14.

| step | reached | passed |
|---|---|---|
| install | 61 | 60 |
| check | 60 | 60 |
| fixes | 60 | 60 |
| build | 60 | 49 |
| archive | 49 | 49 |
| export | 49 | 49 |

| app | nomac | React Native, Expo | result |
|---|---|---|---|
| expo-blank | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-stickersmash | a9b571ab | 0.88.0-rc.1, 58.0.21 | passes (export: 13 MB IPA) |
| expo-with-apollo | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-app-integrity | a9b571ab | 0.86.0, 57.0.31 | passes (export: 9 MB IPA) |
| expo-with-auth0 | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-aws-storage-upload | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-better-auth | a9b571ab | 0.86.0, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-camera | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-clerk | ad202e5b | 0.86.3, 57.0.31 | build: app: a package for another Expo SDK (expo-crypto@58.0.7, the app's Expo is 57.0.31) |
| expo-with-convex | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-custom-font | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-drawer-navigation | a9b571ab | 0.86.0, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-e2e | a9b571ab | 0.88.1, 58.0.21 | passes (export: 11 MB IPA) |
| expo-with-facebook-auth | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-firebase-saml-login | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-firebase-storage-upload | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-formdata-image-upload | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-github-remote-build-cache-provider | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-google-vision | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-graphql | a9b571ab | 0.86.0, 57.0.31 | passes (export: 9 MB IPA) |
| expo-with-html | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-icons | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-legend-state-supabase | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-libsql | a9b571ab | 0.86.0, 57.0.31 | passes (export: 10 MB IPA) |
| expo-with-maestro | a9b571ab | 0.86.3, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-magic | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-maps | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-moti | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-nextjs | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-openai | a9b571ab | 0.86.0, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-pdf | ad202e5b | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-processing | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-react-compiler | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-react-flow | a9b571ab | 0.86.0, 57.0.31 | passes (export: 9 MB IPA) |
| expo-with-react-navigation | a9b571ab | 0.86.0, 57.0.31 | passes (export: 10 MB IPA) |
| expo-with-react-router | a9b571ab | 0.86.0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-react-strict-dom | a9b571ab | 0.86.0, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-react-three-fiber | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-reanimated | a9b571ab | 0.86.0, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-router | a9b571ab | 0.86.0, 57.0.31 | passes (export: 9 MB IPA) |
| expo-with-router-ai | a9b571ab | 0.86.0, 57.0.31 | passes (export: 9 MB IPA) |
| expo-with-router-menus | ad202e5b | 0.86.3, 57.0.31 | build: compile error: cannot find type <q> in scope |
| expo-with-router-tv | ad202e5b | 0.86.3-0, 57.0.31 | build: nomac refuses: nomac does not compile a constraint with an item that is not the view, its safe area or one of its subviews yet (BACKLOG B-265) |
| expo-with-router-uniwind | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-rsc | a9b571ab | 0.86.3, 57.0.31 | install: (expo-fix) npm error code ERESOLVE / npm error ERESOLVE unable to resolve dependency tree / npm error |
| expo-with-s3 | ad202e5b | 0.86.3, 57.0.31 | build: app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) |
| expo-with-satori | a9b571ab | 0.86.3, 57.0.31 | passes (export: 11 MB IPA) |
| expo-with-sentry | ad202e5b | 0.86.3, 57.0.31 | build: a tool's Linux build lacks a subcommand (sentry-cli xcode) |
| expo-with-skia | a9b571ab | 0.86.3, 57.0.31 | passes (export: 13 MB IPA) |
| expo-with-socket-io | a9b571ab | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-splash-screen | ad202e5b | 0.86.3, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-sqlite | a9b571ab | 0.86.3, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-storybook | ad202e5b | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-styled-components | a9b571ab | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-three | a9b571ab | 0.86.3, 57.0.31 | passes (export: 8 MB IPA) |
| expo-with-tv | a9b571ab | 0.86.3-0, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-typescript | a9b571ab | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-victory-native | a9b571ab | 0.86.3, 57.0.31 | passes (export: 7 MB IPA) |
| expo-with-webbrowser-redirect | a9b571ab | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |
| expo-with-webgpu | a9b571ab | 0.86.3, 57.0.31 | passes (export: 11 MB IPA) |
| expo-with-zustand | a9b571ab | 0.86.3, 57.0.31 | passes (export: 6 MB IPA) |

| first failure | step | apps |
|---|---|---|
| app: a module the JavaScript imports is not installed (Metro; fails with Xcode too) | build | 7: expo-with-camera, expo-with-convex, expo-with-facebook-auth, expo-with-html, expo-with-legend-state-supabase, expo-with-router-uniwind, expo-with-s3 |
| app: a package for another Expo SDK (expo-crypto@58.0.7, the app's Expo is 57.0.31) | build | 1: expo-with-clerk |
| compile error: cannot find type <q> in scope | build | 1: expo-with-router-menus |
| nomac refuses: nomac does not compile a constraint with an item that is not the view, its safe area or one of its subviews yet (BACKLOG B-265) | build | 1: expo-with-router-tv |
| install (expo-fix) | install | 1: expo-with-rsc |
| a tool's Linux build lacks a subcommand (sentry-cli xcode) | build | 1: expo-with-sentry |

Not finished (45): expo-with-shadcn, expo-with-stripe, expo-with-svg, expo-with-tailwindcss, expo-with-tfjs-camera, expo-with-tinybase, expo-with-video-background, expo-with-webrtc, expo-with-widgets, expo-with-workbox, expo-with-yarn-workspaces, bluesky, bluewallet, rocketchat, inaturalist, zeus, expensify, rainbow, jitsi-meet, standard-notes, joplin, notesnook, ignite, tooot, chainreact-2023, graysky, showtime, podverse, metamask, eigen, memmy, olas, obytes-template, zulip-mobile, skia-example, reanimated-example, vision-camera-example, maps-example, webview-example, stripe-example, mmkv-example, lottie-example, video-example, screens-example, gesture-handler-example.

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
#   nomac-build's /ref/llvm-tools may be ahead of main). The developer directory's launchers (xcodebuild,
#   ditto, ...) name the binary's real path at install: install from its final folder and never move it
#   (a moved binary fails every nested xcodebuild: "line 5: <old path>/nomac: No such file or directory")
python3 .github/scripts/rn_sweep.py container           # the run container, without network
python3 .github/scripts/rn_sweep.py run [app ...]       # Mac: every step, app by app
python3 .github/scripts/rn_sweep.py report              # the tables below
```

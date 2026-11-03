# React Native and Expo projects: CocoaPods, script phases, C++ interop (state)

Test cases for the general build: a React Native app can contain any custom iOS code, so these
projects exercise CocoaPods' generated projects and scripts, Node and other tools that script
phases run, nested `xcodebuild`, xcframeworks, Objective-C++ and C++ interoperability, static
libraries and resource bundles. Expo is a test app, not a milestone: progress is measured by the
general lines of the README and docs/STATE.md. No React Native or Expo code goes into nomac; every
fix is a general rule of Xcode, Swift Build, CocoaPods' projects, clang, xcframeworks or script
phases, found by experiment and applied to any project. Branch `build/expo`. BACKLOG B-180–B-199,
ADRs 0180–0199.

## Current step

Demo (docs/DEMO.md, 2026-11-03): a fresh bare React Native 0.88.1 app and a fresh Expo SDK 58
app, pods installed on Linux, built, archived and exported by nomac in a clean Ubuntu 24.04
container, then development-signed, installed and launched on the iPhone from it; both kept
running. Fixed on the way: `xcrun`'s clang target off macOS and macOS's SDK in the default install,
macOS's `command` beside the launchers, `nomac doctor`'s PATH check. Left to Expo: its autolinking's
darwin-only module scan (one line, ADR 0182).

Milestone: rn-bare and expo-default, Debug and Release, built on Linux, archived and exported to
an IPA, and compared with Xcode 27.0's references. Remeasured on main `27646070` in an offline
container with a developer directory installed from the subset with the published LLVM tools,
the patched clang among them (`verify --project-fixes`, ADR 0182): all four builds succeed, and
both apps archive and export in both configurations. Xcode clang's constant Objective-C literals
(B-170) no longer differ: rn-bare Release has no different file left. expo-default's Release
archive had four prebuilt frameworks' dSYMs with `<UUID>.plist` source maps that Xcode's lacks:
`nomac verify --build` archived in the checkout as its build left it, where the build's
`[Expo] Switch <pod> XCFramework` phases had already put the release copies in `Pods`, while the
capture restores the checkout after the build, so Xcode's archive switched from the debug copies
and dropped the maps its `[Expo] Resolve <pod> dSYM source maps` phases had just written. `nomac
verify --build` now restores the checkout as the capture does (docs/VERIFICATION.md "Build
products": 13783 paths checked out, 13639 of them ReactNativeDependencies' xcframework, and 332
removed), and the four dSYMs are identical. A device-signed rn-bare IPA was
built, archived, signed and exported by nomac in Linux containers.

| App, configuration (Linux) | build | products: identical / equivalent / different | archive, IPA (nomac's vs Xcode's) | signing, export of Xcode's archive | what the rest waits on |
|---|---|---|---|---|---|
| rn-bare Release | succeeds | 5 / 7 / 0 of 12 | archive 2/4 (2 equivalent), IPA 3/4 (1 equivalent) | 1/1, 1/1 | nothing |
| rn-bare Debug | succeeds | 5 / 6 / 1 of 12 | archive 2/4 (1 equivalent), IPA 3/4: `__preview.dylib` and `ip.txt` | 1/1, 1/1 | `__preview.dylib`'s `__TEXT,__text` (build driver) |
| expo-default Release | succeeds | 5 / 26 / 4 of 35 | archive 7/10 (1 equivalent), IPA 3/4: the executable and its dSYM | 1/1, 1/1 | the clang workstream (Needs from other workstreams); ExpoModulesJSI's module interface |
| expo-default Debug | succeeds | 4 / 26 / 4 of 34 | archive 7/10 (2 equivalent), IPA 3/4: the executable's `NSUserActivity` import, `ip.txt` | 1/1, 1/1 | the same; `__preview.dylib` |

The RN sweep's failure classes (`rn_sweep.py` reports): `file`, which CocoaPods' frameworks script
asks about each framework binary and dSYM (11 of 11 apps), is `nomac file` behind a launcher in the
developer directory's `usr/bin` (`file_experiments.py`: 19 of 19 cases like macOS's).
`embeddedBinaryValidationUtility`, which Swift Build runs for each extension and app an app embeds
(expo-with-widgets, zeus), is `nomac embeddedBinaryValidationUtility`, launcher where Xcode keeps it
(`embedded_binary_validation_experiments.py`: 38 of 38 cases like Xcode's). Bugsnag's `md5 -qs`
(bluewallet, rocketchat) is `nomac md5` (`md5_experiments.py`: 20 of 20); its Ruby dSYM phase
(`shellPath = "/usr/bin/env ruby"`) is `nomac check`'s `build:script-interpreter=ruby`, and React
Native's old Start Packager phase's `nc` (zeus) `build:script-command=nc`, beside `open`, which it
already reported: machine prerequisites, not products. Sentry's `sentry-xcode.sh` (expo-with-sentry)
runs `sentry-cli react-native xcode`, which sentry-cli's Linux build lacks and which runs the
bundling itself: `nomac check`'s `build:script=sentry-cli-react-native-xcode` says to build with
`SENTRY_DISABLE_AUTO_UPLOAD=true`. bluewallet's sticker pack (`lipo` given no `-extract`: Swift Build
read no architectures from the stub) is Swift Build's seventh patch, on main since b74cc592, after
the sweep's nomac (b225fc0c).

## The apps

`.github/scripts/expo_experiments.py generate` writes them under `~/nomac-out/wt-scratch/expo/apps`
(outside the repository), each committed into its own git repository at a fixed date, so that
`capture` and `verify` reset the checkout before every build (script phases rewrite `Pods/`):

| App | Generated by | Container, scheme | Commit |
|---|---|---|---|
| expo-default | `create-expo-app@5.0.0 --template expo-template-default@58.0.28` (Expo SDK 58, React Native 0.88.0), `expo prebuild --platform ios --no-install`, `pod install` | `ios/ExpoDefault.xcworkspace`, `ExpoDefault` | `b40e323` |
| rn-bare | `@react-native-community/cli@20.2.0 init --version 0.88.0`, `pod install` | `ios/RNBare.xcworkspace`, `RNBare` | `70af78a` |

Pins (the script's `PINS`): Node 24.22.1 (nodejs.org tarball, SHA-256 checked, in `<root>/node`:
the Mac's Node 24.0.0 is below Expo SDK 58's and React Native 0.88's `^24.3.0`), npm resolution as
of 2026-10-24 (`npm_config_before`), CocoaPods 1.16.2 with xcodeproj 1.27.0 under rbenv's Ruby
3.0.0 (React Native's Gemfile asks xcodeproj < 1.26.0, which CocoaPods 1.16 cannot use; Bundler
would pick CocoaPods 1.15.2). Each app's record (`apps/<id>.json`) has the tools' versions, the
hashes of `package-lock.json` and `Podfile.lock`, and the `engines` and Gemfile lines the
generated packages declare. `expo prebuild` derives a bundle identifier from the machine's
accounts when `app.json` has none; the script sets `dev.nomac.ExpoDefault`.

What they exercise: CocoaPods workspaces (expo-default's Pods project has 33 targets) with user
schemes, `[CP]` and `[CP-User]` script phases run with Node (`.xcode.env.local` names
`<root>/node/bin/node`, written by `pod install`), prebuilt xcframeworks swapped per
configuration by script phases (React Native core, its dependencies, Hermes, five Expo modules;
both configurations' tarballs are cached in `Pods/`, so builds need no network), 440 C, ObjC and
ObjC++ compiles and 41 Swift compiles (expo-default Release), static libraries, privacy bundles,
the JS bundle and Hermes bytecode (Release; Expo's Debug skips bundling), an Icon Composer app icon.

## Xcode's references

`expo_experiments.py capture` (DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer) writes
`capture_reference.py`'s layout to `refs/<configuration>/<id>`: PIF, `-list` and every settings
capture (746 for expo-default) once per app, the build per configuration, for
`generic/platform=iOS` without signing. Every xcodebuild runs offline under `sandbox-exec`,
except expo-default's builds: its `[CP-User] Build ExpoModulesJSI xcframework` phase runs
`xcodebuild` on a Swift package, whose manifest sandbox cannot be applied inside another sandbox
(`sandbox_apply: Operation not permitted`; nesting works only with an identical profile). Those
builds run without `sandbox-exec`, and lsof samples every socket the build's processes open
(`build/network.log`): Release's JS bundling (`node`, Expo's CLI) opened HTTPS connections to a
Cloudflare address; Debug opened none. Nothing reached Apple.

All four builds succeed with Xcode.

## Results

Products are the entries of `Build/Products/<configuration>-iphoneos` (`nomac verify --build`).

| Run | pif | list | settings | products: identical / equivalent / different / refused |
|---|---|---|---|---|
| expo-default Release, Mac (Xcode's tools) | 1/1 | 1/1 | 746/746 | 17 / 17 / 1 / 0 of 35 |
| expo-default Debug, Mac | 1/1 | 1/1 | 746/746 | 16 / 17 / 1 / 0 of 34 |
| rn-bare Release, Mac | 1/1 | 1/1 | 548/548 | 9 / 3 / 0 / 0 of 12 |
| rn-bare Debug, Mac | 1/1 | 1/1 | 548/548 | 9 / 3 / 0 / 0 of 12 |
| expo-default Release, Linux, milestone 1 | 1/1 | 1/1 | 746/746 | 0 / 0 / 35 / 0 of 35 |
| expo-default Debug, Linux, milestone 1 | 1/1 | 1/1 | 746/746 | 0 / 0 / 34 / 0 of 34 |
| rn-bare Release and Debug, Linux, milestone 1 | 1/1 | 1/1 | 548/548 | 1 / 0 / 11 / 0 of 12 |
| expo-default Release and Debug, Linux, milestone 2 | 1/1 | 1/1 | 746/746 | 0 / 3 / 32 / 0 and 0 / 3 / 31 / 0 |
| expo-default Release, Linux, after B-185 | 1/1 | 1/1 | 746/746 | 0 / 15 / 20 / 0 of 35 |
| rn-bare Release and Debug, Linux, milestone 2 | 1/1 | 1/1 | 548/548 | 2 / 3 / 7 / 0 of 12 |
| expo-default Release and Debug, Linux, `--project-fixes` | 1/1 | 1/1 | 746/746 | 1 / 16 / 18 / 0 of 35 and 0 / 16 / 18 / 0 of 34 |
| rn-bare Release and Debug, Linux, `--project-fixes` | 1/1 | 1/1 | 548/548 | 2 / 3 / 7 / 0 of 12 |
| expo-default Release and Debug, Linux, `--project-fixes`, main `a772610` | 1/1 | 1/1 | 746/746 | 1 / 16 / 18 / 0 of 35 and 0 / 17 / 17 / 0 of 34 |
| rn-bare Release and Debug, Linux, `--project-fixes`, main `a772610` | 1/1 | 1/1 | 548/548 | 3 / 3 / 6 / 0 and 2 / 3 / 7 / 0 of 12 |
| expo-default Release and Debug, Linux, `--project-fixes`, main `27646070`, patched clang | 1/1 | 1/1 | 746/746 | 5 / 26 / 4 / 0 of 35 and 4 / 26 / 4 / 0 of 34 |
| rn-bare Release and Debug, Linux, `--project-fixes`, main `27646070`, patched clang | 1/1 | 1/1 | 548/548 | 5 / 7 / 0 / 0 and 5 / 6 / 1 / 0 of 12 |

On the Mac the one different product is expo-default's app, for its `Assets.car` (and, in Debug,
`ip.txt`), both outputs that Xcode itself does not reproduce (classes below). On Linux (Docker,
`--network none`, the build workstream's installed developer directory) the loader is identical
and the builds stop early: `expo_experiments.py triage <build log>` groups their errors. Since
milestone 2 the Linux runs use a developer directory of this branch in the `nomac-expo` volume
(Reproduce).

## Classes of differences

| Class | Where | Cause | Owner | State |
|---|---|---|---|---|
| Static libraries compared byte for byte | Mac: 15 of expo-default's `lib*.a` | their Swift members differ only by Xcode's driver's stack checks (`___chkstk_darwin`, ADR 0101); `nomac verify` had no rule for `ar` archives | this workstream (`BuildProducts`, the build driver's module) | fixed: members compared one by one (docs/VERIFICATION.md) |
| `LC_LINKER_OPTIMIZATION_HINT` only in Xcode's objects | Mac: expo-default's Debug Swift members | every hint was a stack check's `adrp`/`ldr` (2 of 2 and 20 of 20 addresses) | this workstream | fixed: documented when `___chkstk_darwin` is missing too |
| `_objc_retain_x<N>`/`_objc_release_x<N>` for other registers | Mac: expo-default's Release Swift members | register allocation, which the stack checks move (ADR 0101) | this workstream | fixed: documented |
| `Assets.car` with an Icon Composer icon | Mac: `ExpoDefault.app/Assets.car` | Xcode 27.0's `actool` is not deterministic for a catalog with an `.icon`: two runs of the same command differ in 352 bytes (same size); without the `.icon` the outputs are identical. Three things vary: the appearance-key order, the rendered images' names and the icon facet's part | resources (asset catalogs) | fixed: `nomac verify` puts them aside (ADR 0203); `nomac actool` compiles the icon, its `Assets.car` and icon PNGs equivalent to Xcode's (rendered pixels, ADR 0204) |
| Scripts run by path from script phases start `#!/bin/sh` | Linux: 10 CocoaPods scripts in rn-bare (`*-xcframeworks.sh`, `*-frameworks.sh`, `*-resources.sh`), so no xcframework is copied and every `React/…` header is missing | ADR 0103 points only the phase's own script at nomac's shell; the kernel runs the scripts it calls with the machine's `/bin/sh`, dash (`set: Illegal option -o pipefail`) | this workstream | fixed: ADR 0180 (nested scripts like macOS's in 19 of 20 constructs, dash 4) |
| `ditto` | Linux: 96 calls in expo-default (CocoaPods' "Copy generated compatibility header" phases), so `module X.Swift` is appended to module maps never copied ("parent module must be defined", "redefinition of module 'Swift'") | a macOS command scripts call from PATH | this workstream | fixed: `nomac ditto` (7 of 7 cases like macOS's ditto) |
| `libtool` | Linux: every static library target (Swift Build's `libtool -V` probe fails: 26 in expo-default) | Xcode's `libtool` is `cctools_ld-27037.1`, not open source; the toolchain has none | this workstream | fixed: cctools-port's, patched (ADR 0181): 19 of 19 archives byte-identical to Xcode's |
| `xcodebuild` from a script phase | Linux: expo-default's `[CP-User] Build ExpoModulesJSI xcframework` | Expo SDK 58 builds a Swift package with `xcodebuild` (with `env -i`, in the package's folder) during the app's build | this workstream | Mac: nomac's nested build matches Xcode's; Linux: runs, then B-185. A package folder is a container, `nomac build` takes the call's options, `nomac xcodebuild` behind a launcher; the toolchain's `usr/include/swift/bridging`, which Xcode's compilers search and swift.org's do not (B-181) |
| `hermesc` for macOS | Linux: Release bundling (`HERMES_CLI_PATH` is `…/hermes-compiler/hermesc/osx-bin/hermesc`, set in CocoaPods' xcconfig) | a Mach-O tool shipped in `node_modules`; the same package's `linux64-bin/hermesc` (x86_64, release string `1.0.0`) writes the macOS one's bytecode byte for byte given the same input path (the 40-byte difference noted before was the input's path, which the bytecode records) | the project | `nomac check` reports it (`build:setting=mach-o-executable`, with the override to pass); React Native's phases source `ios/.xcode.env.local` after the build settings, so the project can name the Linux `hermesc` there (`--project-fixes`; x86_64, so an arm64 Linux needs user-mode emulation, as Docker Desktop's): expo-default's `main.jsbundle` identical on Linux |
| `[Expo] Configure project`'s module scan | Linux: expo-default ("Scanning for @ExpoModule classes didn't complete", exit 1) | expo-modules-autolinking skips the scan when Node's `process.platform` is not `darwin`, although expo-modules-macros installs its scanner for Linux; the provider it writes is the same either way (22 classes from `expo-module.config.json`) | the project (ADR 0182) | `--project-fixes` lets the check accept `linux`: `ExpoModulesProvider.swift` identical to the Mac's |
| Expo's Swift macro plugin | Linux: every Expo pod's compile that expands `@ExpoModule`, `@JS`, … (`-load-plugin-executable <node_modules>/expo-modules-macros/apple/ExpoModulesMacros#ExpoModulesMacros`, a macOS executable; the RN holdout's expo-modules app) | the project names a prebuilt plugin, whose Swift package ships beside it (`apple/Package.swift`, a `.macro` target); its build from those sources expands as the macOS binary does, and so does the Linux build Expo publishes as npm platform packages (`expo_experiments.py macros`) | macros (ADR 0151) | `nomac build` off macOS builds the plugin from the package and loads that build first; `nomac check` lists it as `build:macro-plugin=swift-package` |
| App Intents tool on static libraries | Linux: `libExpoLogBox.a: not a thin 64-bit … Mach-O file` | Swift Build runs `appintentsmetadataprocessor --binary-file <lib>.a` for static library targets; Xcode's writes the empty strings data for expo-default's 17 | this workstream | fixed: an archive's objects are read (their `LC_LINKER_OPTION`s) |
| C++ template arguments that point into objects | Linux: `libreact-native-safe-area-context.a`, `libReactCodegen.a` (ranlib tables named other symbols) | Xcode's clang follows Clang 4's C++ ABI unasked; nomac's toolchain asks swift.org's clang and Swift's importer for it (docs/formats/build.md "Clang's C++ ABI"); the libraries' Objective-C literals and `respondsToSelector:` still differ | clang workstream | B-170 |
| Debug dylibs | Linux: rn-bare Debug (`Unable to process debug dylib: … SWBUtil.BinaryReaderError error 1`) | Debug apps link `<App>.debug.dylib` and a stub; Swift Build cannot read the debug dylib lld wrote | build driver | B-183 |
| C++ types under library evolution | Linux: ExpoModulesJSI (`expo.CppError` "from imported module '__ObjC'") | swift.org 6.4.0's compiler rejects a C++ type other than a C-like struct in a library-evolution module's public API; Xcode's accepts it | this workstream | fixed: `AssumeResilientCxxTypes` (docs/formats/build.md) |
| `strip` | Linux: the nested framework (`/usr/bin/strip: file format not recognized`) | no Mach-O strip in the toolchain; Swift Build ran GNU strip | this workstream | fixed: cctools-port's (ADR 0181): 13 of 14 like Xcode's |
| Constant Objective-C literals | Linux: expo-default's and rn-bare's app binaries (`__DATA_CONST,__objc_arrayobj`, `__objc_dictobj`, `__objc_intobj`, `__objc_arraydata` and `_OBJC_CLASS_$_NSConstantArray` imports only in Xcode's) | Xcode 27.0's clang compiles `@[...]`, `@{...}` and number literals into constant objects by default (a self-written `.m`, `-Os`); swift.org's clang has no such option | clang workstream | B-170 |
| Binary property lists | Linux: `Expo.plist`, `PrivacyInfo.xcprivacy`, every privacy bundle's `Info.plist` | the same content, other bytes: key order and string uniquing of Swift Build's writer off Darwin | build driver | known (B-105) |
| swift.org clang's code generation | Linux: static libraries of Objective-C and C++ pods | selector loads instead of stubs, plain ARC entry points, `objc_msgSend` instead of the runtime's `objc_opt_*`, other empty-collection constant names, sized `delete`, private metadata caches in ranlib tables | this workstream | documented (docs/VERIFICATION.md), `delete` aligned with `-fno-sized-deallocation` |
| Storyboards | Linux: rn-bare's `LaunchScreen.storyboard` ("nomac does not compile nibs for --minimum-deployment-target … yet") | `nomac ibtool` | resources (nibs) | fixed: every iOS release's deployment target, labels without color elements, `true`/`false`, `symbolic`, `1/3` multipliers; rn-bare's and expo-default's launch storyboards compile and link identical to Xcode's, Debug and Release |
| `.strings` copies | Linux | Swift Build's copy off Darwin (B-124, patch 0003 waits on the owner) | build driver | known |
| `ip.txt` names the build machine's address | expo-default Debug (rn-bare's too) | React Native's `react-native-xcode.sh` writes `ipconfig getifaddr en0` (else `ifconfig`'s first address) into Debug apps for the packager; the Mac's network changed between the two builds; Linux has neither command | none (the machine's state) | recorded |
| dSYM source maps of prebuilt xcframeworks | Linux: expo-default's Release archive (`dSYMs/ExpoFileSystem.framework.dSYM`, ExpoFont, ExpoModulesCore, ExpoModulesWorklets: `<UUID>.plist` only in nomac's) | the capture restores the checkout after the build, `nomac verify --build` archived in the checkout as the build left it, with the release copies the build's `[Expo] Switch <pod> XCFramework` phases put in `Pods`: Xcode's archive switches from the debug copies after its `[Expo] Resolve <pod> dSYM source maps` phases have written the maps into them (the order in both archive logs) | this workstream | fixed: `nomac verify --build` restores the checkout as the capture does; the four dSYMs identical on Linux |

## Needs from other workstreams

- Clang workstream, expo-default's remaining differences on Linux with the patched clang: the
  executable imports `_OBJC_CLASS_$_NSUserActivity` from CoreServices where Xcode's binds it to
  Foundation (Release and Debug); `rnscreens::conversion::RNSUIBlurEffectFromOptionalUIBlurEffectStyle`
  exported only by Xcode's executable (Release); `_swift_release_n` imported only by nomac's
  `libExpoUI.a(SectionView.o)` (Release); `___chkstk_darwin` and `LC_LINKER_OPTIMIZATION_HINT`
  only in nomac's `libRNReanimated.a(InterpolatorRegistry.o)` and `__TEXT,__const` only in nomac's
  `libRNWorklets.a(WorkletsURLSessionDelegate.o)` (Debug).
- Build driver: `__preview.dylib` without `__TEXT,__text` (rn-bare's and expo-default's Debug).
- Build driver: `xcrun` for script phases (on main since `510fdc9`); B-124 (`.strings` off Darwin).
- Resources (asset catalogs): done on the Mac: `nomac actool` compiles expo-default's icon, its
  `Assets.car` and icon PNGs equivalent to Xcode's build products (ADRs 0203, 0204).

## Reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
S=.github/scripts/expo_experiments.py
python3 $S generate                      # online: npm and CocoaPods
python3 $S capture                       # Xcode's references, Release and Debug
python3 $S capture --archive             # Xcode's ad-hoc archives and `debugging` exports, into each reference
python3 $S verify --nomac .build/debug/nomac   # reports and nomac's derived data next to each reference
python3 $S verify --nomac <nomac> --project-fixes   # on Linux: the projects' changes for Linux first (ADR 0182)
python3 $S triage <build log>            # errors grouped by task and message
```

On Linux: the `nomac-expo` volume holds nomac's sources and build (`/work/src`, `/work/build`),
cctools-port's tools (`/work/cctools`, `build-cctools.sh`), a developer directory installed by
this branch's nomac (`/work/devdir`, whose launchers run `/work/build/…/nomac`) and, under
`expo/`, clones of the apps at the Mac's paths, the Linux Node and links to the references. The
build workstream's `nomac-build` volume is read-only: the SDK subset, the swift.org toolchain and
lld. `~/nomac-out/wt-scratch/expo/linux/verify.sh` (outside the repository) sets up `expo/` and
runs `verify` in a container without network:

```sh
docker run --rm -v nomac-expo:/work -w /work/src nomac-build:6.4.1-noble-ld64 \
  bash .github/scripts/build-cctools.sh /work/cctools          # online: downloads cctools-port
docker exec nomac-expo sh -c 'mkdir -p /work/llvm-tools /work/devdir \
  && cp /ref/lld-recipe/lld /ref/lld-recipe/dsymutil /work/llvm-tools/ \
  && cp -r /work/cctools/ld64 /work/cctools/bitcode_strip /work/cctools/libtool /work/cctools/ld64-licenses /work/llvm-tools/ \
  && cp -a /ref/xcode/Xcode_27.app /work/devdir/ \
  && /work/build/debug/nomac toolchain install /ref/toolchains/swift-6.4.0-RELEASE-ubuntu24.04-aarch64/usr \
       --llvm-tools /work/llvm-tools --developer-dir /work/devdir/Xcode_27.app/Contents/Developer'
docker run -d --name nomac-expo-verify --network none -v nomac-expo:/work \
  --mount type=volume,src=nomac-expo,dst=/Applications/Xcode_27.app,volume-subpath=devdir/Xcode_27.app,readonly \
  --mount type=volume,src=nomac-expo,dst="$HOME/nomac-out/wt-scratch/expo",volume-subpath=expo \
  -v ~/nomac-out/wt-scratch/expo/apps:/mac-apps:ro -v ~/nomac-out/wt-scratch/expo/refs:/mac-refs:ro \
  -v ~/nomac-out/wt-scratch/expo/linux:/linux:ro nomac-linux:6.4.1-noble sleep infinity
docker exec nomac-expo-verify bash /linux/verify.sh [app ...] [--configuration C]
```

(`nomac-expo` is the container that builds nomac, with `nomac-build` mounted at `/ref`.) A
reinstalled developer directory is a new folder: start the verify container again, or it sees an
empty `/Applications/Xcode_27.app` ("could not initialize the developer directory").

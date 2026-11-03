# Build driver: state

Workstream: Swift Build builds on Linux (Swift, ObjC, C, C++; SwiftPM, CocoaPods, xcframeworks).
Branch `build/driver`. BACKLOG B-100–B-199, ADRs 0100–0199.

## Current step

Milestone 3: corpus and Expo apps built fully on Linux. Swift Build comes from the owner's fork
(`d1842806`, nine upstream patches). lld has seventeen patches, the clang workstream's 0009
among them, and `nomac toolchain install` refuses LLVM tools built with other patches. Next: the
Linux-corpus reports' build-driver classes (icecubes next); ExpoModulesJSI's Swift
interface; rn-bare Debug's `__preview.dylib`.

## Just finished

- llbuild from the owner's fork (`b0afd154`, B-137 done): `.github/upstream/swift-llbuild/0001`
  applied, the root dependency replacing Swift Build's and SwiftPM's (ADR 0002).
- Swift stack checks, step 1 (B-100): `swift_stack_experiments.py` records when Xcode's driver
  adds `-stack-check` (and `-disable-clang-spi`), the attribute it gives every function, and the
  probe calls; swift.org's LLVM rejects the attribute, the clang workstream's patched LLVM gives
  Xcode's calls.
- Swift stack checks (B-100, done): the swift-driver fork passes `-stack-check` and
  `-disable-clang-spi` as Xcode's driver does; `.github/swift` 0001 and `build-swift-frontend.sh`
  build swift.org's frontend with `-stack-check` against the clang workstream's LLVM (ADR 0106),
  and `nomac toolchain install` installs it with its scanner. Linux: retro-rampage Engine's 31
  objects call the probe as Xcode's (7 calls).
- The pin at the fork's `d1842806` (patches 0008 and 0009): binary targets' build files with platform
  filters (kickstarter, pocket-casts), static archives off Darwin (kickstarter's static xcframeworks).
- SwiftPM in script phases off macOS (home-assistant's `build_tool`): the toolchain's SwiftPM
  commands run the swift.org toolchain's (`script_swiftpm_experiments.py`: Xcode's output).
- `tapi stubify` writes Objective-C ivars (`objc_ivar`, mastodon's MastodonSDKDynamic) and
  exception types (`objc_eh_type`) as Xcode's `tapi` (`tapi_experiments.py`).
- B-009 off macOS: Xcode projects' build tool plugins link nomac's build of SwiftPM's
  `PackagePlugin` (its entry point to `XcodeProjectPlugin` made callable off Darwin, kept as
  `.github/upstream/swift-package-manager/0001-…`) and nomac's `XcodeProjectPlugin`, both built by
  the plugins' compiler at first use (`NomacPluginAPI`, ADR 0105); `build_plugin_experiments.py`
  on Linux: every variant's status and outputs as Xcode's, the plugin's context but the tool's
  build-machine path.
- B-009, Xcode project targets on a Mac: the plugin is sent the project's representation, and its
  commands become the target's shell-script phases, as Xcode 27.0's (`build_plugin_experiments.py`
  project and project-quoting: context, scripts and outputs identical). Off macOS they are refused
  until nomac's `PackagePlugin` and `XcodeProjectPlugin` (ADR 0105).
- The pin at the fork's `aeb5ba2c` (patch 0007): Mach-O architectures named off Darwin, so
  sticker packs' stub executables copy on Linux as on a Mac.
- B-009, package targets: `nomac build` compiles and applies the build tool plugins of package
  targets as Xcode 27.0 does, on the Mac (compile command, context, outputs and the custom task
  identical, `build_plugin_experiments.py`) and on Linux, where the plugin and its tool are built
  for the build machine; a prebuild command of a tool built from source fails as Xcode's does.
- The build log: a task's own diagnostics (a framework Copy's "not stripping binary because it is
  signed") and output that comes without the task's signature (codesign's "replacing existing
  signature") print in the task's block after its command line, as xcodebuild's (the device
  workstream's report).
- `nomac check` reports a script phase that runs a Mach-O executable by its path
  (`build:script=mach-o-executable`): wikipedia's "Update Localizations" (B-134).
- Sticker packs on Linux (wikipedia's `Wikipedia Stickers.appex`): the SDK subset keeps the
  Messages stub executables, and with Swift Build's seventh patch the appex's executable is the
  stub's `arm64` slice, byte for byte Xcode's (`sticker_stub_experiments.py`).
- The pin at the fork's `10b9393e` (patch 0006): ProcessXCFramework leaves an xcframework's
  AppleDouble (`._*`) files out off Darwin as on a Mac (`xcframework_copy_experiments.py`;
  swiftfin's `include/._vlc`).
- The pin at the fork's `01811544` (patch 0005, `derq` through the tool search paths off Darwin)
  and a `derq` launcher in the toolchain's `usr/bin` (`nomac derq`): a device-signed
  `nomac archive --keychain --provisioning-profiles` of rn-bare Release on Linux (development
  identity, wildcard profile, bundle identifier overridden) succeeds, and Apple's `codesign -v
  --deep --strict` accepts its app, with the identity, the team, the profile's entitlements and
  their DER form.
- lld's thirteenth patch (ADR 0102 item 18): a re-exported dylib also loaded directly binds its
  own symbols, if the client may link it (client name from the install name, prefix of an
  allowable client): `libswift_Builtin_float`, and SwiftUICore for a debug dylib named "App"
  (the macros workstream). B-133 for an autolinked name no search path has.
- `nomac toolchain install` checks `lld.patches.sha256` and `cctools.patches.sha256`, which the
  build scripts now write: the expo workstream's empty package dSYMs came from an lld built
  before the seventh patch. Off macOS, `nomac build` creates the reference Mac's `TMPDIR`.
- lld's patches 10 to 12 (ADR 0102 items 15 to 17, `ld_experiments.py`'s `sections-*`,
  `dead-strip-classrefs`, `autolink-*` and `explicit-*` variants, 112 in all, every one with
  Xcode's libraries and sections but for the documented order): C-string sections kept apart with
  Xcode's merging and literals in `__const` (B-130, B-174); class references dead-stripped with
  their code, and no empty `__cstring` (the RN holdout's rn-native widget, `NSBundle`); libraries
  that only dead code used through `$ld$previous$` moves left out (rn-bare's executable and
  SwiftUI, the expo workstream's hand-off). They compose with the clang workstream's 0009.
- `usr/lib/swift/swiftToCxx` in the Linux toolchain (Nitro's C++ headers, the RN holdout's
  rn-libs); script phases under `ENABLE_USER_SCRIPT_SANDBOXING` run on Linux without enforcement
  (`DISABLE_TASK_SANDBOXING`, ADR 0103 addendum, B-132); SymLink tasks need no `ln`.
- Swift Build's fifth patch, `derq` through the tool search paths off Darwin: the fork's
  `01811544` (docs/upstream/swift-build.md section 5). Other hard-coded tools surveyed:
  `sandbox-exec` (handled above), `/bin/ln` (llbuild's built-in), `/usr/bin/what` (Core ML and
  Reality files' tool probes, resources), `/usr/bin/codesign` (nomac sets `CODESIGN`).
- The flaky Linux tests: the toolchain tests write their scripts through `FileSystem.write`, and
  the exec interposer's phases start again on "Text file busy".
- The pin at the fork's `5a4c08e1` (patch 0004, B-183): rn-bare Debug builds on Linux, 5/3/4 of
  12 as Release; expo-default builds in both configurations (Release 5/19/11 of 35, Debug 4/20/10
  of 34). `-Xcc -fno-sized-deallocation` for Swift compiles off macOS: ExpoModulesJSI's binary is
  no longer different (with lld's patches 5 to 7 its dSYM is equivalent); its `.swiftinterface`
  and `.abi.json` remain. B-130 recorded (lld's `__cstring`/`__literals` merges: rn-bare Debug's
  stub executor). The toolchain tests' scripts are written through `FileSystem.write` (ETXTBSY).
- The corpus on Linux with the fork pin (`scripts/corpus_linux.sh`, captures in `ref/capture`):
  retro-rampage passes (1 identical, 7 equivalent of 8); flappy-fly-bird too with main's lld
  patch 0008 (1/3/0 of 4; its weak `CGFloat` import was B-171); tofu and uncloudnotes stop on storyboards (B-260, B-261, B-265)
  and the `.omo` (B-256), the resources workstream's.
- The "silent" BUILD FAILED and ARCHIVE FAILED on Linux: nomac's log lost failed tasks that
  complete under another signature than they start with (now matched by task ID) and printed
  xcodebuild's failure summary only for a project by scheme (every form now, on standard error,
  `failure_experiments.py`, B-112). Named, rn-bare's failures were real: without the project
  fixes macOS's `hermesc` (Release), and B-183 (Debug); with them rn-bare Release builds on Linux
  (5/3/4 of 12, the 4 B-170's Objective-C code). Its archive then failed on `chown` to the
  reference Mac's user, BSD `chmod -RH` and CocoaPods' `/usr/bin/codesign`: the toolchain's
  `chown`/`chmod` scripts (`CHOWN`, `CHMOD`) and the exec interposer's macOS tool paths fix them,
  and rn-bare archives on Linux. The Linux image needs `file` (docs/VERIFICATION.md).
- B-187 and two more of Xcode's `ld` rules found on the way (ADR 0102 items 11 and 12,
  docs/formats/build.md "Chained fixups and thread-local pointers"): dyld's opcodes instead of
  chained fixups whenever a link has `-undefined dynamic_lookup` or `suppress`, initializer
  offsets kept there, and pointers to thread-local variables in `__got`. lld's patches 5 and 6;
  `ld_experiments.py` (83 variants) matches Xcode's `ld` but for flat-namespace ordinals (B-126)
  and the order of `__got` entries (B-127).
- B-128: lld's seventh patch carries relocatable inputs' stabs into the image's debug map, as
  Xcode's `ld` does (ADR 0102 item 13): `stabs-relocatable`'s debug map and dSYM DWARF are
  Xcode's. Package products' dSYMs on Linux were empty (expo-default's nested ExpoModulesJSI).
- cctools-port's `strip` signed what it stripped (it finds nomac's `codesign` on the tasks'
  `PATH`); `.github/cctools/0002-strip-without-signing.patch`: 18 of 19 `strip_experiments.py`
  outputs identical to Xcode's, 0 before (ADR 0181).
- B-186: off macOS an empty `CODE_SIGN_IDENTITY` signs nothing, as with Xcode
  (`signing_identity_experiments.py`); nomac no longer synthesizes the identity, and answers ad
  hoc for any non-empty one.
- B-183: Swift Build's patch 0004 is commit `5a4c08e1` on the fork's branch in
  `~/nomac-out/swift-build-fork`; with it, rn-bare Debug on Linux links its debug dylib and stub
  executor: 2/3/7 → 4/3/5 of 12, its one error the storyboard (B-263), as Release.
- Swift Build from the owner's fork (`khzouroussama/swift-build`, `release/6.4.2-linux-fixes`,
  `8d0577c4`: the pin with patches 0001 to 0003). B-005's `StatCachePath` is gone; B-005, B-105
  and B-124 are resolved. On Linux, against main's nomac: rn-bare Release 2/3/7 → 4/3/5 of 12
  products (identical/equivalent/different), expo-default Release 1/15/19 → 4/18/13 of 35: every
  privacy bundle's Info.plist is Xcode's; retro-rampage 34 → 39 of 61 files byte-identical (its 5
  Info.plists); swiftfin 2/41 → 7/61 of 138 and its 56 strings copies succeed. rn-bare Release's
  one build error is LaunchScreen's storyboard (resources, B-263). Neither Expo app has strings
  files. Suites: Mac 600 tests, Linux 603, no failures.
- `nomac xcrun` (docs/formats/build.md "xcrun", `.github/scripts/xcrun_experiments.py`): every
  observed answer of Xcode 27.0's xcrun, behind a launcher in the developer directory's `usr/bin`;
  off macOS the tools of macOS's SDK run for Linux (ADR 0103).
- lld's fourth patch: autolinked frameworks load before autolinked libraries, each by name, as
  Xcode's `ld` loads them, so a name two libraries move symbols to gets Xcode's versions
  (`ld_experiments.py`: 48 variants, all as Xcode's `ld`; flappy-fly-bird's `libswiftCoreGraphics`).
- Builds off macOS (`LinuxCompiler`): `-enable-cross-import-overlays`, which Xcode's compiler does
  unasked (B-154, `.github/scripts/cross_import_experiments.py`); Linux targets (macro packages)
  get a resource directory with swift.org's headers (`lib/nomac/swift`); `nomac verify --build`
  leaves out each side's products for its build machine.
- Linux host compiles import `NomacHostFoundation` (`HostFoundationModule`, built by
  `nomac toolchain install`), which loads Foundation as a Mac's swift-syntax does through OSLog,
  without importing its names (B-125, docs/formats/build.md): xctest-dynamic-overlay's
  `IssueReporting`, which importing Foundation itself broke, builds for Linux.
- swiftfin on Linux: PIF, list and 40 settings identical; strings files fail (B-124), and Icon
  Composer icons (B-210), symbol sets (B-202) and `Libmpv.xcframework`'s binary; the Docker VM's
  7.65 GB do not hold its build, which is killed (status 9) before StatefulMacro's macro target,
  so B-125 is confirmed there by the unit test only so far.

Apps without `.strings` files, which can build on Linux before B-124 (their resource blockers
from the Linux runs and the readiness survey; build references in `wt-scratch/build/ref/capture`):

| App | Blockers on Linux |
|---|---|
| retro-rampage | none: builds, Info.plists only (B-105) |
| tofu | Main storyboard's `<navigationItem>` (B-260); an image set without `Contents.json` (actool) |
| flappy-fly-bird | LaunchScreen's `<image>` resources (B-260); `.spriteatlas` (B-202) |
| uncloudnotes | storyboards' `<constraints>`, `<inferredMetricsTieBreakers>` (B-260); `.launchimage` (B-202) |
| netnewswire | 3 storyboards, 4 xibs, symbol sets (survey; no build reference captured yet) |
| gomap | 16 storyboards, a xib, an Icon Composer icon (survey; no build reference yet) |
| flutter-platform-channels | Flutter's `xcode_backend.sh`, which needs a Flutter SDK that builds iOS off macOS; Main storyboard |
- Swift Build's third and fourth upstream patches: strings files' encodings detected off Darwin
  (B-124), and Mach-O files read off Darwin (B-183: Swift Build's reader, not lld's output, fails
  every Debug app's debug dylib on Linux); docs/upstream/swift-build.md sections 3 and 4. The four
  patches pass swift-build's tests on macOS and Linux (28 each; on Linux with SwiftPM's native build
  system, since its Swift Build one misses an object of `SWBBuildSystemTests`).
- Objective-C metadata in linked images (ADR 0102 item 10, `.github/scripts/objc_link_experiments.py`):
  Xcode's `ld` merges categories into their classes by default, which lld does with
  `-objc_category_merging`, now passed by the toolchain's `ld64.lld` before the link's own
  arguments; relative method lists for Swift classes, `__objc_classname` and `__objc_methtype`
  apart from `__cstring`, and the size of `__unwind_info` are lld's layout, recorded as causes.
  retro-rampage's app binary and its dSYM are equivalent to Xcode's on Linux.
- retro-rampage's `Rampage` scheme on Linux with `nomac verify --build`: the build succeeds and
  writes Xcode's 61 product files; 32 are byte-identical, 20 equivalent (compiler and linker,
  ADRs 0101 and 0102). The other 9: the 5 Info.plists, Xcode's content in another binary layout
  (B-105); the two storyboard view nibs, whose views Xcode sized 600 × 600 for an iPhone and iPad
  app where nomac keeps the storyboard's 375 × 667 (resources workstream); the app binary and its
  dSYM, whose ObjC sections Xcode's linker lays out otherwise (category merging, relative method
  lists, `__objc_classname` and `__objc_methtype` kept apart from `__cstring`). The objects
  compiled on Linux carry Xcode's ObjC sections, selector references aside (ADR 0101).
  LinkStoryboards links all of a target's storyboards in one ibtool call, each into its `.lproj`
  folder, as `nomac ibtool --link` now does.
- SwiftPM's shared cache (`~/Library/Caches/org.swift.swiftpm`, as Xcode): swiftfin builds with
  nomac on the Mac (Xcode's tools); 108 of 183 products identical, 57 equivalent.
- `-skipMacroValidation` (`nomac pif`, `nomac build`, `nomac archive`): Swift Build refuses
  unapproved macros, and a fresh Mac approves no remote package's, so swiftfin's reference build
  passes the option (corpus.json's new build `options`); `nomac pif` with it matches Xcode's
  `-dumpPIF` with it (docs/formats/pif.md).
- The owner's decisions: ADR 0102 records that reproduced outputs carry Xcode 27.0's version
  strings; docs/upstream/swift-build.md and `.github/upstream/swift-build/` hold B-105's binary
  plist writer and B-005's MD5 as PRs for the owner (both apply to the pin and to upstream main;
  swift-build's tests pass on macOS with them, the Linux run is still to do), and B-115 as a note.
- `.github/scripts/linux_readiness.py` surveys what each corpus app's Linux build needs from
  tools still missing.
- B-204 on main: tofu, flappy-fly-bird and uncloudnotes compile and link on Linux, their Swift
  modules equivalent to Xcode's. `CopySwiftLibs` failed for want of `bitcode_strip`, which
  `build-cctools.sh` now builds from cctools-port with ld64 (ADR 0104). What still fails is the
  resources workstream's: asset catalogs (B-202), storyboards (B-261), Core Data's `.omo` (B-256).
- `nomac archive` (`xcodebuild archive`): the scheme's entries built for archiving, in its archive
  configuration, as Swift Build's install build into `ArchiveIntermediates/<scheme>`, then
  `nomac xcarchive` (docs/formats/build.md "The archive build"). retro-rampage's archive request
  is identical to xcodebuild's, and its archive has Xcode's files (compiled outputs and
  `CreationDate` aside). `ONLY_ACTIVE_ARCH`, which xcodebuild synthesizes for autocreated
  schemes, is B-122.
- B-121 measured for the owner (`.github/scripts/macro_experiments.py`): `#Preview` is compiled
  into Release builds (a `PreviewRegistry` struct, not under `#if DEBUG`); 4 corpus apps use only
  the Previews macros, 7 also SwiftData, SwiftUI's `@Entry`, AppIntents, TipKit or
  FoundationModels macros (counts in B-121).
- Relocatable links on Linux (B-120, ADR 0104): cctools-port's `ld64` (`ld64-956.6`, built by
  `.github/scripts/build-cctools.sh`) makes the `-r` links, through the toolchain's `ld64.lld`
  dispatcher. icecubes' `Models` on Linux: `SwiftSoup.o` and its module equivalent to Xcode's;
  `Models.o` waits on Apple's SwiftData macros (B-121).
- icecubes' `Models` scheme (Debug) with `nomac verify --build`, Swift packages cloned from local
  mirrors of the packages Xcode resolved: on the Mac every product is identical or equivalent
  (`Models.swiftmodule` identical); on Linux SwiftSoup compiles (its module equivalent to
  Xcode's), but the relocatable links of package products fail, lld having no Mach-O `-r`
  (B-120), and `Models`' `@Model` needs Apple's SwiftData macro plugin (B-121).
- Script phases off macOS run under the shell `nomac toolchain install` ships (ADR 0103,
  accepted): tofu's version script runs with Ubuntu's dash still `/bin/sh`.
- uncloudnotes, tofu and flappy-fly-bird with `nomac verify --build` (references captured with
  their builds). On the Mac (Xcode's tools) all three pass: every product identical or
  equivalent, for the compiler's reasons only (ADR 0101) and source modification times. On Linux
  none compiles yet: every corpus app has image sets or app icons (B-202), and the Swift compile
  waits on `GenerateAssetSymbols` (B-204); storyboards (B-261) and models with an `.omo` (B-256) also fail, and
  `nomac ibtool --version` prints nomac's version (its root `--version` wins, and
  `--minimum-deployment-target` is required). Build-driver fixes found on the way: tofu's script
  phase needs a shell like macOS's `/bin/sh`, which `nomac toolchain install` now ships and
  `nomac build` points script phases at off macOS (ADR 0103), and the toolchain lacked `cc` (the
  Info.plist `Preprocess` task); with both, tofu's `include` product and `Preprocessed-Info.plist`
  are Xcode's, with Ubuntu's dash still `/bin/sh`. `nomac build` takes
  `-IDEBuildingContinueBuildingAfterErrors=YES` as xcodebuild does, and `nomac verify --build
  --continue-building-after-errors` compares what builds despite another workstream's blocker.
- Swift Build's binary property lists on Linux (B-105): NomacPlist's `swiftBuildData` writes
  Xcode's bytes for all 11 Info.plists of the Xcode builds at hand, but Swift Build writes them in
  process, so only a Swift Build change can use it. Tried in a scratch Swift Build (the writer in
  `PropertyListItem.asBytes`, binary format, off Darwin), `Engine`'s Info.plist is identical and
  its scheme passes `nomac verify --build` on Linux; upstream or fork is the owner's decision.
- lld's versions for libraries `$ld$previous$` renames (B-116): `.github/scripts/ld_experiments.py`
  found Xcode's `ld` rule on 29 variants of self-written stubs (docs/formats/build.md); a third
  lld patch applies it, and lld matches Xcode's `ld` in all 29. `build-llvm-tools.sh` now patches
  a pristine source copy again when the patches change. `Engine` on Linux, against Xcode's build:
  its binary and dSYM equivalent, its framework different only by the Info.plist (B-105).
- The `build` check kind (B-101, ADR 0101): `nomac verify --build` builds the app as the
  reference's build capture did, at its derived-data path, and compares each product: compiled
  files by structure with every accepted difference documented (docs/VERIFICATION.md "Build
  products"), the others byte for byte; equivalent products pass in corpus progress. On the Mac
  (Xcode's compiler and linker), retro-rampage's `Rampage` scheme: 3 products identical, 5
  equivalent (no stack checks, ADR 0101; a generated source's modification time in the app's
  `.swiftsourceinfo`). On Linux the scheme stops at the app icon set (B-202); its `Engine`
  scheme, against Xcode's at the same paths: the dSYM equivalent, the framework different only
  by its Info.plist's binary layout (B-105) and lld's `libswiftDarwin` versions (now patched).
- The Swift Build pin (B-115): no upstream revision has both ADR 0005's `arm64e.x1` settings and
  Xcode 27.0's codesign arguments, so the pin stays (ADR 0005).
- `Engine` on Linux, `** BUILD SUCCEEDED **`: 30 of Xcode's 78 files identical (Info.plist
  content aside, B-105), among them `Engine.tbd`, the dSYM's Info.plist, the App Intents strings
  data, module maps, header maps, file lists and `Engine_vers.c`. The binary has Xcode's 785
  exports and linked libraries; its sections differ only by lld's `__literals`,
  `__objc_clsrolist` and missing `__objc_methtype` (ADR 0102). The other differences are
  compiler outputs (ADR 0101), the response file's SHA-256 name (B-005) and quoting, and
  Info.plist's binary layout (B-105).
- Linking (ADR 0102): swiftlang's `ld64.lld` at `swift-6.4.0-RELEASE` with patches
  (`.github/lld`: no platform check; `arm64e.x1`, observed as CPU subtype `0x8000000c`; Xcode's
  versions for libraries `$ld$previous$` renames), built by
  `.github/scripts/build-llvm-tools.sh` (verified: its `lld` is byte-identical to a manual build).
  `clang.cfg` gives clang `-fuse-ld=lld`; `ld` runs `ld64.lld`, so Swift Build's probe sees lld.
- Xcode's tools reimplemented from observation, behind launchers at Xcode's paths: `tapi stubify`
  (`.github/scripts/tapi_experiments.py`, 15 self-written dylibs), `dsymutil` (LLVM's, which wrote
  Xcode's DWARF byte for byte, plus the bundle values dsymutil reads on macOS), and the two App
  Intents tools for targets without App Intents.
- `nomac build` prints xcodebuild's failure summary (identical to xcodebuild's for a failing Ld).
- `nomac build` makes xcodebuild's request, read from the `build-request.json` Swift Build
  records: Engine's and icecubes' `Models`' requests are identical to Xcode's (container path,
  configured targets without their own parameters, the SDK's canonical name and xcodebuild's
  architecture list for `generic/platform=iOS`, the index data store, `ACTION`,
  `ENABLE_PREVIEWS` and `ENABLE_XOJIT_PREVIEWS`). `.github/scripts/build_experiments.py` showed
  that `generatePrecompiledModulesReport` comes from `-showBuildTimingSummary` (B-108).
- Package products in `nomac build` (B-104): a scheme's package entries configure the product's
  PIF target. icecubes' `Models` scheme with nomac on the Mac (Xcode's tools) builds the targets
  Xcode builds; 541 of 712 files identical, the rest objects (B-100), `.priors` and 54 missing
  `.stringsdata` (B-109).
- Review fixes: the App Intents tools refuse only when a listed metadata file exists (Swift Build
  lists every bundle dependency's, written or not); `nomac ibtool` answers Swift Build's version
  probe, and both it and `nomac actool` name nomac in it (ADR 0102 "Tool probes"); off macOS,
  `nomac build` needs `--host-identity` (B-060); the log goes through one stdout path; `tapi`
  rules for weak data, versions of 1.0.0 one by one, libraries without exports and Swift Build's
  extra options, each from a new `tapi_experiments.py` variant, and every expected TBD in the
  tests is one Xcode wrote; formats in docs/formats/tbd.md and docs/formats/build.md; the
  comparison scripts in `.github/scripts/build_compare.py`; ADR 0102 lists the versions that
  reproduced outputs embed, as open questions for the owner.
- Signing: `nomac toolchain install` puts a `codesign` launcher for `nomac codesign` in the
  toolchain's `usr/bin`; off macOS, `nomac build` synthesizes `CODESIGN=codesign` and ad-hoc
  signing (`LinuxSigning`), and answers Swift Build's provisioning question for `-` as Xcode
  does ("Sign to Run Locally", no entitlements). Engine built and signed on Linux passes
  Apple's `codesign -v`. The pin's `--strip-disallowed-xattrs` is B-115.
- Earlier: `nomac build`, `nomac toolchain install` (ADR 0100), the Mac host settings off macOS.

## In flight

- Nothing.

## Next actions

1. The Linux-corpus reports' build-driver classes, one at a time (icecubes).
2. rn-bare Debug's `__preview.dylib`, whose `__TEXT,__text` only Xcode's has.
3. ExpoModulesJSI's `.swiftinterface` and `.abi.json` on Linux against Xcode's.
4. B-132: enforce user script sandboxing with Linux namespaces or Landlock.
5. tofu and uncloudnotes on Linux once the resources workstream's storyboards (B-260, B-261,
   B-265) and `.omo` (B-256) land.
6. B-060: a Linux build records the reference Mac's identity by default.
7. `nomac verify --build` compares universal Mach-O files slice by slice.
8. B-122 (`ONLY_ACTIVE_ARCH` for autocreated schemes), B-117.

## How to reproduce

Builds never run in the shared corpus checkouts (`/tmp/nomac-corpus/<app>`), which are the
references' sources: a build can change its sources (swiftfin's "Generate Strings" phase rewrites
`Translations/en.lproj/Localizable.strings`; a Mac `nomac verify --build` in the shared checkout did
so on 2026-10-22, restored since). Builds run on a copy at the reference's path: on Linux the
shared checkout is mounted read-only and copied into a scratch folder mounted at the path (under
`/private/tmp` with the container's `/tmp` linking there, as the Linux gate does); on the Mac, a
reference of its own captured from a clone under a scratch root (`capture_reference.py --work`),
with the clone restored (`git checkout -- . && git clean -fd`) before each build.

On the Mac (Xcode 27.0 at `/Applications/Xcode_27.app`); outputs stay outside the repository
(`~/nomac-out/wt-scratch/build` here):

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
B=.github/scripts/build_compare.py
# Xcode's reference build of retro-rampage's Engine scheme, at the corpus's settings
python3 $B reference <checkout> <ref-dd> Source/Rampage.xcodeproj Engine Release IPHONEOS_DEPLOYMENT_TARGET=15.0
# nomac with Xcode's tools, at the same paths
.build/debug/nomac build -project Source/Rampage.xcodeproj -scheme Engine -configuration Release \
    -destination generic/platform=iOS -derivedDataPath <dd> --developer-dir "$DEVELOPER_DIR" \
    --host-identity ~/nomac-out/reference/retro-rampage/host.json CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= IPHONEOS_DEPLOYMENT_TARGET=15.0 build
python3 $B files <ref-dd> <dd>; python3 $B request <ref-dd> <dd>
# A reference with its build, and nomac's build compared with it (docs/VERIFICATION.md "Build products")
python3 corpus/scripts/capture_reference.py retro-rampage <refs> --work <corpus>
.build/debug/nomac verify <refs>/retro-rampage --developer-dir "$DEVELOPER_DIR" --build
python3 .github/scripts/tapi_experiments.py <out>; python3 .github/scripts/build_experiments.py <out>
```

On Linux (Docker, `swift:6.4.1-noble`, arm64): the `nomac sdk` subset at the reference's Xcode
path, the swift.org toolchain and the LLVM tools installed into it, the checkout at its Mac path
and the reference host's `TMPDIR` created:

```sh
.github/scripts/build-llvm-tools.sh <llvm-out>           # cmake, ninja, clang, patch
.github/scripts/build-cctools.sh <llvm-out>                 # make, clang, the Swift toolchain's libdispatch
nomac toolchain install swift-6.4.0-RELEASE-ubuntu24.04-aarch64/usr --llvm-tools <llvm-out> \
    --developer-dir /Applications/Xcode_27.app/Contents/Developer
nomac build ... --host-identity host.json ...             # as above
```

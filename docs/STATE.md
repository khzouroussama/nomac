# nomac: current state

This is the resume file. A new contributor (human or agent) with no other context should be
able to read it and continue within five minutes. It is updated at every milestone and at the
end of every working session.

<!-- progress:begin -->
## Progress toward "any Xcode project builds on Linux"

Overall: 63% (weighted) · Corpus: 2 / 20 apps build on Linux (4 / 20 on the Mac with Xcode's compilers) · 0 / 20 pass their tests on device

- [ ] Project loader (xcodeproj, xcworkspace, xcconfig, schemes → PIF) · 85% · weight 20 · 17 / 20 apps
- [ ] Build driver (Swift Build on Linux, Swift/ObjC/C/C++, pods, SwiftPM, xcframeworks) · 77% · weight 25 · 929 / 1198 build checks on Linux in 16 apps · 21 / 21 on the Mac with Xcode's compilers, in 4 apps
- [ ] Asset catalogs (actool replacement, .car writer) · 54% · weight 10 · 54 / 99 assets checks in 18 apps
- [ ] Storyboards and xibs (ibtool replacement) · 55% · weight 10 · 271 / 485 nib checks in 15 apps
- [x] Strings and localization · 100% · weight 3 · 3022 / 3022 strings checks in 13 apps
- [x] Core Data models (momc replacement) · 100% · weight 4 · 11 / 11 coredata checks in 5 apps
- [x] Packaging and signing (IPA, entitlements, dSYM) · 100% · weight 8 · 12 / 12 signing and export checks in 4 apps
- [ ] Extensions, App Clips, widgets, watch targets · 0% · weight 5 · no check kind yet
- [ ] Device workflow (install, launch, XCTest on device) · 0% · weight 6 · no check kind yet
- [ ] Distribution (TestFlight, App Store Connect) · 0% · weight 3 · no check kind yet
- [ ] Rare file types (intents, SceneKit, texture atlases) · 0% · weight 2 · no check kind yet
- [ ] Metal and CoreML (Wine-hosted tools, runtime fallbacks) · 0% · weight 2 · no check kind yet
- [ ] Verification harness (corpus, macOS reference builds, nomac verify) · 90% · weight 2 · 18 / 20 apps verified

Last updated: 2026-11-02 · Full per-app results: corpus/RESULTS.md
<!-- progress:end -->

Paths under `~/nomac-out` name the folder outside the repository where experiments, captures,
corpus checkouts and runs write (docs/VERIFICATION.md "Without CI"); what they hold is never
published. Docker volumes named in the state files are the development machines' own. Commit
hashes cited in docs/ are those of the development repository's history, which is not public.

## Workstreams

Agents may work in parallel, one workstream each (CLAUDE.md "Working in parallel"). Each keeps
its state in `docs/state/<workstream>.md`; this file stays the overview.

| Workstream | Branch | State | Status |
|---|---|---|---|
| Project loader, SDK, verification harness | `main` | this file | active |
| Build driver | `build/driver` | `docs/state/build-driver.md` | active: `nomac verify --build` compares build products (ADR 0101); next retro-rampage's app target on Linux |
| Resources: asset catalogs | `res/assets` | `docs/state/resources-assets.md` | started 2026-10-21 (B-200–B-249) |
| Resources: strings, Core Data, nibs | `res/nibs` | `docs/state/resources-nibs.md` | started 2026-10-21 (B-250–B-299) |
| Resources: Core Data (momc, mapc) | `res/coredata` | `docs/state/resources-coredata.md` | started 2026-10-22 (B-255–B-258, B-270–B-279): every corpus `.mom`, mapping model and generated class identical; `.omo` parked (B-256) |
| Resources: strings symbols and the `.omo` (B-230–B-239, ADRs 0230–0249; B-254, B-256) | `res/strings` | `docs/state/strings.md` | started 2026-10-30: `xcstringstool generate-symbols` for manual strings, every corpus and holdout strings check identical; the `.omo` (B-256) parked after a second pass |
| Packaging and signing | `pack/signing` | `docs/state/packaging.md` | started 2026-10-21 |
| Macros (build driver's range, B-150–B-169) | `ws/macros` | `docs/state/macros.md` | started 2026-10-22: Previews, `@State` and `@Entry` identical to Xcode's expansions (ADR 0150); `@State` in local types as the property wrapper's code, `#Predicate` (swift-foundation's macros built as Apple's), SwiftData (`@Model`, `@ModelActor`, `@Query`; icecubes); a project's Mach-O macro plugins built off macOS from the package beside them (ADR 0151, Expo's); SwiftPM's swift-syntax prebuilts as Xcode's PIF uses them; TipKit (`@Parameter`, `#Rule`; wikipedia), FoundationModels (`@Generable`, `@Guide`), AppIntents (home-assistant's schemas, `@UnionValue`): every Apple macro the corpus uses |
| React Native and Expo projects: CocoaPods, script phases, C++ interop (test cases for the general build; build driver's range, B-180–B-199) | `build/expo` | `docs/state/react-native.md` | since 2026-10-24: scripts that phases run by path, `ditto`, `libtool`, `strip`, a phase's `xcodebuild`, C++ types under library evolution (ADRs 0180, 0181), project fixes that nomac makes itself and shows the user (ADR 0184), other project-side changes reported by `nomac check` (ADR 0182); on Linux rn-bare Release builds with no errors and both apps' storyboards and JS bundles are identical; next: the fork's binary property lists (B-105), Debug dylibs (B-183), `nomac verify` of nomac's own archive and IPA (B-188) |
| React Native and Expo holdout apps (loader's range, B-050–B-059) | `corpus/rn-holdout` | `docs/state/rn-holdout.md` | started 2026-10-30: three generated apps nomac is measured on but not developed against (`rn_holdout_experiments.py`) |
| React Native and Expo sweep (loader's range, B-043–B-049; ADRs 0030–0039) | `corpus/rn-sweep` | `docs/state/rn-sweep.md` | paused 2026-11-03: round 2 partial, 49 of 61 finished apps build, archive and export on Linux (nomac a9b571ab and ad202e5b); 45 to run (`docs/state/rn-sweep.md` has the resume command) |
| Wild sample: real projects built end to end (B-500–B-509, ADRs 0500–0509) | `corpus/wild-sample` | `docs/state/wild-sample.md` | started 2026-11-07: a seeded sample of the projects the survey reads, built unchanged on Linux, each failure judged nomac's, the project's or not known (`wild_sample.py`) |
| Clang (build driver's range, B-170) | `build/clang` | `docs/state/clang.md` | started 2026-10-30: Xcode's C++ ABI from swift.org's clang (ADR 0170); a patched clang and libclang (`CLANG=1 build-llvm-tools.sh`) for Objective-C literals, `objc_opt_` calls and `this`, installed when built; next driver defaults and selector stubs (B-170) |
| Linux corpus (build driver's range, B-171–B-179; ADRs 0130–0149) | `build/linux-corpus` | `docs/state/linux-corpus.md` | started 2026-10-30: the corpus apps built on Linux and their Linux reports; retro-rampage builds; lld's weak imports of moved symbols, `ld64 -r` without optimization hints |
| Resources: Metal and Core ML (B-240–B-249, ADRs 0240–0249) | `res/metal-coreml` | `docs/state/metal-coreml.md` | started 2026-11-03: feasibility (ADR 0240: Core ML reimplemented from observation and the public format; Metal refused by `nomac check` until the owner decides on Apple's Windows tools under Wine); `nomac coremlc` compiles simple models and ML programs and generates Swift classes identically to Xcode on every observed model; `coreml` tool checks; Swift Build patch 10 (`what` off macOS): a Core ML app builds on Linux with outputs matching Xcode's |
| Device and distribution | `device/install` | `docs/state/device.md` | started 2026-10-30: from Linux, `nomac install` and `nomac launch` installed and launched on the owner's iPhone a demo app signed in Linux and rn-bare built, signed and exported by nomac in Linux (usbmux, lockdown, TLS, AFC, installation_proxy, CoreDevice tunnel, RemoteXPC; ADRs 0400–0402); next expo-default, the network route (B-404) and mounting the Developer Disk Image (B-403) |
| Distribution: App Store export and upload (B-460–B-499, ADRs 0460–0499) | `dist/upload` | `docs/state/distribution.md` | started 2026-11-03: `nomac upload` through the App Store Connect API's build uploads with an API key (ADR 0460), tested up to the network; only Apple-signed profiles count as installed, with Xcode's refusals in exports and builds, export options as Xcode keeps them, and app thinning (`nomac assetutil`, thinned variants); the first upload waits on the owner's key (B-463), distribution signing on an Apple Distribution certificate (B-460) |
| Release preparation (B-070, B-074, B-079; ADRs 0070–0079) | `release/prep` | `docs/state/release.md` | started 2026-11-03: the early preview's privacy and legal sweep, NOTICE, release downloads of the Linux tools (docs/RELEASES.md), the one-commit public snapshot, README install and quick start tested on a clean Ubuntu 24.04; nothing is published before the owner's go |
| Cross-platform frameworks other than React Native (B-510–B-519, ADRs 0510–0519) | `corpus/frameworks` | `docs/state/frameworks.md` | started 2026-11-07: fresh Flutter, Capacitor, Cordova, Kotlin Multiplatform, NativeScript and Tauri apps through nomac on Linux; none has reached an IPA yet |

## Current step

All workstreams but device and distribution run at once on the owner's Mac (macOS 27.0.1,
Xcode 27.0 at `/Applications/Xcode_27.app`), one branch and worktree per fix or workstream,
merged here after the Mac and Linux suites pass. Against the local references of all twenty
corpus apps (2026-10-22, main `a0bf0c3`), fifteen match Xcode in everything the loader compares
(loader 75%); home-assistant, mattermost, nextcloud, pocket-casts and signal wait on branches in
flight (file types, user schemes, target keys). On Linux every app gives the same result as on
the Mac (the gate in docs/VERIFICATION.md, run on Docker).

How far beyond the corpus the loader holds:
- `nomac check` over 1,490 open-source projects: 51.4% use only verified features (95% CI
  48.9–53.9%; 5.8% the day before), `.github/scripts/feature_survey.py`, next features in B-081.
- The differential fuzzer on unseen seeds: 12.5% of 200 random projects identical (main
  `e7e8a13`, before most fixes landed).
- A holdout set of 20 open-source apps never used for development (in progress).

The other progress lines (docs/PROGRESS.md) measure corpus checks only; the build driver, resources and
packaging have results measured outside `nomac verify` so far (Just finished, and each
workstream's state file). Milestone `v0.1.0-loader` is tagged at `5ac2715`.

## Just finished

- One Xcode per release (ADR 0012, proposed): `nomac --version` prints `nomac 27.0.1 (Xcode 27.0,
  27A266a)`; `sdk install`, `sdk link` and `--developer-dir` warn on another Xcode build, and
  refuse it with `--strict-xcode`; every value nomac takes from Xcode 27.0 is in `XcodeProfile`
  (`nomac sdk profile`), which NomacPackages, NomacProject, NomacNib, NomacAssets and the host
  identity read (`nomac build` next, B-060); off macOS, `inspect` and `list` present the
  reference Mac. `.github/scripts/xcode_upgrade.py` reruns, with another Xcode, the 16 experiment
  suites that observe Xcode, the corpus captures, the fuzzer and the survey, and reports what
  changed (docs/UPGRADING.md); run against 27.0 itself (the 16 suites, the 20 corpus apps, 100
  fuzz seeds, the survey) it reports no change, with the outputs that change from one run to the
  next listed (B-097 has the new ones).
- Linux builds sign ad hoc through `nomac codesign` (Apple's `codesign -v` accepts Engine built
  on Linux); packaging adds universal binaries, App Store symbol files and back-deployed Swift
  libraries (71/71 signing steps, 30/30 exports identical to Xcode's, clock and owner fields
  aside).
- Linux parity: Mac host settings off macOS, the subset's `libobjc.tbd`, `SDK_STAT_CACHE_PATH`
  with MD5 (B-005 for settings); nothing Linux-only remains on the twenty references.
- Loader coverage 5.8% → 51.4% (object versions, object IDs, workspace items, missing xcconfigs,
  untyped references, Package.resolved, scheme options, asset tags) and `nomac verify`'s
  envelope check (B-082); firefox identical.
- The build driver builds retro-rampage's `Engine` framework end to end on Linux (Docker,
  swift.org 6.4.0, `nomac build`, `** BUILD SUCCEEDED **`): 30 of Xcode's 78 output files are
  byte-identical, the compiled ones export the same 785 symbols (ADR 0101, option A, decided by
  the owner: compiled code is judged equivalent; ADR 0102: swiftlang's `ld64.lld` with two
  patches). No version string is faked.
- Packaging and signing: ad-hoc and certificate code signatures, ditto's zip and
  `nomac export` byte-identical to Xcode's for the cases observed (docs/state/packaging.md).
- Resources: `.strings`, `.stringsdict` and `.xcstrings` compile byte-identical on all 9,885
  corpus strings files and 188 catalog compilations; plain-view xibs (`nomac ibtool`); asset
  catalogs' color and data sets and actool's LZFSE/LZVN (`nomac actool`).
- `nomac check` and the verified envelope (ADR 0011); Unicode names in either normalization
  form, as Xcode writes them (decomposed) and as Linux stores them.
- swiftfin, kickstarter and moonlight match Xcode, each rule from an experiment:
  - synchronized folders list the missing files their exception sets name, and add their
    localized files' regions to `knownRegions`; one product entry per
    `XCSwiftPackageProductDependency`, found by name in another package when the named one
    lacks it; remote packages' macros are not approved by the user; unlinked products go at
    the start of the Frameworks phase; every local package gets product schemes;
  - a workspace's shared `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded = false` turns
    scheme autocreation off; a test product's deployment floor is the lowest `minos` of the
    testing binaries' slices; a package scheme builds only what the package's PIF has (66
    otherwise); only a launch or profile covers an executable package product;
  - projects a project references are projects of the workspace, with their own autocreated
    schemes; `-list` and `-target` see only the opened project's targets.
- The test suite and `nomac verify` ran on Linux (`swift:6.4.1-noble`, arm64, in Docker on the
  owner's Mac, case-sensitive volume): every test passes; the Linux-only settings differences
  are the host settings Swift Build takes from the machine, `libobjc.tbd` missing from the
  subset's non-iOS SDKs, and B-005's `SDK_STAT_CACHE_PATH` (fixes in flight).
- cwa, flappy-fly-bird, gomap and uncloudnotes captured and matched, each difference found by
  an experiment (`loader-experiments` `infoplist-macros`, `file-encodings`, `coverage`,
  `provisioning-style`, `source-languages`, `build-rules`, `workspace`; `package-experiments`
  for more `canImport` modules):
  - package folders a workspace references are root packages (B-011, cwa);
  - a workspace needs `-scheme` for `-showBuildSettings` (status 64);
  - code coverage comes from a scheme's default test plan when it has test plans;
  - `INFOPLIST_FILE` and `CODE_SIGN_STYLE` written with macros are evaluated by Swift Build
    for the PIF; `provisioningStyle` follows `CODE_SIGN_STYLE` before the target attribute;
  - which file types keep `fileTextEncoding`, which count for which language in
    `predominantSourceCodeLanguage` (headers included, ties to the first name), and the name
    Xcode gives an unnamed build rule: observed tables over every file type and compiler of
    Swift Build's specifications;
  - how a Mac answers `canImport(Compression)` and twelve other modules.
- Member order in build phases that mix synchronized folders or own build files (B-007,
  docs/formats/pif.md "Order in a phase"): each folder's members go in as one block at
  `h mod (n + 1)`, where `h` folds `h * 33 + NSString hash(name)` over the folder's items of the
  phase's kind. Found by recovering a block's 64-bit `h` from its positions with large folders
  (`pif-experiments` locally); confirmed on 137 experiment phases, a fourth round of
  `pif-experiments`, and all 12 mixed phases of icecubes and netnewswire.
- Autocreated schemes as Xcode 27.0 makes them, from ten new `loader-experiments` (`autocreate`,
  `extension-points`, `product-types`, `autocreate-hosts`, `scheme-coverage`, `test-bundles`,
  `test-hosts`, `autocreate-order`, `autocreate-names`, `autocreate-three`) and the `schemes`
  experiment rerun with product references:
  - netnewswire's `Subscribe to Feed` gets no scheme because its Info.plist names the Safari
    extension point (found by editing one value in a copy of netnewswire); the old guess,
    `CreatedOnToolsVersion`, was wrong;
  - a shared scheme covers an app only by launching or profiling it, other targets by
    building or testing them; it builds what it launches;
  - an extension's autocreated scheme also builds the apps that depend on it (netnewswire's
    widget extension scheme now prints `NetNewsWire-iOS` too);
  - test bundles: which an app's autocreated scheme tests (code coverage) and which get a
    scheme of their own;
  - the Info.plist and test-host settings are evaluated with Swift Build (`TargetSettingsQuery`),
    in Debug or the first configuration; `nomac list` starts Swift Build only when a project
    needs that.
- nomac evaluates package manifests with the selected Xcode's toolchain on a Mac (it used
  `/usr/bin/swiftc`, the `xcrun` shim, and found no `PackageDescription`).
- The test suite passes on macOS too (Swift Build's resource bundles next to the test bundle;
  the package preamble prints the path the workspace was opened with, `/tmp`, not `/private/tmp`).
- Earlier: schemes of Swift packages and xcodebuild's scheme failures, `nomac list`, quoted
  target names, Swift packages in the PIF (ADR 0010), synchronized folders, Linux
  verification (ADR 0008, withdrawn on 2026-11-03), milestone tags (ADR 0007).

## In flight

- Loader fixes, each on its own branch: mastodon and nextcloud's `intentsCodegenVisibility` and
  `provisioningStyle` (`fix/codegen`); file types without a spec, more synchronized-folder
  rules and signal's module maps (`fix/filetypes`); wikipedia's crash on a test plan in a
  build action, and copy-files destinations (`fix/signal-wikipedia`); the Linux-only settings
  differences (`fix/linux`).
- A differential fuzzer for the loader against Xcode (`loader/fuzz`).
- References of pocket-casts, home-assistant, mattermost, firefox and
  flutter-platform-channels.

## Next actions

1. Every difference of mastodon, nextcloud, signal and wikipedia fixed (branches in flight);
   references of pocket-casts, home-assistant, mattermost, firefox and
   flutter-platform-channels, every difference fixed; then corpus/RESULTS.md from all local
   reports (`nomac corpus results --source`).
2. Linux verification runs in Docker on a Mac (docs/VERIFICATION.md "Without CI"); the Linux
   runners' verification of ADR 0008 is withdrawn. Every difference is either a nomac bug or a
   Swift Build difference off Darwin (BACKLOG B-005).
3. The rest of the loader: build tool plugins (B-009), product references for hand-written
   projects (B-012), the autocreation cases no experiment covers yet (B-014).
4. When the repository is public, start `reference` from the Actions tab without an app list
   to verify the full 20-app corpus, and regenerate corpus/RESULTS.md.
5. Then the build driver (milestone 2): a Swift Build build of retro-rampage's `Engine`
   framework on Linux against the `nomac sdk` subset.

## What each kind of session can do

- **A session on the owner's Mac with Xcode 27.0** can do everything: experiments,
  references and `nomac verify` (docs/VERIFICATION.md "Without CI").
- **A cloud session** (Linux, no Xcode, no SDK) can change code and run the test suite, and
  read the Xcode outputs already captured (below) through GitHub's API; it cannot produce new
  ones.

## Data from earlier runs

Xcode's outputs are kept as Actions artifacts, never in the repository (CLAUDE.md, legal line):

| What | Run | Artifacts | Kept until |
|---|---|---|---|
| References of retro-rampage, tofu, netnewswire, icecubes (commit `c89ad83`) | `reference` 39596580971 | `reference-<app>-xcode-27A266a`, `verify-<app>` | 2027-01-19 |
| Loader experiments run 4: target-names, schemes, `-alltargets`, `-list` | `loader-experiments` 39598797016 | `loader-experiments` | 2026-11-20 |
| Mixed-phase size grid (B-007) | `pif-experiments` 39595205611 | `pif-experiments` | 2026-11-20 |
| References of icecubes, netnewswire, retro-rampage, tofu, cwa, flappy-fly-bird, gomap, uncloudnotes (no build), every `loader-experiments` and `pif-experiments` | the owner's Mac, 2026-10-21 | `~/nomac-out/reference`, `~/nomac-out/loader-experiments`, `~/nomac-out/pif-experiments` | on that Mac |

## Known blockers

- The account's GitHub Actions minutes ran out on 2026-10-21 (every run since 12:31 failed
  without a runner). The macOS workflows are now manual-only and `ci` runs on pull requests
  and pushes to `main`. Until the limit resets, Xcode's side runs on the owner's Mac
  (docs/VERIFICATION.md "Without CI"), which is set up: macOS 27.0.1, Xcode 27.0 (27A266a) at
  `/Applications/Xcode_27.app` next to Xcode 26, selected per command with `DEVELOPER_DIR`. The
  Linux test suite runs in Docker on the same Mac (`swift:6.4.1-noble`, arm64).
- GitHub API calls from the agent's environment cannot dispatch or cancel workflow runs (403):
  the owner starts the manual workflows from the Actions tab.

## Decisions made by the project owner

- 2026-11-03: Apple's SDK runs only on Apple hardware. The `reference` workflow's Linux verification and its encrypted SDK cache are removed (ADR 0008 withdrawn); Linux builds that use the SDK run in Docker on a Mac; Linux CI jobs use no Apple software.
- 2026-11-04: the public repository is the only origin; development happens there, and nomac-dev is the private archive of the earlier history (docs/state/release.md).
- 2026-11-03: nomac goes public as khzouroussama/nomac, a snapshot of this repository's tree (now khzouroussama/nomac-dev, which keeps the full history), after the release polish; publish when the React Native/Expo demo works end to end on Linux, with Linux CI green; GitHub's Linux runners may run CI, macOS jobs stay manual; CLAUDE.md ships; the snapshot commit keeps the Co-Authored-By trailer.
- 2026-11-02: ADR 0012's version scheme `27.0.N` is confirmed; the ADR is accepted.
- 2026-10-30: B-182 needs no patched clang: `-fclang-abi-compat=4.0` gives Xcode's C++ ABI (ADR 0170). A patched clang is still planned for Xcode clang's Objective-C code (B-170); no binary is published without the owner.
- 2026-10-30 (integrator, under the owner's "do what you think is best"): pixels actool converts between color profiles count as rendered pixels under ADR 0204 (B-213). Device signing uses a new Apple Development certificate whose key nomac holds outside the repository, and a wildcard development profile (ADR 0400).
- 2026-10-24: rendered pixels are *equivalent* (B-211, ADR 0204): nomac renders SVG and symbol glyphs, Icon Composer icons and resized app icons itself; every other byte stays identical.
- 2026-10-24: Swift Build is taken from the owner's fork (release/6.4.2-linux-fixes: the pinned upstream commit plus nomac's patches) until upstream merges them.
- 2026-10-24: React Native and Expo apps are test cases of the general build, not a separate target: nomac has no React Native- or Expo-specific code.
- Xcode 27.0 (27A266a) stays the reference Xcode; the move to 27.1 comes later (B-013).
- 2026-10-22: outputs are identical to Xcode's, version strings included (`DTXcode`,
  `DTXcodeBuild`, `DTCompiler`, `DTPlatformBuild`, `DTSDKBuild`, `BuildMachineOSBuild`, the
  `Assets.car` header, `actool-25098`); each nomac release reproduces one Xcode build (its
  version scheme waits on the owner, below); a Linux machine records the Mac of the reference
  captures unless `--host-identity` names another (B-060). Written down in ADR 0012, with the
  Xcode profile.
- 2026-10-22 (integrator, pending the owner's review): identical experiment cases credit every
  feature they use, as corpus apps do (ADR 0011); no private key is exported for B-302, signatures
  on the owner's chain are checked by verification instead.
- 2026-10-22: ADR 0101, option A: compiled code from open-source compilers is judged
  equivalent, everything else byte for byte; prove App Store acceptance early (validation only,
  then a TestFlight internal upload, then review), after checking Apple's current license terms
  with the owner.
- 2026-10-21: commits keep the owner's own email, public when the repository is published,
  with no history rewrite. The device and distribution workstream starts at the end, with
  the owner's iPhone. Signing with the owner's Apple identities may be observed on the
  owner's Mac (B-302), for observation only: nothing identifying is committed, and a scan of
  the history for the identities' and profiles' identifiers runs before every push.
- 2026-11-02: the public repository starts from a fresh one-commit snapshot of the tree; this
  private repository keeps the full history, including the 34 Apple macro-plugin response files
  committed in 8277e6c and 2d44231 and removed in 301bc3f. Release preparation waits until
  compatibility work has moved further.
- 2026-11-02: Linux builds of the patched LLVM tools and cctools may be published as release
  downloads.
- 2026-11-02: B-403 approved: nomac may contact Apple's TSS server (gs.apple.com) to personalize
  and mount a device's developer disk image, as Xcode does.
- 2026-11-03: the first public release is an early preview at khzouroussama/nomac (public, one-commit
  snapshot); this private repository becomes khzouroussama/nomac-dev. CI runs on GitHub's Linux
  runners (macOS jobs stay manual); CLAUDE.md ships; the snapshot commit keeps the Co-Authored-By
  trailer.

## Decisions needed from the project owner

- **Repository visibility and runner cost.** macOS minutes are billed at 10x; the `xcode-27`
  runner label looks like a paid larger runner, which a public repository would not make
  free. A run of `reference` without an app list verifies four apps while the repository is
  private.

## Commands

```sh
swift build                          # build nomac and Swift Build (about 2-3 minutes clean)
swift test                           # run the test suite (119 tests; needs swift on PATH for package manifests)
.build/debug/nomac --help
.build/debug/nomac sdk install <Xcode.xip|Xcode.app>   # or: sdk link <Xcode.app> on a Mac
.build/debug/nomac pif <App.xcodeproj> -o App.pif
.build/debug/nomac list -project <App.xcodeproj> [-json]
.build/debug/nomac inspect -project <App.xcodeproj> -target <T> -configuration Debug
.build/debug/nomac inspect -project <App.xcodeproj> -scheme <S> -destination generic/platform=iOS
.build/debug/nomac verify <reference-app-dir> --source <checkout> --developer-dir <Xcode>/Contents/Developer
.build/debug/nomac corpus results --reports <dir-of-verify-json> --output corpus/RESULTS.md \
    --update docs/PROGRESS.md --update docs/STATE.md
.github/scripts/milestone-tags-test.sh  # test the tagging script
.build/debug/nomac sdk profile           # the Xcode this nomac reproduces, as JSON (ADR 0012)
python3 .github/scripts/xcode_upgrade.py run|report   # move to another Xcode (docs/UPGRADING.md)
```

To tag a milestone, add `<tag> <full commit SHA> <message>` to `.github/tags` and push; the
`tags` workflow creates the tag once `ci` has succeeded on that commit (ADR 0007).

## Reproduce the current state

```sh
# Ubuntu 24.04, Swift 6.4.1 (https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz)
sudo apt-get install -y libsqlite3-dev libxml2-dev zlib1g-dev libncurses-dev
swift build --build-tests && swift test --skip-build
# Reference artifacts and macOS verification: docs/VERIFICATION.md
```

# The `xcodebuild -showBuildSettings` text format

Observed with Xcode 27.0 (27A266a) on the corpus. `nomac inspect` writes the same format.

## Standard output

```
Command line invocation:
    /Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild -project /path/App.xcodeproj -showBuildSettings -target App -configuration Debug

Build settings for action build and target App:
    ACTION = build
    AD_HOC_CODE_SIGNING_ALLOWED = NO
    ...
    YACC = yacc

```

- A preamble `Command line invocation:` names the tool and its arguments, followed by an empty
  line. Some invocations add `User defaults from command line:` (not yet observed).
- When the workspace uses Swift packages, `Resolve Package Graph`, two empty lines,
  `Resolved source packages:` and one line per package of the resolved graph follow, then an
  empty line:

  ```
  Resolve Package Graph


  Resolved source packages:
    SQLite.swift: https://github.com/stephencelis/SQLite.swift.git @ 0.16.0
    EmojiText: https://github.com/Dimillian/EmojiText @ fix-ios26 (3b11459)
    Zip: https://github.com/marmelroy/Zip.git @ bca30f6
    Account: /path/IceCubes/Packages/Account
    Dep: /path/App/Deps/Dep @ local

  ```

  The name is the manifest's; a remote package shows the URL `Package.resolved` records and its
  pin (version, `branch (revision)` or revision, revisions shortened to 7 characters); a root
  package (a folder in the file tree) its path; a local dependency (`XCLocalSwiftPackageReference`)
  its path and `@ local`. xcodebuild's order changes from one run to the next (icecubes); nomac
  lists packages by identity. With `-json` none of this is printed.
- One block per target: `Build settings for action <action> and target <name>:`, then one line
  per setting, four spaces of indentation, `KEY = value`, then an empty line.
- The target name is printed as is when it is made of ASCII letters and digits, non-ASCII
  characters and `-._+,=/`, and otherwise in double quotes, with `"` and `\` escaped by a
  backslash (loader-experiments `target-names`, every ASCII punctuation character):
  `"Subscribe to Feed"`, `"At@Name"`, `"Double\"Name"`, but `Dash-Name`, `Slash/Name`, `Ünïcödé`.
- **Key order is by byte value** (`ARCHS_STANDARD` before `ARCH_COHORT_arm64e`, upper case before
  lower case). The PIF instead uses a case-insensitive order (docs/formats/pif.md).
- Values are printed verbatim, with no quoting or escaping. An empty value leaves a trailing
  space after `=` (`BUILD_STYLE = `).
- Warnings and notes go to standard error (for example the "Using the first of multiple
  matching destinations" warning).

## Settings of the machine

Some settings describe the Mac xcodebuild runs on. In every capture of the corpus (macOS 27.0.1,
build 26A434, Apple silicon): `HOST_PLATFORM = macosx`; `NATIVE_ARCH`, `NATIVE_ARCH_ACTUAL`,
`NATIVE_ARCH_64_BIT` and `HOST_ARCH` `arm64`; `NATIVE_ARCH_32_BIT = arm`;
`MAC_OS_X_VERSION_MAJOR = 270000`, `MAC_OS_X_VERSION_MINOR = 270000`,
`MAC_OS_X_VERSION_ACTUAL = 270001` and `MAC_OS_X_PRODUCT_BUILD_VERSION = 26A434`. A target
that sets no `SDKROOT` gets the macOS SDK (netnewswire's `NetNewsWireTests`).

Swift Build computes these from the machine it runs on, not from the system information its
client gives it (SWBCore `Settings.swift`): its host operating system is fixed when it is
compiled, and its architecture is read from the process. On Linux arm64 it printed `linux` and
`aarch64` (as `uname -m` spells it), no `NATIVE_ARCH_32_BIT`, `NATIVE_ARCH_64_BIT` or
`MAC_OS_X_*`, and gave a target that sets no `SDKROOT` the default `$(HOST_PLATFORM)`, which
made `NetNewsWireTests` a Linux target (`ARCHS = aarch64`, `.../Debug-linux-aarch64`).

Off macOS, nomac therefore evaluates every setting with the Mac's values among the synthesized
overrides (`MacHostSettings`): `HOST_PLATFORM = macosx`, the `NATIVE_ARCH*` of the host
identity's architecture (Swift Build's `Architecture.as32bit` and `as64bit`: `arm`/`arm64`,
`i386`/`x86_64`) and, when the identity is a Mac's, the `MAC_OS_X_*` settings Swift Build
computes from its version (`MAJOR` is `<major>0000`, `MINOR` `<major><minor>00`, `ACTUAL`
`<major><minor><update>`, two digits each; for 10.x `MAJOR` is `10<minor>00` and `MINOR`
`<minor><update>`). Swift Build derives the rest from them as on a Mac: `HOST_ARCH`
(`$(NATIVE_ARCH_ACTUAL)`), the SDK of a target without `SDKROOT`, and `SUPPORTED_PLATFORMS` and
`VALID_ARCHS` of host tools. A Linux machine's own identity has no macOS version, so without a
reference identity the `MAC_OS_X_*` settings are left out (B-060). Being overrides, these values
also replace a project's own assignment of one of these settings, which no corpus app makes. A
build (`nomac build`) takes only the `MAC_OS_X_*` values (a framework's Info.plist reads
`BuildMachineOSBuild` from `MAC_OS_X_PRODUCT_BUILD_VERSION`): Swift Build also builds host tools
(macros, plugins) for `HOST_PLATFORM` and `NATIVE_ARCH`, and those run on the machine (B-061).
Off macOS a build needs a Mac identity (`--host-identity`) and refuses to run without one (B-060).

## `SDK_STAT_CACHE_PATH`

`$(SDK_STAT_CACHE_DIR)/SDKStatCaches.noindex/<SDK canonical name>-<SDK build>-<hash>.sdkstatcache`,
for example `.../SDKStatCaches.noindex/iphoneos27.0-24A430-edb66e1c87ad9550e0cc33700c257328.sdkstatcache`.
Swift Build writes the hash as `$(TOOLCHAINS:__md5)$(SDKROOT:__md5)` (SWBCore `Settings.swift`).
In every capture of the corpus the `TOOLCHAINS` part adds nothing although `TOOLCHAINS` is
printed as `com.apple.dt.toolchain.XcodeDefault`, and the hash is the MD5 of `SDKROOT`. Off
Darwin upstream Swift Build's `__md5` is SHA-256, so on Linux the name ended with the SHA-256 of
`SDKROOT`; the owner's fork carries the upstream patch that makes it MD5 everywhere (ADR 0005), so
Linux prints the Mac's name.

With this and the settings of the machine above, every settings capture of the corpus verified
on Linux arm64 matches the Mac's (2026-10-21).

## JSON (`-json`)

Only the JSON is printed (no preamble), and nothing at all when xcodebuild fails:

```json
[
  {
    "action" : "build",
    "buildSettings" : {
      "__ARCHS__" : "arm64",
      "ACTION" : "build",
      ...
      "GCC_C_LANGUAGE_STANDARD" : "gnu11",
      "GCC3_VERSION" : "3.3",
      ...
    },
    "target" : "Subscribe to Feed"
  }
]
```

This is Foundation's JSON writer with sorted keys, pretty printing and unescaped slashes,
followed by a newline. Keys sort case-insensitively, numerically and by locale (`_` before
digits before letters); target names are not quoted; a result without blocks is `[`, an
empty line and `]`. nomac renders blocks the same way, and the output matched all 276
successful `-json` captures of the netnewswire, icecubes, retro-rampage and tofu references
byte for byte when their text captures were rendered with it.

## Which targets and settings

- The settings are exactly Swift Build's exported settings for the target
  (`allExportedMacroNamesAndValues`, implemented by `computeScriptEnvironment`, the same
  environment shell-script phases receive).
- A workspace (`-workspace`) needs `-scheme`: without it, and with `-target` or `-alltargets`,
  xcodebuild fails with 64 (`If you specify a workspace then you must also specify a scheme.
  Use -list to see the schemes in this workspace.`, after `You cannot specify targets with a
  workspace.` or `You cannot specify -alltargets with a workspace.`; loader-experiments
  `workspace`, cwa).
- With neither `-target` nor `-scheme`: the first target of the project, in the project's
  default configuration (retro-rampage: `Rampage`, `Release`).
- `-target` names a target byte for byte: the name in another normalization form fails with 65
  like any unknown name. `-configuration` with `-target`, `-alltargets` or no selection does
  too: a name the project lacks, in its bytes, makes xcodebuild print `--- xcodebuild: WARNING:
  Configuration Bêta is not in the project. Building default configuration.` on standard error
  and use the default configuration. With `-scheme`, the name goes to Swift Build, which takes
  a canonically equivalent name as the same (loader-experiments `unicode-nfc`, `unicode-nfd`).
- `-target`, `-alltargets` and the default target see only the opened project's targets, not
  those of the projects it references; `-target` naming one of those fails with 65:
  `The project '<project path>' does not contain a target named 'Lib'.` (loader-experiments
  `project-references`).
- With `-alltargets`: every target of the project in project order, then the first one again,
  identical (loader-experiments: `App, App` for one target; `App, Agg, Legacy, App`).
- With `-scheme`: the scheme's build-action entries that are built for running, in entry
  order; their dependencies are not listed. Without `-configuration`, the scheme's Launch
  configuration applies (retro-rampage, tofu: `Debug`). Swift package products and targets in
  the build action print no block (icecubes' package schemes print none; loader-experiments
  `schemes`: `AppAndKit` prints `App` only).
- A target that does not support the destination still gets its block, evaluated for its own
  platform, as long as something else the scheme builds for running supports it
  (loader-experiments `schemes`: `Both` with an iOS and a macOS app, `-destination
  generic/platform=iOS`, prints both, the second with `SDKROOT` macosx).

## Schemes

`-scheme` and `-list` see these schemes (loader-experiments `schemes`, `autocreate`,
`extension-points`, `product-types`, `autocreate-hosts`, `scheme-coverage`, `test-bundles`,
`test-hosts`, `autocreate-order`, `autocreate-names`, `autocreate-three`, `project-references`,
`user-schemes`, `user-schemes-workspace`, `user-schemes-references`, `user-schemes-packages`,
`own-test-schemes`, `own-test-schemes-hosts`, `own-test-schemes-more`, `scheme-order`,
`test-plan-entries`; icecubes, netnewswire, retro-rampage, tofu, moonlight, wikipedia). The
projects the workspace's projects reference (docs/formats/pif.md "Project references") count as
its projects throughout: their shared and per-user schemes are read and cover targets, and their
targets get autocreated schemes (moonlight: `moonlight-common` and `moonlight-common-tv`;
`project-references`: `SubShared`, shared by a referenced project, covers its app, and the
opened project's shared scheme covers a referenced project's `Covered`;
`project-references-bundles`: a referenced project's unit test bundle and app extension get
schemes as in their own project; `user-schemes-references`: `SubUser`).

- Shared schemes of the workspace, of each project, and of each Swift package of the resolved
  graph (`.swiftpm/xcode/xcshareddata/xcschemes`), dependencies and remote packages included
  (icecubes: `RevenueCatUI` from purchases-ios-spm). A package scheme's `container:` paths are
  relative to the package's directory. A `BuildableReference` names its target by
  `BlueprintIdentifier` alone: one without `BlueprintName`, or with another target's name, means
  the target it identifies (loader-experiments `blueprint-names`; home-assistant's `WatchApp`
  schemes test bundles through references without a name).
- Per-user schemes, in the same places with `xcuserdata/<user>.xcuserdatad/xcschemes` for
  `xcshareddata/xcschemes`, where `<user>` is the account's name: another user's folder is not
  read, and neither `USER` nor `LOGNAME` changes which (`user-schemes`: `OtherLaunch`, in
  another user's folder, is not listed and leaves `AppOther` its own scheme). They are listed,
  built and cover targets exactly as shared schemes (`MineLaunch` covers `AppMine`, `MineTests`
  covers `TestsMine`, `MineBuildApp` builds `AppBuildOnly` without covering it; mattermost: the
  189 schemes CocoaPods writes in `Pods.xcodeproj/xcuserdata/<user>.xcuserdatad` for the user
  who ran `pod install`). A project's own `project.xcworkspace` gives no schemes, shared or
  per-user, when the project is opened (`WsShared`, `WsUser`). In the user's
  `xcschememanagement.plist`, `isShown` and `orderHint` change nothing (`Hidden`, `SharedHidden`
  are listed and cover their targets), and a project's `SuppressBuildableAutocreation` entry
  whose `primary` is true keeps that target from getting an autocreated scheme (`FwSuppressed`,
  `AppSuppressed`; `FwSuppressedNo`, `primary` false, keeps its scheme; another user's file is
  not read).
- A name that several shared or per-user schemes have, in one container or several, is listed
  for each followed by its container: ` (P project)`, ` (W Workspace)`, or a package's folder
  name in parentheses (`user-schemes`: a shared and a per-user `Dup` are both `Dup (P project)`;
  `user-schemes-workspace`: `Same (P project)`, `Same (Q project)`, `Same (W Workspace)`;
  `user-schemes-references`: `Both (Sub project)`; `user-schemes-packages`: `Clash (Kit
  Folder)` for the package `Kit` in the folder `Kit Folder`). A scheme that already has the
  resulting name is not renamed, so `Pair (P project)` can be listed twice. Autocreated schemes
  neither count nor change. `-scheme` with a listed name uses that scheme (the renamed one before
  a scheme with that name of its own: `Pair (P project)` is P's `Pair`), and the original name
  also works: with schemes of several containers, which one it uses changes from one run to the
  next (`Same`, `Pair`, `Mixed`, `BothUser`, `UserPair`, four runs each); with a shared and a
  per-user scheme of one project, it is stable: the one the user's `xcschememanagement.plist`
  gives an `orderHint`, the lower of two, by either name, the project opened alone or through a
  workspace (`scheme-pairs-hints`, `-hints-reverse`, `-hints-shared-only`, `-hints-user-only`,
  `-workspace-hints`: `Dup`, `Inner`, `Aaa`, `Zed`, two runs each; `user-schemes`: `Dup`).
  Without hints the choice depends on the other schemes (`scheme-pairs`: `Zed` the shared one,
  `Dup`, `Inner`, `Aaa` the per-user one, also through a workspace and with other target kinds;
  `scheme-pairs-many`, `scheme-pairs-single-*`: `A` the per-user one among forty pairs, the shared one alone), and nomac
  takes the shared one (BACKLOG B-065). Such a name
  uses one of the renamed schemes even when an autocreated scheme has it (`scheme-name-clashes`:
  `-scheme Dup`, four runs, Q's or R's shared Dup, never the autocreated Dup of P's target).
- A shared or per-user scheme is named by its file name as it is on disk, and `-scheme` finds it
  by a name in either normalization form (not in another case); an autocreated scheme's name is
  its target's as written, and `-scheme` finds it only byte for byte. A `container:` path names
  its project in either form (loader-experiments `unicode-nfc`, `unicode-nfd`: `Schémé`,
  `Àutre`, `Ötro`, `container:Café.xcodeproj`).
- A shared or per-user scheme builds its build action's entries and what its Launch action runs (a
  `BuildableProductRunnable`) for running: in that entry's place when an entry names it, else
  after the entries (`scheme-coverage`: `S17` prints `App11, App12`, `S22` `App17, Fw05`, `S03`
  launches `App03` with no entries and prints it). What its Profile action runs is built, but not
  for running (`S18`, profiling only, fails with 64).
- A build action entry can hold a `TestPlanReference` instead of a `BuildableReference`
  (wikipedia's `WikipediaUITests`, built for testing only). It stands, in its place, for the
  plan's test targets in plan order, each built for what the entry is built for; a missing plan
  stands for nothing (`test-plan-entries`: `S02` prints `App, Loose02`, `S05` `Loose05, App`,
  `S11` `App, Loose12, Loose11`, `S01` and wikipedia's scheme `App` only, `S04`, a plan built for
  testing only, fails with 64). These test targets count as built by the scheme, so they get no
  scheme of their own (only `Loose14`, in no plan, gets one); the plan does not change code
  coverage (`S08`). A target several entries build for running is printed once, where it first
  is (`S14`: a plan building `Loose16` for testing, then `App`, then an entry building `Loose16`
  for running prints `App, Loose16`; `S16`, the same entry twice around `App`, prints
  `Loose18, App`).
- An autocreated scheme, named after its target, for each target no shared or per-user scheme
  covers and the user does not suppress. Such a scheme covers an *app* (a target with a product
  reference whose product type is `application`, `tool`, `application.on-demand-install-capable`
  or `application.watchapp2`) only by launching or profiling it, with a
  `BuildableProductRunnable`, or by building it with a `RemoteRunnable` whose `MacroExpansion`
  names it; building it, even for running, or a `PathRunnable` leaves it its own scheme
  (`scheme-coverage`; `product-types`: of the targets a shared scheme builds, only those four
  types keep one). It covers any other target by building it, for any action, or by testing it,
  a skipped testable too (`own-test-schemes-more`: `SkipTests`, `SkipDepTests`). Autocreated
  schemes cover nothing, and an autocreated scheme is listed even when a shared or per-user
  scheme has its name (`test-bundles`: `Shared` is listed twice; `-scheme Shared` uses the
  shared one; `user-schemes`: `FwNamed`, a per-user scheme, likewise). Targets of different
  projects with one name get one autocreated scheme, and `-scheme` builds one of them, which one
  changing from one run to the next (`project-reference-names`, `workspace-names`: four runs of
  each scheme, the root's target or the other's, whether the projects reference each other or a
  workspace lists them; `same-name-destinations`: with an iOS and a macOS `Twin`, six runs each
  with and without `-json` print the iOS block or fail with 64, so the two captures can
  disagree); nomac builds the first project's, in the order the `.xcworkspace` lists its
  projects, then the referenced projects breadth first in `projectReferences` order, and
  `nomac verify` compares a capture of such a scheme with each of the targets
  (docs/VERIFICATION.md; envelope-experiments `same-name-targets`). A target and a local
  package's product with one name likewise (`scheme-name-clashes`: `-scheme Kit` printed the
  target's block in three runs of four, the product's empty one in the fourth; `nomac verify` compares the capture with both). A unit test bundle whose `TEST_HOST` names an executable that several targets
  build, in one project or several, is tested by its dependency's scheme in some runs and gets a
  scheme of its own in others (`test-host-clashes`, `-reversed`, `-project`, `-project-reversed`,
  three runs each; BACKLOG B-090); nomac lets its dependency test it.
- Never autocreated, for targets with a product reference: `application.watchapp2-container`,
  `watchkit2-extension` and `application.messages` (`product-types`), and app extensions
  (`app-extension`, `extensionkit-extension`) whose Info.plist names `com.apple.Safari.extension`
  or `com.apple.Safari.web-extension` as `NSExtension`'s `NSExtensionPointIdentifier`
  (netnewswire: `Subscribe to Feed`; `extension-points`: of 47 extension points only these two,
  on iOS and macOS; `EXAppExtensionAttributes` is not read; apps, frameworks and XPC services
  with such a plist keep their scheme). The Info.plist is the evaluated `INFOPLIST_FILE`, so
  macros, SDK conditions and xcconfigs apply, relative to `SRCROOT`; plist values are not
  expanded. A target without a product reference (only hand-written projects, BACKLOG B-012)
  gets a scheme whatever its type or Info.plist.
- A watch app's (`application.watchapp2`) autocreated scheme comes with two more, the same but
  for their name: `<app> (Complication)` when a `watchkit2-extension` it depends on names a
  `CLKComplicationPrincipalClass` in its Info.plist (read as for Safari extensions), whatever the
  deployment target, and `<app> (Notification)` when such an extension's Sources phase compiles a
  file whose name, or whose path when it has none, is exactly `NotificationController.swift`
  (loader-experiments `watch-schemes`: not a path ending so, `MyNotificationController.swift`,
  `NotificationController.m`, a storyboard's notification scene or an `.apns` payload; octopod's
  `OctoPod Watch`). A file reference whose path ends in `.storyboard` and names no file on
  disk, in any project of the workspace (a referencing, a referenced or an unrelated one), gives
  every watch app both `<app> (Glance)` and `<app> (Notification)`, listed after
  `(Complication)` (loader-experiments `watch-schemes-missing`, `-extension-only`,
  `-referencing`, `-referenced`, `-workspace`, `-complication`; the differential fuzzer's seed
  70155, whose `App Sources/Storage.storyboard` is missing; in a variant group, the storyboard is
  looked for under the variant group's own group: `-variant`, `-variant-missing`, seed 70101).
  An empty or unreadable storyboard (`-empty`, `-garbage`), one on disk (`-written`), a missing
  xib (`-xib`) or the storyboard type on another name (`-type-only`) give neither, nor do a
  `GlanceController.swift` (even at watchOS 2.0) or an extension Info.plist without
  `NSExtension` (`watch-schemes-plist`).
- An autocreated scheme builds its target. For an app extension (`app-extension`,
  `extensionkit-extension`, `app-extension.messages-sticker-pack`, `app-extension.messages`,
  `tv-app-extension`, `xcode-extension`) it then builds each app (`application`,
  `application.on-demand-install-capable`, `application.watchapp2`, `application.messages`; not
  a `tool`) that depends on the extension directly or through one other target, followed by
  that other target (`autocreate-hosts`: `Inner, HostH, Outer`; `ViaFramework, FrameworkUser,
  Middle`; nothing three dependencies away). Embedding the extension without depending on it
  does not count. With several such apps, xcodebuild's order changes from one run to the next
  (`ManyHosts`, `Mixed`, run six times); nomac keeps project order, and `nomac verify` compares
  those blocks in the capture's order (docs/VERIFICATION.md; BACKLOG B-015). The first app
  is what the scheme launches (see "Failures"). Other targets list no app (netnewswire's autocreated widget extension scheme prints
  `NetNewsWire iOS Widget Extension, NetNewsWire-iOS`; retro-rampage's `Renderer` framework
  prints itself only).
- An autocreated scheme tests, with code coverage, the test bundles that depend on its target
  and either are UI test bundles whose `TestTargetID` names it, an iOS or macOS app or an App
  Clip (`autocreate-ui-targets`: not a framework, app extension, sticker pack, static library,
  bundle, command-line tool or watchOS app, whose UI test bundle no scheme tests), or unit test
  bundles whose `TEST_HOST` is its executable (`$(BUILT_PRODUCTS_DIR)/$(EXECUTABLE_PATH)`, so
  the bundle path alone or a missing app does not count) and whose `TestTargetID` names it or,
  without one, whose `BUNDLE_LOADER` is that executable too (`test-hosts`; tofu: `TofuTests` and
  `TofuUITests`, so `-showBuildSettings -scheme Tofu` reports `CLANG_COVERAGE_MAPPING`).
  `TEST_TARGET_NAME` is not read. A path names the executable when its part under the bundle's
  own `BUILT_PRODUCTS_DIR` is the target's `EXECUTABLE_PATH`, as for a bundle or an app whose
  `SDKROOT` is `auto` (products in `Debug-unknown`); such an app, which
  `-showBuildSettings -target` gives no executable, is named by its iOS or its macOS one
  (`autocreate-testables`: Auto16 to Auto20; `autocreate-auto-hosts`: A01 to A04, A11, A12, but
  not A09, whose `TEST_HOST` names another app). The scheme tests no bundle a shared or per-user
  scheme builds, tests, skips or names in a test plan (`autocreate-testables`: App01 to App06,
  App24). An app extension's scheme also tests the bundles of each app it builds
  (`autocreate-testables`: Ext07 to Ext15, both apps of Ext14; the differential fuzzer's sticker
  packs and intents extensions).
- A test bundle gets a scheme of its own, which tests it and builds nothing for running, unless
  a shared or per-user scheme covers it or the user suppresses it, or it is a bundle the
  previous rule has a target's scheme test (whichever scheme covers that target). Otherwise its
  `TEST_HOST` in the project's default configuration decides when it names the executable of a
  target of any project: the bundle gets a scheme unless that target gets an autocreated one.
  The part of `TEST_HOST` under the bundle's `BUILT_PRODUCTS_DIR` is compared with each target's
  `EXECUTABLE_PATH` in its own project's default configuration, so the configuration's name does
  not matter. When it names no target, the bundle gets a scheme unless it depends on a target
  that gets an autocreated scheme (`own-test-schemes`, 35 bundles: a bundle depending on a
  framework or an app a shared or per-user scheme covers gets one, a hosted bundle of such an app
  does not; `own-test-schemes-hosts`: a `TEST_HOST` naming no target, an app's bundle rather than
  its executable, a suppressed app or a messages app does not prevent it, nor does depending on
  a suppressed target or a messages app, while depending on an aggregate target does;
  `own-test-schemes-more`: `B1Tests`, `B4Tests` and `B5Tests` depend on an autocreated framework
  and name an app a shared scheme launches, in their project, another one, or one whose
  configurations are `AppStore` and `Production`, and get one, while `B3Tests`, naming nothing,
  does not; the fuzzer's `Tests`, whose dependency's `SDKROOT` is `auto`, names another
  project's `Fuzz`; `test-bundles`, `test-hosts`: a `TestTargetID` alone does not prevent it;
  `BUNDLE_LOADER` alone does not count).
- A scheme that gathers code coverage adds `CLANG_COVERAGE_MAPPING = YES` and
  `CLANG_PROFILE_DATA_DIRECTORY` to every block it prints. Without test plans, the Test action's
  `codeCoverageEnabled` decides, whether or not it has testables, unless it sets
  `shouldAutocreateTestPlan` and has testables, skipped ones included: the plan Xcode autocreates
  for them gathers coverage (loader-experiments `coverage-autocreated-plan`; pocket-casts'
  `Pocket Casts Prototype Build`; icecubes' extension schemes, without testables, gather none).
  With test plans, the scheme's
  flag is ignored and its default plan (else the first) decides: coverage unless the plan's
  default options set `codeCoverage` to `false` (a list of targets, `true` or nothing are on),
  and none when the plan is missing or unreadable, as when a configuration's `id` is not a
  UUID (loader-experiments `coverage`, 39 schemes; cwa: `ENAScreenshots`, whose plan sets
  `false`). `onlyGenerateCoverageForSpecifiedTargets` and `CodeCoverageTargets` change no block.
  An autocreated scheme gathers coverage when it tests something.
- The settings above are evaluated as `-showBuildSettings -target` evaluates them, in the
  configuration named Debug, else the first one, except the test-bundle `TEST_HOST`, which is
  read in the default configuration. Autocreated schemes launch with the configuration named
  Debug, else the first whose name starts with `Debug` (case-sensitive), else the project's
  default configuration (`autocreate-order`, configurations `Release, Debug`; `autocreate-names`
  and `autocreate-three`, without Debug: Info.plists and test hosts read in Alpha, the first;
  schemes launching with Beta, the default; `autocreate-debug-dev`: `Debug-Dev` of `Adhoc,
  Debug-Dev, Production`; `-suffix`: `Debugging`, not `MyDebug`; `-upper`: `Debugger`, not
  `DEBUG`; `-lower`: `Release`, not `debug`; `-both`: `Debug` before `Debug-Dev`). Info.plists and
  test hosts are still read in Debug, else the first configuration.
- For a local package, an autocreated scheme for each library and executable product that no
  scheme builds (`kit-cli`, `KitExtras`, but not `Kit`, which a project scheme builds). As for
  apps, a scheme covers an executable product only by launching or profiling it, or by building
  it with a `RemoteRunnable` whose `MacroExpansion` names it (loader-experiments
  `package-target-kinds`: `tool`, which a shared scheme builds for running, keeps its scheme, in
  a root package and a dependency alike; `tool2`, launched, `tool3`, profiled, and `tool4`,
  named by a `RemoteRunnable`'s `MacroExpansion`, do not). Local
  packages are root packages (package folders in a project's file tree) and dependencies on a
  local path: `XCLocalSwiftPackageReference`s, whether or not the project uses their products,
  and the path dependencies of local packages (loader-experiments `local-packages`: `Plain`,
  `MultiA`, `MultiB`, `multi-tool`, `Unused` and `Plain`'s dependency `Inner`; swiftfin:
  `PreferencesView` and `SwiftfinMacros`). It tests nothing ("not currently configured for the
  test action": `schemes`' `KitExtras`, `root-package-references`' `Alpha` and `Beta`); only a
  root package's test targets are loaded. A shared or per-user scheme of the product's name
  does not replace it, unless it builds the product: both are listed (`scheme-package-clashes`:
  Stale, building a target the project no longer has, and Other, building the app; wordpress's
  `WordPressKit`). A package
  with several products gets no `<Package>-Package` scheme. Remote packages get none: of
  swiftfin's 41 remote packages only `TVOSPicker` is listed, through the scheme it shares.
- For a root package, a scheme for each test target that no scheme tests, through its
  testables or its test plans (icecubes: `EnvTests`, whose package shares an `Env` scheme that
  tests another package's tests; netnewswire's test plans test all of its packages' tests),
  except one named `<Product>Tests` after a product of the package whose autocreated scheme is
  listed, whatever it depends on (loader-experiments `root-package-references`: `AlphaTests`,
  which tests `Beta`, gets none, `BetaChecks` and `GammaTests` get one; `schemes`: `KitTests`,
  whose `Kit` a shared scheme builds, gets one, `KitExtrasTests` none; element-x's
  `MacrosTests`). A package folder in the group tree is a root package with or without an
  `XCLocalSwiftPackageReference` to it, whether its reference is typed `wrapper` or `folder`.
- No scheme is autocreated, for targets or packages, when the opened workspace's shared
  settings (`xcshareddata/WorkspaceSettings.xcsettings` of the `.xcworkspace`, or of
  `<Name>.xcodeproj/project.xcworkspace` for a project) set
  `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded` to false: only shared and per-user
  schemes are listed (`autocreate-contexts-off-user`: `MineFw`), and `-scheme` with any other
  name fails with 65. `true` changes nothing. A per-user
  copy (`xcuserdata/<user>.xcuserdatad/WorkspaceSettings.xcsettings`) is not read, even to turn
  autocreation back on, and neither is a member project's own `project.xcworkspace` when an
  `.xcworkspace` is opened. `-target` is unaffected (loader-experiments `autocreate-contexts`,
  `-off`, `-on`, `-user-off`, `-shared-off-user-on`, `-workspace-off`, `-workspace-project-off`,
  `-off-user`;
  kickstarter, whose local packages' products then get no schemes).
- `-list` sorts the listed names by Unicode collation in English: letters before their case
  and accents, so case, accents and ligatures only break ties, lowercase first; spaces and
  punctuation before symbols before digits, digits not read as numbers, then Latin, Greek,
  Cyrillic and Han letters (`scheme-order`: ` Leading`, `_under`, `-dash`, `🙂 smile`, `10lives`,
  `9lives`, `a b`, `a_b`, `ab`, `Ab1`, `Ab10`, `ab2`, `Émile`, `Eve`, `ezra`, `ﬁle`, `file2`,
  `item10`, `Item2`, `Oeuvre`, `Œuvre`, `strasse`, `straße`, `u`, `U`, `Ü`, `Uber`, `über`,
  `Ünï Kit`, `Unit`, `UNIT`, `Vendor`, `zed`, `Zed`, `Ωmega`, `Яблоко`, `日本`; `LANG` does not
  change it, and the Mac's locale is English). Foundation's comparison with the `en` locale gives
  this order on macOS and Linux alike.

## Failures

`-showBuildSettings -scheme` fails, with nothing after the preamble on standard output, in three
ways (loader-experiments `schemes`, icecubes, netnewswire); `nomac inspect` exits with the same
statuses and messages:

| Status | When | Message (after `xcodebuild: error: `) |
|---|---|---|
| 65 | the workspace has no such scheme | `The project named "P" does not contain a scheme named "Kit". The "-list" option can be used to find the names of the schemes in the project.` |
| 66 | nothing the scheme builds or tests, or skips testing, exists (`own-test-schemes-more`: `SkipScheme`, which only skips its testables, fails with 64): a target ID or package product that is not there, a dependency's test target, a package's binary target, a dependency's target that none of its products uses (loader-experiments `package-target-kinds`: an unused plugin, a target in no product; kickstarter: `FBSDKCoreKit`, a binary target). A root package's other targets and every library or executable product count, even one made of binary targets only (`ByBinaryProduct`) | `Scheme Broken is not currently configured for the build action.` |
| 64 | what the scheme launches does not support the destination, or, when it launches nothing, nothing it builds for running does: test-only schemes, entries built for testing only or targets only profiled, a macOS-only scheme with an iOS destination, a tvOS one (moonlight: `Moonlight TV` and `moonlight-common-tv`, whose `SDKROOT` is `appletvos`; `project-references`: `TVLib`). A target whose `SDKROOT`, in the scheme's launch configuration whatever `-configuration` is, names a simulator SDK supports that simulator only, whatever its `SUPPORTED_PLATFORMS` (loader-experiments `simulator-sdks`: `SimIOS`, `SimIOSBoth` with `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, `SimIOSDeviceOnly`, `PerConfigSimDebug` also with `-configuration Release`, `SimTV`, `SimWatch` and `SimXR` fail with an iOS destination, `PerConfigSimRelease` does not, nor does `LaunchRelease`, a scheme launching `PerConfigSimDebug` in Release; `simulator-sdks-project`: the project's `SDKROOT`); Xcode reads that `SDKROOT` itself, not as Swift Build evaluates it: from the levels (the target's configuration, its base xcconfig with its includes, the project's configuration, its base xcconfig) the highest with an assignment that applies decides, a conditional one before the plain one whatever their order; `[sdk=…]` applies to the target's own SDK, `[config=…]` to the launch configuration in an xcconfig only, and any other pattern, `[config=…]` in the project file included, only when it is `*`; the macros its value names are read the same way (`SimIOSSdkCondition` fails, `SimIOSConditional` does not, `DevIOSConditional` does; loader-experiments `simulator-sdk-conditions`: `SdkOfDestination`, `macosx` with `[sdk=iphoneos*] = iphonesimulator`, does not fail, `ConfigWildcard` and `ArchWildcard` fail, `ConfigPattern` (`[config=D*]`), `Arch`, `SdkAndConfig` and `MacroConfig` do not; in an xcconfig `Xcconfig`, `XcconfigConditionFirst` and `XcconfigWildcard` fail, `XcconfigReverse`, `XcconfigArch` and `XcconfigSdkOfDestination` do not; `ProjectFileMacroFromXcconfig` fails, `XcconfigMacroFromProjectFile` does not; `-project`, `-project-reverse`: the project's `SDKROOT[config=Debug]` does not apply). Other condition parameters and `$(inherited)` there are not observed; nomac takes Swift Build's value then. Any other target supports the platforms of its `SUPPORTED_PLATFORMS` (`DevIOSSimOnly` fails); an aggregate target also those of the targets it depends on, through other aggregates, but a native target not (loader-experiments `scheme-destinations`: `AggDepIOS` and `AggDeep`, macOS aggregates depending on an iOS framework, print their macOS block for an iOS destination; `MacFwDepIOS` fails; the fuzzer's `Lint`). What a scheme launches is its Launch action's `BuildableProductRunnable`, or the target a `RemoteRunnable`'s `MacroExpansion` names; a Profile action's runnable does not count (`LaunchTool`, which builds an iOS bundle and launches a macOS tool, fails, `ProfileTool` does not; `RemoteTool` fails; pocket-casts' `Pocket Casts Watch App` and home-assistant's `WatchWidgetsExtension` build an iOS app for running too, and launch a watchOS app and a watchOS extension). An autocreated extension scheme launches its first app (`ExtIOS18`, an iOS extension a macOS app depends on, fails, and `ExtMac19` does not; `autocreate-hosts`: `WatchWidget`, whose first app is a watch app) | `Could not configure request to show build settings: Unable to find a destination matching the provided destination specifier:` then `{ generic:1, platform:iOS }` on a line indented by two tabs |

For 64, xcodebuild then lists the destinations the scheme supports, which depend on the Mac
(its simulators and its identifier); nomac prints none. It also logs `Supported platforms for
the buildables in the current scheme is empty.` when the scheme builds nothing for running.
- Without `-scheme`, products go to `<project dir>/build` and target-mode caches to the
  per-user cache directory. With `-scheme`, products go to
  `~/Library/Developer/Xcode/DerivedData/<name>-<hash>`; see `DerivedData.folderHash` and
  docs/adr/0006-machine-specific-roots.md. `<name>` is the workspace's (or project's) name,
  decomposed, with each run of spaces, tabs, carriage returns and line feeds replaced by one
  `_`; `<hash>` hashes the decomposed path of what was opened (loader-experiments
  `derived-data-names`: `App 2` → `App_2`, ` Leading` → `_Leading`, `Space \t Tab` →
  `Space_Tab`, `Under_ Space` → `Under__Space`; vertical tabs, form feeds, other control
  characters, no-break and other Unicode spaces and all punctuation are kept;
  `derived-data-packages`: remote packages are checked out in the same folder). Names and paths
  derived from the project's path are decomposed too: `PROJECT_NAME`, `PROJECT_FILE_PATH`,
  `SRCROOT`, `PROJECT_TEMP_DIR` (pif.md "Unicode").
- A project opened alone whose project or target configurations, or their base xcconfig files,
  assign `SYMROOT` without a condition, in any configuration and to any value, keeps with
  `-scheme` the folders of every target's products, intermediates and precompiled headers
  (`SYMROOT`, `OBJROOT`, `SHARED_PRECOMPS_DIR`) where they are without it, a target that sets
  none under `<project dir>/build`, while its caches (`MODULE_CACHE_DIR`, `SDK_STAT_CACHE_DIR`,
  `COMPILATION_CACHE_CAS_PATH`) stay under DerivedData (loader-experiments `symroot-targets`:
  `Plain` in a scheme of its own; `symroot-project-*`: `SYMROOT` empty, `$(SRCROOT)/build`, a
  macro, in Debug or Release only; not `SYMROOT[sdk=iphoneos*]`, which applies, nor
  `SYMROOT[sdk=macosx*]`; envelope-experiments `unresolved-proxies`, `symroot-locations`).
  Through a workspace, DerivedData holds them all whatever `SYMROOT` is (`symroot-locations`;
  mattermost's Pods). With `-derivedDataPath` the same, its caches there
  (`symroot-project-none`, `-custom`: `-derived`). Only the opened project's assignments count,
  and they apply to the projects it references too (`symroot-references-sub`: a referenced
  project's `SYMROOT` changes nothing; `-top`: the referenced project's target goes under its
  own `build` folder).

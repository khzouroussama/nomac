# Macros: state

Workstream: Swift macro plugins on Linux. Apple's closed plugins, reimplemented (B-121, scope
decided by the owner: reimplement each macro from its observed expansions), and the plugins a
project brings itself (the owner, 2026-10-31: build them from their sources when they ship, else
`nomac check` reports them). Part of the build driver's range: BACKLOG B-150–B-169, ADRs
0150–0159. Branch `ws/macros`. Mechanisms: ADR 0150 (Apple's), ADR 0151 (the project's); rules:
docs/formats/macros.md.

## Current step

Milestone 7: corpus apps that use macros on Linux. Milestone 6 done: every Apple macro the corpus compiles is reimplemented (Previews, `@State`,
`@Entry`, SwiftData, Foundation's, TipKit, FoundationModels, AppIntents) and expands as Xcode's
on every corpus file that type-checks alone. Next: the forms no experiment covers (B-150, B-151,
B-156, B-157, B-158) as projects need them, and Linux builds of corpus apps that use the macros.
The expo-modules app's full Linux run (ADR 0151) is the RN holdout workstream's to make.

## App Intents metadata on Linux (B-107, assigned 2026-11-02)

`appintentsmetadataprocessor` and `appintentsnltrainingprocessor` for targets that use App
Intents, which stop icecubes (`ExtractAppIntentsMetadata` x4), home-assistant and every app with
widgets or shortcuts on Linux. nomac's `AppIntentsTools` (build driver) handles only targets
without App Intents. Its launcher exists in the installed toolchain: no shared toolchain edit is
needed, only `AppIntentsTools`. Experiments: `.github/scripts/app_intents_experiments.py
record` (outputs in `~/nomac-out/wt-scratch/appintents/exp`).

Observed (Xcode 27.0, `basic` and `no-shortcuts`):
- The metadata processor runs with `--compile-time-extraction`: its input is the Swift
  compiler's `.swiftconstvalues` (`--swift-const-vals-list`), which Swift Build requests with
  `-emit-const-values` and a protocol list from its own Apple platform plugin, on Linux too
  (icecubes' Linux log). swift.org 6.4.0's const values are Xcode's byte for byte
  (`basic`'s `Intents.swift`). They hold every type conforming to the listed protocols, its
  conformances, associated types and each property's initializer as a typed value tree
  (titles, descriptions, `IntentParameter` init calls, the parameter summary's interpolation,
  the App Shortcuts builder with phrases and its source line).
- It writes `Metadata.appintents/extract.actionsdata` (compact JSON, keys sorted: actions,
  entities, enums, queries, autoShortcuts, generator `xcode-tools`/`27A266a`, ...),
  `version.json` (`toolsVersion`, `version` "3.0"; Foundation's pretty style, ` : `), and the
  strings data (`ExtractedAppShortcutsMetadata.stringsdata`: Foundation's
  pretty style with `\/`, the provider's source path and line, `AppShortcuts` and `Localizable`
  tables). The `--dependency-file` it reads is the linker's `_dependency_info.dat`.
- The training processor generates `root.ssu.yaml` from `extract.actionsdata` and the
  Info.plist, then writes `nlu/nlu.lzfse` (a FlatBuffers file, LZFSE-compressed, of the expanded
  phrases) and `nlu/<hash>.version`. Its expansions come from YAML resources of Xcode's
  `Contents/Frameworks/SiriSSUKitModel.framework` (`prefix/<locale>.yaml`,
  `standardAppShortcutNegatives/<locale>.yaml`), which the `nomac sdk` subset now keeps.

Done (batch 1): `FoundationJSON` (Darwin Foundation's compact and pretty JSON), and
`AppIntentsMetadata`, which `nomac appintentsmetadataprocessor` runs for targets that use App
Intents: six experiments (`basic`, `no-shortcuts`, `queries`, `widget`, `dialogs`, `linked`)
compare identical to Xcode's outputs but for set order (`compare --nomac`), forms in
docs/formats/app-intents.md. Xcode's own outputs change from build to build in the order of
`resolvableInputTypes` and of `root.ssu.yaml`'s parameter variables (three builds of `basic`).
icecubes on Linux: the widget extension's metadata is written; its app stops at "a dependency of
the target has App Intents metadata" (its embedded widget extension). Next (B-159): dependencies'
metadata (an experiment with an app embedding an extension that has intents), then the training
outputs, `nomac verify`'s rule for set order, more parameter types, home-assistant.

Batch 2: dependencies' metadata (`embedded`: an app embedding a WidgetKit extension; the
extension's metadata adds nothing to the app's), `nomac verify`'s rule for set order
(`appintents.set-order`, also `typeSpecificMetadata`'s pairs, three builds of `types`), and
home-assistant's parameter forms (`types`). Eight cases identical but for set order. The Linux
measurement of this batch waits on the shared Docker daemon, which stopped answering on
2026-11-02 with the disk at 95%. Next: the training outputs (with `SiriSSUKitModel.framework`'s
YAML resources added to the `nomac sdk` subset), then home-assistant's schema intents.

Batch 3 (B-159 step 2): App Shortcuts training (`AppShortcutsTraining`, `FlatBufferBuilder`).
Found by running Xcode's training processor on its own: the metadata processor writes no
`root.ssu.yaml`; the training generates it from `extract.actionsdata` (batches 1 and 2 wrote it in
the wrong step). `nlu.lzfse` decoded and reproduced field by field; with the header's digest and
time equal it is byte-identical (`basic`, and the new `training` case: several phrases, enum and
entity parameters in phrases, a display name with an apostrophe). The strings data has one entry
per shortcut (`training`). Open: the digest's input (no MD5 or SHA of the YAML; nomac writes the
YAML's MD5) and `nomac verify`'s rule for `nlu/` (needs an LZFSE decoder), both in B-159. Shared
changes: the `nomac sdk` subset keeps the phrase lists, `NomacBuild` depends on `NomacLZFSE`.

Batch 4: an LZFSE decoder in NomacLZFSE (nomac's own, from the format its encoders write; small
shared change) and `nomac verify`'s rule for `nlu.lzfse`: the training's time is equivalent
(`appintents.training-time`), the digest a reported difference. A digest round (2,721
combinations of 128-bit, truncated and split hashes) found nothing; the digest stays in B-159.

Linux, 2026-11-02 (batches 2 to 4, developer directory installed again from a fresh `nomac sdk`
subset with the phrase lists, `~/nomac-out/scripts/linux_devdir.sh`; rebased on 159b2aed): the suite passes (878
tests). icecubes `nomac verify --build`: settings 190/190, strings 130/130, build 5/86 identical
and 70 equivalent; the widget extension's `Metadata.appintents` is identical to Xcode's; the
app's metadata stops at `InlinePostImageIntent`'s `ProvidesDialog & ShowsSnippetView` result, and
its training is localized (19 `<locale>.lproj/nlu.appintents/`), both B-159. home-assistant is not
measured: its corpus checkout has no objects and its reference no build.

Batch 5 (2026-11-02): result protocols as `outputFlags` and `enums` in name order (`results`);
localized App Shortcuts training (`localized`: 30 locales and Base, every `.lproj` folder trained
into its own `nlu.appintents`, translations from `AppShortcuts.strings`, `Localizable.strings`
and `InfoPlist.strings`, Siri's phrase lists by locale name or `pt` for `pt-BR`), 31 of 31
trainings identical but for digest and time. icecubes on Linux: the app's `extract.actionsdata`
byte-identical to Xcode's; its training, run on the build's product (the build itself stops
earlier at the asset catalog's `--include-all-app-icons`, B-202), gives `root.ssu.yaml` identical
but for set order and 19 of 19 locales identical but for digest and time. Two rules came from
icecubes' reference: entity names are translated as case titles are, and a scalar ending in a
blank is single-quoted.

Plan: (1) an Apple-style JSON writer (Darwin Foundation's compact and pretty output, which
corelibs Foundation does not reproduce); (2) the model from const values for intents,
parameters, entities, queries, enums and App Shortcuts, compared byte for byte on recorded
inputs (`app_intents_experiments.py compare`), widened by experiments per parameter type and
feature (widgets, controls, availability, assistant schemas, dependencies' metadata);
(3) `root.ssu.yaml` and the strings data; (4) the training outputs; (5) icecubes and
home-assistant on Linux.

## Which corpus apps need which macros

`macro_experiments.py survey` on the corpus checkouts (files that use each; Observation's and
Foundation's macros are open source and ship with swift.org's toolchain):

| App | Previews | `@State` | Others |
|---|---|---|---|
| firefox | 9 | 43 | |
| gomap | | 4 | |
| home-assistant | 460 | 172 | AppIntents 22 (21 expand) |
| icecubes | 10 | 86 | SwiftData 5, `@Query` 13, `@Entry` 1, FoundationModels 1 |
| kickstarter | 17 | 16 | `@Entry` 1 |
| mastodon | 1 | 26 | `@Entry` 2 |
| mattermost | | 10 | |
| netnewswire | 2 | 16 | |
| nextcloud | 46 | 42 | |
| pocket-casts | 148 | 186 | |
| signal | 82 | 11 | |
| swiftfin | | 118 | `@Entry` 14 |
| wikipedia | 7 | 11 | TipKit 3 |

14 of 20 apps compile Apple's macros; B-121's count (11) predates `@State`. firefox, gomap,
mattermost, netnewswire, nextcloud and signal need only the Previews macros and `@State`.

## Just finished

- A real Linux build of wikipedia (`nomac verify --build`, the Linux corpus workstream's
  `verify.sh`, developer directory installed from this branch): every Swift target compiles,
  WMFComponents' TipKit included (its object differs from Xcode's only by
  `swift_conformsToProtocol2`, Swift's code generation); pif 1/1, settings 638/638, strings
  99/99, build 7/42 identical and 17 equivalent, the rest resources. The build workstream's
  "plugin for module 'TipKitMacros' not found" came from a developer directory installed before
  TipKit's plugin: `nomac build` off macOS now warns about such an installation and names the
  missing modules (`MacroPlugins.missing`).
- icecubes on Linux: pif 1/1, settings 190/190, strings 130/130; its reference has no Xcode
  build, so `verify --build` compares no product (B-098).

- The three Linux differences (`preview-availability`, `preview-previewable`, `state-local`):
  all three are `@State` in local types, which swift.org's compiler expands with the macro and
  Xcode's with the property wrapper (swift.org's `CustomAttr::shouldPreferPropertyWrapperOverMacro`
  prefers the wrapper only for a variable in a function or closure itself, on `main` too). The
  objects: `@Previewable`'s view no longer gets an init accessor, whose dynamic access check
  (`swift_beginAccess`) both compilers emit in a closure-local type; its preview's object now
  differs from Xcode's only as any Swift object built with swift.org does. `linux` reports the
  three as "identical but for the @State of local types" (`linux`: 67 of 67).

- AppIntents (`AppIntentsMacros`, docs/formats/macros.md "AppIntents"): `AppEntityMacro`,
  `AppIntentMacro`, `AppEnumMacro`, `_UnionValueMacro`. Which members a schema marks is the
  plugin's own table; nomac's holds the 13 schemas home-assistant uses, observed in
  `appintents-calendar` and `appintents-reminders` (home-assistant's names and types on
  self-written types) and `appintents-forms` (names a schema lacks, existing attributes,
  `let`, public types, availability and documentation, unions). All three cases identical
  under Xcode's compiler and on Linux (`linux`: 64 of 67 cases, the other three the known
  Preview and local `@State` ones); home-assistant: 22 of 22 corpus files identical (142
  buffers). Forms and schemas without an experiment: B-158.

- FoundationModels (`FoundationModelsMacros`, docs/formats/macros.md "FoundationModels"):
  `GenerableMacro` (structs; enums plain, `String`-backed and with associated values, whose
  discriminated structs Xcode writes as nested types) and `GuideMacro`. All four
  `foundationmodels-*` experiments identical, diagnostics included, under Xcode's compiler and
  on Linux end to end (`linux`: 61 of 65 cases, the other four as before). icecubes' one file
  stops at its module's other types before expanding; its `Tags` is `foundationmodels-generable`'s.
  `facts` now addresses a lexical context declared in the middle of an earlier expansion
  (`.headAt`). Forms without an experiment: B-157.

- TipKit (`TipKitMacros`, docs/formats/macros.md "TipKit"): `ParameterMacro` and `RuleMacro`.
  `#Rule` translates its closure with swift-foundation 6.3's predicate code, the last release
  without module selectors, which TipKit's output matches (vendored with `donatedWithin` added,
  `Plugins/TipKitMacros/UPSTREAM.md`); several inputs split at `&&` and `||`. All six
  `tipkit-*` experiments identical, diagnostics included, under Xcode's compiler (`compare`)
  and on Linux end to end (`linux`); wikipedia's three corpus files identical (`corpus ...
  tipkit`). Forms without an experiment: B-156.

- SwiftPM's swift-syntax prebuilts (docs/formats/pif.md "Prebuilts"). Xcode 27.0's SwiftPM uses
  them; nomac's workspace kept SwiftPM's default `usePrebuilts: false`, which matched Xcode only
  on a Mac where Xcode's own `SourcePackages` state already listed them (macro-package's PIF
  differed once that state was moved away, and on Linux). nomac now uses them under Xcode's
  name, `swiftlang-6.4.0.34.1-macosx27.0` (`SwiftPackages.xcodePrebuiltName`), and off macOS
  puts SwiftPM's build of the same version for the installed compiler and this machine
  (`swift-6.4.0-RELEASE-ubuntu_noble_aarch64`) in that folder.
  - macro-package (a local package's `.macro` target on swift-syntax 604.0.0) with
    `nomac verify --build` on Linux: PIF 1 of 1 identical (0 of 1 before), settings 18 of 18;
    build products 1 of 6 identical, the dSYM and both modules equivalent. The app binary
    differs by the SwiftUICore binding (as macro-prebuilt's), and `Greet.o`, which holds only
    the macros' declarations, has `__TEXT,__text` and `__LLVM,__swift_modhash` only in nomac's:
    swift.org's compiler, not the macros (reported to the build driver).
  - On the Mac from an empty `DerivedData`: PIF identical, `SourcePackages/prebuilts` as
    Xcode's.

- A project's Mach-O macro plugins (ADR 0151, `.github/scripts/macro_plugin_experiments.py`,
  outputs in `~/nomac-out/wt-scratch/macros/plugins`). `nomac build` off macOS evaluates every
  target's `OTHER_SWIFT_FLAGS`; for a `-load-plugin-executable` whose executable is Mach-O and
  whose nearest `Package.swift` declares a macro target of its name, it builds that target with
  `swift build --build-system native --product <name>` in `scratch/macro-plugins` and puts its
  own flag first (Xcode's and swift.org's compilers use the first flag of a module: `order`).
  `nomac check` lists such a plugin as `build:macro-plugin=swift-package` (verified); one
  without a package stays `build:setting=mach-o-executable`, with the Expo workstream's hint
  naming npm's Linux builds.
  - macro-prebuilt (an app whose flags name a universal Mach-O built from `Plugin/apple`) on
    Linux with `nomac verify --build` against Xcode 27.0's Debug build: PIF and 12 of 12
    settings identical; build products 1 of 4 identical, the dSYM and `App.swiftmodule`
    equivalent; its expansions are Xcode's byte for byte (`expansions`: 2 of 2). The app binary
    differs, not by the macros: it binds five imports to SwiftUI and `libswiftDarwin` where
    Xcode's binds them to SwiftUICore and `libswift_Builtin_float`, as macro-package's does
    (reported to the build driver).
  - Expo: `expo-modules-macros/apple` built from its sources on Linux (2 min 23 s, debug,
    the package's folder unchanged) expands expo-haptics' module as the shipped Mach-O does
    under Xcode's compiler: 10 expansions, every diagnostic, byte for byte
    (`expo_experiments.py macros`).

- SwiftData (`SwiftDataMacros`): `PersistentModelMacro` (member, member attribute, extension),
  `PersistedPropertyMacro`, `TransformablePersistedPropertyMacro`, `TransientPropertyMacro`,
  `AttributePropertyMacro`, `RelationshipPropertyMacro`, `UniqueConstraintsMacro`, `IndexMacro`,
  `PersistentModelActorMacro` and `QueryMacro`. All 14 `swiftdata-*` experiments are identical,
  diagnostics included: models, access levels, property forms, attributes, relationships,
  `#Unique`/`#Index`, subclasses, doc comments, errors, `@ModelActor`, `@Query` forms.
  - On the Mac, under Xcode's compiler (`compare`: 14 of 14; two only print the compiler's own
    errors in another order).
  - In `NomacMacrosTests` (Mac and Docker): 52 cases, 1,429 uses. Member and extension requests
    now also carry the parent declaration, the conformance list and the extended type, as facts.
  - On Linux end to end (`linux`: 51 of 54 cases identical, all `swiftdata-*` among them). This
    needs `-Xfrontend -enable-cross-import-overlays`, which `linux` now passes; the other three
    are the known Preview and local `@State` differences.
  - The corpus (`corpus ... swiftdata`): all 18 icecubes files identical. 146 buffers come from the
    8 files that type-check alone (its five models, `AppView`, `TimelineTab`, `EditTagGroupView`).
    The 10 other view files stop at types from icecubes' other modules before `@Query`; their two
    forms (`@Query(sort:order:)`, bare `@Query`) are in `swiftdata-query`.
- `compare` and `linux` count a case as identical when only the compiler's own errors come in
  another order: the same buffers and lines.
- Cross-import overlays (B-154): Xcode's compiler loads `_SwiftData_SwiftUI` unasked (no flag in
  the driver's commands or in icecubes' build log). swift.org 6.4.0's on Linux loads it only with
  `-Xfrontend -enable-cross-import-overlays`, so `@Query` is "unknown attribute 'Query'" there.

- The review of `920f84f` (wf_dda847d4-f4e): its confirmed findings are fixed. The fixtures were
  captures (`301bc3f`); the corpus total is 8,234 buffers; `@State`'s access rule took
  `private(set)` for `private` and stored such state lazily, where Xcode stores it directly
  (`state-modifiers`: setter access never counts, `package` and `open` are kept); an `@Entry` of
  `FocusedValues` without a type is "Property missing a type annotation" with a fix-it, not "must
  be Optional", and attributed function types are warned about as closures
  (`entry-closures-focused`).

- `#Predicate`, `#Expression` and `#bundle` (B-152): swift-foundation's `FoundationMacros`
  (`swift-6.4.0-RELEASE`, vendored in `Plugins/FoundationMacros`) built with
  `FOUNDATION_FRAMEWORK`, as Xcode's platform copy is: `foundation-predicate` and
  `foundation-predicate-forms` identical, unsupported functions' errors included, under Xcode's
  compiler, in `NomacMacrosTests` and on Linux end to end.

- `@State` in local types (B-153): Xcode 27.0's compiler gives state in a type declared in a
  function, closure or property the `State` property wrapper and never asks the plugin
  (`state-local`: no expansion; its object calls `State.init(wrappedValue:)`), where swift.org's
  compiler applies the macro. `StateMacro` recognizes those types by their lexical context and
  gives the property wrapper's code: on Linux the objects of `state-local` and
  `preview-previewable` import the same Swift symbols as Xcode's; types local to a closure or a
  property also import `swift_beginAccess` and `swift_endAccess` (the init accessor the
  memberwise initializer needs), besides the stack checks and register-specific retains of
  ADR 0101.

- The mechanism (ADR 0150): nomac's plugins are swift-syntax libraries with Apple's module and
  type names, compiled by `nomac toolchain install` against the installed swift.org toolchain's
  own swift-syntax and installed in the platform's plugin directory, next to links to the
  toolchain's `swift-plugin-server` and its open-source plugins. Swift Build's compile commands
  are unchanged; a `.d` file names the plugin with `.so` where Xcode's has `.dylib`.
- `PreviewsMacros` (`SwiftUIView`, `SwiftUIViewGroup_1`, `KitViewMacro`, `PreviewCommonGroup`,
  `Common`, `Previewable`): 18 of 18 experiments identical to Xcode's expansions, diagnostics
  included (names, traits, spacing, `body:`, bodies, indentation, `@available` in every form
  observed, `@Previewable`, UIKit, `arguments:`, WidgetKit, errors):
  - on the Mac, under Xcode's compiler (`compare`: 18 of 18);
  - in `NomacMacrosTests`, through the test toolchain's `swift-plugin-server`, on the Mac (Xcode
    27.0's swift-syntax) and in Docker (swift.org 6.4.1's);
  - on Linux end to end (`linux`, swift.org 6.4.0 installed by `nomac toolchain install` into the
    `nomac sdk` subset): every Preview expansion identical; the two cases with `@Previewable
    @State` stop at `@State`, which waits on B-150. A `.d` file there names
    `Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins/libPreviewsMacros.so`.
- `SwiftUIMacros`: `@State` (`StateMacro` with `_PropertyWrapperProjectedValue`,
  `_StateProjectedValue`, `_StatePropertyWrapperStorage`, `_StateInitialStoredValue`) and `@Entry`
  (`EntryMacro`, `__EntryDefaultValue`, `_SwiftUIEntryTypeCheck`): all 10 `state-*` and 6 `entry-*`
  experiments identical, diagnostics included (directly and lazily stored state, types, optionals,
  attribute arguments, classes, actors, observers, spacing; the four `@Entry` containers, the type
  check for call values, closure and class warnings, every error), on the Mac (`compare`), in
  `NomacMacrosTests` (Mac and Docker) and on Linux end to end (`linux`: 33 of 36 cases identical; two
  Preview cases differ only by the nested expansions swift.org's compiler also prints, see B-153,
  and `#Predicate` differs, B-152).
- The corpus (`corpus`, Xcode's compiler with Apple's and with nomac's plugins): all 1,294 files of
  13 apps that use `#Preview`, `@State` or `@Entry` give the same expansions, 8,234 buffers
  (4,554 `@State`, 82 `@Entry`, 168 `#Preview` reached when a file is type-checked alone, and
  the helper macros).
- `@Observable` and `@ObservationIgnored` expand on Linux, with swift.org's plugin, as Xcode's do.
- `macro_experiments.py`: `record` (Xcode's expansions and the plugin protocol, through a logging
  `swift-plugin-server` the driver's `PLATFORM_DIR` puts first), `compare` (nomac's plugins under
  Xcode's compiler), `linux` (the installed swift.org compiler), `corpus` (every corpus file that
  uses a kind of macro, type-checked alone with Apple's and with nomac's plugins), `facts` (the
  tests' data: self-written sources, the compiler's addressing and digests of Xcode's answers).
- Captures stay out of the tree: `NomacMacrosTests` no longer reads recorded protocol logs (the
  `Fixtures` that `920f84f` added held Apple's plugins' answers verbatim; they remain in git
  history, whose purge is the owner's decision). The recordings stay in
  `~/nomac-out/wt-scratch/macros`.

## In flight

- Nothing.

## Next actions

1. icecubes' full build on Linux once B-202 (`--include-all-app-icons`) lands, to measure its
   training in the build.
2. B-159: more parameter types, home-assistant's schema intents (once its checkout is restored),
   the training digest's input.
3. icecubes on Linux once the build driver passes `-enable-cross-import-overlays` (B-154).
4. `nomac verify --build` of a corpus app that needs only Previews and `@State` (netnewswire or
   signal) on Linux, as far as the other workstreams' blockers allow.

## For the other workstreams

- App Shortcuts training reads `SiriSSUKitModel.framework`'s phrase lists from the developer
  directory's Xcode: a `nomac sdk` subset made before 2026-11-02 lacks them, so a target with App
  Shortcuts fails its `AppIntentsSSUTraining` task until the subset is made again.

- `nomac toolchain install` installs the macro plugins of the nomac that runs it: a developer
  directory installed by an older nomac lacks the modules added since (TipKitMacros,
  FoundationModelsMacros, AppIntentsMacros on 2026-10-31); install again into a fresh
  `nomac sdk` subset. `nomac build` warns about it.
- Build driver: Swift compiles on Linux need `-Xfrontend -enable-cross-import-overlays` to match
  Xcode's compiler, which loads cross-import overlays by default (B-154): icecubes' `@Query` comes
  from `_SwiftData_SwiftUI`.
- swiftfin, the build driver's first full app on Linux, needs `@State` (118 files) and `@Entry`
  (14 files): both are done. Its `@Observable` (3 files) expands identically with swift.org's
  plugin.

## How to reproduce

On the Mac (Xcode 27.0), outputs outside the repository:

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
S=.github/scripts/macro_experiments.py
python3 $S record ~/nomac-out/wt-scratch/macros/exp            # Xcode's expansions and protocol logs
python3 $S compare ~/nomac-out/wt-scratch/macros/exp           # nomac's plugins under Xcode's compiler
python3 $S facts ~/nomac-out/wt-scratch/macros/exp FoundationMacros PreviewsMacros SwiftDataMacros SwiftUIMacros > Tests/NomacMacrosTests/ObservedExpansions.swift
python3 $S corpus <corpus-checkouts> ~/nomac-out/wt-scratch/macros/corpus-run previews state swiftui swiftdata
swift build --build-tests -j 4 && swift test --skip-build --filter NomacMacrosTests
```

On Linux, with `nomac toolchain install` into a `nomac sdk` subset at Xcode's path and the
experiment directory at the Mac's path:

```sh
python3 .github/scripts/macro_experiments.py linux <exp-dir> /Applications/Xcode_27.app/Contents/Developer
```

A project's own plugins (`macro_plugin_experiments.py`, root `~/nomac-out/wt-scratch/macros/plugins`):

```sh
python3 .github/scripts/macro_plugin_experiments.py generate      # Mac: the three apps, the plugin binary
python3 .github/scripts/macro_plugin_experiments.py capture       # Mac: Xcode's Debug references
python3 .github/scripts/macro_plugin_experiments.py order         # Mac or Linux (--swiftc): which flag wins
python3 .github/scripts/macro_plugin_experiments.py expansions --plugin <exe> --sdk <sdk> --label xcode
# Linux, the developer directory installed at Xcode's path, the root at the Mac's path:
python3 .github/scripts/macro_plugin_experiments.py verify --nomac .build/debug/nomac
python3 .github/scripts/macro_plugin_experiments.py expansions --swiftc <installed swiftc> \
    --plugin ~/.nomac/scratch/macro-plugins/GreetMacros-*/debug/GreetMacros-tool --sdk <sdk> --label linux
```

`verify` replays the reference's environment, whose `TMPDIR` is the Mac's: create that folder in
the container, or the macro's link on Linux fails (`couldNotFindTmpDir`).

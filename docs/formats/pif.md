# PIF: how Xcode turns a project into Swift Build's input

The PIF (Project Interchange Format) is the JSON document Xcode hands to Swift Build. Swift
Build documents the format's purpose (`SwiftBuild.docc/Core/project-interchange-format.md`)
and its loader is open source (`Sources/SWBCore/ProjectModel/PIFLoader.swift` and siblings),
but how Xcode *produces* a PIF from a project file is not documented anywhere. This document
records that, as established by comparing `xcodebuild -dumpPIF` output for corpus apps
with nomac's output. Every rule names the corpus app that exercises it. Rules not yet
exercised by any corpus app are listed under "Open questions".

Reference: Xcode 27.0 (27A266a). Capture: `xcodebuild -dumpPIF <file> -project|-workspace <path>`.

## Document

A JSON array of top-level objects, in this order: the workspace, then for each project in
the order of the workspace's `projects` (path order, below) the project object followed by its
targets (netnewswire). A workspace
project's targets follow in project order; a package project's targets in the order of
"Swift packages" below. The projects a project references are projects of the workspace too
(see "Project references").

```json
[
  { "contents" : { ... }, "signature" : "WORKSPACE@v11_hash=(null)_subobjects=...", "type" : "workspace" },
  { "contents" : { ... }, "signature" : "PROJECT@v11_mod=..._hash=...plugins=...", "type" : "project" },
  { "contents" : { ... }, "signature" : "TARGET@v11_hash=...", "type" : "target" }
]
```

Package projects (SwiftPM packages the workspace depends on) appear as additional project
objects with `"projectIsPackage" : "true"`, after the workspace's own projects (netnewswire:
21 package projects; icecubes: 31). See "Swift packages".

### Text format

Exactly what Foundation's `JSONSerialization` writes on Apple platforms with
`[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`:

- two spaces of indentation per level, `" : "` between key and value, `,` at line end;
- an empty object is `{`, an empty line, then `}` at the object's indentation. An empty
  array is the same with `[` and `]`;
- strings escape `"`, `\`, and control characters (`\n`, `\r`, `\t`, `\b`, `\f`, others as
  `\u00XX`). `/` and non-ASCII characters are written as is;
- no trailing newline;
- **key order** is `.sortedKeys`'s, not byte order (loader-experiments `pif-key-order`, the same
  on about 10,000 random keys sorted by `JSONSerialization` itself). Characters compare by a fixed
  order: space `_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % \` ^ + < = > | ~ $`, then digits, then
  letters without regard to case. So `CLANG_WARN__DUPLICATE_METHOD_MATCH` comes before
  `CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING` (retro-rampage), and
  `PROVISIONING_PROFILE_SPECIFIER` before `PROVISIONING_PROFILE[sdk=iphoneos*]`. Digit runs compare
  by value (`a2` before `a10`). Among keys equal under those rules the first difference decides:
  the shorter run of digits, or lowercase before uppercase (`9b`, `9B`, `09b`). A letter with an
  accent or another non-ASCII letter sorts in Unicode's order in Xcode (`KEz`, `KÉz`, `KFz`, and
  `Kαz` and `K日z` after `Kzz`); nomac puts every non-ASCII character after all ASCII ones, by code
  unit (BACKLOG B-520).

### Values

Strings, arrays and objects only. Booleans are the strings `"true"` and `"false"`. The single
number observed is `provisioningStyle`.

## Identifiers (GUIDs)

- **Workspace:** `md5(<workspace name>)`, the lowercase hex MD5 of the name. For a bare
  `.xcodeproj`, the name is the project name: `md5("Rampage")` is
  `a9744fc5b0ca952b17ef07c0aa99602e` (retro-rampage).
- **Project:** `md5(<project path relative to the workspace's folder>)`: for a project opened
  on its own, its file name, for example `md5("Rampage.xcodeproj")` is
  `dfb26fd5fb1a9217e6667a819fd9d9f8` (retro-rampage, tofu); in a workspace,
  `md5("One/P.xcodeproj")`, so two projects with the same file name get different GUIDs
  (`loader-experiments`). A referenced project's path is relative to the same folder, the
  opened project's for a project opened on its own, with `..` resolved:
  `md5("moonlight-common/moonlight-common.xcodeproj")` (moonlight); `Deep/Deep.xcodeproj`,
  referenced from `Sub/Sub.xcodeproj` as `../Deep/Deep.xcodeproj` (`project-references`).
- **Every other object** (groups, file references, targets, configurations, build phases,
  build files, product references): the project GUID followed by `md5(<object ID>)`, where
  the object ID is that object's identifier in `project.pbxproj` as written: usually 24
  upper-case hexadecimal digits, but any string, its case kept (envelope-experiments
  `object-ids`: 32 digits as CocoaPods writes them, lower case, `B00001`, `OBJ_7`,
  `P::App::Target`, `APP_GROUP-3.x`). Example: the project's Debug configuration
  `016E41BF228E9A5E00ACF137` gets `dfb26fd5…d9f8` + `19876192b11e271bb738737170024fa7`.

Note for implementers on Linux: Swift Build's `String.md5()` is not MD5 there. Off Apple
platforms its `InsecureHashContext` is SHA-256. Implement MD5 yourself (RFC 1321).

## Signatures

Signatures are opaque transfer keys. Swift Build only requires them to be unique per type
within a document, and stable for an unchanged object. Xcode derives them from in-memory
state (`TARGET@v11_hash=<32 hex>`; `PROJECT@v11_mod=<32 hex>_hash=<project GUID>plugins=<…>`;
`WORKSPACE@v11_hash=(null)_subobjects=<32 hex>`). nomac uses the same prefixes with the MD5 of
each object's serialized contents. Comparisons replace each signature with `<TYPE-index>`.

## Workspace object

| Key | Value |
|---|---|
| `guid` | see Identifiers |
| `name` | workspace name (file name without `.xcworkspace`; for a bare project, the project name) |
| `path` | absolute path of the `.xcworkspace`; for a bare project `<…>/<Name>.xcodeproj/project.xcworkspace` |
| `projects` | project signatures: the workspace's projects and the projects they reference in path order, whatever order the workspace lists them in (`loader-experiments`: Kit/M, Apps/A, Core/A, Zeta/M are listed Apps/A, Core/A, Kit/M, Zeta/M; `project-references`: P.xcodeproj referencing Sub/Sub and Alpha/A gives Alpha/A, Deep/Deep, P, Sub/Sub), then package projects |

## Project object

| Key | Value |
|---|---|
| `appPreferencesBuildSettings` | `{}` |
| `buildConfigurations` | the project's configurations, in configuration-list order (see below) |
| `classPrefix` | `attributes.CLASSPREFIX`, or `""` |
| `defaultConfigurationName` | the configuration list's `defaultConfigurationName` |
| `developmentRegion` | `developmentRegion` |
| `groupTree` | the main group (see Group tree) |
| `guid` | see Identifiers |
| `knownRegions` | `knownRegions`, in order, with the development region first when it lacks it, then the regions of synchronized folders' localized items it lacks (see Synchronized folders), then those of the other variant groups (see Group tree) |
| `path` | absolute path of the `.xcodeproj` |
| `projectDirectory` | the directory containing the `.xcodeproj`, joined with `projectDirPath`, decomposed (loader-experiments `unicode-project-dir`, `unicode-project-dir-nfd`) |
| `targets` | target signatures, in the project's `targets` order |

`projectName` and `projectIsPackage` are omitted for Xcode projects.

### Build configurations

```json
{ "buildSettings" : { ... }, "guid" : "<GUID>", "name" : "Debug" }
```

`baseConfigurationFileReference` (the GUID of the xcconfig file reference) is added when the
configuration has a base configuration file (tofu). When the xcconfig lives in a synchronized
folder (`baseConfigurationReferenceAnchor` + `baseConfigurationReferenceRelativePath`), it is
the GUID of that folder member (netnewswire). Build settings are copied as written,
with one conversion: **a list value becomes a single string with the elements joined by one
space**, as they are, without quoting. `GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1",
"$(inherited)")` becomes `"DEBUG=1 $(inherited)"` (retro-rampage); the elements `"-D",
"FLAG WITH SPACE", "quote\"inside"` become `-D FLAG WITH SPACE quote"inside`, so an element
with a space becomes several words (`loader-experiments`; `-showBuildSettings` shows the same).
Settings with conditions (`KEY[sdk=iphoneos*]`) keep the condition in the key.

## Group tree

The main group and its descendants. Children that are the product reference of any target
in the project are removed (they appear inside their targets instead). `children` is omitted
when a group has no remaining children (retro-rampage's `Products` and `Frameworks` groups).

| Element | Keys |
|---|---|
| group (`PBXGroup`) | `guid`, `name`, `path`, `sourceTree`, `type: "group"`, `children` |
| variant group (`PBXVariantGroup`) | `guid`, `name`, `path`, `sourceTree`, `type: "variantGroup"`, `children` |
| file (`PBXFileReference`) | `guid`, `path`, `sourceTree`, `type: "file"`, `fileType`, optional `fileTextEncoding`, `regionVariantName`, `expectedSignature` |

- Group `name`: the group's `name`, else the last component of its `path`. The main group's
  name is the project name, even when the main group has a `name` of its own (loader-experiments
  `root-group-name`, `-name-path`; wordpress's `CustomTemplate`). `path` is `""` when absent.
- File references have no `name` key. `fileType` is `explicitFileType` when Xcode knows that
  type, else `lastKnownFileType` when Xcode knows it, else the type of what is on disk, by the
  rules of synchronized folders' items (loader-experiments `declared-types`: every type of
  Swift Build's specifications, declared on a file, a folder and a path not on disk, is kept,
  whatever the path's extension; the types the specifications lack are not). signal's Pods
  project declares its module maps `sourcecode.module`, which becomes `sourcecode.module-map`;
  `wrapper.mlmodelc` on a plain file becomes `text`, on a folder `wrapper`; with no declared
  type at all, `a.swift` is `sourcecode.swift`. `file` and `wrapper.framework.static` are kept as
  `explicitFileType` but typed again as `lastKnownFileType` (cwa's binary `api-response-*`
  files stay `file`; a `.swift` file declared `file` becomes `sourcecode.swift`). A folder with
  no type of its own is a `folder`. The path is resolved from the reference's group,
  `SOURCE_ROOT` or an absolute path; Xcode also finds `SDKROOT` and `DEVELOPER_DIR` paths,
  which nomac types as paths not on disk (BACKLOG B-033). The type found is the one
  `fileTextEncoding` and `predominantSourceCodeLanguage` go by (`declared-types-2`: `x.png`
  declared `nomac.unknown` with `fileEncoding = 4` has no `fileTextEncoding`;
  `declared-language`: two `.swift` files declared `file` count for Swift).
- `fileTextEncoding` is the IANA character-set name of `fileEncoding`: `4` → `"utf-8"`
  (retro-rampage). The full table nomac uses follows CoreFoundation's
  `CFStringConvertEncodingToIANACharSetName`. 104 file types never carry it, whatever their
  `fileEncoding`: images except SVG and HEIC, audio, video, archives, compiled code, folders,
  most wrappers, and `file.xib`, `file.storyboard`, `file.bplist`, `file.sks`, `file.skybox`,
  `file.uicatalog`, `file.playground`, `file.xcplaygroundpage`, `file.scp` (cwa's xibs;
  loader-experiments `file-encodings`, every file type of Swift Build's specifications and the
  common ones they lack, 206 in all; the list is `typesWithoutTextEncoding`), and `file`, the
  type found counting, whatever was declared (`declared-encodings`: a declared `file`, binary
  and missing files typed `file`; mattermost's fonts, declared `explicitFileType = undefined;
  lastKnownFileType = unknown; fileEncoding = 9`; no `file` of the 20 corpus references has
  one). Every other type keeps it (`declared-encodings`: a `.ttf` holding text, typed `text`).
- Inside a variant group, each child file carries `regionVariantName`: the name of the
  `.lproj` folder that holds it on the file system, its groups' paths included, without the
  extension, whatever the child's `name` (loader-experiments `lproj-groups`: `L1.strings` in a
  group whose path is `x/ar.lproj` is `ar`, as mattermost's `Localizable.strings` in its
  `ar.lproj` groups are, and `../sv.lproj/L7.strings` there is `sv`; `"Base"`
  for `Base.lproj/Main.storyboard`, retro-rampage; loader-experiments `variant-regions`:
  `name = Base; path = fr.lproj/…` is `fr`, `sub/fr.lproj/…` is `fr`, `fr.lproj/de.lproj/…` is
  `de`, `FR.lproj/…` is `FR`, a child without a name in `Base.lproj` is `Base`;
  `regions-classic-2`: `name = Foo; path = it.lproj/F.strings` is `it`).
  A child whose path is not directly in a `.lproj` folder (`X.strings`,
  `nl.lproj/sub/N.strings`, `nl.LPROJ/…`, `es.lproj.txt/…`; `lproj-groups`: a group only
  named `it.lproj`) is listed in the variant group's parent, just before the variant group,
  under the variant group's path if it has one (`lproj-groups`: `sub/L4.strings` for a variant
  group whose path `sub` is inside `es.lproj`), and the variant group is not listed when no
  child is left
  (`regions-classic-3`: children `ko`, `M.strings`, `ja` give the file `M.strings`, then the
  variant group with `ko` and `ja`; `variant-regions`; `regions-case`: `.lproj/B.strings`;
  envelope-experiments `variant-groups`: alone, first or among others, in a Sources phase too).
  A variant group with no children at all is listed. A build file that names the variant group
  names those children too (see Build files).
- Variant groups add the regions of their children that `knownRegions` lacks, after those of
  synchronized folders: Base too, `mul` never (`regions-classic`, run four times: `af` and `ko`
  of two folders, then `de, ja, es-419`, `zu, fr`, `it`, `pt-BR` of four variant groups). Each
  variant group's regions come in child order, but the variant groups come in an order that
  changes from one run to the next; nomac adds them in group-tree order (BACKLOG B-030). A
  region is added as Foundation's `canonicalLocaleIdentifier` spells it on a Mac when that
  changes only case and separators, else as it is written, and regions with the same spelling
  match (`regions-case`, `-4`, `-5`, `-6`, `variant-regions`: all 159 regions observed). So
  the names of 115 languages Foundation knows are kept (`English`, `French`, `Nynorsk`), other
  words lowercased (`Klingon`, `ENGLISH`), the first subtag of a tag lowercased, a script
  titled and joined with `-`, a region uppercased with its own separator, the subtags after a
  region joined with `_` uppercased (`Es` → `es`, `zh_hans` → `zh-Hans`, `Zh-HANT-tw` →
  `zh-Hant-TW`, `Portuguese_BR` → `portuguese_BR`, `Norwegian_Nynorsk` → `norwegian-nynorsk`);
  any case of `base` is `Base`. `De` after `de` adds nothing, `fr` matches a listed `Fr`, `base`
  and `BASE` match `Base`, but `German` and `german` are both added; `mul` in any case never is.
  nomac writes these rules out (`canonicalRegion`, `languageNames`): Foundation spells regions
  otherwise off Darwin. When `knownRegions` lacks the development region, matched exactly, it
  comes first (`regions-classic-3`: `developmentRegion = pt`, `knownRegions = (fr, de)` give
  `pt, fr, de, …`; `regions-classic-4`: an empty list gives `en, …`; `regions-case-2`: `EN`
  goes first next to `en`).
- `sourceTree` is copied as written (`<group>`, `<absolute>`, `SOURCE_ROOT`,
  `BUILT_PRODUCTS_DIR`, `SDKROOT`, `DEVELOPER_DIR`, or another setting name).

## Target object (native targets)

| Key | Value |
|---|---|
| `buildConfigurations` | as for projects |
| `buildPhases` | in the target's `buildPhases` order (see below) |
| `buildRules` | the target's build rules (see "Build rules" below) |
| `classPrefix` | the project's `CLASSPREFIX` when the project sets it, empty or not; absent otherwise (`loader-experiments` `class-prefix`, `-empty`, `-unset`) |
| `dependencies` | `{ "guid": <target GUID>, "name": <target name> }` per target dependency, with `platformFilters` when it has some; a target of another project of the workspace, through a project reference, is named `<target> (from <Project>.xcodeproj)` (`loader-experiments`; moonlight: `moonlight-common (from moonlight-common.xcodeproj)`), without `guid` when that target does not resolve: its project is not on disk (`project-references-missing`) or has neither an object with its ID nor a target its proxy's `remoteInfo` names (`project-references-stale`; `project-references-renamed`, delta's Harmony: a stale ID resolves by that name). A proxy into the target's own project resolves the same way, the dependency's `target` missing or naming no object; one that does not keeps its place as `{name}` (its `remoteInfo`, else the dependency's `name`), or `{}` without either (`dependency-proxies`; session's `SessionUtil`); then `{ "guid": "PACKAGE-PRODUCT:…", "name": <product> }` per build file of the target's first Frameworks phase that names a package product, the ones Xcode adds there for unlinked `packageProductDependencies` included, each with its own `platformFilters`. Nothing is merged: a target, product or product object named twice is listed twice; a product only another phase names (a copy-files phase that embeds it, a second Frameworks phase, Resources, Sources) is not listed (loader-experiments `product-duplicates`, 33 targets; home-assistant's `WatchApp` links `PromiseKitDynamic` through one object and embeds it through another: listed once; swiftfin's app links `StatefulMacros` through eleven: eleven entries) |
| `guid`, `name` | |
| `performanceTestsBaselinesPath` | test bundles (`bundle.unit-test`, `bundle.ui-testing`, `bundle.ocunit-test`) whose product's name (see "Product names") has the extension `xctest`: `<project>.xcodeproj/xcshareddata/xcbaselines/<target object ID>.xcbaseline`, **whether or not it exists** (tofu); an OCUnit bundle's `.octest` product has none unless its `WRAPPER_EXTENSION` is `xctest`, a unit test bundle whose `WRAPPER_EXTENSION` is `octest` has none (envelope-experiments `survey-shapes-3`: `ocunit-tests`, `ocunit-xctest-extension`, `unit-test-octest-extension`) |
| `predominantSourceCodeLanguage` | `Xcode.SourceCodeLanguage.Swift` and siblings: the language of the file type with the most files among the target's build files in every phase, synchronized members a phase of the target receives included (a file only in the group tree counts for none). Files count by type, not by language: three `.swift` files beat two `.h` and two `.mm` files, both Objective-C++ (loader-experiments `language-types`; `language-bisect`: one file of each of 37 types gives AppleScript). A tie goes to the language that comes first in this order, observed on every pair of 42 types (`language-pairs`): Ada\*, AppleScript, Intel-Assembly, Assembly\* (`sourcecode.asm`, `sourcecode.asm.asm`), C, Clips, C-Plus-Plus, DTrace, Dylan\*, Fortran, Fortran90, GLSL, Java, JavaScript, LLVM, Makefile, Markdown, Metal, ModuleMap, NQC\*, Objective-C, Objective-C-Plus-Plus, OpenCL, Pascal\*, Protobuf, Rez\*, Swift (`languageOrder`; icecubes' action extension, one `.swift` source and one `.js` resource, is JavaScript). The languages marked \* are those of `sourcecode.ada`, `.asm`, `.asm.asm`, `.dylan`, `.nqc`, `.pascal` and `.rez`, which the PIF does not name: when one wins, the key is absent (`language-weights`: two `sourcecode.ada` files and one Objective-C file; codegen-file-types, where `sourcecode.ada` ties with every other type). 35 file types count for a named language (`sourceCodeLanguages`): headers `sourcecode.c.h` for Objective-C++ and `sourcecode.cpp.h` for C++ (cwa's CWASQLite, two headers and one C file: Objective-C++), lex, yacc and iig files for Objective-C++, TypeScript for JavaScript, Metal, Markdown, `file.swiftpm-manifest` for Swift, and others; scripts, `sourcecode` itself, exports and MIG files count for none (`source-languages`, a target of one file of each of 211 types; `language-weights`). When no build file counts for a language, the target's synchronized candidates decide: the items of each folder it lists of the kinds of its phases (Sources, Headers, Frameworks, Resources), those its exception sets remove included, and the items the exception sets of other folders name for it (`language-fallback`, `language-synchronized`: an app whose only Swift file is excluded is Swift, one without a Sources phase has no language; an assembly member that wins leaves the key out, with no fallback). Candidates count once per file type, not per file, so the order above alone decides among them, and a path an exception set names that is not on disk is a candidate of its extension's type (`language-fallback-missing`: three excluded `.swift` files and one `.m` give Objective-C, as do one `.m` and three `.swift` paths not on disk; three `.m` files and one `.c` give C) |
| `productReference` | `{ "guid": <GUID of the product file reference>, "name": <the product's name, see "Product names">, "type": "product" }` |
| `productTypeIdentifier` | `productType` |
| `provisioningSourceData` | one object per configuration (below) |
| `type` | `"standard"` |

`provisioningSourceData` entries are `{ "bundleIdentifierFromInfoPlist", "configurationName",
"provisioningStyle" }`. `bundleIdentifierFromInfoPlist` is the raw `CFBundleIdentifier`
string of the Info.plist named by that configuration's `INFOPLIST_FILE`, relative to the
project directory (`"$(PRODUCT_BUNDLE_IDENTIFIER)"` in retro-rampage). `INFOPLIST_FILE` is
looked up in the target configuration, its base xcconfig (with `#include`s), the project
configuration of the same name and its base xcconfig (netnewswire, icecubes); written with
macros, or with an SDK condition at any of those levels, it is evaluated as build settings are,
for the target's SDK (flappy-fly-bird: `$(SRCROOT)/FlappyFlyBird/Info.plist`;
loader-experiments `infoplist-macros`: `${SRCROOT}`, `$(PROJECT_DIR)`, `$(TARGET_NAME)`,
`$(PRODUCT_NAME)`, custom and nested macros, `INFOPLIST_FILE[sdk=iphoneos*]` alone, and
`[sdk=macosx*]` beside a plain value, which keeps the plain one; `info-plist-conditions`:
`[sdk=iphonesimulator*]` alone names no plist, nor do `[arch=…]` and `[config=…]` conditions).
Written with a condition, a setting nomac reads itself takes the assignment Xcode chooses, as for
`CODE_SIGN_STYLE` below: the highest level that assigns it decides, with its assignment whose
conditions are all `[sdk=…]` patterns matching the target's SDK before its plain one, whatever
their order in an xcconfig (`xcconfig-conditions`: `PRODUCT_NAME` and `GENERATE_INFOPLIST_FILE`,
both orders), where Swift Build takes an xcconfig's last assignment and applies `config`
conditions. nomac evaluates such values with Swift Build, on a first generation of the PIF, and
generates the PIF again. When the file does
not set `CFBundleIdentifier`, or there is no file, and `GENERATE_INFOPLIST_FILE` is true, the
value is `"$(PRODUCT_BUNDLE_IDENTIFIER)"` (netnewswire's test targets, icecubes).
`GENERATE_INFOPLIST_FILE` is looked up and evaluated the same way and read as `NSString.boolValue`
reads a string: after spaces and tabs, `Y`, `y`, `T`, `t` or a digit from 1 to 9, or a sign or
leading zeros followed by such a digit (`yes`, ` YES`, `true`, `7`, `+1`, `007` are true; `on`,
`0Y`, `+YES`, `-0` and a leading newline are not). Unset, it is true for
`application.watchapp2-container` only, among 28 product types (`info-plist-conditions`).

`provisioningStyle` comes from the configuration's `CODE_SIGN_STYLE`, looked up and evaluated
the same way (conditions included: `CODE_SIGN_STYLE[sdk=iphoneos*] = Manual` in a target or its
xcconfig counts for an iOS target, `[sdk=macosx*]` does not; within a level, see below): `1`
when it is `Manual` (case-sensitive), `0` when it is anything else that is not empty (`manual`,
`Bogus`), even when
the target names a profile. When no level sets it, it is `""`, or it evaluates to nothing, the
target's style decides, the same for each such configuration and whatever the configuration
list's default:

1. the project's `TargetAttributes` `ProvisioningStyle`: `1` for `Manual`, else `0`, even when
   the target names a profile;
2. otherwise `1` if any configuration of the target, one that sets a style included, evaluates
   `PROVISIONING_PROFILE_SPECIFIER` or `PROVISIONING_PROFILE` to a string that is not empty (a
   blank counts), at any level, with macros, in an xcconfig or with a condition for the target's
   SDK, or evaluates `CODE_SIGN_IDENTITY` to `-` or to nothing; else `0`. A condition for another
   SDK, a macro that evaluates to nothing, `DEVELOPMENT_TEAM`, or any other identity
   (development, distribution or Developer ID) do not count. `-` is the macOS default when no
   `DEVELOPMENT_TEAM` is set, so macOS targets that set no style get `1` (loader-experiments
   `provisioning-defaults`: nine product types and aggregate targets on iOS, `0`, and on macOS,
   `1`; `-` or no identity in one configuration, through a macro or an SDK condition too, gives
   `1` to every configuration that sets no style). A target whose `SDKROOT` is `auto`, which
   `-showBuildSettings -target` leaves without an identity, signs as for macOS: `1` without a
   `DEVELOPMENT_TEAM`, `0` with one, whatever its `SUPPORTED_PLATFORMS` (loader-experiments
   `provisioning-auto`: apps for iOS, macOS or both, in either order, and frameworks, tools, test
   bundles and extensions; nomac evaluates its `CODE_SIGN_IDENTITY` with `SDKROOT=macosx`). An identity assigned at one level both with
   and without a condition is the SDK's conditional one, in the target's settings and in an
   xcconfig, whichever side holds `-` or nothing, as `-showBuildSettings` evaluates it
   (envelope-experiments `identity-conditions`: `CODE_SIGN_IDENTITY = -` beside
   `[sdk=iphoneos*] = Apple Development` is `0`, the reverse `1`; a simulator condition does not
   apply to the iOS target).

Observed: cwa (per configuration), netnewswire (the attribute), mastodon (`Profile` and
`Release Snapshot` set no style and each target's `Release` sets
`PROVISIONING_PROFILE_SPECIFIER = ""` beside `"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
= "match AppStore …"`: 1), loader-experiments `provisioning-style` (a project-level
`CODE_SIGN_STYLE` overrides the attribute too), `provisioning-fallback` and
`provisioning-fallback-project(-debug)` (no fallback to the default configuration's style),
`provisioning-profile` and `provisioning-profile-project` (26 and 6 targets),
`provisioning-defaults` (62 targets). nomac evaluates every configuration of the targets whose
style these settings can decide with Swift Build: no attribute, and some configuration whose
`CODE_SIGN_STYLE` is unset, empty or evaluated.

For these values Xcode does not evaluate an xcconfig as `-showBuildSettings` does. Within one
level (a configuration's own settings, or its base xcconfig with what it includes), an assignment
whose SDK condition matches the target beats the unconditional one whatever their order, and a
higher level still beats a lower one; `-showBuildSettings` takes the xcconfig's last matching
assignment (loader-experiments `provisioning-conditions`: `CODE_SIGN_STYLE[sdk=iphoneos*] =
Automatic` then `CODE_SIGN_STYLE = Manual` in one xcconfig, or across an `#include`, gives `0`
where `-showBuildSettings` says Manual; `[sdk=iphoneos*] = Manual` then `= Automatic` gives `1`
where it says Automatic; a target's own `Manual` over its xcconfig's condition gives `1`;
home-assistant's project-level `HomeAssistant.release.xcconfig` gives `0` for 14 Release
configurations). For `CODE_SIGN_STYLE`, nomac picks the assignment this way, reading each level
and the files it includes itself, and has Swift Build evaluate the chosen value for the target.
Several matching assignments in one level, conditions other than `sdk`, `$(inherited)` in the
chosen value, and `INFOPLIST_FILE` and the profile settings assigned both ways are not observed
(BACKLOG B-026): nomac takes the level's last matching assignment, counts one with another
condition as not matching, leaves a value with `$(inherited)` and the other settings to Swift
Build, and so follows `-showBuildSettings` there.

**Aggregate targets** (`"type" : "aggregate"`) have `guid`, `name`, `buildConfigurations`,
`buildPhases`, `buildRules`, `classPrefix` (as native targets), `dependencies` and
`provisioningSourceData` (its `bundleIdentifierFromInfoPlist` empty), and no product. **Legacy targets** (`"type" :
"external"`) have `toolPath`, `arguments`, `workingDirectory` and
`passBuildSettingsInEnvironment` instead of phases (`loader-experiments`).

### Build rules

Each rule has `guid`, `name`, `compilerSpecificationIdentifier`, `fileTypeIdentifier`,
`inputFilePaths`, `outputFilePaths`, `inputFileListPaths` and `outputFileListPaths` (always empty,
whatever the project file says) and `runOncePerArchitecture`: `"false"` when the rule says 0,
`"true"` otherwise, the key left out included (the fuzzer's rules; loader-experiments
`build-rule-keys`, 31 rules). The other keys depend on the rule:

- `filePatterns` only when the file type is `pattern.proxy`, whatever the compiler, `""` when the
  rule has none; a rule of another file type drops its patterns;
- `scriptContents` only for the script compiler (`com.apple.compilers.proxy.script`), `""` when
  the rule has no script; other compilers drop theirs (also every compiler of `build-rules`);
- `outputFilesCompilerFlags` when the rule has some: one array per entry, split into words as a
  shell splits them (`-DA="x y" -DB='p q' -DC\ D  -E` gives `-DA=x y`, `-DB=p q`, `-DC D`, `-E`; an
  empty entry gives `[]`), however many outputs there are;
- `dependencyFileFormat: "makefile"` and `dependencyFilePaths: [<dependencyFile>]` when the rule
  has a `dependencyFile`, an empty one included;
- `isEditable` changes nothing.

A rule without a name is named `<files> using <compiler>`: `Files '<patterns>'` for
`pattern.proxy` (`Files ''` without patterns), else the file type's description (`C source files`)
or `(null)`, then the compiler's name (`Script`, `Apple Clang`) or, for compilers Xcode has no
name for, the identifier (gomap: `Files '*.secret' using Script`; loader-experiments
`build-rules`, 82 compilers and 206 file types). An empty name stays empty.

### Product names

`productReference.name` is the target's `FULL_PRODUCT_NAME`, not the reference's path,
evaluated in the target's Debug configuration, else its first (Alpha of Alpha, Beta, Gamma
whose default is Beta; Debug of Release, Debug), and decomposed (NFD): `.app` for an app
without `PRODUCT_NAME`, `Dynamic.dylib` for a dynamic library whose reference is
`libDynamic.dylib`, `libName.a` for a static library, `Name` for a tool, `Café.app` decomposed
for `$(TARGET_NAME)` and for a literal name alike; `$(inherited)`, xcconfig values, custom
macros, `$(TARGET_NAME:c99extidentifier)`, `[sdk=iphoneos*]` conditions (not `[arch=…]`, and
chosen as for `INFOPLIST_FILE` above) and `WRAPPER_EXTENSION`, `EXECUTABLE_EXTENSION`,
`EXECUTABLE_PREFIX` all apply (loader-experiments
`product-names`, `product-names-configurations`, `product-names-order`). nomac computes the
name itself when `PRODUCT_NAME` is unset, literal or `$(TARGET_NAME)` and no level sets a
setting that changes the prefix or suffix, and has Swift Build evaluate `FULL_PRODUCT_NAME`
otherwise. Prefix and suffix by product type: `.app` (applications, App Clips, iMessage and
watch apps and their iOS containers), `.appex` (app, ExtensionKit, sticker, iMessage, Xcode,
intents, watch and TV extensions), `.framework` (static too), `.xpc`, `lib….a`, `.dylib`,
`.bundle`, `.xctest`, `.octest`, `.systemextension`, `.dext`, `.instrdst`, `.metallib`, none for
tools.

A product type that does not exist for the target's platform keeps the reference's path as
written, not decomposed (`product-types-sdks`, 30 types under seven SDK settings;
`product-types-restricted`, `product-types-other`, `product-names-no-sdk`): `watchapp2`,
`watchkit2-extension` and `app-extension.intents-service` exist on watchOS only, `tv-app-extension`
on tvOS only, `xcode-extension` on macOS only, `application.watchapp` and `watchkit-extension`
nowhere, and an unknown type nowhere. The platform is SDKROOT's: the device and simulator SDK
names of iOS, watchOS, tvOS and visionOS name theirs, anything else is macOS (`auto`, `auto` with
`SUPPORTED_PLATFORMS = watchos`, an empty value, no SDKROOT at any level, `macosx27.0`, and
`watchos26.0`, which no installed SDK has; BACKLOG B-073).

**Version groups** (`XCVersionGroup`, `.xcdatamodeld`) are `"type" : "versionGroup"` nodes
with their versions as children and the `fileType` of their extension
(`wrapper.xcdatamodeld`, although `versionGroupType` is `wrapper.xcdatamodel`;
`loader-experiments`).

## Build phases

Common keys: `guid`, `type`, `buildFiles`, and `runOnlyForDeploymentPostprocessing: "true"`
only when the phase sets it.

| pbxproj | `type` | Extra keys |
|---|---|---|
| `PBXSourcesBuildPhase` | `com.apple.buildphase.sources` | |
| `PBXHeadersBuildPhase` | `com.apple.buildphase.headers` | |
| `PBXFrameworksBuildPhase` | `com.apple.buildphase.frameworks` | |
| `PBXResourcesBuildPhase` | `com.apple.buildphase.resources` | |
| `PBXCopyFilesBuildPhase` | `com.apple.buildphase.copy-files` | `destinationSubfolder`, `destinationSubpath` (= `dstPath`). The phase name is not recorded |
| `PBXShellScriptBuildPhase` | `com.apple.buildphase.shell-script` | `name`, `shellPath`, `scriptContents`, `inputFilePaths`, `outputFilePaths`, `inputFileListPaths`, `outputFileListPaths`, `emitEnvironment` (`showEnvVarsInLog`), `alwaysOutOfDate`, `alwaysRunForInstallHdrs: "false"`, `sandboxingOverride: "basedOnBuildSetting"`, `originalObjectID` (the phase's object ID), and `buildFiles: []` (tofu) |

`destinationSubfolder` by `dstSubfolderSpec`, whatever the `dstPath` and the target
(loader-experiments `copy-files`: every value, with no, an empty, a relative and an absolute
`dstPath`, in a macOS tool and an iOS app; wikipedia's `localization` and `languages` copy man
pages with 0 and `/usr/share/man/man1/`; retro-rampage: 10):

| `dstSubfolderSpec` | `destinationSubfolder` |
|---|---|
| 0, or none | `""` |
| 1 | `$(WRAPPER_NAME)` |
| 2 | `$(INFOPLIST_PATH)` |
| 3 | `$(PKGINFO_PATH)` |
| 4 | `$(EXECUTABLE_PATH)` |
| 5 | `$(CONTENTS_FOLDER_PATH)` |
| 6 | `$(EXECUTABLE_FOLDER_PATH)` |
| 7 | `$(UNLOCALIZED_RESOURCES_FOLDER_PATH)` |
| 8 | `$(PUBLIC_HEADERS_FOLDER_PATH)` |
| 9 | `$(PRIVATE_HEADERS_FOLDER_PATH)` |
| 10 | `$(FRAMEWORKS_FOLDER_PATH)` |
| 11 | `$(SHARED_FRAMEWORKS_FOLDER_PATH)` |
| 12 | `$(SHARED_SUPPORT_FOLDER_PATH)` |
| 13 | `$(PLUGINS_FOLDER_PATH)` |
| 14 | `$(SCRIPTS_FOLDER_PATH)` |
| 15 | `$(JAVA_FOLDER_PATH)` |
| 16 | `<builtProductsDir>` |
| 17 | `$(EXECUTABLE_PATH)` |

On 18 and above, `-dumpPIF` and `-showBuildSettings` stop with SIGTRAP (a shell reports 133)
and `-list` succeeds (`copy-files-18`, and 19, 20 and 99 tried by hand); nomac fails with 133
(BACKLOG B-040). XcodeProj reads only 0, 1, 6, 7 and 10 to 16, so nomac reads the other values
from the project file.

Xcode 26 and later write `dstSubfolder = <name>` instead of `dstSubfolderSpec` (survey projects at
objectVersion 90, 100 and 110: `PlugIns`, `Product`, `Frameworks`, `Wrapper`). Xcode 27.0 reads
nine names (envelope-experiments `dst-subfolders`): `None` → `""`, `Wrapper`, `Executables`,
`Resources`, `Frameworks`, `SharedFrameworks`, `SharedSupport` and `PlugIns` → the same
destinations as specs 1, 6, 7, 10, 11, 12 and 13, and `Product` → `<builtProductsDir>`. On any
other name (`AbsolutePath`, `JavaResources`, `Products`, `XPCServices`, `SystemExtensions`,
`ExtensionKitExtensions`) every command, `-list` included, aborts (SIGABRT, a shell reports 134);
nomac fails with 134 for the PIF only.

### Build files

`{ "guid", "fileReference": <file GUID> }`, or **`"targetReference": <target GUID>` when the
file is the product reference of a target** of the project (retro-rampage links and
embeds `Engine.framework` this way; `workspace-twins`: in two projects with the same object
IDs, each app's build file names its own project's framework) or a `PBXReferenceProxy` for one
in a referenced project (moonlight links `libmoonlight-common.a` this way), found by the product's
ID, else by the container proxy's `remoteInfo` as a target name (`project-references-renamed`;
delta's Harmony and CwlPreconditionTesting). A proxy whose product does not resolve, because its
project is not on disk or has neither,
gives `{ "guid", "fileType": <the proxy's fileType>, "name": <its path> }` (`project-references-missing`,
`project-references-stale`). Its GUID is the project GUID followed by the MD5 of the proxy's path
in the project's legacy build folder, `$(CONFIGURATION_BUILD_DIR)` as the project's own levels
give it in its `Debug` configuration, else its first (envelope-experiments `unresolved-proxies`,
40 cases): `$(PROJECT_DIR)/build/<configuration><EFFECTIVE_PLATFORM_NAME>` by default, the
suffix `-iphoneos`, `-iphonesimulator`, `-appletvos`, `-watchos` or `-xros`, none for `macosx`
or a project that sets no `SDKROOT`; `SYMROOT`, `BUILD_DIR` and `CONFIGURATION_BUILD_DIR` apply,
relative to the project directory (`SRCROOT` included, with `projectDirPath`), `$()` and `${}`
alike, standardized (`../`) and decomposed; the target's settings, every object ID, `remoteInfo`
and the referenced project's path do not count. nomac computes it from plain values of those
settings; a condition, another macro or another SDK leaves it a GUID of nomac's own
(`remoteRef=unresolved-other-build-folder`, BACKLOG B-036). The hash covers an absolute path, so
`nomac verify` hashes the path again under the reference's source root. A build file that names a variant group gives one
build file per element the group tree lists for the group: its children outside `.lproj` folders, then the group itself if
it is listed (loader-experiments `variant-build-files`: `[fr.lproj/V2.strings, V2.strings]`
gives `V2.strings`, then the group; two such children and no other give two build files). The
group's keeps the build file's GUID; the children's have GUIDs that change from one run to the
next (`variant-build-files`, `variant-regions`, four runs; envelope-experiments
`variant-groups`), which nomac derives from the build file's and the child's object IDs and
`nomac verify` replaces with stand-ins (docs/adr/0009). A child's build file carries the code
generation key of its own type (`V6.intentdefinition`: `public`); the experiment's build files
have no attributes, and nomac gives each the build file's.
Attributes from `settings.ATTRIBUTES`:
`CodeSignOnCopy` → `codeSignOnCopy: "true"`, `RemoveHeadersOnCopy` →
`removeHeadersOnCopy: "true"` (retro-rampage), `Weak` → `shouldLinkWeakly: "true"`,
`Public`/`Private` → `headerVisibility` (`Public` when both are listed; loader-experiments
`intents-codegen`; `Project` gives none: envelope-experiments `survey-shapes`).
`settings.COMPILER_FLAGS` → `additionalCompilerOptions`. `settings.ASSET_TAGS`, the on-demand
resource tags, → `assetTags`, sorted, in any phase, and nothing for an empty list
(envelope-experiments `survey-shapes`: `(Zeta, Alpha)` is `["Alpha", "Zeta"]`, a tagged source
build file has them too).

**`intentsCodegenVisibility`** is set on build files of a Sources phase whose reference is an
intent definition (`file.intentdefinition`, default `"public"`) or a Core ML model
(`file.mlmodel`, `folder.mlpackage`, default `"project"`), by the reference's type, not its
extension (`Typed.txt` typed `file.intentdefinition` has it; an `.intentdefinition` typed
`text.xml` does not; no other of 212 types, `wrapper.mlmodelc` included; missing files too).
Resources and copy-files build files never carry it. Swift Build's intents and Core ML
compilers read it to decide whether to generate code, and with which visibility.

- **A variant group** has the type of its `Base` variant, else of its development region's
  variant (regions as in `regionVariantName`), else none, whatever the group's name and its
  other variants: `[Base: text, en: intent]` and `[en: strings, de: intent]` have none,
  `[en: strings, Base: intent]` and `[Base: model, en: intent]` take the Base type,
  `[fr: strings, en: intent]` is an intent definition with development region `en` and not with
  `fr` (nextcloud: `Intent.intentdefinition`, a Base intent definition with 50 `.strings`
  variants and no `ATTRIBUTES`, `"public"` in three targets).
- **`ATTRIBUTES`** (case-sensitive): with `Weak`, `Public` or `Private` there is none (`Public`
  and `Private` still give `headerVisibility`); otherwise the first present of `no_codegen` →
  `"no_codegen"`, `codegen` → `"public"`, `private_codegen` → `"private"`, `project_codegen` →
  `"project"`, whatever their order in the list and whatever other attributes are next to them
  (`CodeSignOnCopy`, `RemoveHeadersOnCopy`, `Project`, `public_codegen`, `Foo`); otherwise an
  empty or absent list, or `COMPILER_FLAGS` alone, keeps the default, and any other list
  (`CodeSignOnCopy`, `Project`, `public_codegen`, `Codegen`, `public`) has none. mastodon: five
  `.intentdefinition` build files, one with `ATTRIBUTES = (codegen, )`, all `"public"`.

Evidence: loader-experiments `intents-codegen` and `intents-codegen-fr` (130 build files each:
62 attribute lists on intent definitions, 21 on models, phases, types, 29 variant groups, the
second with development region `fr`), `codegen-file-types` (one build file of each of 212 types).

## Synchronized folders

A `PBXFileSystemSynchronizedRootGroup` (objectVersion 77, the default for new projects since
Xcode 16) names a folder whose contents Xcode reads from disk. Rules observed on netnewswire
(8 folders, 1,299 items) and icecubes (7 folders, 2,272 items), and on the small projects of
the `pif-experiments` workflow; nomac reproduces both apps' group trees exactly.

**Group tree.** The folder is a `group` with the folder's GUID (project GUID + `md5(object
ID)`), `name` (its `name`, else its whole `path`: `Outer/Libs`, `../zz-elsewhere/Libs` in
`pif-experiments` libraries-folder-paths and libraries-elsewhere) and `path`. Its items, read
from disk:

- A folder that is not on disk, or whose path is a file, is read as an empty folder: a group
  with no children but the missing top-level paths its exception sets name (below), and no
  build files (home-assistant's `Sources/Shared/Iconic`; loader-experiments
  `synchronized-missing`).
- Item names are decomposed (NFD) whatever their form on disk, and the paths exception sets,
  `explicitFileTypes` and anchored xcconfigs name are matched byte for byte against them
  (section "Unicode").
- `.DS_Store`, `.git`, `.svn`, `.hg` and `CVS` (folders or files), names ending in `~` and
  names starting with `.#` or `._` are left out, in every subfolder and `.lproj` folder
  (`pif-experiments` dot-files, dot-files-2). Other names starting with `.` are items like any
  other: `.gitkeep` and `.env` are `text`, `.hidden.swift` Swift and a member of Sources, a
  folder `.xcassets` (no extension) a group, and so are `.bzr`, `_darcs`, `.build`, `.swiftpm`
  and `xcuserdata`.
- An item takes the type the folder's `explicitFileTypes` gives it when Xcode knows that type,
  `file` included (`pif-experiments` explicit-types: `known.zzz` declared `sourcecode.swift` is
  Swift; `unknown.swift` declared `nomac.unknown` is typed from disk).
- A subfolder named in the folder's `explicitFolders` is a `file` with `fileType: "folder"`
  (netnewswire's `xcconfig/common`).
- A subfolder whose extension names a type that is not a text type (`IsTextFile`, inherited
  through `BasedOn`) is one `file` of that type (`.xcassets` → `folder.assetcatalog`, `.icon` →
  `folder.iconcomposer.icon`; `pif-experiments` untyped-folders: `.a` → `archive.ar`, `.png` →
  `image.png`, `.xib` → `file.xib`, `.xcmappingmodel` → `wrapper.xcmappingmodel`, while `.swift`,
  `.json`, `.mlmodel`, `.txt`, `.plist` and other text types are groups). A subfolder whose
  extension no type claims is a `wrapper` when the Mac registers that extension as a package
  (`.key`, `.mlmodelc`, `.pages`, `.photoslibrary`, `.plugin`; not `.rcproject`, `.reality`,
  `.usdz`, `.ttf`), and so is a subfolder that holds a `Package.swift` (netnewswire's
  `Modules`). Its contents are not listed, except a `.xcdatamodeld` folder's: it is a
  `versionGroup` with the keys of an `XCVersionGroup` (`fileType: "wrapper.xcdatamodeld"`,
  `name` and `path` its name) and its `.xcdatamodel` folders as `file` children
  (loader-experiments `synchronized-phases`: a folder holding a plain file has no children;
  the differential fuzzer's `Extensions.xcdatamodeld/Model.xcdatamodel`).
- Any other subfolder is a `group` with `name` and `path` both set to its name.
- The files of `<region>.lproj` subfolders become variant groups in the folder that holds the
  `.lproj` folder: one per file name, with `path: ""`. The `.strings` and `.xcstrings` files of
  other regions join the variant group of a Base `.storyboard`, `.xib`, `.nib` or
  `.intentdefinition` of their stem, which keeps its name (`pif-experiments` base-variants,
  base-variants-2: `Base.lproj/S.storyboard` and `en.lproj/S.strings`, a plain `Base.lproj/R.nib`
  and `en.lproj/R.strings`; netnewswire's `Base.lproj/AccountStatsWindow.xib` and
  `mul.lproj/AccountStatsWindow.xcstrings`). Nothing else joins: a Base `.h`, `.m`, `.json`,
  `.txt`, `.png`, `.plist`, `.mlmodel`, `.mlpackage`, `.metallib` or `.strings` keeps its
  variant group apart from the `.strings` of its stem, a `.stringsdict` stays apart, and so does
  a string table next to a development-region document without a Base one
  (`en.lproj/E.intentdefinition`, `fr.lproj/E.strings`). A joining string table replaces the
  variant of its region (`Base.lproj/F2.storyboard`, `Base.lproj/F2.strings` and
  `en.lproj/F2.strings` give the group `F2.storyboard` of the two string tables). The children
  are files with `path: "<region>.lproj/<file>"` and `regionVariantName`: Base first, then the
  project's development region, then the other regions in order (icecubes: `en`, then `be`,
  `ca`, `en-GB`, …; `pif-experiments` variants-order: `Base, en, ab, de, en-GB, fr`, and with
  the development region `fr`, `Base, fr, ab, de, en, en-GB`). A folder named `.lproj` gives
  its files no `regionVariantName` (dot-files).
- A path an exception set names that no item of the folder holding it has as its name is
  listed too, as a `file` of the type its extension names (swiftfin's
  `XcodeConfig/DevelopmentTeam.xcconfig`, which each developer creates; `pif-experiments` round
  5: `gone.swift`, `gone.xcconfig`). Every key names paths: membership exceptions, the keys of
  `platformFiltersByRelativePath`, `attributesByRelativePath` and
  `additionalCompilerFlagsByRelativePath`, and the membership exceptions of build phase
  membership exception sets (loader-experiments `synchronized-exceptions-2`: `filtered.swift`,
  `attributed.swift`, `flagged.m`, `phased.png`). Names are compared byte for byte, decomposed,
  so `B.swift` is listed next to `b.swift` on a case-insensitive disk. A missing path in an
  existing subfolder is listed in it (`Sub/deep.png`), one in a subfolder that does not exist
  is not (round 5: `sub/gone.swift`). Such a file is a member like any other: an exception set
  of a folder the target does not list adds it to the target.
- Order: groups first, then files and variant groups together. Names compare without their
  extension first, then names whose extension is `h`, `h++`, `hh`, `hp`, `hpp`, `hxx` or `ipp`
  (case-sensitive; not `pch`, `pch++`, `H`, `HPP`, `inl`) come before the others of their stem,
  then by extension, each comparison case-insensitive with numbers by value (Foundation's
  `localizedStandardCompare` semantics, `en_US`): `NetNewsWire.entitlements` before
  `NetNewsWire-dev.entitlements`, `IceCubesApp.swift` before `IceCubesApp+Menu.swift`,
  `NetNewsWire_project.xcconfig` before `NetNewsWireTests_target.xcconfig`; `pif-experiments`
  same-stem, same-stem-2: `Y.h, Y.c, Y.m, Y 1.c, Y_1.c, Y-1.c, Ya.c`, `N2.h, N2.c, N10.h`,
  `U.c, U.H`, `w.c, W.h`, the folders `G.h, G.hpp, G.c`; loader-experiments
  `synchronized-headers`: `PublicList.h, PublicList.hpp, PublicList.a, PublicList.m`).
- File types come from the `FileType` specifications of Swift Build's universal and Apple
  platform plugins, extensions matched case-sensitively first (`h` is C, `H` is C++). When two
  types claim an extension, the last one keeps it (`pif-experiments` untyped-duplicates: `.o`
  is `compiled.object-library`, `.ll` `sourcecode.asm.llvm`, `.appex`
  `wrapper.extensionkit-extension`). A file keeps its extension's type unless that type is a
  folder type (`IsFolder`, inherited): a plain file named `P.framework`, `P.bundle` or
  `P.xcdatamodeld` is typed by its contents below, while `P.xcdatamodel` and `P.storyboardc`
  keep theirs (untyped-folders). A `.plist` holding an XML property list is
  `text.plist.xml`. A Mach-O or archive header decides the type of a file whose extension names
  a `compiled.mach-o` type (`object.dylib` with an object header is
  `compiled.mach-o.objfile`, `archive.o` `archive.ar`), and of no other (`object.png` is
  `image.png`, `object.a` `archive.ar`; untyped-macho). A file whose extension no type
  claims, or that has none, is typed from its name and its first 1,024 bytes, in this order
  (untyped files, 256 files; nextcloud's `.tx/config` is `text`): a `FilenamePatterns` match
  (`Makefile` and `makefile` are `sourcecode.make`, `AppIntents.vocabulary`
  `text.plist.vocabulary`; `GNUmakefile` is not); a `MagicWord` prefix, exactly at the start
  (`#!/bin/sh` → `text.script.sh`, `bplist00` → `file.bplist`, `<?xml` and its UTF-16 and
  UTF-8 byte-order-mark forms → `text.xml`; `  <?xml` and `#!/usr/bin/env bash` are not); a
  Mach-O header, by its `filetype` (`compiled.mach-o.objfile`, `.executable`, `.dylib`,
  `.bundle`, …, other values `compiled.mach-o`) or `!<arch>` (`archive.ar`); otherwise `text`,
  unless the bytes are binary: a UTF-8 or UTF-16 byte order mark makes them text, a NUL
  binary, and so do control characters other than tab, line feed, vertical tab, form feed and
  carriage return making up more than a tenth of the bytes read (10 of 100 is text, 11 binary;
  bytes 0x7F to 0xFF count as text; the executable bit does not matter). netnewswire's `.opml`,
  `.sdef` and `.xcprivacy` are `text.xml`, its `.provisionprofile`, icecubes' `.ttf`, `.otf`
  and `.caf` `file`. A path an exception set names that is not on disk is its extension's type,
  else `text` without an extension and `file` with one, whatever its name (a missing `Makefile`
  is `text`).

**GUIDs.** Every item and every member's build file has a GUID that is the base64 encoding of 32
bytes. Xcode's are deterministic: identical across dumps and unchanged when the checkout moves
(`pif-stability`). In the small projects an item's GUID changes with the project name, the
folder's object ID and the item's path in the folder, and not with the folder's own path, file
contents or the target's ID or name. How the bytes are derived is not documented; nomac
generates its own from the same inputs and comparisons treat these GUIDs as opaque
(docs/adr/0009-synchronized-folder-identifiers.md). A member has a different build-file GUID in
each target (netnewswire: 496 build files, 496 GUIDs). A variant group with neither a
development-region nor a `Base` variant gets a hex GUID instead (64 digits, the project GUID's
prefix and 32 more), and so do its build files; Xcode draws them at random, so two dumps of one
project differ in them (`pif-experiments` round 7, `hexguid-*`, each dumped twice; firefox's
`InfoPlist.strings` in `ActionExtension`, whose development region is `en-US`). nomac gives
such a group the base64 GUID of other items, and comparisons treat these hex GUIDs as
synchronized ones (docs/adr/0009-synchronized-folder-identifiers.md).

**Known regions.** The project's `knownRegions` gain the regions of the folders' variant groups
that they lack: variant group by variant group in group-tree order (a subfolder's before its
folder's own items, folder by folder), whether or not a target lists the folder. Regions are
matched exactly and added as they are spelled, and only `mul` itself is never added
(`pif-experiments` regions-case-sync: `IT`, `De`, `EN`, `BASE`, `MUL`, `PT-BR` and `pt-br` are
all added next to `en`, `Base` and `it`; a folder named `.lproj` adds `.lproj`); the
development region's variant adds nothing new. swiftfin's
`Translations/af.lproj` appends `af`; netnewswire's `mul.lproj` string catalogs add nothing
(`pif-experiments` round 6: `regions-*`, a `.strings` or `.xcstrings` variant alike). When one
variant group brings several new regions, Xcode appends them in an order that changes from one
run to the next (`regions-one-folder`, four runs: `zu, zh-Hans, af, fr`, `zu, af, fr,
zh-Hans`, …); nomac appends them in variant order (BACKLOG B-017).

**Build phases.** A target's members are the items of the folders it lists in
`fileSystemSynchronizedGroups`, minus the paths named for that target by the folders'
`PBXFileSystemSynchronizedBuildFileExceptionSet`s, plus the paths named for the target by the
exception sets of folders it does not list (netnewswire's widget takes `Widget/WidgetData.swift`
from `Shared` this way). Paths are relative to the folder; a variant group is named
`/Localized/<folder path>/<name>`. Each member joins the target's first phase of one kind:

| File type | Phase |
|---|---|
| `sourcecode.*` except those below, plus `.intentdefinition`, `.mlmodel`, `.mlpackage`, `.docc`, `.xcdatamodeld`, `.archivingdescription` | Sources (`.applescript` in netnewswire's tests) |
| `sourcecode.c.h`, `sourcecode.cpp.h`, `text.apinotes` | Headers, only if the target has that phase (netnewswire's app drops its `.h` files) |
| frameworks, `.xcframework`, `.dylib`, `.a`, `.tbd`, `.jar`, `.ear`, `.war`, Mach-O object files (by their header, with or without `.o`) | Frameworks, only if the target has that phase |
| `text.plist.entitlements`, `sourcecode.module-map`, `sourcecode.rez`, `sourcecode.typescript`, `file.playground` | none |
| anything else, variant groups and `sourcecode.javascript`, `sourcecode.glsl` and Markdown included | Resources (`.js`, `.md`, `.vsh`, `.xcconfig`, `.xcprivacy`, images, …) |

(loader-experiments `synchronized-phases`, -2: one member of each of 113 extensions and 12
folder types, in a target with and without a Headers phase; `synchronized-phases-all`: one of each
of the 256 extensions Xcode's specifications name, in a target with all four phases; `pif-experiments`
untyped-folders-2: `.jar` in a target without a Frameworks phase.)

A target that lists the folder takes its members in walk order, except the missing paths named
in subfolders, which come after all the others, a level at a time (loader-experiments
`synchronized-missing-order`: `Sub/m0.swift` before `Sub/Deep/m3.swift`, `Sub/m1.png` before
`Sub2/m2.png`, while the group tree lists them in their folders); missing paths at the top level
keep their place. A target that does not list the folder takes the paths its exception sets name
in walk order (`Sub/m1.png` before `Sub/x.png`).

Exception sets also give `additionalCompilerFlagsByRelativePath` (→ `additionalCompilerOptions`)
and `attributesByRelativePath` (`CodeSignOnCopy`, `RemoveHeadersOnCopy`, `Weak`, as for build
files). `headerVisibility` comes from `publicHeaders`/`privateHeaders` for members of the
Headers phase, and from `Public`/`Private` in `attributesByRelativePath` for members of every
other phase; the lists do nothing for the others and the attributes nothing for headers
(loader-experiments `synchronized-headers`: a `.h` the attributes call `Public` has none, a
`.swift`, `.m`, `.strings`, `.json` or `.a` they call `Public` or `Private` has it, and none of
those has it when the lists name them). Sources members carry `intentsCodegenVisibility` by the
rules of build files, with `attributesByRelativePath` as their attributes
(loader-experiments `codegen-members`: the defaults of `.intentdefinition`, `.mlmodel` and
`.mlpackage`, `(no_codegen)`, `(codegen)`, `(private_codegen)`, `(project_codegen)`, `( )`,
`(CodeSignOnCopy, codegen)`, and none for `(Weak, codegen)`, `(Public, codegen)`,
`(CodeSignOnCopy)` and `(Foo)`). `platformFiltersByRelativePath` gives a member's build file
`platformFilters`, written as for build files (below), in every phase, variant groups (by
`/Localized/<path>`) and missing paths included; a subfolder's key filters nothing, and of two
sets naming one path for a target, the later one's filters apply (loader-experiments
`synchronized-exceptions`: `ios`, `macos`, `tvos`, `watchos`, `(ios, maccatalyst)` and
`maccatalyst`). A localized intent definition is a variant group and goes to
Resources, without the key. Each variant of such a group whose type has a fallback build phase
in Swift Build's specifications (`FallbackAutoroutingBuildPhase`: `file.intentdefinition` and
`archive.metal-library`) gets a build file of its own after the group's, with no other key: the
Base variant's, else the development region's, has the GUID of the group's build file, the
others GUIDs of their own (`pif-experiments` base-variants, base-variants-2, base-variants-3;
codegen-members' `Base.lproj/D.intentdefinition`). Xcode lists several of them in an order that
changes from one run to the next (base-variants-3, three runs); nomac lists them in variant
order (BACKLOG B-034). nomac matches the membership of all 13 targets of the two apps.

**Search paths.** A target with a Frameworks phase gets search paths for its folders'
libraries and frameworks in each of its configurations (`pif-experiments` round 9,
libraries-*): `LIBRARY_SEARCH_PATHS` for a member that joins Frameworks and is an archive, a
dynamic library or a `.tbd` (by its type or its extension: `object.dylib` holding an object
file counts, `c.o` does not), `FRAMEWORK_SEARCH_PATHS` for a `.framework` (a folder, or a plain
file with that extension); an `.xcframework` adds none. Each path is the member's folder:
`$(PROJECT_DIR)` followed by what follows the project's directory in its path, decomposed
(loader-experiments `unicode-nfc`: `$(PROJECT_DIR)/He\u0308aders`), spaces, `'` and `"`
escaped with a backslash (`$(PROJECT_DIR)/Outer/Libs $(PROJECT_DIR)/My\ Libs`;
loader-experiments `synchronized-search-paths`: `$(PROJECT_DIR)/R&D\ (it\'s)\ Ünï/a\ \"b\"`); a folder whose path
does not start with the project's directory adds none, and one that only starts with it as a
string adds the rest (`../libraries-outside-Libs` next to the project's folder
`libraries-outside` gives `$(PROJECT_DIR)-Libs`). The members that count are those the
order of a phase counts: all of a folder the target lists, excluded ones included, and those
the exception sets of other folders name for the target. A configuration without the setting
gets `$(inherited)` and the paths; one with it gets its value and the paths it lacks
(`/opt/lib $(PROJECT_DIR)/Src`; a value naming `$(PROJECT_DIR)/Src` stays as it is), and an
empty one only the paths (`synchronized-search-paths`: Empty). Folders
come in group-tree order; within one folder the order changes from one run to the next
(`libraries-nested`, three runs), and nomac lists them in walk order (BACKLOG B-031).

**Order in a phase.** Members follow a walk of each folder (a folder's subgroups before its own
items, as in the group tree). A phase's build files are its own build files, in phase order,
then the members of each synchronized folder that has members for the phase, folder by folder
in group-tree order (not in the order the target lists them). Each folder's members go in as
one block, in walk order, at position `h mod (n + 1)` of the `n` build files so far (a build
file whose file reference is missing counts, though the PIF leaves it out: loader-experiments
`dangling-synchronized`, `-renamed`, `-ids`, `-members`, `-lengths`, `-lengths-members`, `-pairs`,
281 phases), so a later
block can land inside an earlier one (`grid3-1-3-1`: `b01, c01, b02, b03, a01`). `h` starts at
0 and takes `h * 33 + hash(name)`, with 64-bit wraparound, for each of the folder's items of the
phase's kind (Sources, Headers, Frameworks, Resources), in walk order. `hash` is the hash
`NSString` reports on a Mac (CoreFoundation's string hash over UTF-16 code units, each group of
four units summed in 32 bits, `FoundationStringHash`), and `name` is the item's file name,
decomposed as the group tree spells it, or a variant group's name, with no folder path;
subfolders themselves do not count. When the target lists the folder, every item of that kind
counts, including those its exception sets remove (icecubes: `ListEntity.swift`, not a member of
IceCubesApp, decides where `IceCubesAppIntents` goes); when it does not, only the items its
exception sets name for the target count (netnewswire's share extensions).
Evidence: `pif-experiments` (137 phases with two or three folders, and round 4: an excluded
item, items of other kinds, a folder the target does not list, a phase's own files, a target
listing its folders out of order, nested items), and all 12 phases of icecubes and
netnewswire that mix folders or own build files.

A `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` adds the items its
`membershipExceptions` name to its `buildPhase`, whatever the phase's kind (a `.swift` file to
Resources, a `.png` to Sources, a copy-files phase, a target's second Resources phase), whatever
the target lists or excludes, and a second time when the item is a member of the phase already:
files, missing paths, variant groups (`/Localized/<path>`) and subfolders (a group's GUID as the
file reference). Each set's items are one block, ordered by their paths compared as strings
(`/Localized/V1.strings`, `Sub/r3.png`, `r1.png`), placed after the folder's own block by the
rule above, with `h` folded over the last component of each path in that order; several sets of
one folder go in their order in `exceptions`. Their build files carry `codeSignOnCopy` and
`removeHeadersOnCopy` from the set's `attributesByRelativePath`, and their file types count for
the target's `predominantSourceCodeLanguage` (loader-experiments `synchronized-exceptions`,
`synchronized-phase-order`: 20 phases, `synchronized-phase-order-2`: 15 phases naming variant
groups). The experiments had one folder; how sets of several folders interleave is not observed. How the hash was found: on the 10 × 10 size
grid, each block's positions agree with one value modulo 2 to 11 for every first folder size;
with first folders of 4,000 to 4,020 members, the positions gave a block's `h` modulo six primes
whose product exceeds 2^64 (a seventh, 4,049, confirmed it), and the values for one, two and
three members matched `hash(name)` and the fold. The 32-bit sum of each group of four units
changes the hash only for non-ASCII names: `NSString.hash` gives it for 405 random strings of
accented, Greek, CJK and combining characters, and only it places the blocks of
loader-experiments `unicode-order`. There, sixteen folders with one accented or Greek member
each, at the top level or in subfolders, in every form on disk, after thirty own build files
(`unicode-order-ascii` is the same without the accents), and the fuzzer's 27 phases with such
names fit only the decomposed names, whatever their form on disk.

## Unicode

macOS hands Xcode the paths and names it reads from the file system decomposed (Unicode
normalization form D), whatever form the disk or the command line has; what Xcode reads from
the project file stays as written. Observed with loader-experiments `unicode-nfc` and
`unicode-nfd` (one project written in NFC or in NFD, some files and keys in the other form),
`unicode-project-dir` and `unicode-project-dir-nfd`, and the fuzzer's `odd-names` cases:

- Decomposed: the workspace's `name` and `path`, the project's `path` and `projectDirectory`
  (with `projectDirPath` written in either form), the root group's `name` (the project's
  name), the names and paths of synchronized folders' items (subfolders, files, variant
  groups, missing excepted files), and the `name` of a target's `productReference` (but a
  product type the target's platform lacks keeps its reference's path as written, see "Product
  names"). The
  workspace GUID is the MD5 of the decomposed name, the project GUID of the decomposed relative
  path.
- As written: group and file reference names and paths, a synchronized folder's own `name` and
  `path`, target and configuration names, build settings, phase names and scripts, build
  rules. (Settings Xcode adds itself follow the rule above: `LIBRARY_SEARCH_PATHS` gains
  `$(PROJECT_DIR)/He\u0308aders`, decomposed, for a folder written `Hëaders`.)
- A synchronized folder is found on disk whatever the form of its `path`, and a path an
  exception set names counts as present when a file of the same name in any form exists. So is
  an xcconfig (`Ödd.xcconfig`, written in the other form on disk, sets `FROM_ODD_XCCONFIG`).
- Matched byte for byte against an item's decomposed path: `membershipExceptions`,
  `publicHeaders`, `privateHeaders`, the keys of `attributesByRelativePath`,
  `additionalCompilerFlagsByRelativePath` and `explicitFileTypes`, and an anchored
  `baseConfigurationReferenceRelativePath`. Written precomposed, they name nothing: the item
  stays a member, keeps its inferred type, gets no flags; the configuration has no base. A
  missing excepted file is listed decomposed and, with a precomposed key, is a member.
- Matched in any form: `explicitFolders`.

On Linux, whose file systems compare the bytes of names, nomac finds a file by any spelling
of its path, in either form and, as a Mac's default file system does, in any case
(`FileSystem.onDisk`), and writes the decomposed spellings above itself. Swift Build opens files
by their bytes, so the PIF nomac loads into it for a build names each file reference whose path
is spelled otherwise on disk by its absolute path on disk (`PIFDocument.resolvingPathsOnDisk`):
a base xcconfig in the other form (`Ödd.xcconfig`), cwa's sources in a `PDFGeneration` folder
that is `PdfGeneration` on disk (BACKLOG B-062). The PIF nomac prints is Xcode's. An xcconfig's
`#include` is still opened by its bytes (BACKLOG B-075).

## Project references

A project's `projectReferences` name other projects (`ProjectRef`, a file reference of type
`wrapper.pb-project`, which stays a `file` in the group tree; moonlight's
`moonlight-common/moonlight-common.xcodeproj`). Xcode loads each as a project of the workspace,
and the projects those reference in turn (`project-references`: P references Sub, which
references Deep through `..`), each once, whether or not the workspace lists it too
(`workspace`, `project-references-workspace`). A referenced project that is not on disk is left
out (`project-references-missing`). Their packages are the workspace's
(`project-references-packages`: a local package only the referenced project uses gets a
package project). Their position among the projects, their GUIDs, and dependencies and build
files that point into them are described above.

## Swift packages

Xcode makes package projects with SwiftPM's open-source package PIF builder
(`SwiftBuildSupport/PackagePIFBuilder`), answering its delegate questions itself. nomac runs
the same builder (ADR 0010); everything below is what Xcode 27.0 does around it. Evidence:
netnewswire and icecubes (all 52 package projects identical), and the `package-experiments`
workflow (packages written from scratch).

### Which packages, and how they are loaded

| Reference in the project | Package kind | Observed |
|---|---|---|
| a folder holding `Package.swift` in the file tree: a file reference (`lastKnownFileType = wrapper`) or inside a synchronized folder | root: no `BUILD_SERVER_PROTOCOL_TARGET_TAGS = dependency`, one test product per test target | icecubes, netnewswire |
| a folder holding `Package.swift` that the `.xcworkspace` references itself | root, as above | cwa (`ENA/ENASecurity`, `ENA/HealthCertificateToolkit`) |
| `XCLocalSwiftPackageReference` | dependency, no test products | package-experiments |
| `XCRemoteSwiftPackageReference` | dependency, checked out in `DerivedData/<workspace>-<hash>/SourcePackages/checkouts`, binary artifacts in `SourcePackages/artifacts` | netnewswire, icecubes |

- Versions are pinned by `<workspace>/xcshareddata/swiftpm/Package.resolved` (a bare
  project's workspace is `<Name>.xcodeproj/project.xcworkspace`), even when a root package pins
  other versions. A workspace without one whose only root package has a `Package.resolved` of
  its own is pinned by that file, which Xcode leaves as it is and does not copy (pocket-casts'
  `Modules`). Otherwise (no root package, two of them, a root package without the file, or
  only a local dependency's own `Package.resolved`) Xcode resolves the latest versions the
  requirements allow and writes the workspace's file, creating `xcshareddata/swiftpm` (the same
  bytes as SwiftPM's version 3 format, `originHash` included). loader-experiments
  `package-pins-*`: a remote package tagged 1.0.0, 1.1.0 and 1.2.0. Without the file that pins,
  Xcode creates whatever of `project.xcworkspace/xcshareddata/swiftpm` and an empty
  `configuration` folder in it are missing, a local package without dependencies included, and
  removes none of them; with a root's own pins it creates nothing (envelope-experiments
  `package-resolved`, docs/formats/project-file.md).
- One test product per test target (`PACKAGE-PRODUCT:<package>_<Target>.<Target>`), no
  umbrella `<Package>PackageTests` product and no `-test-runner` targets.
- Files are classified with Xcode's rules: xibs, asset catalogs, string catalogs, Core Data
  and Metal files are resources; `.docc` catalogs are kept (`folder.documentationcatalog` in
  the group tree); Core ML models and RealityKit assets are resources. These are the builder's
  own `additionalFileRules`.
- Manifests are evaluated on the Mac (icecubes: SQLite.swift picks its default traits with
  `#if os(Linux)`). A Mac with Xcode 27.0 answers: `os(macOS)`, `os(OSX)`, `arch(arm64)`,
  `_endian(little)`, `_pointerBitWidth(_64)`, `_runtime(_ObjC)`, `_hasAtomicBitWidth(_64)`,
  `_hasAtomicBitWidth(_128)` are true, every other `os`, `arch`, `targetEnvironment`,
  `_endian`, `_pointerBitWidth`, `_runtime` false; `canImport` is true for Accelerate,
  ActivityKit, AppIntents, AppKit, AVFoundation, Combine, CommonCrypto, CompilerPluginSupport,
  Compression, CoreFoundation, CoreGraphics, CoreImage, CoreLocation, CoreML, CoreServices,
  CoreText, CryptoKit, Darwin, `Darwin.C`, Dispatch, Foundation, FoundationModels, ImageIO,
  Metal, NaturalLanguage, Network, ObjectiveC, Observation, OSLog, PackageDescription,
  QuartzCore, RegexBuilder, Security, SQLite3, StoreKit, Swift, SwiftData, SwiftUI,
  Synchronization, System, SystemConfiguration, Testing, UniformTypeIdentifiers,
  UserNotifications, Vision, WebKit, WidgetKit, XCTest, `_Concurrency`, `_StringProcessing`,
  `os`, `zlib` (FoundationModels: firebase-ios-sdk, in nextcloud, adds its Gemini targets with
  it), and false for Android, Bionic, CRT, FoundationEssentials,
  FoundationInternationalization, FoundationNetworking, FoundationXML, Glibc,
  MobileCoreServices, Musl, UIKit, WASILibc, WatchKit, WinSDK, `ucrt`. A condition the table
  lacks is left to the compiler: on a Mac that is the selected Xcode's, which answers as Xcode
  does; on Linux it answers as Linux does, and nomac warns (`package-experiments`).
  `compiler(>=6.4)` and `swift(>=6.0)` hold, `compiler(>=6.5)` does not.
  The Mac's branches import its C library as `Darwin` (kickstarter: facebook-ios-sdk takes
  `#if os(Linux) import Glibc #else import Darwin.C #endif` for `getenv`); off Darwin, nomac
  compiles an `import Darwin` or `import Darwin.<submodule>` at the start of a line as an import
  of the machine's C library (`Glibc`), which Linux has and Darwin's C functions come from.

### Builder questions (`PackagePIFBuilder.BuildDelegate`)

- `deviceFamilyIDs`: 1, 2, 3, 4, 6, 7 (`TARGETED_DEVICE_FAMILY = 1,2,3,4,6,7` in every package
  project).
- Local rpaths in Debug only (`addLocalRpaths: .debugOnly`): Release imparts no
  `LD_RUNPATH_SEARCH_PATHS`.
- `suggestAlignedPlatformVersionGiveniOSVersion`: for a platform the package does not
  declare, the SDK's own version map from iOS (`VersionMap` in `SDKSettings.json`: `iOS_tvOS`
  in AppleTVOS.sdk, `iOS_watchOS` in WatchOS.sdk, `iOS_visionOS` in XROS.sdk), at the greatest
  iOS version not above the declared one. Checked for every iOS minor version from 15.0 to
  27.4 (`sdk_version_maps.py`: 0 of 53 packages differ): iOS 17.4.1 gives tvOS 17.4, watchOS
  10.4, visionOS 1.1; iOS 17.6 gives visionOS 1.2; iOS 26.1 gives watchOS and visionOS 26.0;
  iOS 15.5 gives tvOS 15.4. macOS is not aligned. A mapped version below the platform's oldest
  supported version is not used (iOS 15 keeps watchOS 9.0).
- `validateMacroFingerprint`: true for the macros of local and root packages, false for a
  remote package's (`approvedByUser: "false"` on its `host-build` target: swiftfin's four
  remote macro packages; loader-experiments `macros`, a git repository at a file URL). Xcode
  stores the macros a user trusts and would answer true for those; a Mac that never built the
  app, such as a CI runner, has trusted none. With `-skipMacroValidation` every macro is true:
  swiftfin's `-dumpPIF` with the option differs from its plain one only in its four remote
  macro targets and the signatures of the objects that list them (`nomac pif`, `nomac build`
  and `nomac archive` take the option). Swift Build refuses to build a target that is not
  approved ("Target '…' must be enabled before it can be used"), so swiftfin's reference
  build passes the option, as its own release lane does (`fastlane/Fastfile.swift`).
- Prebuilts: Xcode 27.0's SwiftPM uses SwiftPM's prebuilt swift-syntax for a remote
  swift-syntax at a version download.swift.org has one for. A target that uses its products
  (the macro's `host-build` tool and its testable object target) gets no target dependencies on
  them, `OTHER_SWIFT_FLAGS` with `-I <prebuilt>/Modules` and `-I` of the checkout's C shims
  (`Sources/_SwiftSyntaxCShims/include`, `Sources/_SwiftLibraryPluginProviderCShims/include`),
  `OTHER_LDFLAGS` with `-lMacroSupport` and `LIBRARY_SEARCH_PATHS` with `<prebuilt>/lib`, where
  `<prebuilt>` is `SourcePackages/prebuilts/swift-syntax/<version>/swiftlang-6.4.0.34.1-macosx27.0-MacroSupport`:
  SwiftPM's name for Xcode's toolchain, its compiler's `swiftlang-` version and the macOS SDK
  (`macro_plugin_experiments.py` macro-package with swift-syntax 604.0.0, firefox's reference
  with 603.0.2). nomac's workspace uses them under that name everywhere; off macOS it then puts
  the build machine's library of the same version in that folder (SwiftPM's
  `swift-6.4.0-RELEASE-ubuntu_noble_aarch64-MacroSupport`, a marker file `.nomac-build-machine`
  records it), so the PIF stays Xcode's and the macro links (ADR 0151). Without Xcode's
  `SourcePackages` state, SwiftPM's default (`usePrebuilts: false`) gave the macro target its
  swift-syntax dependencies instead.
- Everything else as SwiftPM's own delegate, except `configureSourceModuleBuildSettings`, which
  adds nothing (no symbol-graph settings).

### Test products

A test product never deploys below the platform's testing frameworks: the higher of
`XCTest.framework/XCTest`'s and `Testing.framework/Testing`'s values in the platform's
`Developer/Library/Frameworks`, each the lowest `minos` (`LC_BUILD_VERSION`) of its slices for
the platform, and at least 14.0 for macOS. Xcode 27.0: iOS 17.0, macOS 14.0, tvOS 17.0, watchOS
10.0, visionOS 1.0. Its watchOS binaries are arm64 26.0, arm64e 26.0 and arm64_32 10.0
(`vtool -show-build`); a root package's test product gets watchOS 10.0 when the package
declares watchOS 4, 5 or 9, and keeps a declared 10.5 or 11.0 (package-experiments `RootWatch*`;
kickstarter: `Library-Tests`, watchOS 5 declared). SwiftPM's own reading, the first slice, would
give 26.0. The other platforms' slices agree (declared iOS 15 and tvOS 15 give 17.0, macOS 12
gives 14.0, visionOS 1.1 stays). The last slice would give the same values as the lowest with
these binaries (BACKLOG B-021). icecubes' test products get macOS 14.0 where their packages
leave macOS at 12.0; netnewswire's keep the macOS 15.0 their packages declare.

### Order

- **Package projects** in the workspace: an order that changes with the checkout path
  (icecubes `first` and `moved`; package-experiments `first` and `second-location`), stable
  for one path. nomac lists them by package identity; `nomac verify` compares them in GUID
  order (ADR 0010).
- **Target objects** of a package project in the document: the order in which the builder
  reports its modules and products (`build()`), dynamic-library variants
  (`isDynamicLibraryVariant`) last. The project's `targets` list keeps the builder's
  project order. Checked on all 52 packages of netnewswire and icecubes.

### Workspace targets that use package products

- Each `PBXBuildFile` with a `productRef` becomes a build file with `targetReference` =
  the product's target GUID (`PACKAGE-PRODUCT:<package>_<Product>.<Product>`) and
  `guid` = the MD5 hex digest of the `XCSwiftPackageProductDependency`'s object ID, without
  the project GUID prefix, so a framework and an embed build file of one product share it
  (netnewswire: 73 of 73).
- Xcode adds a build file to the start of the target's first Frameworks phase for each
  `packageProductDependencies` entry that no build file of that phase links, one after the
  other in list order, so they end up reversed (`[RootKit, OtherKit, LocalKit]` linking only
  `OtherKit` gives `LocalKit, RootKit, OtherKit`); a product only an embed phase copies counts
  as unlinked. A target without a Frameworks phase gets none, and lists none of them
  (loader-experiments `unlinked-products`). No corpus app checked so far has such an entry.
- `dependencies` lists the target dependencies, a `PBXTargetDependency` with a `productRef`
  included in its place as the product it names, with its own `platformFilters` (firefox's
  `RustMozillaAppServices` depends on `Glean` this way; loader-experiments
  `product-target-dependencies`), then the package products the build phases link or copy, in
  build-file order (the added build files included), once per
  `XCSwiftPackageProductDependency` object: swiftfin's iOS app names `StatefulMacros` in eleven
  objects and lists it eleven times; a product a target dependency names is listed again, even
  through the same object. A product's entry is `{guid, name}`, with the `platformFilters` of
  the first build file that uses it (icecubes: WishKit, iOS only).
- A product is found by name: in the remote package the dependency names when that package
  has it, else in the root packages and then the others (swiftfin names `PulseLogHandler` in
  the Pulse package; it is the PulseLogHandler package's).

### Platform filters

A build file's or target dependency's `platformFilters` (`platformFilter`) list becomes
`"platformFilters" : [ … ]` with one object per name: `{ "platform" : "<name>" }`, except
`maccatalyst`, which is `{ "environment" : "maccatalyst", "platform" : "ios" }` (icecubes;
`macos` on build files and target dependencies: envelope-experiments `survey-shapes-2`,
`survey-shapes-3`; `tvos`, `watchos`, `xros` and `driverkit`: `survey-shapes-4`). The singular
`platformFilter` counts only when it is `ios` or `maccatalyst` (gomap, `survey-shapes-2`); Xcode
writes no filters for any other name there (`survey-shapes-4`: `macos`, `tvos`, `watchos`,
`xros`, `driverkit`), where the list form names them. A synchronized folder's
`platformFiltersByRelativePath` gives its members' build files the same lists
(loader-experiments `synchronized-exceptions`).

## Open questions

These rules are implemented as described, but no corpus app has confirmed them yet. Each one
will be confirmed or corrected when an app that exercises it is compared.

- Build tool plugins applied to workspace targets (`plugin:` product dependencies): the target
  depends on the plugin product, `PACKAGE-PRODUCT:<package>_<plugin>.<plugin>` named after the
  plugin, and the package's project has the plugin's targets (loader-experiments
  `build-tool-plugin`: the PIF identical to Xcode's). nomac's builds do not run the plugin yet (B-009).
- `isUserManaged` and `isBranchOrRevisionBased` only change `USES_SWIFTPM_UNSAFE_FLAGS`; nomac
  answers that local packages are user-managed and that remote packages pinned to a branch or
  revision are branch-based, which no corpus app has exercised yet (B-010).
- Package folders referenced directly by an `.xcworkspace` (B-011).
- The product reference Xcode synthesizes for a target whose project file has none
  (`loader-experiments`: `{guid, name: "App.app", type: "product"}`, with a GUID derived from
  inputs not found yet, though the same on every run). Xcode always writes `productReference`,
  so only hand-written projects lack one; nomac emits none and Swift Build then refuses the
  target (B-012).

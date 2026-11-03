# What Xcode 27.0 reads from a project file and a workspace

The rules here come from `.github/scripts/envelope_experiments.py` (BACKLOG B-081): self-written
projects and workspaces whose `-dumpPIF`, `-list` and `-showBuildSettings` (every target and
scheme in every configuration, text and `-json`) Xcode 27.0 (27A266a) wrote, compared with
nomac's by `nomac verify` and `nomac list`. Each rule names its experiment; the features it
verifies are in `LoaderEnvelope+Survey.swift` (docs/formats/check.md).

## objectVersion

Xcode 27.0 reads a project file whose `objectVersion` is one of 42 to 56, 60, 63, 70 to 77, 90,
100 and 110 (`object-versions`, every value from 41 to 111). Every other value, older or newer,
fails `-dumpPIF`, `-list` and `-showBuildSettings` with status 74:

```
xcodebuild: error: Unable to read project 'P.xcodeproj'.
	Reason: Could not open “P”
	The project has an unsupported Xcode project file format. Adjust the project format using a compatible version of Xcode to allow it to be opened by this version of Xcode.
```

For the versions it reads, the version changes nothing in the outputs: one project written as
Xcode of each era wrote it (`compatibilityVersion` up to 63, `preferredProjectObjectVersion`
from 70; `name` plus `SOURCE_ROOT` paths, English regions, a static library and no schemes up
to 45; Swift, a framework, a test bundle, an asset catalog, a Core Data model and a shared
scheme from 46; entitlements and signing attributes from 48; a synchronized folder from 77)
gives outputs nomac matches at every readable version, and the objectVersion-77 project, its
synchronized folder included, saved at 42, 46, 48, 51, 55, 56, 63, 70 and 110 gives the same
outputs as at 77 (`object-versions-newest`). nomac refuses the others alike, with status 74 and
Xcode's message, and `nomac verify` compares such a failure with xcodebuild's: every command
it ran must have failed with nomac's status.

## Object IDs

An object ID need not be 24 hexadecimal digits: Xcode reads any string, and the PIF's GUIDs hash
it as written (docs/formats/pif.md "Identifiers"). The objectVersion-77 project with every ID
replaced by 32 hexadecimal digits (upper or lower case), 24 lower-case digits, `B00001`-style
short digits, `OBJ_<n>`, names with colons (`P::App::Delegate`) or words with dashes and dots
(`APP_GROUP-3.x`) gives outputs nomac matches (`object-ids`); schemes name targets by these IDs
(`BlueprintIdentifier`).

## Workspace items other than projects

A workspace's `FileRef`s to anything but a project, a package folder or a playground (a Podfile,
a README, a script, a test plan, an xcconfig, a folder, a missing file; by `group:` or
`container:`) leave no trace in the outputs, and neither do projects that are not on disk,
listed first or last, in a `Group` or by `container:`: the outputs are those of the workspace
of its other projects alone (`workspace-refs`). nomac leaves such a project out (it stopped
before). CocoaPods' shape before `pod install` is the common case: the workspace lists
`Pods/Pods.xcodeproj`, the app's configurations are based on the missing
`Pods/Target Support Files/Pods-App/Pods-App.<configuration>.xcconfig`, it links
`Pods_App.framework` from the products directory and runs the `[CP] Check Pods Manifest.lock`
and `[CP] Embed Pods Frameworks` scripts (`pods`, `pods-old` at objectVersion 46).

## Missing xcconfig files

A configuration based on an xcconfig that is not on disk, at the target or the project level,
and an `#include` or `#include?` of a missing file, are skipped without a message: Xcode prints
no warning, the PIF keeps the `baseConfigurationFileReference`, and the settings are those
without the file (`xcconfig-missing`). Swift Build, which nomac's settings come from, does the
same.

## File references without a type

A `PBXFileReference` with neither `lastKnownFileType` nor `explicitFileType` gets a type in the
PIF, and the same type counts for the target's `predominantSourceCodeLanguage`
(`file-type-none`, at objectVersion 77 and 46):

| Reference | Type |
|---|---|
| a folder on disk whose extension names a folder or wrapper type | that type (`Images.xcassets`: `folder.assetcatalog`, `Resources.bundle`: `wrapper.plug-in`) |
| any other folder on disk | `folder` (`Folder`, `Thing.stuff`, `Lproj.lproj`) |
| a file, on disk or not, whose extension names a type | that type, extensions matched as for synchronized folders (`Upper.H`: `sourcecode.cpp.h`, `Script.SH`: `text.script.sh`, `Missing.bundle`: `wrapper.plug-in`) |
| a `.plist` on disk | `text.plist.xml` for XML, `file.bplist` for a binary property list, `text.plist` otherwise |
| a missing file whose extension names no type | `text` without an extension, `file` with one |
| a file on disk whose extension names no type | read in its first 1024 bytes (a NUL at offset 1023 counts, at 1024 not): `file.bplist` for a binary property list; after a UTF-16 or UTF-32 byte order mark, `text.xml` for an XML declaration, `text` otherwise; else `file` for a control byte other than tab, line feed, vertical tab, form feed and carriage return (NUL, backspace, escape, PNG's 0x1A, UTF-16 without a mark); `text.xml` for an XML declaration, after a UTF-8 mark too; a script type for a `#!` line at byte 0 (sh, bash, zsh: `text.script.sh`; csh, tcsh: `text.script.csh`; perl, ruby, python, python3: theirs; any other, `env` with any, `text`); `text` otherwise (empty, bytes above 127, DEL, HTML, JSON, PDF) |

The last two rows and the `.plist` row read the contents (`sniffed`, about 70 contents);
`nomac check` reports those references as `pbxproj:PBXFileReference.fileType=none-by-contents`
and the others as `pbxproj:PBXFileReference.fileType=none`, both verified.

## Scheme `AdditionalOptions`

An `AdditionalOptions` element in a scheme's launch or test action, empty or with
`AdditionalOption` children (`key`, `value`, `isEnabled`), changes none of the outputs: they are
those of the same scheme without it (`additional-options`).

## Remote packages without Package.resolved

Without `<workspace>/xcshareddata/swiftpm/Package.resolved`, Xcode resolves the remote packages:
an exact version, a version range (the highest matching tag) or a branch (its head), named by
the project or by a local or root package's manifest. It creates whatever of
`project.xcworkspace/xcshareddata/swiftpm` is missing and an empty `configuration` folder in it,
for a local package without dependencies too, and writes `Package.resolved` (format 3) when there
are remote packages. nomac creates the same folders and writes the same file byte for byte,
with the same outputs (`package-resolved`: with `xcshareddata`, without it, without
`project.xcworkspace`, and through a local or a root package).

## Other shapes the survey ranks next

Each a single change to the objectVersion-77 project, all with outputs nomac matches
(`survey-shapes`): a variant group with a `path` (a folder, or `.`), children relative to it;
a variant group whose source tree is `SOURCE_ROOT`; a header with `ATTRIBUTES = (Project, )`;
`<absolute>` file references, missing (`/usr/lib/libz.dylib`, linked) and on disk (a compiled
source); the `DevelopmentTeamName` target attribute and the `LastTestingUpgradeCheck` project
attribute; a named version group; `plistStructureDefinitionIdentifier`; a group child whose
object does not exist (left out); a UTF-16 strings file (`fileEncoding = 10`);
`parallelizeBuildables = "NO"`; command-line arguments enabled and not; a playground listed by a
workspace; `BuildSystemType` `Original` and `Latest` in the project's shared workspace
settings. `ASSET_TAGS` became the build file's `assetTags` (docs/formats/pif.md "Build files"),
which nomac now writes. A module map typed `sourcecode.module`, the type older Xcode wrote, is
`sourcecode.module-map` in Xcode's PIF; nomac copies the type as written, which the file-type
rules of another branch cover, so `nomac check` leaves the type unknown.

## More shapes the survey ranks next

Each a change to the objectVersion-77 project, all with outputs nomac matches (`survey-shapes-2`):
editor attributes (`indentWidth`, `tabWidth`, `usesTabs`, `wrapsLines` on files and groups);
launch options (a `LocationScenarioReference`, a `StoreKitConfigurationFileReference`,
`customLLDBInitFile`, `migratedStopOnEveryIssue`, `notificationPayloadFile`,
`showNonLocalizedStrings`, `viewDebuggingEnabled`, `enableGPUFrameCaptureMode`, `consoleMode`,
`structuredConsoleMode`, `launchStyle = "1"`); test options (command-line arguments, environment
variables, `customLLDBInitFile`, `onlyGenerateCoverageForSpecifiedTargets = "NO"`,
`disableMainThreadChecker`, a testable with `parallelizable = "NO"`, post-actions); build
pre- and post-actions with `runPostActionsOnFailure` and `buildImplicitDependencies = "NO"`;
profile options and a profile `RemoteRunnable`; `customArchiveName`; scheme versions 1.8 and
2.2; a copy-files phase run only when installing (`buildActionMask = 8`) and `showEnvVarsInLog
= 1`; `productInstallPath`; `fileEncoding` 9 and 30; `[config=…]` and several conditions on one
setting; `macos` platform filters and `platformFilter = maccatalyst`;
`minimizedProjectReferenceProxies = 0`; nested groups in a workspace; and a local package
reference whose folder is missing, which fails every command with status 74 ("Could not
resolve package dependencies"), as nomac now does. One differs: `explicitFileType = undefined`
with `lastKnownFileType = unknown` is `file`, without its encoding, in Xcode's PIF (file types
without a specification).

## Shapes the survey ranks after those

Each a change to the objectVersion-77 project, all with outputs nomac matches (`survey-shapes-3`):
an environment variable whose value is `NO`; Sources and Resources phases that list build files
the project does not have (left out of the PIF); `platformFilter = maccatalyst` and
`platformFilters = (macos, )` on a target dependency; a launch `PathRunnable` with a
`MacroExpansion`; archive post-actions; `GPUProfilerEnabled = "NO"` and
`debugDocumentVersioning = "NO"`; a top-level `validationLevel`; an xcframework reference with an
`expectedSignature`; a test plan whose target is not `parallelizable`. A build action entry that
holds an `AutocreatedTestPlanReference` builds nothing, built for testing alone or for every
action: the scheme's blocks are those without it, as nomac's now are (`autocreated-test-plan`,
`autocreated-test-plan-running`; XcodeProj could not read the entry). Two differ. An OCUnit test
bundle (`com.apple.product-type.bundle.ocunit-test`) whose product's path is `AppTests.xctest`
names its product `AppTests.octest` in Xcode's PIF, its `FULL_PRODUCT_NAME`, as a dynamic
library's is renamed (docs/formats/pif.md "Product names"), and has no
`performanceTestsBaselinesPath`: Xcode writes
one when the product's extension is `xctest`, an OCUnit bundle's `WRAPPER_EXTENSION = xctest`
included and a unit test bundle's `octest` excluded (`ocunit-xctest-extension`,
`unit-test-octest-extension`; docs/formats/pif.md "Target object"). `fileEncoding = undefined` gives the reference a
`fileTextEncoding` that changes from dump to dump (`528511387225`, then `521118269577`), which
`nomac check` reports as unverified.

## The survey's small shapes

Each a change to the objectVersion-77 project, all with outputs nomac matches (`survey-shapes-4`):
a local package whose target sets `cxxSettings`, and one whose manifest has no
`swift-tools-version` line; a variant group whose source tree is `<absolute>`, its child an
absolute path not on disk; `includeInIndex` on a group and `comments` on a file reference; a USDZ
file (`file.usdz`) and an Icon Composer icon (`wrapper.icon`) in the resources phase;
`debugAsWhichUser`, `queueDebuggingEnabled`, `memoryGraphOnResourceException` and
`ignoresPersistentStateOnLaunch = "YES"`; a pre-action's `shellToInvoke`; a StoreKit
configuration in the test action; a workspace naming its project with an `absolute:` location;
and every platform filter name in both forms, the singular `platformFilter` counting for `ios`
and `maccatalyst` only (docs/formats/pif.md "Platform filters"). A build file whose file
reference is missing is left out of the PIF, with outputs nomac matches when the target has no
synchronized folder (`dangling-file-reference-70`); with one, it still counts where the folder's
members go in the phase (`dangling-file-reference`; pif.md "Order in a phase").

## Products of referenced projects

Reference proxies of a framework, a bundle, an app, an app extension, a test bundle and a tool
of a referenced project, linked, embedded and copied by the app, give outputs nomac matches
(`proxy-file-types`, `without-dependencies`). With target dependencies on them, the
autocreated scheme of the referenced project's app extension also builds the referencing
project's app, which nomac's does not (`linked`; BACKLOG B-014). A proxy whose project is not
on disk, or does not have the product, gets a build file `{guid, fileType, name}` whose GUID is
the project GUID followed by the MD5 of the product's path in the project's legacy build
folder, `$(CONFIGURATION_BUILD_DIR)/<proxy path>` with the project's own settings in its `Debug`
configuration, else its first (`unresolved-proxies`, 40 cases: `<folder>/build/Debug-iphoneos/
libGone.a`, `build/Debug/` for macosx, `Out/` for `SYMROOT = $(PROJECT_DIR)/Out`; docs/formats/pif.md
"Build files"), as nomac now writes it. The cases also show two settings rules nomac follows
too: with `SYMROOT` set in a project opened alone, a scheme's settings use the legacy
locations, while through a workspace they stay in DerivedData (`symroot-locations`;
show-build-settings.md), and a project whose `SDKROOT` is `iphonesimulator` has no generic iOS
destination (show-build-settings.md "Failures"; B-089 for a conditional `SDKROOT`).

# The `.xctestrun` file

What `xcodebuild build-for-testing` writes next to the build products for `xcodebuild
test-without-building -xctestrun` (and `nomac test`) to run. Observed with Xcode 27.0 (27A266a)
on self-written projects (`.github/scripts/xctest_experiments.py`, experiments
`build-for-testing` and `xctestrun-*`, 2026-11-03 and 2026-11-06); nomac writes it in
`Sources/NomacDeviceTest/XCTestRunWriter.swift` and reads it in `XCTestRun.swift`. The plan options
are the ones the corpus's and the holdout's 68 test plans use.

## File

`Build/Products/<scheme>_<sdk><version>-<arch>.xctestrun` (`App_iphoneos27.0-arm64.xctestrun`
for scheme `App`, a generic iOS destination); with a test plan,
`<scheme>_<plan>_<sdk><version>-<arch>.xctestrun`. An XML property list as Foundation writes it
(tabs, keys sorted).

Paths start with `__TESTROOT__` (the file's folder), `__TESTHOST__` (the entry's host app),
`__PLATFORMS__` (the developer directory's `Platforms`) or `__DERIVEDDATA__`.

## Format 1: a scheme with testables

The top dictionary has one entry per testable, by blueprint name, and
`__xctestrun_metadata__` `{ContainerInfo: {ContainerName, SchemeName}, FormatVersion: 1}`.
`RunOrder` numbers the entries in the scheme's testable order. Keys of every entry:

| Key | Value |
|---|---|
| `BlueprintName`, `ProductModuleName` | the target's name and module |
| `BlueprintProviderName`, `BlueprintProviderRelativePath` | the project's name and its path from the container (`App.xcodeproj`) |
| `BundleIdentifiersForCrashReportEmphasis` | the bundle identifiers of every target the run builds (sorted and build order agree in every variant so far) |
| `CommandLineArguments`, `EnvironmentVariables` | the test action's arguments and variables, or the launch action's when the test action uses them (`shouldUseLaunchSchemeArgsEnv`), the variables added to Xcode's defaults below |
| `DefaultTestExecutionTimeAllowance` | 600 |
| `DependentProductPaths` | every product the run builds, including each test bundle inside its host (sorted and build order agree in every variant so far) |
| `DiagnosticCollectionPolicy` | 1 |
| `IsMemoryTaggingAddressSanitizerEnabled` | false |
| `PreferredScreenCaptureFormat` | `screenRecording` |
| `ProcessNamesForCrashReportCollection` | the executables of the apps the run builds (`App`, `AppUITests-Runner`) |
| `SystemAttachmentLifetime`, `UserAttachmentLifetime` | `deleteOnSuccess` |
| `TestBundlePath` | `__TESTHOST__/PlugIns/<name>.xctest`, or `__TESTROOT__/<config>-iphoneos/<name>.xctest` for an unhosted bundle |
| `TestHostPath` | the host app, or for an unhosted bundle `__PLATFORMS__/iPhoneOS.platform/Developer/Library/Xcode/Agents/xctest` |
| `TestHostBundleIdentifier` | the host app's identifier (a UI test's runner: `<UI test bundle id>.xctrunner`); absent for an unhosted bundle |
| `TestInteropMode` | `complete` |
| `TestLanguage`, `TestRegion` | empty |
| `TestTimeoutsEnabled` | false |
| `TestingEnvironmentVariables` | `XCODE_SCHEME_NAME`; for a hosted unit test also `DYLD_INSERT_LIBRARIES` `__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib`, `PERFC_SUPPRESS_SYSTEM_REPORTS` 1, `XCInjectBundleInto` `unused`; for an unhosted one `DYLD_INSERT_LIBRARIES` `/usr/lib/libRPAC.dylib` |
| `ToolchainsSettingValue` | empty |

A hosted unit test has `IsAppHostedTestBundle` true. A UI test has `IsUITestBundle` and
`IsXCTRunnerHostedTestBundle` true, `UITargetAppPath` (the app `TEST_TARGET_NAME` names),
`UITargetAppCommandLineArguments`, `UITargetAppEnvironmentVariables` (`APP_DISTRIBUTOR_ID_OVERRIDE`
and `XCODE_SCHEME_NAME`) and `UITargetAppPerformanceAntipatternCheckerEnabled` true.

Xcode's default `EnvironmentVariables`: `APP_DISTRIBUTOR_ID_OVERRIDE` `com.apple.AppStore`,
`DYLD_INSERT_LIBRARIES` `/usr/lib/libRPAC.dylib`, `IDE_CHOSEN_LOGGING_METHOD` 1,
`OS_ACTIVITY_DT_MODE` YES, `PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT` 1,
`PERFC_ENABLE_PROFILE_MODE` 1, `PERFC_RESET_INSERT_LIBRARIES` 1,
`PERFC_SUPPRESS_SYSTEM_REPORTS` 1, `SQLITE_ENABLE_THREAD_ASSERTIONS` 1, `TERM` `dumb`.

With the scheme's code coverage on, each entry adds `ClangProfileDataDirectoryPath`
(`__DERIVEDDATA__/Build/ProfileData`) and `__xctestrun_metadata__` adds
`CodeCoverageBuildableInfos`.

The Release configuration changes only the products' folder (`Release-iphoneos`).

## CodeCoverageBuildableInfos

One dictionary per product the run builds, sorted by `Name` whatever the project's target order
(`xctestrun-coverage`, `-files`, `-libraries`, `-order`, `-prefix`, `-assets`, `-bundle`, `-package`,
`-specified`, `-release`):

| Key | Value |
|---|---|
| `Architecture` | the build's (`arm64`) |
| `BuildableIdentifier` | `<target's identifier in the project>:primary`; a package's library: `<name>:primary` |
| `IncludeInReport` | true, or with `onlyGenerateCoverageForSpecifiedTargets` (a plan's `codeCoverage` `targets`) only for those targets |
| `IsStatic` | true for a static library and a package's library |
| `Name` | the product's name (`App.app`, `libStat.a`); a package's library: its name |
| `ProductPath` | the product's binary from `__TESTROOT__` (`Debug-iphoneos/App.app/App`, `Debug-iphoneos/libStat.a`, a test bundle's inside its host); a package's library: `Debug-iphoneos/PackageFrameworks/<name>_<hash>_PackageProduct.framework/<name>_<hash>_PackageProduct` |
| `SourceFiles` | the files of the target's Sources phases, not generated ones (`GeneratedAssetSymbols.swift`) or headers. Two or more: sorted bytewise (`Zed.swift` before `apple.swift`), each from the folder they share (`Sub/Only.swift`). One: its whole path. None (a resource bundle): empty |
| `SourceFilesCommonPathPrefix` | with two or more files, that folder with a final `/`: a folder, not a common start (`CounterMore.swift` and `CounterTests.swift` share `AppTests/`) |
| `Toolchains` | `com.apple.dt.toolchain.XcodeDefault` |

## Format 2: a test plan

A scheme with `TestPlans` gets one file per plan, `<scheme>_<plan>_<sdk><version>-<arch>.xctestrun`,
and so does a scheme with `shouldAutocreateTestPlan = "YES"`, one named after the scheme. The top dictionary:

- `__xctestrun_metadata__` `{FormatVersion: 2}`, `ContainerInfo`, `TestPlan` `{IsDefault, Name}`.
- `CodeCoverageBuildableInfos` unless the plan's `codeCoverage` is `false`; the default, `true` and a
  list of `targets` all gather, the list only choosing what counts in the report.
- `TestConfigurations`: one per plan configuration, `{IsEnabled: true, Name, TestTargets}`, the
  targets in the plan's order, without those with `enabled: false` (which still build). An
  autocreated plan has one configuration, `Test Scheme Action`, holding the scheme's test arguments
  and variables, and gathers coverage.

An entry is as in format 1 without `RunOrder` and `TestInteropMode`, with `ClangProfileDataDirectoryPath`
when the plan gathers, `XCODE_TEST_PLAN_NAME` in `TestingEnvironmentVariables` and in
`UITargetAppEnvironmentVariables`. A plan does not take the scheme's own arguments and variables
(`xctestrun-plan-launch-env`). A configuration's option replaces the same option of `defaultOptions`
whole, the others coming from the defaults (`-plan-configurations`, `-config-overrides`).

| Plan option | In the entry |
|---|---|
| `environmentVariableEntries` | `EnvironmentVariables`; `enabled: false` stays out |
| `commandLineArgumentEntries` | `CommandLineArguments`; `enabled: false` stays out |
| `language`, `region` | `TestLanguage`, `TestRegion`, and arguments after the plan's, also in `UITargetAppCommandLineArguments`: `-AppleLanguages (<language>) -AppleTextDirection <NO, YES for a right-to-left language>`, then `-AppleLocale <language>_<region>`. A region alone: `-AppleLocale en_<region>`. `IDELaunchSchemeLanguageRLO`: `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES -NSForceRightToLeftLocalizedStrings YES`. `IDELaunchSchemeLanguageDoubleLocalizedStrings`: `-NSDoubleLocalizedStrings YES` |
| `targetForVariableExpansion` | `$(…)` in variables and arguments expands with that target's settings; without it they stay as written |
| `testTimeoutsEnabled` | `TestTimeoutsEnabled` |
| `defaultTestExecutionTimeAllowance`, `maximumTestExecutionTimeAllowance` | the same names, capitalized; `null` writes nothing |
| `testExecutionOrdering` | `TestExecutionOrdering` |
| `testRepetitionMode` `retryOnFailure`, `maximumTestRepetitions` | `TestRepetitionPolicy` `{XCTMaximumIterations, XCTRepeatInNewRunnerProcess: false, XCTRepetitionMode: 2}` |
| `diagnosticCollectionPolicy` | `DiagnosticCollectionPolicy`: `Never` 0, `Always` 2 (else 1) |
| `preferredScreenCaptureFormat` | `PreferredScreenCaptureFormat` |
| `uiTestingScreenshotsLifetime`, `userAttachmentLifetime` | `SystemAttachmentLifetime`, `UserAttachmentLifetime` |
| `locationScenario`, `mainThreadCheckerEnabled`, `performanceAntipatternCheckerEnabled` | nothing in the file |

Fields of a plan's test target: `parallelizable` gives `ParallelizationEnabled`, `skippedTests`
`SkipTestIdentifiers`, `selectedTests` `OnlyTestIdentifiers`.

Not implemented, so nomac stops with the option's name (B-408): `addressSanitizer`, which also builds
into `Variant-ASan` and adds `SanitizerOptions` to the configuration; `threadSanitizerEnabled`, which
fails for iOS devices in Xcode's own build; other repetition modes.

## What the build products are

`build-for-testing` builds what `build` builds for the scheme's testing entries and its
testables, with the same build settings (`-showBuildSettings` with either action prints the same
settings for the app). Xcode 27.0 embeds no XCTest frameworks in the host app or the UI test
runner: `AppUITests-Runner.app` is the platform's `Developer/Library/Xcode/Agents/XCTRunner.app`
(Swift Build's `CopyAndPreserveArchs` of its executable, `CopyPlistFile` of its Info.plist, its
`PkgInfo`) with the UI test bundle in `PlugIns`, signed with the UI test target's identity and
profile; the frameworks come from the device's Developer Disk Image.

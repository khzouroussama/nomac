# The `.xctestrun` file

What `xcodebuild build-for-testing` writes next to the build products for `xcodebuild
test-without-building -xctestrun` (and `nomac test`) to run. Observed with Xcode 27.0 (27A266a)
on self-written projects (`.github/scripts/xctest_experiments.py`, experiments
`build-for-testing` and `xctestrun-*`, 2026-11-03); nomac reads it in
`Sources/NomacDeviceTest/XCTestRun.swift`.

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
(`__DERIVEDDATA__/Build/ProfileData`) and the top dictionary `CodeCoverageBuildableInfos` (one
per built product: architecture, `<target id>:primary`, product path, source files).

The Release configuration changes only the products' folder (`Release-iphoneos`).

## Format 2: a test plan

`__xctestrun_metadata__` `{FormatVersion: 2}`, `TestPlan` `{IsDefault, Name}`, `ContainerInfo`,
`CodeCoverageBuildableInfos` (a plan gathers coverage unless it turns it off), and
`TestConfigurations`: one per plan configuration, `{IsEnabled, Name, TestTargets}`, each target
an entry as above without `RunOrder` and `TestInteropMode`, with the plan's variables in
`EnvironmentVariables` and `XCODE_TEST_PLAN_NAME` in `TestingEnvironmentVariables`.

## What the build products are

`build-for-testing` builds what `build` builds for the scheme's testing entries and its
testables, with the same build settings (`-showBuildSettings` with either action prints the same
settings for the app). Xcode 27.0 embeds no XCTest frameworks in the host app or the UI test
runner: `AppUITests-Runner.app` is the platform's `Developer/Library/Xcode/Agents/XCTRunner.app`
(Swift Build's `CopyAndPreserveArchs` of its executable, `CopyPlistFile` of its Info.plist, its
`PkgInfo`) with the UI test bundle in `PlugIns`, signed with the UI test target's identity and
profile; the frameworks come from the device's Developer Disk Image.

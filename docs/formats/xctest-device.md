# Running XCTest bundles on a device

How `xcodebuild test-without-building -xctestrun` (and `xcodebuild test`) runs an app's test
bundles on an iPhone with iOS 17 or later, and how `nomac test` does the same
(`Sources/NomacDeviceTest/TestManager.swift`, ADR 0430).

What is observed and from where:

- Xcode 27.0's outputs on the owner's iPhone (iOS 27.0.1), self-written project
  (`.github/scripts/xctest_experiments.py`, `test-pass`, 2026-11-03): exit status, standard
  output and error, the result bundle.
- Which device services Xcode uses: the Mac's unified log during that run (`log show` for
  `xcodebuild`, `CoreDeviceService` and `remoted`): `remoted` handed CoreDeviceService
  `com.apple.dt.testmanagerd.remote` twice, `com.apple.coredevice.openstdiosocket` and
  `com.apple.coredevice.appservice`, and xcodebuild invoked CoreDevice's app install, launch,
  send-signal and termination-handler actions. The messages themselves travel inside the
  encrypted tunnel and were not captured (a capture of the Mac's tunnel interface needs root).
- The messages: go-ios (`ios/testmanagerd`, `runXUITestWithBundleIdsXcode15Ctx`) and
  pymobiledevice3 (`services/dvt/testmanaged`), which run XCUITest and XCTest bundles on iOS 17+
  devices with the same services.

## The run

For each test target of the `.xctestrun`, in run order:

1. Install every app among its `DependentProductPaths` (the host app, the UI test runner).
2. In the CoreDevice tunnel, two DTX connections (docs/formats/dtx.md) to
   `com.apple.dt.testmanagerd.remote`; on each, a channel
   `dtxproxy:XCTestManager_IDEInterface:XCTestManager_DaemonConnectionInterface`.
3. First connection: `_IDE_initiateSessionWithIdentifier:capabilities:` with a new session
   `NSUUID` and the IDE's `XCTCapabilities`; the reply is the daemon's capabilities.
4. A connection to `com.apple.coredevice.openstdiosocket`, which sends a 16-byte UUID first and
   then the process's output; the host is launched by the app service
   (`com.apple.coredevice.feature.launchapplication`) with that UUID as its standard input,
   output and error, `terminateExisting`, its arguments and its environment (below).
5. Second connection: `_IDE_initiateControlSessionWithCapabilities:` with empty capabilities,
   then `_IDE_authorizeTestSessionWithProcessID:` with the launched process's identifier.
6. The test process opens `dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface` on the
   first connection and calls `_XCT_testRunnerReadyWithCapabilities:`, answered with the
   archived `XCTestConfiguration`; the IDE then sends
   `_IDE_startExecutingTestPlanWithProtocolVersion:` (36) on that channel.
7. The process reports through `_XCT_*` calls on that channel (each acknowledged when it expects
   a reply): suites and cases started and finished (`_XCT_testCaseWithIdentifier:didFinishWithStatus:duration:`
   with `passed`, `failed`, `skipped` or `expected failure`), issues, activities, log messages,
   and `_XCT_didFinishExecutingTestPlan` last.
8. The host is killed with the app service's `sendsignaltoprocess` (signal 9), and the rest of
   its output read until the stdio socket closes.

## The launch

Environment: the entry's `EnvironmentVariables` with its `TestingEnvironmentVariables` over them
(`__TESTHOST__` as the installed host's path), and `XCTestBundlePath` (the bundle in the
installed host), `XCTestSessionIdentifier` (the session, upper case),
`XCTestConfigurationFilePath` empty (the configuration comes over DTX), `XCTestManagerVariant`
`DDI`, `DYLD_FRAMEWORK_PATH` `/System/Developer/Library/Frameworks`, `DYLD_LIBRARY_PATH`
`/System/Developer/usr/lib`, `NSUnbufferedIO` `YES`. The XCTest frameworks are the Developer
Disk Image's: Xcode 27.0 puts none in the app (docs/formats/xctestrun.md), so the
`.xctestrun`'s `__TESTHOST__/Frameworks/libXCTestBundleInject.dylib` becomes
`/System/Developer/usr/lib/libXCTestBundleInject.dylib`. A UI test runner is launched with the
platform options `ActivateSuspended` 1, `StartSuspendedKey` 0, `__ActivateSuspended` 1.

## `XCTestConfiguration`

`testBundleURL` (`file://` and the bundle's path on the device), `sessionIdentifier`,
`automationFrameworkPath` `/System/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework`,
`reportResultsToIDE`, `reportActivities` and `testsMustRunOnMainThread` true,
`initializeForUITesting` true only for a UI test, which also has `productModuleName`,
`targetApplicationBundleID`, `targetApplicationPath`, `targetApplicationArguments` and
`targetApplicationEnvironment`; `IDECapabilities`; `testsToRun`/`testIdentifiersToRun` and
`testsToSkip`/`testIdentifiersToSkip` (`XCTTestIdentifierSet` of `XCTTestIdentifier`s:
components `c`, options `o` 3 for a class and 2 for a method) for `-only-testing` and
`-skip-testing`.

## Output

xcodebuild's standard output (`test-pass`):

```
Command line invocation:
    <xcodebuild> test-without-building -xctestrun <file> -destination platform=iOS,id=<UDID> -resultBundlePath <bundle>

Writing result bundle at path:
	<bundle>

<each test process's output, as XCTest prints it>

Test session results, code coverage, and logs:
	<bundle>

** TEST EXECUTE SUCCEEDED **

```

XCTest writes `XCTestOutputBarrier` (no newline) before its lines; xcodebuild's output has none,
and `nomac test` removes it, also when a read splits it.

`nomac test` on the owner's iPhone (iOS 27.0.1), from Linux, 2026-11-03: the unit-only variant of
`xctest_experiments.py`'s project, built and signed by `nomac build ... build-for-testing`, ran
its 2 tests through this sequence, both passed, status 0 and `** TEST EXECUTE SUCCEEDED **`.

The test process's own lines (`Test Suite 'All tests' started at <device time>.`,
`Test Case '-[AppTests.CounterTests testNext]' passed (0.001 seconds).`, `Executed 2 tests, with
0 failures (0 unexpected) in ...`, the UI test's `t = 0.00s Start Test at ...` activity lines,
`AppUITests-Runner[719:21270] [Default] Running tests...` from `OS_ACTIVITY_DT_MODE`) are
XCTest's console output in the process. Standard error has `Testing started` and xcodebuild's
own diagnostics (destination warnings, timed `IDETestOperationsObserverDebug` lines). Status 0
when every test passed; 70 when the destination never became available ("Timed out waiting for
all destinations matching the provided destination specifier to become available").

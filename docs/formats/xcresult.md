# The result bundle (`.xcresult`)

What `xcodebuild test -resultBundlePath` of Xcode 27.0 writes, and what `nomac test -resultBundlePath`
writes of it (`Sources/NomacDeviceTest/ResultBundle.swift`). Observed on self-written projects on a
simulator made and deleted for the run (`.github/scripts/xctest_experiments.py` `xcresult-pass`,
`-mixed`, `-ui`, `-configurations`, `-without-building`, 2026-11-07), read back with `xcresulttool`.
The bundles stay outside the repository. nomac's has not come from a device yet: the writer is
tested with results a test supplies, and on a Mac read back by Xcode's `xcresulttool`.

## Layout

- `Info.plist`: `dateCreated`, `directoryImportMode` `concurrent`, `externalLocations` empty, `rootId`
  `{hash}`, `storage` `{backend: fileBacked2, compression: standard}`, `version` `{major: 3, minor: 60}`.
- `database.sqlite3`: 40 tables and 16 indexes (`ResultBundleSchema`). `xcresulttool get test-results`
  reads this alone: it answers with `Data` emptied.
- `Data/`: `data.<id>` an object, `refs.<id>` the ids it references or a single zero byte for none. The
  id is `0~` and the base64url of the BLAKE2b (64 bytes) of the file's bytes. `xcresulttool get
  object --legacy` and `get content-availability` read these, from `rootId`.

A `data` file is a Zstandard frame. nomac writes raw blocks, which `xcresulttool` reads, so its files
are larger than Xcode's and their ids differ.

## Objects

Text, keys sorted: an object is `[T[K2:_nV<n>:<type>]` the first time its type appears in the file and
`[S<n>:<type>` after, then `K<n>:<key>` and a value, then `]`. A scalar is `String`, `Int`, `Double`,
`Bool` or `Date` with `K2:_vV<n>:<value>`. An array is type `Array` with its elements after the type.
`<n>` counts bytes. A date is `2026-11-07T00:58:43.857+0100`.

The root is `ActionsInvocationRecord` (`actions`, `issues`, `metadataRef`, `metrics`). Under
`test-without-building`, `ActionRecord`'s `schemeTaskName` is `Action`, it has no `title`, and its
`buildResult` has `status` `notRequested` with zero metrics; `xcodebuild test` has `BuildAndAction`, a
`title` and the build's result. `actionResult.testsRef` names `ActionTestPlanRunSummaries`, whose
`hasTestResults` `content-availability` reports: per configuration, testables (`testKind` `app hosted`
or `UI`, `testLanguage`, `testRegion`), then groups `All tests`, `<target>.xctest` and each class, then
`ActionTestMetadata` per test. A failure in `testFailureSummaries` has `testCaseName`
`<class>.<method>()` and a location whose line numbers count from 0
(`#EndingLineNumber=9&StartingLineNumber=9` for line 10).

## The database's rows

`Actions` one per `Test` action; `TestPlanRuns` one per configuration, `TestableRuns` under it,
`TestSuiteRuns` under that. `TestSuites` and `TestCases` are shared by the runs. Results:

| Status from testmanagerd | `result` |
|---|---|
| `passed` | `Success` |
| `failed` | `Failure` |
| `skipped` | `Skipped` |
| `expected failure` | `Expected Failure` |

A test's `name` is `<method>()`, its `identifier` `<class>/<method>()`, its `identifierURL`
`test://com.apple.xcode/<container>/<target>/<class>/<method>`.
`TestCaseResultsByDestinationAndConfiguration` has for each test one row with neither destination nor
configuration, one with the destination, and one per configuration with both. A failure is a
`TestIssues` row with `issueType` `Assertion Failure` and `compactDescription`, which is
`xcresulttool`'s `failureText`, its place in `SourceCodeContexts` and `SourceCodeLocations`; a skip a
`SkipNotices` row on its `TestCaseRuns`.

## What nomac's bundle lacks

- Failures and skips come from the lines XCTest prints (`<file>:<line>: error: -[<module>.<class>
  <method>] : <message>`, a skip without `error: `), one line each. `sanitizedDescription` holds the
  message as printed, where Xcode replaces values (`((multiple strings))`), and an expected failure has
  no reason. Xcode has these from testmanagerd, which only a device can check (B-408).
- `modelName` is the product type (`iPhone17,2`), since a device does not report its marketing name.
- No `host_fk` or developer tools: `environmentDescription` is the scheme alone, without ` · Built with
  macOS …`. No diagnostics and no logs: `content-availability` has `hasDiagnostics` false and `logs` empty.
- `xcresulttool merge`, code coverage (`.xccovreport`), attachments and activities.

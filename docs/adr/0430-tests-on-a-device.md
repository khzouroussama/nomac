# ADR 0430: Running XCTest bundles on a device through testmanagerd

- Status: proposed (extends ADR 0400)
- Date: 2026-11-03

## Context

`xcodebuild test-without-building -xctestrun` runs an app's test bundles on an iPhone: it
installs the host app and the UI test runner, launches the host with the test bundle injected
and drives it through testmanagerd, printing what XCTest prints. nomac reaches the device from
Linux through usbmuxd, lockdownd and the CoreDevice tunnel (ADR 0400, ADR 0402), and launches
apps with the app service (docs/formats/remotexpc.md).

What Xcode 27.0 does was observed on the owner's iPhone with a self-written project
(`xctest_experiments.py`): its outputs, and, from the Mac's unified log, the services it uses
(`com.apple.dt.testmanagerd.remote` twice, `com.apple.coredevice.openstdiosocket`,
`com.apple.coredevice.appservice`). The messages travel inside the encrypted tunnel; their
layout comes from the open-source go-ios (MIT) and pymobiledevice3, which drive testmanagerd on
iOS 17 and later.

## Decision

`nomac test -xctestrun <file> -destination platform=iOS,id=<UDID>` runs each test target of the
`.xctestrun` as xcodebuild does (docs/formats/xctest-device.md): DTX (docs/formats/dtx.md) to
testmanagerd over TCP in nomac's own tunnel, keyed archives written and read by nomac (no
Foundation archiver on Linux), the host launched with the app service and its output read from
`openstdiosocket`, the XCTest frameworks from the mounted Developer Disk Image. `nomac build
build-for-testing` writes the `.xctestrun` (docs/formats/xctestrun.md). Code coverage and test
plans got their `.xctestrun` later, as observed (docs/formats/xctestrun.md; what is left, B-408).

The work started in the xctest workstream (`device/xctest`, uncommitted) and continues in the
device workstream.

## Consequences

- The same tunnel serves install, launch, crash reports, the console and tests.
- The run's output is XCTest's own, printed by the test process; xcodebuild's result bundle
  (`.xcresult`) is not written yet.

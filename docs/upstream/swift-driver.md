# Changes for swiftlang/swift-driver

Swift Build and SwiftPM require swift-driver on branch `release/6.4.x`, at `174567a5` (tagged
`swift-6.4.0-RELEASE` and `swift-6.4.1-RELEASE`). nomac depends on the owner's fork
(`khzouroussama/swift-driver`) with the same requirement, which replaces theirs: its
`release/6.4.x` and `release/6.4.1-linux-fixes` are `ffcb804a`, that revision with exactly the
change below, which applies with `git apply` to it (ADR 0002). Proposing it upstream is the
owner's decision.

## 1. `-stack-check` and `-disable-clang-spi` in compile jobs

Patch: `.github/upstream/swift-driver/0001-stack-check-and-disable-clang-spi.patch`.

**Problem.** Xcode 27.0's swiftc passes `-stack-check` to compile jobs for the targets
docs/formats/build.md "Swift stack checks" lists, and `-disable-clang-spi` to every compile job.
swift.org's driver passes neither, so with Xcode's frontend nomac's Swift objects have no calls to
`___chkstk_darwin` where Xcode's have them, and their `__swift_modhash` hashes differ.

**Change.** The driver options `-stack-check` and `-no-stack-check` (as Xcode's swiftc lists them
in `-help-hidden`), and the observed default: `-stack-check` for macOS 10.15, iOS and tvOS 13 and
arm64 watchOS 6 and later, visionOS and its simulator, Mac Catalyst and Apple firmware, except for
the iOS, tvOS and watchOS simulators, arm64_32, Embedded Swift and sanitizer builds; the last of
`-stack-check` and `-no-stack-check` wins, and `-no-stack-check` is not passed on. Each flag is
passed only when the frontend supports it, so swift.org's frontend, which has no `-stack-check`,
gets only `-disable-clang-spi`. Both go where Xcode's jobs have them: `-stack-check` after the
Objective-C interop flag, `-disable-clang-spi` after `-module-name` (and `-package-name`,
`-disable-all-autolinking`) and before the flags saved from unknown driver options.

**Evidence.** `.github/scripts/swift_stack_experiments.py driver` with the fork's `swift-driver`
and Xcode's `swift-frontend` gives Xcode's jobs in 62 of its 66 cases; the other four are DriverKit
targets, which swift.org's driver does not know, and Apple firmware, where it stops in
`darwinPlatformName`, with or without the patch. With the patch, swift-driver's own
`CompileJobTests` pass on macOS (Xcode 27.0's Swift 6.4): 36 tests, the new `stackCheckOptions`
with 25 cases.

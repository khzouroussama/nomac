# Changes for swiftlang/swift-package-manager

nomac links SwiftPM at `8054c59f` (the head of `release/6.4.2`) and, off macOS, builds its
`PackagePlugin` runtime from those sources for the build tool plugins of Xcode projects (ADR
0105, `Sources/NomacPluginAPI/PluginAPI/PackagePlugin`). The change below is applied there; it is
kept here as a patch for upstream, which the owner decides when to propose. It applies with
`git apply` to that revision.

## 1. Calling `XcodeProjectPlugin`'s entry point off Darwin

Patch: `.github/upstream/swift-package-manager/0001-xcode-project-plugin-entry-point-off-darwin.patch`.

**Problem.** `PackagePlugin` hands a plugin applied to an Xcode project's target to the add-on
library `XcodeProjectPlugin` through a C entry point it looks up by name
(`call_XcodeProjectPlugin_build_command_creation_entry_point`), which returns `(any Error)?`.
Off Darwin the call is `fatalError("FIXME: Compiler crashes when trying to compile a call to
callerFunc")` (rdar://130826719&136043295), so no such library can work there: the plugin stops
before its Xcode conformance runs.

**Change.** Off Darwin, the entry point returns an `UnsafeMutableRawPointer?`: `nil` on success,
else a retained `XcodeProjectPluginError` (a new SPI class holding the error), which
`PackagePlugin` takes back and throws. Darwin's path is unchanged.

**Evidence.** nomac's `build_plugin_experiments.py` on Linux (swift.org 6.4.1): with the change
and nomac's `XcodeProjectPlugin`, the `project` and `project-quoting` plugins return their
commands and the builds succeed, as Xcode 27.0's do on a Mac.

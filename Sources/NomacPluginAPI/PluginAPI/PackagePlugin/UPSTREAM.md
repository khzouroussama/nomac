# PackagePlugin, vendored from SwiftPM

These files are SwiftPM's `Sources/Runtimes/PackagePlugin` at nomac's SwiftPM pin,
`swiftlang/swift-package-manager` `8054c59f07a9c8cc8e67b3ec57870710c7154854` (the head of
`release/6.4.2`), under the Apache License 2.0 with the Runtime Library Exception
(`LICENSE.txt`), with one change: `.github/upstream/swift-package-manager/0001-xcode-project-plugin-entry-point-off-darwin.patch`
(docs/upstream/swift-package-manager.md). Off macOS, nomac builds them with the plugins' own
compiler next to its `XcodeProjectPlugin` (ADR 0105).

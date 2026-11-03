# Vendored: swift-foundation's macros

This plugin module is a copy of open-source code from swift-foundation
(https://github.com/swiftlang/swift-foundation), licensed under the Apache License v2.0
(`LICENSE.md` in this directory, with swift-foundation's `NOTICE.txt`). Each copied file keeps its
original header.

## Origin

Tag `swift-6.4.0-RELEASE` (commit `3b9d8f42b7923a7c1ae9ce20f3b05d1facac334e`), the Swift release
of Xcode 27.0's toolchain:

| File here | Upstream path |
|---|---|
| `PredicateMacro.swift` | `Sources/FoundationMacros/PredicateMacro.swift` (unchanged) |
| `BundleMacro.swift` | `Sources/FoundationMacros/BundleMacro.swift` (unchanged) |

`Sources/FoundationMacros/FoundationMacros.swift`, the executable plugin's entry point, is not
copied: it compiles to nothing when `FOUNDATION_FRAMEWORK` is defined.

## Why

swift.org's toolchain ships these macros built for swift-foundation's own modules: `#Predicate`
names `FoundationEssentials`, which does not compile for iOS. Built with `FOUNDATION_FRAMEWORK`
(`MacroPlugins.compilationConditions`), they name `Foundation` and accept the functions Apple's
Foundation adds (`localizedStandardContains`, `localizedCompare`, `caseInsensitiveCompare`,
`evaluate`), as the copy Xcode 27.0 keeps in the iPhoneOS platform does: the `foundation-*`
experiments of `.github/scripts/macro_experiments.py` expand identically (docs/formats/macros.md
"Open-source macros").

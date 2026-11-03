# Vendored: SwiftPM's package PIF builder

This module is a copy of open-source code from the Swift Package Manager
(https://github.com/swiftlang/swift-package-manager), licensed under the Apache License v2.0
with Runtime Library Exception (`LICENSE.txt` in this directory, with SwiftPM's `NOTICE.txt`).
Each copied file keeps its original header. Why nomac vendors it, and how the revision was chosen, is in
docs/adr/0010-swift-packages.md.

## Origin

Tag `swift-6.4.1-RELEASE` (commit `f0065c5a061542acce0f3aa6394cc77c726c6577`):

| File here | Upstream path |
|---|---|
| `PackagePIFBuilder.swift` | `Sources/SwiftBuildSupport/PackagePIFBuilder.swift` |
| `PackagePIFBuilder+Helpers.swift` | `Sources/SwiftBuildSupport/PackagePIFBuilder+Helpers.swift` |
| `PackagePIFBuilder+Plugins.swift` | `Sources/SwiftBuildSupport/PackagePIFBuilder+Plugins.swift` |
| `PackagePIFProjectBuilder.swift` | `Sources/SwiftBuildSupport/PackagePIFProjectBuilder.swift` |
| `PackagePIFProjectBuilder+Modules.swift` | `Sources/SwiftBuildSupport/PackagePIFProjectBuilder+Modules.swift` |
| `PackagePIFProjectBuilder+Products.swift` | `Sources/SwiftBuildSupport/PackagePIFProjectBuilder+Products.swift` |
| `MainAttrDetection.swift` | `Sources/SPMBuildCore/MainAttrDetection.swift` (unchanged) |
| `WarningControlFlags.swift` | `Sources/SPMBuildCore/WarningControlFlags.swift` (unchanged) |

The six builder files are identical at the head of `release/6.4.2` except for commit
`b3613845d` ("Enable promotion of automatic libraries to dynamic libraries"), which Xcode 27.0
does not have: its PIF sets `SWIFT_COMPILE_FOR_STATIC_LINKING[__platform_filter=windows-msvc]`
where that commit sets `SWIFT_DISABLE_COMPILATION_FOR_STATIC_LINKING_WHEN_ANY_TARGET_IS_PROMOTED_TO_DYNAMIC`.

## Written for nomac

- `ModuleGraphFacts.swift`: package identities and test-support modules, derived from public
  API (SwiftPM gives them `package` access).
- `NomacInterface.swift`: exposes the builder's file rules and product GUIDs to nomac.

## Changes to the copied files

Every change is marked with a `// nomac:` comment.

1. `packageIdentity`, `isTestSupportModule` and `umbrellaPackageTestsProductName` have
   `package` access in SwiftPM; the copies read them through `ModuleGraphFacts` or compute
   them as SwiftPM does.
2. `PackagePIFBuilder.build()` does not add the umbrella `<Package>PackageTests` product, and
   unit-test products get no `-test-runner` target: Xcode's PIF has neither (netnewswire,
   icecubes).
3. `PackagePIFProjectBuilder.additionalFileRules` is internal instead of private.

To review the changes against upstream:

```
git -C swift-package-manager show swift-6.4.1-RELEASE:Sources/SwiftBuildSupport/PackagePIFBuilder.swift \
  | diff - Sources/VendoredPackagePIFBuilder/PackagePIFBuilder.swift
```

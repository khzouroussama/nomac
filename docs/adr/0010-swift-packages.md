# ADR 0010: Swift packages through SwiftPM's own PIF builder, loaded as Xcode loads them

- Status: accepted (resolves BACKLOG B-006; extends ADR 0002, ADR 0003 and ADR 0004)
- Date: 2026-10-21

## Context

Xcode adds a project to the PIF for every Swift package a workspace uses
(`"projectIsPackage" : "true"`; netnewswire has 21, icecubes 31). These projects decide how
package code is compiled and linked into the app, so an IPA cannot match Xcode's without them.

Xcode makes them with SwiftPM's open-source package PIF builder
(`Sources/SwiftBuildSupport/PackagePIFBuilder*.swift`): its GUIDs (`PACKAGE:<identity>`,
`PACKAGE-PRODUCT:…`, `PACKAGE-TARGET:…`) and settings are the builder's. The builder asks a
delegate the questions that differ between Xcode and `swift build`. Around it, Xcode decides
which packages are roots, how manifests are evaluated, which file rules apply, where packages
are checked out and how the workspace's targets reference products.

A probe running the builder on Linux reproduced Xcode's package projects for netnewswire and
icecubes only after these changes, each found by comparison with the reference PIFs and with
`package-experiments` (packages written from scratch, docs/formats/pif.md "Swift packages"):

- The builder at the head of `release/6.4.2` sets
  `SWIFT_DISABLE_COMPILATION_FOR_STATIC_LINKING_WHEN_ANY_TARGET_IS_PROMOTED_TO_DYNAMIC` where
  Xcode 27.0 sets `SWIFT_COMPILE_FOR_STATIC_LINKING`. The difference is commit `b3613845d`,
  the only change to the builder files between `swift-6.4.1-RELEASE` and that head.
- Xcode adds no umbrella `<Package>PackageTests` product and no `-test-runner` targets, and makes
  one test product per test target.
- Package folders in the file tree are roots; `XCLocalSwiftPackageReference` and remote
  packages are dependencies.
- Xcode answers `TARGETED_DEVICE_FAMILY` with 1,2,3,4,6,7, imparts local rpaths in Debug only,
  and aligns undeclared tvOS, watchOS and visionOS versions with the SDKs' version maps from
  iOS (`sdk_version_maps.py`: 0 of 53 packages differ, iOS 15.0 to 27.4).
- Test products deploy no lower than the platforms' testing frameworks (SwiftPM reads their
  `minos` with `xcrun vtool` on a Mac, and falls back to the oldest supported version on Linux).
- Manifests run on the Mac: SQLite.swift picks its traits with `#if os(Linux)`.
- The order of package projects in the workspace changes with the checkout path.

## Decision

1. **SwiftPM as a dependency** for package loading and resolution: revision `8054c59f`, the head
   of `release/6.4.2` like Swift Build (ADR 0005), product `SwiftPMDataModel-auto`.
2. **The builder vendored** in `Sources/VendoredPackagePIFBuilder` from `swift-6.4.1-RELEASE`,
   the revision whose output Xcode 27.0 matches. It is compiled in Swift 5 mode, keeps SwiftPM's
   headers, `LICENSE.txt` and `NOTICE.txt`, and lists its changes in `UPSTREAM.md`: reading
   three `package`-access values through public API, and leaving out the umbrella test product
   and test runners. SwiftPM does not export the builder as a product, and its `package`-access
   API cannot be called from another package.
3. **Packages loaded as Xcode loads them** (`NomacPackages`): roots and dependencies as above;
   `shouldCreateMultipleTestProducts`; the builder's own file rules (Xcode's: xibs, asset and
   string catalogs, Core Data, Metal, DocC, Core ML, RealityKit); remote packages checked out in
   `DerivedData/<workspace>-<hash>/SourcePackages` (or the `-derivedDataPath` folder) and pinned
   by the workspace's `xcshareddata/swiftpm/Package.resolved`.
4. **Manifests evaluated as on the Mac.** Before SwiftPM compiles a manifest, nomac replaces each
   host condition in its `#if` and `#elseif` lines (`os`, `arch`, `canImport`,
   `targetEnvironment`, `_endian`, `_pointerBitWidth`, `_runtime`, `_hasAtomicBitWidth`) with the
   answer observed on a Mac with Xcode 27.0, and leaves every other condition and all other text
   to the compiler. A `canImport` of a module outside the observed list is evaluated on Linux and
   reported as a warning. Off Darwin, the `Darwin` imports the Mac's branches keep are compiled
   as imports of the machine's C library (`Glibc`).
5. **Xcode's answers to the builder** (`XcodeBuildDelegate`), with the platform alignment read from
   the user's SDKs (`SDKSettings.json` version maps) and the test-product minimums from the
   user's testing binaries (their `LC_BUILD_VERSION`, read by nomac). The SDK subset keeps
   `XCTest` and `Testing` binaries of every platform for this (only the paths that resolve the
   two binaries; ADR 0003 otherwise unchanged).
6. **Document order as Xcode writes it**: each project followed by its targets; a package's
   targets in the order the builder reports them, dynamic-library variants last; package
   projects after the workspace's own, by package identity.
7. **Package project order is opaque to comparisons.** `nomac verify` moves package projects,
   with their targets, after the workspace's projects in GUID order before comparing, a fourth
   rewrite next to those of ADR 0004, ADR 0006 and ADR 0009.

## Consequences

- netnewswire and icecubes: every package project and every package reference of the app
  targets is identical to Xcode's; the app projects still differ only by the order of
  synchronized members across folders (B-007).
- nomac needs a Swift toolchain on `PATH` to evaluate manifests, as SwiftPM does, and network
  access to fetch remote packages. Like Xcode, resolution may update the workspace's
  `Package.resolved` when it no longer satisfies the project.
- A workspace without packages needs no developer directory for `nomac pif`, unless Swift Build
  must evaluate settings for its PIF (`INFOPLIST_FILE`, `CODE_SIGN_STYLE` or a provisioning
  profile set with macros or conditions, the signing identity of a target that sets no
  provisioning style); `nomac list`, which prints none of them, needs one only for packages and
  for schemes that depend on target settings.
- A new reference Xcode means re-running `package-experiments`: the manifest-condition answers,
  the builder revision (by comparison, as in ADR 0005) and the delegate answers can change. The
  alignment and test minimums follow the installed Xcode by themselves.
- Not covered yet: build tool plugins on workspace targets (B-009), unsafe flags (B-010),
  package folders referenced by a workspace (B-011).

## Alternatives considered

- **Writing a package PIF builder.** About 5,000 lines that would have to follow SwiftPM's
  change by change; using the builder Xcode itself uses removes that whole class of differences.
- **Depending on SwiftPM's `SwiftBuildSupport` module.** Not a product of the package, at a
  revision Xcode 27.0 does not match, and it calls `package`-access API.
- **Evaluating manifests on a Mac.** nomac's purpose is to need none; the host conditions are
  a small, observable surface.

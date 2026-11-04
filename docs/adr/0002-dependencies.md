# ADR 0002: Upstream dependencies and how they are pinned

- Status: accepted
- Date: 2026-10-21

## Context

nomac's output must match one specific Xcode release. Build-setting defaults, spec files and
task construction all live in Swift Build, so the Swift Build version determines
the behavior nomac reproduces.

## Decision

| Dependency | Pin | Why |
|---|---|---|
| Swift toolchain | 6.4.1 (`swift-6.4.1-RELEASE`) | The Swift shipped in Xcode 27.0 |
| swiftlang/swift-build, through the owner's fork `khzouroussama/swift-build` | revision `2c105e3a95888becac2ba9f559eea91495c4691c`: swiftlang's `2d847030` (ADR 0005) with exactly the eleven upstream patches of docs/upstream/swift-build.md, until upstream merges them | The Swift Build in Xcode 27.0, the corpus reference Xcode; the patches change only what it does off Darwin |
| swiftlang/swift-driver, through the owner's fork `khzouroussama/swift-driver` | branch `release/6.4.x`, `ffcb804a` in `Package.resolved`: swiftlang's `174567a5` (`swift-6.4.1-RELEASE`) with the upstream patch of docs/upstream/swift-driver.md | The driver Swift Build and SwiftPM require by that branch; a root dependency with the same requirement replaces theirs, and the patch passes the frontend flags Xcode 27.0's driver passes |
| swiftlang/swift-llbuild, through the owner's fork `khzouroussama/swift-llbuild` | branch `release/6.4.x`, `b0afd154` in `Package.resolved`: swiftlang's `ab642120` with the upstream patch of docs/upstream/swift-llbuild.md | The llbuild Swift Build and SwiftPM require by that branch; a root dependency with the same requirement replaces theirs, and the patch keeps a directory listing from aborting on an entry it cannot read |
| swift-tools-protocols | the `release/6.4.x` revision recorded in `Package.resolved` | Swift Build depends on it by branch |
| swiftlang/swift-package-manager | revision `8054c59f07a9c8cc8e67b3ec57870710c7154854` (head of `release/6.4.2`), product `SwiftPMDataModel-auto`; its package PIF builder vendored from `swift-6.4.1-RELEASE` (ADR 0010) | Package resolution and the package PIF Xcode generates |
| apple/swift-argument-parser | `from: 1.5.0`, exact version in `Package.resolved` | CLI parsing |
| tuist/XcodeProj | `exact: 9.17.6` (added with the project loader) | pbxproj, xcworkspace and xcscheme parsing, and conversion to Apple's `XCSchema` model |
| apple/xcode-project-format | via XcodeProj (0.1.0) | Typed model of Xcode 27's JSON project format |
| apple/swift-crypto | `revision: "3.12.5"`, the requirement SwiftPM declares (ADR 0300) | Digests and signatures for code signing |
| apple/swift-nio, apple/swift-nio-ssl | `exact: 2.104.0`, `exact: 2.37.5` (ADR 0401) | TLS for lockdownd's sessions with a device |
| xtool-org/xtool (XKit) | added with signing and device work (BACKLOG B-004) | Apple Developer Services |
| saagarjha/unxip | subprocess, see ADR 0003 | Xcode.xip extraction |

Swift Build pins its siblings by branch, so SwiftPM only accepts it as a `revision:`
dependency. `Package.resolved` is committed, which pins every transitive dependency
to an exact commit and keeps builds reproducible.

The reference Xcode version is recorded in `corpus/corpus.json` (`xcode.version`,
`xcode.build`). It must always be the Xcode release that shipped the pinned Swift Build.

## Consequences

- Upgrading to a new Xcode means four things in one change: the Swift Build revision, the
  toolchain in CI, the corpus `xcode` block, and re-capturing every reference artifact.
- A difference between nomac and Xcode can come from a Swift Build version mismatch.
  The pin rules that out for the reference Xcode.

## Deviation from the initial plan

The first-session plan listed xtool as a dependency to add up front. xtool's SDK
builder (`XToolSupport.SDKBuilder`) is internal API, and it rewrites the platform
`Info.plist` (`CODESIGN=true`, `ALTERNATE_LINKER=lld`, resource directory overrides).
That changes the build settings nomac must reproduce, so nomac cannot use it as-is.
nomac uses the same extraction library xtool uses (unxip, ADR 0003) and keeps the
developer directory unmodified. XKit, the part of xtool nomac does need, is added when
signing and device registration are implemented, so no dependency sits unused in the
meantime.

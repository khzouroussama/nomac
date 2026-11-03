# ADR 0001: Swift for nomac, other languages only as pinned subprocesses

- Status: accepted
- Date: 2026-10-21

## Context

nomac turns Xcode projects into signed iOS apps on Linux. Its largest building
blocks are already open source, and almost all of them are Swift packages:

- Swift Build (`swiftlang/swift-build`), the engine Xcode itself uses to resolve build
  settings, plan tasks and run builds. It is a Swift package that builds and runs on Linux.
- SwiftPM, whose Swift Build integration (`SwiftBuildSupport`) shows how a client drives it.
- XcodeProj (`tuist/XcodeProj`) and Apple's `xcode-project-format` for reading `.pbxproj`
  and Xcode 27's JSON `project.xcproj`.
- xtool's XKit for Apple Developer Services.

Other required pieces are written in other languages: rcodesign (Rust),
pymobiledevice3 (Python), iTMSTransporter (Java), `unxip` (Swift, but LGPL-3.0, see ADR 0003).

## Decision

nomac is written in Swift (language mode 6) and built with SwiftPM. Swift Build is linked
into the `nomac` executable and runs in-process, as SwiftPM does.

Components in other languages are used as subprocesses with pinned versions and a
documented install procedure. nomac never links them. If a subprocess dependency becomes a
liability (unmaintained, slow to install, wrong license), the small part nomac needs is
ported to Swift, and a new ADR records the port.

## Consequences

- Swift Build, XcodeProj and XKit are used through their Swift APIs, with no FFI layer and no
  serialization boundary to keep in sync.
- `nomac` ships as one executable plus the resource bundles SwiftPM emits next to it (Swift
  Build's `.xcspec` files live in those bundles). The install layout keeps the bundles beside
  the binary (see docs/ARCHITECTURE.md, "Install layout").
- Clean builds are slow (about 2-3 minutes on 4 cores) because Swift Build, llbuild and
  swift-driver compile from source. CI caches `.build`.
- Contributors need a Swift 6.4.1 toolchain. Linux is the primary development platform.
  macOS builds the same package for the reference comparisons in CI.
- Rust, Python and Java tools must be installed separately. `nomac doctor` (planned, see
  BACKLOG) reports which ones are missing and how to install the pinned versions.

## Alternatives considered

- Rust for nomac: rcodesign would be native, but Swift Build, SwiftPM's PIF builder,
  XcodeProj and XKit would all sit behind a process or FFI boundary. Swift Build is by far the
  biggest dependency, so its language decides.
- Python glue around the Swift tools: quick to start, but it cannot ship as a single binary
  and would talk to Swift Build only through its serialized message protocol.

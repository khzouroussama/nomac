# ADR 0100: The swift.org toolchain runs from Xcode's toolchain layout

- Status: accepted
- Date: 2026-10-21

## Context

Swift Build looks for `swiftc`, `clang` and the other tools first in the `usr/bin` of the
session's toolchain, `XcodeDefault.xctoolchain`, and plans command lines that name them there.
The `nomac sdk` subset (ADR 0003) has that toolchain's metadata and libraries but no executables,
and Xcode's executables do not run on Linux.

The compilers find their resource directories from their own location. Observed by compiling
retro-rampage's `Engine` for `arm64-apple-ios15.0` against the iPhoneOS 27.0 SDK in
`swift:6.4.1-noble` (arm64), with the swift.org release toolchains 6.4.0 and 6.4.1:

- From `/usr/bin`, `swift-frontend` fails on the SDK's `Swift.swiftinterface` with "no such
  module 'SwiftShims'". Swift's Clang importer uses `<resource dir>/shims` when it exists and the
  SDK's `usr/lib/swift/shims` only when it does not (`lib/ClangImporter/ClangImporter.cpp`,
  `getNormalInvocationArguments`, tag `swift-6.4.0-RELEASE`). Xcode's toolchain has no `shims`,
  so Xcode's compiler uses the SDK's (`-Xcc -v`: the SDK's shims are the first system path).
- Copied into `XcodeDefault.xctoolchain/usr` whole, the toolchain's `usr/lib/swift/{os,
  dispatch,Block,CoreFoundation}` headers (corelibs' Linux versions) hide the SDK's: `import
  Foundation` fails in `os/workgroup_object.h` ("unexpected type name 'OS_object'").
- With only the executables, the shared libraries they load, `lib/swift/linux`,
  `lib/swift/host` and `share/{clang,swift}` copied in, `import Foundation` and the whole of
  `Engine` compile for iOS with both releases.
- Xcode's `usr/lib/swift/clang` is a link to `../clang/21`; the Clang importer reads the builtin
  headers through it. The subset lacked it.
- Swift Build reads `share/clang/features.json` and `share/swift/features.json` next to each
  compiler to decide which options it may pass (for example `-ivfsstatcache`, which needs
  `vfsstatcache`). Those files describe the compiler binary, so the swift.org ones are used.

swift.org lists `6.4.0` (`swift-6.4.0-RELEASE`) as the Swift of Xcode 27.0, whose compiler
reports `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`.

## Decision

- `nomac toolchain install <usr>` copies a swift.org toolchain's `bin`, `lib/*.so*`,
  `lib/swift/linux`, `lib/swift/host`, `share/clang` and `share/swift` into the developer
  directory's `Toolchains/XcodeDefault.xctoolchain/usr` (`NomacBuild.LinuxToolchain`), which
  must have no Swift compiler yet: a `nomac sdk` subset, whose toolchain has none of these paths.
  A full Xcode or a second installation is refused, so the feature lists next to the compilers
  are always the installed compilers' own. No file is ever replaced.
- The toolchain is the swift.org release swift.org pairs with the reference Xcode:
  `swift-6.4.0-RELEASE` for Xcode 27.0. nomac itself stays on 6.4.1 (ADR 0002); the two are
  independent.
- The subset keeps `usr/lib/swift/clang` and the API notes of the toolchain's modules,
  `usr/lib/swift/apinotes` (Dispatch, os, std, std_span, std_string_view) (`XcodeSubset`).

## Consequences

- Command lines name the same tool paths as Xcode's, and the compilers see the same SDK, shims
  and Clang resource headers as Xcode's.
- The developer directory now holds files that are not Xcode's. They are open source, sit at
  paths the subset leaves empty, and are added only by an explicit `nomac toolchain install`;
  ADR 0003's rule that Xcode's files are copied unmodified still holds.
- Whether the swift.org compiler's output can equal Xcode's is ADR 0101.

# ADR 0101: Open-source compilers cannot produce Xcode 27.0's object code

- Status: accepted (option A, decided by the project owner on 2026-10-22; extends ADR 0004)
- Date: 2026-10-21

## Context

nomac's goal is the IPA Xcode produces, byte for byte where Xcode is deterministic. Xcode 27.0
builds retro-rampage's `Engine` framework deterministically: two clean builds at the same paths
gave identical files, all 78 of them (products and intermediates).

Observations (retro-rampage `Engine`, Release, generic iOS, at the reference's paths; the
compiler invocations and Swift Build's in-process driver as Xcode runs them):

1. **Xcode's Swift compiler has options open-source Swift 6.4.0 does not.** Logging every
   `swift-frontend` invocation (`SWIFT_EXEC` pointing at a wrapper) shows that Xcode's driver
   adds `-stack-check` and `-disable-clang-spi` to every compile job. `-stack-check` is in
   Xcode's `libSwiftDriver.dylib` and frontend but in neither the swift-driver nor the swift
   sources tagged `swift-6.4.0-RELEASE` (the swift-driver Swift Build links is exactly that tag).
   With Xcode's own frontend but without these two flags, 3 of the 30 objects get different code:
   the missing instructions are the stack check (`adrp x16`, `ldr x16`, `blr x16`). Xcode's
   driver also has `-emit-localized-strings`, which neither open-source tool has, so the
   `.stringsdata` files of Swift compiles are missing (icecubes' `Models`: 54 files; B-109).
2. **Xcode's Clang has defaults and options open-source Clang does not.** The Clang importer of
   Xcode's compiler runs with `-fobjc-msgsend-selector-stubs`, `-fno-odr-hash-protocols`,
   `-fstack-check`, `-fno-strict-return`, `-fcommon`, `-fclang-abi-compat=4.0`, six
   `-clang-vendor-feature=` flags, `-target-linker-version` and `-D__SWIFT_COMPILER_VERSION`;
   the swift.org one adds `-Wundef-prefix=TARGET_OS_` and `-Werror=undef-prefix` instead (the
   importers' `-dump-clang-diagnostics`). The first three exist nowhere in `swiftlang/llvm-project`
   at `swift-6.4.0-RELEASE`. Xcode's `clang` accepts `-ivfsstatcache` (an SDK stat cache Swift
   Build passes to every compile); swift.org's rejects it, and `clang-stat-cache` is not open
   source.
3. **The swift.org 6.4.0 compiler generates different code.** Compiled with Xcode's driver
   flags, 18 of the 30 `Engine` objects differ in `__text` (register allocation, and the stack
   checks above), and all 30 in DWARF: the producer is `Swift version 6.4 (swift-6.4-RELEASE)`
   where Xcode's is `Apple Swift version 6.4 effective-5.10 (swiftlang-6.4.0.34.1
   clang-2100.3.34.1)`, and every DWARF offset after it moves. 12 objects match Xcode's in every
   code and data section. The difference is the compiler binary, not how modules are found: with
   prebuilt modules disabled (the standard library rebuilt from `.swiftinterface`, as on Linux),
   Xcode's compiler still produces Xcode's code in all 30 objects.
4. **The swiftlang linker refuses Apple platforms.** swift.org's `ld64.lld` stops with "This
   version of lld does not support linking for platform iOS", a "Swift LLVM fork downstream
   change" in `lld/MachO/InputFiles.cpp`. Neither upstream LLVM 21.1.8's `ld64.lld` nor
   swiftlang's at `swift-6.4.0-RELEASE` rebuilt without that check can read the iOS 27.0 SDK's
   stubs: their TextAPI does not know `arm64e.x1` ("unknown target" `arm64e.x1-ios`), and stubs
   such as `usr/lib/swift/libswiftDispatch.tbd` list only `arm64e-ios` and `arm64e.x1-ios`.
   Xcode links with its own `ld` (`ld-27037.1`, `Apple TAPI version 21.0.0 (tapi-2100.3.8.1)`),
   which is not open source.

So no open-source toolchain reproduces Xcode 27.0's objects: the differences come from Apple's
own, unpublished changes to its compilers, not from the inputs nomac controls.

## Options

- **A. Equivalent code, explained differences.** Build with the open-source toolchain of the
  same Swift release (ADR 0100) and an open-source Mach-O linker. Compiled outputs (objects,
  linked binaries, dSYMs, Swift modules) are compared by a defined, narrower rule: same symbols,
  sections and load commands, with code and debug-info differences recorded as compiler
  differences; every file that does not come from a compiler (property lists, headers, module
  maps, resources, signatures, packaging) stays byte for byte. Cost: none beyond the work.
  Risk: the IPA is not Xcode's, so its code differs in ways a review or a crash report could see
  (no stack checks).
- **B. Rebuild the open-source compiler with Xcode's identity.** Build swift and Clang from the
  `swift-6.4.0-RELEASE` sources with Xcode's version strings, so producers, module hashes and
  module cache keys match. Cost: a toolchain build per Xcode release (hours of CPU, about 60 GB
  of disk) and a place to publish it. It does not add `-stack-check`, the Clang vendor features
  or the other closed changes, so code would still differ (observation 3).
- **C. Run Xcode's own compilers and linker.** They are macOS binaries. Running them on Linux
  needs a Mach-O loader with enough of macOS underneath (Darling-like), and running Xcode's
  tools outside macOS may conflict with the Xcode license. That is a legal question as much as
  a technical one.

## Decision

Option A. Compiled outputs of the open-source compilers (objects, linked binaries, dSYMs, Swift
modules and their companions, generated headers) are judged equivalent to Xcode's when they have
the same symbols and the same structure, and every remaining difference is documented with its
cause. Every file that does not come from a compiler stays byte for byte, as ADR 0004 requires.

B is rejected: it would stamp Xcode's compiler version into binaries Xcode did not build. C is
rejected: running Xcode's tools outside macOS conflicts with the Xcode license. nomac never
fakes the version of a compiler or linker it does not reimplement, in outputs or in answers to
Swift Build's tool probes; how the tools nomac reimplements answer those probes is ADR 0102.

### Proving acceptance early

The owner's plan to show that equivalent apps are accepted by Apple, in this order:

1. As soon as nomac links a complete app, run Apple's validation only (`altool --validate-app` or
   Transporter's validation), with no submission.
2. Then a TestFlight upload for internal testing (automated processing only).
3. App Store review only after both pass.

Before step 1, the integrator checks the current Apple Developer Program License Agreement and
App Review Guidelines with the owner.

## Consequences

- The comparison rule for compiled outputs is the `build` check kind (`nomac verify --build`,
  docs/VERIFICATION.md "Build products"), and corpus progress for the build driver counts apps
  whose compiled outputs are equivalent and whose other outputs are identical.
- Apple's validation and TestFlight processing, not byte equality, are the evidence that the
  compiled code is acceptable; they come in the order above.
- Every file Swift Build writes without a compiler is still expected to match byte for byte.

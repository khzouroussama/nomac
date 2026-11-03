# ADR 0106: A patched swift-frontend for Xcode's stack checks

- Status: accepted (the owner's go-ahead, 2026-11-03: built by users, nothing published, as the patched clang of ADR 0170)
- Date: 2026-11-03

## Context

Xcode 27.0's Swift compiler checks the stack: its driver passes `-stack-check` to the frontend for
Apple devices from iOS and tvOS 13, watchOS 6 and macOS 10.15 (docs/formats/build.md "Swift stack
checks"), the frontend then names `__chkstk_darwin` as the stack probe of every function it makes,
and the backend calls `___chkstk_darwin` before frames of 4096 bytes or more and before dynamic
allocations. 270 of the corpus's 274 objects that call the probe are Swift's. nomac's swift-driver
passes the option as Xcode's does (docs/upstream/swift-driver.md), but swift.org's frontend has no
`-stack-check`, and swift.org's LLVM stops on the probe attribute ("Unsupported stack probing
method"), so on Linux nomac's Swift objects have no probe calls where Xcode's have them.

The LLVM of the clang workstream's patches (`.github/clang` 0017 and 0025) emits Xcode's probe
calls: swift.org's IR with the attribute added compiles to Xcode's calls. The frontend itself
embeds Clang, for the importer and for the IR it emits of C functions.

## Options

1. **Leave the probes out on Linux.** Every Swift object of an app for a recent iOS differs from
   Xcode's in its large functions, and code that relies on the probe (large stack frames on
   threads with small stacks) behaves otherwise.
2. **Add the attribute to swift.org's IR in a pass after the frontend.** The frontend has no
   plugin interface for its pipeline, and its LLVM would still reject the attribute.
3. **Build swift.org's frontend with `-stack-check`, against the patched LLVM and Clang.** The
   option and the attribute are a few lines in the frontend; the backend is the clang workstream's.

## Decision

3. `.github/swift` keeps the patches; `.github/scripts/build-swift-frontend.sh` builds swiftlang/swift
at the installed toolchain's tag with them, against the llvm-project `build-llvm-tools.sh` patches
with `CLANG=1`, as swift.org builds its frontend: Swift's `build-script`, no assertions, the tag's
version strings (`Swift version 6.4 (swift-6.4-RELEASE)`, compiler tag `swift-6.4.0-RELEASE`) and
llvm-project revision, the toolchain's own clang and Swift compiler, the toolchain's run paths. It
writes `swift-frontend` and the dependency scanner (`lib_InternalSwiftScan.so`), which the driver
asks which options the frontend takes, with the SHA-256 of `.github/swift`'s patches.
`nomac toolchain install` installs both in place of the toolchain's files when the LLVM tools
directory has them, and refuses a frontend built with other patches.

The other patches bring the frontend's calls of the runtimes to Xcode's, by the same rules of
observation: Objective-C messages through selector stubs (0002, docs/formats/build.md "Swift
selector stubs"), and the module flag by which Xcode's LLVM calls the Swift runtime's entry points by
register (0003, "Swift runtime entry points by register").

The first patch takes `-stack-check` and `-no-stack-check` as Xcode's frontend does, and gives the
functions it makes the attribute as Xcode's does (docs/formats/build.md "Swift stack checks"). Swift
functions start from Clang's default function attributes, and the patched Clang names the probe in
those for Apple devices (`.github/clang` 0017): Xcode's Swift functions never have it without
`-stack-check`, so the patch keeps it out of them, while the functions Clang itself emits keep it,
as Xcode's do.

## Consequences

- Swift objects built on Linux call the stack probe where Xcode's do.
- The frontend is the one binary nomac's Linux toolchain replaces that the Swift compiler is made
  of; it loads the toolchain's own runtime and swift-syntax libraries, which the same tag's build
  makes the same.
- The embedded Clang is the one `build-llvm-tools.sh` patched when the frontend was built; the
  stamp covers `.github/swift` only, so that a change to `.github/clang` does not refuse every
  installed frontend, and building both from the same tree is the build scripts' order.
- swift.org's frontend has every LLVM target swift.org builds; this one AArch64 and X86, the
  targets of the patched clang, which are those of Apple's platforms and the build machine.
- Building takes about 9 GB (sources and build tree) and, with the clang workstream's LLVM and Clang configured as swift.org
  configures them, about three hours on the shared 16 cores (LLVM 2.4 hours, the frontend and
  scanner 0.6); it is optional, as the patched clang is.
- Measured (`swift_stack_experiments.py run` on Linux): the probe on the same functions and
  declarations as Xcode's in its 16 IR cases and Xcode's probe calls in its objects; without
  `-stack-check`, swift.org's frontend's bytes for modules, and for objects but for a function with
  a dynamic stack allocation at `-Onone`, which the clang workstream's LLVM compiles as Xcode's
  (`.github/clang` 0018). retro-rampage's Engine built by nomac on Linux: Xcode's probe calls in all
  31 objects.

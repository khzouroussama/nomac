# ADR 0104: Relocatable links and bitcode_strip with cctools-port

- Status: accepted (the integrator's decision, 2026-10-22)
- Date: 2026-10-22

## Context

Swift Build links each Swift package product an app uses into one relocatable object
(`Ld …/SwiftSoup.o`, `clang -r`; icecubes' `Models` scheme). swiftlang's `ld64.lld` defines `-r`
but never handles it (`lld/MachO/Options.td`; no `OPT_r` in its driver): it links an image
instead and fails on undefined symbols. No tool of the swift.org toolchain writes a relocatable
Mach-O file (B-120).

A relocatable link merges object files; it reads no library stubs, so neither `arm64e.x1` nor
TBD v5, which kept the classic ld64 from the iOS 27.0 SDK (ADR 0102), matter to it. Apple
publishes ld64 under the Apple Public Source License 2.0, and tpoechtrager/cctools-port ports it
to Linux; osxcross uses it so.

## Options

- **A. cctools-port's `ld64` for `-r` only.** Built from source, like lld.
- **B. A relocatable merge in nomac** from `<mach-o/loader.h>`, `<mach-o/nlist.h>` and
  `<mach-o/reloc.h>`: sections, symbols, relocations, compact unwind, linker options.
- **C. `-r` in lld**, a fourth patch: lld's Mach-O port has no design for relocatable output.

## Decision

A, now; B stays the long-term option, to drop a second linker.

- `.github/scripts/build-cctools.sh` builds `ld64` from cctools-port at a pinned commit (branch
  `1030.6.3-ld64-956.6`, `ld64-956.6`) with clang, the Swift toolchain's libdispatch and
  BlocksRuntime (found through `$ORIGIN/../lib/swift/linux` once installed), and GNU make, and
  writes `ld64` with `ld64-licenses/` (Apple's APSL, cctools-port's `COPYING` and `AUTHORS`) next
  to `lld`. No binary is committed.
- `nomac toolchain install` copies `ld64` into the toolchain's `usr/bin` and the licenses into
  `usr/share/ld64`, and replaces the toolchain's `ld64.lld` link with a dispatcher that clang
  runs for every link (`-fuse-ld=lld`): with `-r` it runs `ld64`, otherwise `lld -flavor darwin`.
  Swift Build's linker probe (`ld`) still reaches lld, which reports its own version.
- The objects ld64 writes are judged by structure, as lld's images are (ADR 0101).
- Xcode 27.0's `ld -r` leaves the inputs' linker optimization hints out of the object, where
  `ld64-956.6` wrote them as `LC_LINKER_OPTIMIZATION_HINT` (netnewswire's package objects on
  Linux, `.github/scripts/relocatable_experiments.py`: C, Objective-C and Swift inputs).
  `.github/cctools/0003-relocatable-links-without-optimization-hints.patch` writes none; the
  three cases then have Xcode's load commands (none before).
- Xcode's `ld -r` also leaves out every section with no content, and the local labels in it (an
  empty `__TEXT,__text`, netnewswire's `RSCoreObjC.o`, whose sources compile to nothing for iOS);
  `ld64-956.6` kept it. `.github/cctools/0005-relocatable-links-without-empty-sections.patch`
  removes such sections before the output is written; `relocatable_experiments.py`'s `empty-*`
  cases then have Xcode's sections (none before).
- A Swift object's `__LLVM,__swift_modhash` is left out by Xcode's `ld -r`, of one input or several;
  `ld64-956.6` copies the `__LLVM` sections of a single input as data, as it did for bitcode, so
  swiftfin's one-file package products kept it (B-173).
  `.github/cctools/0006-relocatable-links-without-swift-module-hashes.patch` skips that section;
  `relocatable_experiments.py`'s six cases then have Xcode's load commands and sections (4 before).
- `bitcode_strip`, from the same source and recipe (`build-cctools.sh`), goes into the
  toolchain's `usr/bin` too. Swift Build passes it to every `CopySwiftLibs` it finds it for
  (`--strip-bitcode-tool`, SWBCore `SwiftStdLibTool.swift`), and its builtin refuses
  `--strip-bitcode` without it, even when it then ignores the stripping because nothing is signed
  (tofu, flappy-fly-bird and uncloudnotes on Linux: "Passed --strip-bitcode without
  --strip-bitcode-tool"). Without bitcode, `bitcode_strip -r` copies the file with `/bin/cp`;
  Xcode 27.0's and cctools-port's both copy the toolchain's `libswiftCompatibilitySpan.dylib` byte
  for byte. With bitcode it relinks through `ld -r`, which reaches ld64.

## Consequences

- icecubes' `Models` on Linux: `SwiftSoup.o` links, and against Xcode's it is equivalent: same
  header, load commands and section order; it differs only by the compiler's selector stubs
  (`_objc_msgSend$<selector>` imports in Xcode's, `objc_msgSend` and `__objc_selrefs` in nomac's,
  ADR 0101), stack checks and the linker named in `LC_BUILD_VERSION`. `Models.o` waits on
  Apple's SwiftData macros (B-121).
- A second linker to build per release of cctools-port, and its license to carry: APSL 2.0
  requires the notice with the binary, which the toolchain keeps in `usr/share/ld64`.
- `ld64-956.6` is the classic ld64, not Xcode 27.0's `ld-27037.1`; a difference it shows is
  recorded with its cause, and B would remove the dependency.

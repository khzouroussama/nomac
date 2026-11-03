# Changes for swiftlang/swift-build

nomac runs Swift Build in process, pinned to `2d847030` (the head of `release/6.4.2`, ADR 0005),
taken from the owner's fork (`khzouroussama/swift-build`, branch `release/6.4.2-linux-fixes`,
`d1842806`), which carries exactly patches 1 to 9 below, one commit each, until upstream merges
them.
Nine behaviors differ between macOS and Linux in ways that make a Linux build's outputs differ
from a Mac's, or its strings copies, binary reads and entitlements fail; these are the changes the owner
proposes upstream. Each
patch is in `.github/upstream/swift-build/` and applies with `git apply` (or `patch -p1`) both to
the pin and to upstream `main` at `fa73f8e7` (2026-10-24), without the others. With the first four
applied at the pin, swift-build's own `PropertyListTests`, `HashContextTests`,
`FileTextEncodingTests` and `MachOPortableTests` pass on macOS (Xcode 27.0's Swift 6.4) and on
Linux (swift.org 6.4.1, arm64; SwiftPM's native build system): 28 tests on each.

## 1. Deterministic binary property lists on every platform (nomac B-105)

Patch: `.github/upstream/swift-build/0001-binary-property-lists-off-darwin.patch`.

**Problem.** `PropertyListItem.asBytes(.binary)` hands Foundation a property list made stable by
`swb_stableData`: an `NSDictionary` subclass that enumerates its keys sorted, and strings interned
through a table so that equal strings are one object. On Darwin, Core Foundation's binary writer
follows both. swift-corelibs-foundation's writer does not: dictionaries come out in Swift
`Dictionary` order, which is seeded per process, and equal strings can be written several times.
So every binary property list Swift Build writes on Linux (`ProcessInfoPlistFile`'s Info.plists,
`builtin-copyStrings`) has other bytes than on macOS, and can change from one build to the next.

**Reproduce on Linux.** Build an iOS framework or app with Swift Build (any `INFOPLIST_FILE`),
then compare `<product>/Info.plist` with the same build on macOS, or with a second Linux build:
the content is the same, the bytes differ. For retro-rampage's `Engine` framework
(github.com/nicklockwood/RetroRampage), the Linux Info.plist has its keys in another order and
`24A430` stored twice: 774 bytes where macOS writes 756.

**Change.** Off Darwin, `asBytes(.binary)` writes the list itself (`BinaryPropertyListWriter`,
SWBUtil) instead of through Foundation: keys sorted, equal strings and integers written once,
objects depth first, the offset and reference sizes Core Foundation chooses. XML output is left to
Foundation, whose writer sorts keys itself. Items wrapping an opaque Foundation value still go
through Foundation.

**Evidence.** The same writer, in nomac (`BinaryPropertyList.swiftBuildData`), reproduces byte
for byte the 11 Info.plists Xcode 27.0's Swift Build wrote for retro-rampage (`Engine`,
`Renderer`, `Rampage.app`, Debug and Release). Built into Swift Build at the pin, it makes
`Engine`'s Info.plist on Linux identical to Xcode's. The patch's test, `stableBinaryBytes`
(SWBUtilTests), expects one byte sequence for a list with unsorted keys, a repeated string and
nested containers, on every platform: on macOS Foundation writes it, elsewhere the new writer.

**Suggested PR.**
- Title: *Write binary property lists deterministically on non-Darwin platforms*
- Description: *`swb_stableData` relies on Core Foundation honoring an `NSDictionary` subclass's
  key order and sharing interned strings; swift-corelibs-foundation does neither, so binary
  property lists written on Linux (Info.plists, copied strings files) differ from macOS's and
  between builds. On non-Darwin platforms, write the binary format directly with sorted keys and
  shared equal strings and integers, matching Core Foundation's layout. Adds a test that pins the
  bytes on all platforms.*

## 2. MD5 for `InsecureHashContext` on every platform (nomac B-005)

Patch: `.github/upstream/swift-build/0002-md5-off-darwin.patch`.

**Problem.** `InsecureHashContext` is MD5 on Darwin (CryptoKit) and Windows (BCrypt), and SHA-256
(`VendoredSHA256HashContext`) where neither exists, Linux included. Everything derived from it
then differs on Linux: the `__md5` macro operator (`SDK_STAT_CACHE_PATH`, `$(SDKROOT:__md5)`),
`String.md5()`, the names of the response files and other per-task files (`<hash>-common-args.resp`),
and the signatures built from them. A Linux build of an Apple-platform project cannot then match
the Mac's, and its intermediate file names are a different length.

**Reproduce on Linux.** `-showBuildSettings` for an iOS target: `SDK_STAT_CACHE_PATH` ends with a
64-character digest where macOS has 32. Build retro-rampage's `Engine`: macOS writes
`Objects-normal/arm64/7187679823f38a2a940e0043cdf9d637-common-args.resp`, Linux
`9f65232cb83f8421e3a495a5062eba382369c975104ee97bafc405ab795bfc5e-common-args.resp`.

**Change.** A vendored MD5 (RFC 1321) beside the vendored SHA-256, used by `InsecureHashContext`
where CryptoKit and BCrypt are not available. The hash stays named "insecure": it is for
identities, not security.

**Evidence.** `HashContextTests.value` and `HashContextTests.numbers`, which check known MD5
digests, ran only on macOS and Windows (`.requireHostOS(.macOS, .windows)`); with the patch they
run everywhere, and `value` adds RFC 1321's `abc` and 80-character test vectors. Until the
change is upstream, nomac computes the same digests with the same algorithm (`NomacCore.MD5`) for
the PIF identifiers and for `SDK_STAT_CACHE_PATH` off macOS, and those match Xcode's.

**Suggested PR.**
- Title: *Use MD5 for InsecureHashContext on all platforms*
- Description: *On platforms without CryptoKit or BCrypt, `InsecureHashContext` falls back to
  SHA-256, so `__md5`, `String.md5()` and the file names and signatures derived from them differ
  from macOS (for example `SDK_STAT_CACHE_PATH` and `*-common-args.resp`). Vendor an MD5
  implementation next to the vendored SHA-256 and use it, and run the known-digest tests on all
  platforms.*

## 3. Detecting a strings file's encoding on every platform

Patch: `.github/upstream/swift-build/0003-strings-encoding-detection-off-darwin.patch`.

**Problem.** `builtin-copyStrings` without `--inputencoding`, as every Xcode project's
`CopyStringsFile` runs it, detects the input's encoding with `FileTextEncoding.string(from:encoding:)`,
which asks Foundation's `NSString.stringEncoding(for:...)` on Darwin and returns nil elsewhere. On
Linux every such task then fails with "no --inputencoding specified and could not detect encoding
from input file", whatever the file holds: 13 of nomac's 20 corpus apps have `.strings` files
(firefox 7,677, home-assistant 171, nextcloud 147, swiftfin 56, ...), and none of them builds on
Linux.

**Reproduce on Linux.** Build any app target with a `Localizable.strings` resource; swiftfin's
UTF-16 files (with a byte order mark) and UTF-8 ones fail alike.

**Change.** Off Darwin, detect the Unicode encodings Foundation detects in these files: a UTF-8 or
UTF-16 byte order mark, which is not part of the text, else valid UTF-8. Other bytes still give
nil, as before; on Darwin Foundation may detect legacy encodings too.

**Evidence.** nomac's own strings copy (`NomacStrings.StringsFileCopy`) detects with the same rule
and writes Xcode's bytes for all 9,885 strings files of the corpus. The patch's test,
`detection` (SWBCoreTests), expects the same strings and encodings for ASCII, UTF-8, UTF-8 with its
mark and UTF-16 with either mark on every platform; it passes on macOS, through Foundation.

**Suggested PR.**
- Title: *Detect the encoding of strings files on non-Darwin platforms*
- Description: *`FileTextEncoding.string(from:encoding:)` only detects an encoding through
  `NSString.stringEncoding(for:)`, which is Darwin-only, so `builtin-copyStrings` without
  `--inputencoding` fails for every file on Linux. On other platforms, detect a UTF-8 or UTF-16
  byte order mark, else valid UTF-8, which are the encodings Foundation reports for such files, and
  add a test of the detection that runs on all platforms.*

## 4. Reading Mach-O files on every platform

Patch: `.github/upstream/swift-build/0004-macho-parsing-off-darwin.patch`.

**Problem.** SWBUtil's Mach-O reader (`MachO.swift`) takes its structures and constants from
Darwin's `MachO` module, and every reading path throws "Mach-O parsing not supported on this
platform" elsewhere. Builds of Apple-platform targets on Linux then fail wherever Swift Build reads
a binary: every Debug app links a debug dylib (`ENABLE_DEBUG_DYLIB`), whose stub executor input
task (`ConstructStubExecutorInputFileListTaskAction`) reads it ("Unable to process debug dylib: …
(SWBUtil.BinaryReaderError error 1.)", nomac B-183), and the xcframework of swiftfin's MPVUI
package fails the same way.

**Reproduce on Linux.** Build any iOS app in Debug: the task that writes the stub executor's
input file list fails on `<App>.debug.dylib`.

**Change.** Off Darwin, define the structures and constants the reader uses, with the names, field
types and layouts Darwin's module imports them with (sizes and alignments observed on macOS with
Xcode 27.0's Swift 6.4: `mach_header_64` 32 bytes, `segment_command_64` 72, `section_64` 80, ...),
and compile every reading path on all platforms. Static archives' members still need Darwin's
`ar.h`.

**Evidence.** A new test, `MachOPortableTests` (SWBUtilTests), reads a thin arm64 dylib written
byte by byte: one slice, its `__TEXT,__swift5_entry` section, install name, rpath and build
version. It passes on Linux with the patch, and on macOS through Darwin's structures, as before.

**Suggested PR.**
- Title: *Parse Mach-O files on non-Darwin platforms*
- Description: *The Mach-O reader in SWBUtil relies on Darwin's MachO module and throws "Mach-O
  parsing not supported on this platform" elsewhere, so building Apple-platform targets on Linux
  fails wherever a binary is read, for example the stub executor input of every debug dylib. Define
  the load commands and structures the reader uses, with Darwin's names and types, on platforms
  without the MachO module, and add a test that reads a hand-written Mach-O file on every
  platform.*

## 5. Looking up `derq` on every platform

Patch: `.github/upstream/swift-build/0005-derq-lookup-off-darwin.patch` (the fork's `01811544`).

**Problem.** `ProcessProductPackagingDER` (`GeneratedFilesTaskProducer.swift`), which turns a
target's signed entitlements into their DER form, runs a hard-coded `/usr/bin/derq`. `derq`
ships only with macOS, so building an Apple-platform target that signs with entitlements fails
elsewhere (a device-signed `nomac archive` on Linux), where a toolchain could provide one.

**Change.** On macOS the task still runs `/usr/bin/derq`; on other hosts `derq` is resolved
through the executable search paths (`resolveExecutablePath`), as `CHOWN` and `CODESIGN` are.

**Evidence.** `PlatformTaskConstructionTests` and `UnitTestTaskConstructionTests`, which expect
`/usr/bin/derq` on macOS, pass unchanged.

**Suggested PR.**
- Title: *Look up derq through the tool search paths on non-Darwin platforms*
- Description: *ProcessProductPackagingDER runs a hard-coded /usr/bin/derq, which ships only with
  macOS, so signing an Apple-platform target with entitlements fails on other hosts. Keep
  /usr/bin/derq on macOS and resolve derq through the executable search paths elsewhere, like the
  other tools, so that a toolchain can provide it.*

## 6. Directory listings without AppleDouble files on every platform

Patch: `.github/upstream/swift-build/0006-listings-without-appledouble-off-darwin.patch` (the
fork's `10b9393e`).

**Problem.** On Darwin, Foundation's `contentsOfDirectory(atPath:)` and `enumerator(atPath:)` leave
out files named `._*`, the AppleDouble files an archive made on a Mac carries for each file's
extended attributes, whatever they hold and whether or not their file is there; directories named
`._*` stay. Foundation elsewhere lists them. `LocalFS.listdir` and `LocalFS.traverse` use the two,
so off Darwin ProcessXCFramework copies an xcframework's `._*` headers into the products'
`include` (swiftfin's `libvlc.xcframework`), and every other listing sees them too.

**Change.** Off Darwin, `LocalFS.listdir` and `LocalFS.traverse` leave out what Darwin's Foundation
does: entries named `._*` that are not directories.

**Evidence.** nomac's `xcframework_copy_experiments.py`: Xcode 27.0 copies none of an
xcframework's `._Vendor.h`, `._Orphan.h`, `._junk.h` (not AppleDouble) and `._sub`, and applies none
as extended attributes; nomac on Linux copied all four before the change and copies what Xcode copies with it. A new
`FSProxyTests.localListingsLeaveOutAppleDoubleFiles` passes on macOS (Xcode 27.0's Swift 6.4),
as Darwin's Foundation behaves. The patch applies to the pin and to upstream `main` at
`fa73f8e7`.

**Suggested PR.**
- Title: *Leave AppleDouble files out of directory listings on non-Darwin platforms*
- Description: *Foundation on Darwin omits files named `._*` from contentsOfDirectory(atPath:)
  and enumerator(atPath:), and Foundation on other platforms does not, so LocalFS.listdir and
  traverse see AppleDouble files only there; ProcessXCFramework then copies an xcframework's `._*`
  headers into the products. Omit them off Darwin as well.*

## 7. Naming Mach-O architectures on every platform

Patch: `.github/upstream/swift-build/0007-architecture-names-off-darwin.patch` (the fork's
`aeb5ba2c`).

**Problem.** `Architecture.stringValue(cputype:cpusubtype:)` names a Mach-O slice through dyld's
`macho_arch_name_for_cpu_type`, which exists only on Darwin, so elsewhere every slice reads as
`unknown`. Copying a stub executable, a sticker pack's or a Messages app's
(`StubBinaryTaskProducer`), then finds no slice for the target's architectures ("does not contain a
slice for 'arm64'") and runs `lipo` without `-extract`, which fails (wikipedia's
`Wikipedia Stickers.appex`).

**Change.** Off Darwin, the CPU types and subtypes of Apple's platforms are named as dyld names
them, with the subtype's capability bits (`CPU_SUBTYPE_MASK`) ignored: `i386`, `x86_64`, `x86_64h`,
`armv6`, `armv7`, `armv7s`, `armv7k`, `armv6m`, `armv7m`, `armv7em`, `arm64` (subtypes 0 and 1),
`arm64e`, `arm64e.x1`, `arm64_32` and `ppc`; other values stay unnamed.

**Evidence.** The names are what `macho_arch_name_for_cpu_type` returns on macOS 27 for each pair
(and `nil` for x86 subtype 8, ARM subtype 0 and 0x01000012), and a new
`ArchitectureTests.namesOfCPUTypesAndSubtypes` that expects them passes on macOS (Xcode 27.0's Swift
6.4), where dyld answers. nomac's `sticker_stub_experiments.py`: on Linux with the patch, the
sticker pack's executable is the stub's `arm64` slice, as Xcode 27.0's. The patch applies to the pin
and to upstream `main` at `fa73f8e7`.

**Suggested PR.**
- Title: *Name Mach-O architectures on non-Darwin platforms*
- Description: *Architecture.stringValue(cputype:cpusubtype:) relies on dyld's
  macho_arch_name_for_cpu_type, so off Darwin every Mach-O slice is "unknown" and copying a stub
  binary (sticker packs, Messages apps) runs lipo without -extract. Name the CPU types and subtypes
  Apple's platforms use as dyld does elsewhere.*

## 8. A binary target's build file with platform filters

Patch: `.github/upstream/swift-build/0008-binary-target-platform-filters.patch` (the fork's
`4c42b1f8`).

**Problem.** `SwiftPackageCopyFilesTaskProducer` asserts that the build files of a package's
binary target, which has no target product, have no platform filters. A project's Frameworks
phase can set platform filters on such a product's build file (kickstarter and pocket-casts), so
a debug build of Swift Build stops there (`Assertion failed`, SwiftPackageCopyFilesTaskProducer.swift
line 174), while release builds, Xcode's among them, compile the assertion out and embed the
first build file.

**Change.** The assertion is removed, and the first build file stands for the others, as in
release builds. On upstream `main` (`fa73f8e7`) the same line sits next to a newer assertion for
build configuration filters, which the same change removes.

**Evidence.** Xcode 27.0 builds both apps (their references); a debug build of nomac stopped there
in the Linux corpus run. The patch applies to the pin.

**Suggested PR.**
- Title: *Return a binary target's build file when an Xcode project gives it platform filters*
- Description: *A project's Frameworks phase can set platform filters on the build file of a
  package's binary product, so the assertion that such build files have none fails in debug
  builds on valid projects. Keep the release behavior without the assertion.*

## 9. Reading static archives on every platform

Patch: `.github/upstream/swift-build/0009-static-archives-off-darwin.patch` (the fork's
`d1842806`). It builds on patch 4 and applies on top of patches 1 to 8.

**Problem.** `StaticArchive.machOs()` reads an archive's members through Darwin's `ar_hdr`
(`<ar.h>`) and throws "Mach-O parsing not supported on this platform" elsewhere, so off Darwin
no static library, thin or universal, can be read: processing a static xcframework fails with
"Cannot open file handle for file at path: <binary>: ... (SWBUtil.BinaryReaderError error 1.)"
(kickstarter's facebook-ios-sdk, braze-swift-sdk, firebase-ios-sdk and GoogleAppMeasurement
xcframeworks), the message `LocalFS.read` gives any error of its reader.

**Change.** Off Darwin, `ar_hdr`, `SARMAG` and `AR_EFMT1` are declared as `<ar.h>` declares
them, and archives are read as on Darwin.

**Evidence.** A new `MachOPortableTests.universalStaticLibraryOfArchives` (a universal library
of two archives, members named in the extended format) passes on macOS; on Linux, nomac built
with the patch reads facebook-ios-sdk 12.3.2's `FBSDKCoreKit_Basics` (universal, arm64 and armv7
archives) as static, 20 objects, as Swift Build does on a Mac.

**Suggested PR.**
- Title: *Read static archives on non-Darwin platforms*
- Description: *StaticArchive reads members through Darwin's ar_hdr and throws elsewhere, so
  static libraries and static xcframeworks cannot be processed off Darwin. Declare ar_hdr and
  the constants it needs as <ar.h> does there.*

## 10. Looking up `what` on every platform

Patch: `.github/upstream/swift-build/0010-what-lookup-off-darwin.patch` (the fork's
`79a7d991`). It applies on top of patches 1 to 9.

**Problem.** `CommandLineToolSpec.parseWhatStyleVersionInfo`, which reads the version of
`coremlc` (and of Reality Composer's tool) before planning their tasks, runs a hard-coded
`/usr/bin/what -q <tool>`. `what` ships only with macOS, so off macOS planning a target with a
Core ML model fails before nomac's `coremlc` runs (nomac B-243).

**Change.** On macOS the probe still runs `/usr/bin/what`; on other hosts `what` is resolved
through the executable search paths, as patch 5 does for `derq`.

**Evidence.** On macOS nothing changes. On Linux (Docker, swift 6.4.1), with nomac's `what` and
`coremlc` launcher in the toolchain, `nomac build` of a self-written app with six Core ML models
(five `.mlmodel`, one `.mlpackage`) plans and runs its 12 CoreML tasks, `** BUILD SUCCEEDED **`; the
32 files they write match Xcode 27.0's build of the same app (30 byte-identical, 2 differing only
in the order of user metadata entries, which Xcode's coremlc changes from run to run).

**Suggested PR.**
- Title: *Look up what through the tool search paths on non-Darwin platforms*
- Description: *parseWhatStyleVersionInfo runs a hard-coded /usr/bin/what, which ships only with
  macOS, so planning tasks whose tool version is read this way (Core ML models) fails on other
  hosts. Keep /usr/bin/what on macOS and resolve what through the executable search paths
  elsewhere, so that a toolchain can provide it.*

## Not a change: `--strip-disallowed-xattrs` (nomac B-115)

Swift Build at the pin adds `--strip-disallowed-xattrs` to codesign on macOS 14 and later
(`0b7017c1`), and Xcode 27.0 did not: Xcode 27.0's Swift Build predates that change, which is
correct and stays upstream. nomac keeps the pin and records the one difference (ADR 0005).

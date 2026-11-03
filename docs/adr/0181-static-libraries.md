# ADR 0181: Static libraries and strip with cctools-port

- Status: accepted (the Expo workstream, 2026-10-24; extends ADR 0104)
- Date: 2026-10-24

## Context

Swift Build makes every static library target with `libtool -static -arch_only <arch> -D
-syslibroot <sdk> -L<dir> -filelist <list> -dependency_info <file> -o <archive>`, and probes it
with `libtool -V` while it plans the build. CocoaPods makes every pod a static library target by
default: expo-default has 19 and rn-bare 9. The swift.org toolchain has no `libtool`, so on Linux
every one of them fails (`/…/libtool -V failed to launch`), and the targets that use their
headers fail after them.

Xcode 27.0's `libtool` reports `cctools_ld-27037.1`, from Apple's new linker project, which is not
open source. cctools-port, which `build-cctools.sh` already builds for `ld64` and `bitcode_strip`
(ADR 0104), has Apple's open-source `libtool` of cctools 1030.6.3.

Observed (`.github/scripts/libtool_experiments.py`, which replays a build log's `Libtool` tasks
with another `libtool` on the same objects):

- Every `Libtool` task of expo-default's Release build by nomac on the Mac (Xcode's compiler, so
  Xcode's objects; Xcode's `libtool`), replayed with cctools-port's `libtool` on Linux: all 19
  archives the same size, with the same members, names, padding, dates, owners and ranlib table,
  but each object member's mode field `100644` where Xcode's is `644`.
- Xcode's `libtool` writes a member's own permission bits, `st_mode & 0777`, with or without
  `-D` (self-written objects with modes 0600, 0755, 04755 and 01644 give `600`, `755`, `755` and
  `644`); the table of contents' mode is `100644`. cctools-port's writes the table of contents'
  mode for every member with `-D`, and the whole `st_mode` without it.
- The dependency info differs only by the version of the tool that wrote it (`27037.1`,
  `cctools-1030.6.3`).

## Options

- **A. cctools-port's `libtool`, patched to write members' modes as Xcode's does.**
- **B. A static library writer in nomac**, from the observed format (BSD `ar`, `#1/<length>`
  names, the ranlib table).
- **C. LLVM's `llvm-libtool-darwin`**, built with lld: another layout to study, and nothing
  observed yet.

## Decision

A. `.github/cctools/0001-libtool-member-modes.patch` keeps each member's mode under `-D` and writes
`st_mode & 0777`; `build-cctools.sh` applies the patches in `.github/cctools` to a copy of the
pristine source (again when they change) and builds `misc/libtool`; `nomac toolchain install`
installs it in the toolchain's `usr/bin` with the other cctools tools.

With the patch, all 19 replayed archives are byte-identical to Xcode's.

## Consequences

- Static libraries of identical objects are identical to Xcode's; of objects the open-source
  compilers wrote, `nomac verify` compares them member by member (docs/VERIFICATION.md "Build
  products").
- `libtool -V` and the dependency info name cctools 1030.6.3, the tool that ran; nothing fakes
  Xcode's version (ADR 0101). Swift Build's probe accepts it: rn-bare's static libraries build on
  Linux, equivalent to Xcode's.
- A second cctools patch to carry; B stays the option that drops the dependency, as for `ld64`.

## Addendum: strip (2026-10-24)

Swift Build's Strip tasks run `strip -D <style> [-T]` (`STRIP_DETERMINISTIC_MODE`, `STRIP_STYLE`,
`STRIP_SWIFT_SYMBOLS`). With no `strip` in the toolchain, Swift Build ran Ubuntu's GNU
`/usr/bin/strip` on expo-default's nested ExpoModulesJSI framework ("file format not
recognized"); on the Mac the same build runs Xcode's toolchain `strip -D -S`.
`.github/scripts/strip_experiments.py` strips a C dylib, a Swift dylib and a Swift executable that
Xcode's tools link with debug information, with the five forms Swift Build's specs give, by Xcode's
`strip` and by cctools-port's (unpatched): 13 of 14 outputs identical; both refuse "all" on the
Swift dylib alike; "all" on the executable differs in the export trie's encoding only (29 bytes,
the same size, load commands and symbols). `build-cctools.sh` builds `misc/strip` and `nomac
toolchain install` installs it with `libtool`.

Run as Swift Build's tasks run it, with the toolchain's `usr/bin` first on `PATH`, cctools-port's
`strip` finds nomac's `codesign` there and signs every ARM binary it strips ad hoc
(`FAKE_SIGN_ARM_BINARY`, "generating fake signature"): expo-default's nested ExpoModulesJSI
framework got an `LC_CODE_SIGNATURE` Xcode's has not. Xcode 27.0's `strip` never signs: an
unsigned input stays unsigned, and a signed one keeps the signature it invalidates, with a warning
(`strip_experiments.py`, which now strips with the tool's directory first on `PATH` and has an
ad-hoc-signed input). `.github/cctools/0002-strip-without-signing.patch` removes the signing:
18 of 19 outputs identical to Xcode's (0 of 19 before), the 19th the export trie above.

`lipo`, the same way: scripts that phases run call it from the toolchain's `usr/bin`, which Xcode
puts first on their `PATH` and where Xcode 27.0 has one; CocoaPods' frameworks script runs
`lipo -info` on each framework it embeds in an archive build, and rn-bare's archive failed on
Linux without one ("lipo: command not found"). `.github/scripts/lipo_experiments.py` runs ten
cases (`-info`, `-archs` and `-verify_arch` on a thin and a universal dylib, `-remove`, `-thin`,
`-extract`, `-create`) with Xcode's `lipo` and cctools-port's (unpatched): all ten alike in
standard output, exit status and the bytes written. `build-cctools.sh` builds `misc/lipo` and
`nomac toolchain install` installs it.

The exports trie, later (B-189): rn-bare's archived executable on Linux kept 55 exports that
Xcode's has not (its Objective-C classes, CocoaPods' dummy classes, global functions). Xcode
27.0's `strip -D` of an executable removes from the exports trie every symbol it removes from the
symbol table, keeping `__mh_execute_header` and the weak definitions (63 exports to 8, on
Xcode's executable and on lld's alike); cctools-port's `strip` prunes the trie only when built
with `TRIE_SUPPORT`, which calls ld64's `prune_trie()`, and cctools-port ships neither.
`.github/cctools/0004-strip-prunes-the-exports-trie.patch` defines `TRIE_SUPPORT` for strip and
adds `prune_trie()`, which writes the kept exports' trie as Xcode's `strip` does: the root first,
each of its child offsets a ULEB128 padded with zeros to 5 bytes, every other node after its
children, edges in byte order of their labels, the trie padded with zeros to 8 bytes where the
old one starts, the rest of the old bytes and the load command's size left as they were (read off
Xcode's output, byte for byte on both executables). `strip_experiments.py` gains an executable
that exports globals, an Objective-C class and C++ weak definitions: 24 of 24 outputs identical
to Xcode's, the "all" form on the Swift executable among them; both tools refuse "all" on the
Swift dylib.

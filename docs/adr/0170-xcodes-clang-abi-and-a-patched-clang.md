# ADR 0170: Xcode's C++ ABI from swift.org's clang, and a patched clang for the rest

- Status: accepted (the ABI by the clang workstream, the patched clang by the owner, 2026-10-30: built by users, nothing published)
- Date: 2026-10-30

## Context

On Linux, objects nomac compiled defined and referenced other C++ symbols than Xcode's: rn-bare's
`libReactCodegen.a` and `libreact-native-safe-area-context.a` named `Node<Name>` (a
`const char *` template argument given an array) `XadsoKcL_Z4NameEE` where Xcode's name it
`XadL_Z4NameE`. The apps linked, because each side instantiates those templates itself, but a
reference into a prebuilt library that Xcode's clang compiled (React Native's prebuilt frameworks,
any vendor xcframework with C++ templates) would not resolve. The difference had been put down to
`-clang-vendor-feature=+revert09abecef7bbf`, one of six vendor features Xcode's driver passes and
swiftlang's clang does not accept, with no `-fclang-abi-compat` level helping. The owner approved
building a patched clang for it.

Observed with `.github/scripts/clang_abi_experiments.py` and Xcode 27.0 (27A266a), observation only
(docs/formats/build.md "Clang's C++ ABI"):

1. Xcode's clang mangles `Node<Name>` the same with any vendor feature turned off; the upstream
   commit `09abecef7bbf` is a 2020 fix to where a local class's elaborated type specifier is
   declared (PR48002), not a mangling change.
2. Xcode's clang, without any flag, gives at every target the output it gives with
   `-fclang-abi-compat=4.0` (3.8 too), and not that of any later level: mangling, record layout and
   argument passing. Its Swift compiler's Clang importer adds `-fclang-abi-compat=4.0` to its own
   arguments.
3. swift.org 6.4.0's clang with `-fclang-abi-compat=4.0` writes Xcode's symbols, code and data for
   every self-written case, arm64 and x86_64; its importer with `-Xcc -fclang-abi-compat=4.0`
   writes Xcode's C++ symbols. Without the flag, layouts and argument passing differ as well: a
   class with deleted copy and move constructors goes in memory instead of in registers.
4. The level is part of a module's configuration. The importer of an installed swift-frontend
   reads the toolchain's `clang.cfg` (removing the flag from it brings back `XadsoKc…`), yet with
   the flag only there, rn-bare's Swift compiles on Linux could not load the SDK's modules built
   for them ("version of Clang that we should attempt to be ABI-compatible with differs in
   precompiled file"); with `-Xcc -fclang-abi-compat=4.0` in the Swift flags as well, they do.
5. What remains between the two clangs is Objective-C and `this`: Xcode's clang writes collection
   and number literals as constant objects from iOS 14 and calls `objc_opt_respondsToSelector`
   from iOS 13, and `thisNoNullAttr` and `thisNoAlignAttr` keep `this == nullptr` tests (B-170).
   Upstream LLVM has the constant literals since 2026 (llvm-project #185130 and its follow-ups);
   swiftlang's `swift-6.4.0-RELEASE` does not, and no open-source clang has
   `objc_opt_respondsToSelector` or the vendor features.

## Options

- **A. The ABI from a flag.** `-fclang-abi-compat=4.0` in the toolchain's `clang.cfg` and
  `clang++.cfg` (written by `nomac toolchain install`, read by every clang compile), and
  `-Xcc -fclang-abi-compat=4.0` among the Swift flags nomac adds off macOS. Cost: none; a
  developer directory installed by an earlier nomac has to be installed again.
- **B. A patched clang for the ABI.** Builds and ships a compiler to change one default the flag
  already sets.
- **C. A patched clang for what no flag gives** (observation 5). swiftlang/llvm-project at the
  installed toolchain's tag, built by `build-llvm-tools.sh` as `lld` is (ADR 0102) with patches in
  `.github/clang`: the upstream literal commits backported, and `objc_opt_respondsToSelector` and
  the two `this` features written from Xcode's observed output, each with an experiment against
  Xcode's objects. Cost: a clang build per Swift release, and backports to keep while swiftlang lacks
  them.

## Decision

A, now. B is rejected: the flag reproduces Xcode's ABI exactly, and the guard below covers the
only way to get it wrong.

C as well, accepted by the owner on 2026-10-30 with nothing published. `build-llvm-tools.sh` with
`CLANG=1` builds `clang` (arm64 and x86_64 targets) with `.github/clang`'s patches: 0001 to 0009
backport upstream's constant literals (llvm-project #185130, #189058, #191091, #195000, #200303,
#201877, #204208, #209688, #209927; adaptations noted in each header), 0010 calls the `objc_opt_`
entrypoints, 0011 leaves `nonnull`, `dereferenceable` and `align` off `this` for Apple targets
and 0012 compiles blocks passed to non-escaping parameters as other blocks, all three written from
Xcode's observed output, 0013 and 0014 backport upstream's selector stubs (llvm-project
#186293, #186433), on from Xcode's linker version, 0015 calls the register-specific ARC entry points
from the AArch64 backend, 0016 claims `-fmodules-cache-path` as Xcode's driver does, 0017 calls
Apple's stack probe where Xcode's driver turns stack checks on, 0018 leaves variable length arrays
to SelectionDAG at -O0, 0019 gives stack-protected functions with a personality Xcode's cleanup
landing pad, 0020 to 0024 reproduce Xcode's driver defaults and vendor features that no
configuration file can (`@import` in a module's implementation, folded array bounds, the revert of
llvm-project 09abecef7bbf, fields of the current instantiation, `TARGET_OS_` warnings), 0025
calls the probe through an authenticated pointer for arm64e, 0026 checks arm64e's lr before tail
calls, 0027 costs ARC operations in the inliner as Xcode's and 0028 searches the comments of a
declaration in its own file (a crash with -Wdocumentation), all written from Xcode's observed output (docs/formats/build.md "Objective-C literals,
runtime entrypoints and `this`", "Stack checks", "Exception tables of stack-protected functions",
"Clang's driver", "arm64e tail calls", "Inlining of ARC code", "Comments of declarations in
included files"). The script also builds libclang from the same source: Swift Build's
dependency scan runs clang's driver from the toolchain's `libclang.so`, and the compiles run the
command lines it plans. `nomac toolchain install` copies both over the files the swift.org
toolchain's `clang` and `lib/libclang.so` link to (`clang-21`, `libclang.so.21.0.0`; the same
exported functions and symbol versions) when the LLVM tools directory has them, so `clang`,
`clang++`, `cc` and `c++` all run the patched clang, refuses one without the other or a clang
built with other patches than its own (the script writes the SHA-256 of `.github/clang`'s patches
next to it, `clang.patches.sha256`), and keeps swift.org's otherwise: the patched clang is optional
and nomac prefers it when installed. Users build it with the script; the clang workstream publishes
the one built at main's patches in the shared `nomac-build` volume's `/ref/llvm-tools`.

## Consequences

- C++ that nomac compiles on Linux has Xcode's symbols and Xcode's layouts, and can call into and
  be called from C++ that Xcode's clang compiled.
- `nomac build` refuses a developer directory whose `clang.cfg` is not the one this nomac
  installs, with the reason, instead of failing on the SDK's modules.
- Swift's command lines on Linux carry one more `-Xcc` flag; Xcode's importer has it among the
  arguments it adds itself, so the modules' configurations match Xcode's.
- Code that a project compiles with its own `-fclang-abi-compat` keeps its choice: the project's
  flags come after the configuration file's.
- With the patched clang, Objective-C literals, the five messages and `this` compile as Xcode's;
  without it they stay documented differences. Its producer string is swiftlang's clang 21 built
  from a source archive, not swift.org's binary's. What Xcode's driver passes that neither clang
  does and no patch reproduces yet stays B-170.

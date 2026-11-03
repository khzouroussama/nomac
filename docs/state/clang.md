# Clang: state

Workstream: what swift.org's clang compiles otherwise than Xcode 27.0's, and the patched clang the
owner approved for it (built by users, nothing published). Part of the build driver's range:
BACKLOG B-170 (B-171–B-179 went to the Linux-corpus workstream; ask the owner for more numbers),
ADRs 0170–0179. Branch `build/clang`. Decisions: ADR 0170; rules: docs/formats/build.md "Clang's
C++ ABI" and "Objective-C literals, runtime entrypoints and `this`".

## Current step

The patched clang (`build-llvm-tools.sh` with `CLANG=1`: clang and libclang with `.github/clang`'s
twenty-nine patches) compiles Objective-C literals, the `objc_opt_` messages, `this`, non-escaping
blocks, selector stubs, the register-specific ARC entry points, Apple's stack probe (arm64e too),
the exception tables of stack-protected functions and the effects of Xcode's driver defaults and
vendor features and arm64e's lr checks before tail calls as Xcode's, and `nomac toolchain install`
installs it when it is built. B-170's remaining items need observations not yet found (see Next
actions).

## Just finished

- `.github/clang` 0029: matrix intrinsic lowering on by default, as Xcode's LLVM (the extra
  `early-cse` it brings kept moonlight's `ConnectionTester.c` loop scalar at -Os, so no
  `__literal16`/`__literal8`); `ConnectionTester.o` byte-identical to Xcode's at -Os and -O2,
  `clang_driver_experiments.py` 42 of 42, the stack and Objective-C experiments unchanged.
- The patched clang and libclang at main's `.github/clang` are in the shared `/ref/llvm-tools` with
  `clang.patches.sha256`, which `build-llvm-tools.sh` writes with `CLANG=1` and `nomac toolchain
  install` checks as it checks lld's (the expo workstream's Objective-C constant literals).
- B-193 done: `.github/lld` 0027 lays archive members out at the archive's place on the command
  line, in the archive's order (the profile runtime's `__cstring`, `__bss` and `__common` order);
  `ld_layout_experiments.py`: 44 of 44 cases as Xcode's `ld`.
- B-193: `.github/lld` 0021 lays out `__unwind_info` as Xcode 27.0's `ld` (common encodings only
  for more than one entry, pages at their size, the index's reserved entries, the sentinel), 0022
  orders the GOT (own symbols, each dylib's, weak definitions, flat lookups; by name), 0023 puts
  `__objc_methlist` after `__init_offsets` and `__oslogstring` last in `__TEXT`, 0024 writes the
  literals into `__TEXT,__const` at their first occurrence, 0025 lays merged categories and
  `__objc_methlist` out as Xcode's (first category kept, untouched lists kept, Xcode's names,
  protocol method lists relative, by name, 8-byte aligned), 0026 folds the address of a class
  reference into the class's GOT slot (swiftfin's `__objc_classrefs`);
  `ld_layout_experiments.py`: 41 of 42 cases as Xcode's `ld` (the profile runtime's `__bss` and
  `__cstring` order left in B-193).
- B-193: `.github/lld` 0018 orders `__DATA_CONST` and `__DATA` as Xcode 27.0's `ld` (known sections
  in one fixed order, the others in input order, then `__thread_vars`, `__got`, thread data and
  zerofill in input order), 0019 merges categories by default, 0020 merges `+load` categories as
  Xcode's `ld` (into a class of the image with one `+load` in all, then listed in
  `__objc_nlclslist`; none of a dylib class's categories when one has `+load`);
  `ld_layout_experiments.py`: 13 of 22 cases as Xcode's `ld`, the `+load` ones with Xcode's lists in
  all seven (the others: merged list names and layout, `__bss` against `__common` with the profile
  runtime; B-193).
- swiftfin's linker differences (Linux-corpus run): `.github/lld` 0014 puts class, protocol and
  superclass references in `__DATA_CONST` from iOS 17.4 and loads classes through the GOT from iOS
  18, 0015 loads archive members in sorted rounds (the weak `_vlc_thread_set_name`), 0016 applies
  no linker optimization hint, as Xcode 27.0's `ld` applies none, and 0017 links `-alias` of a dylib
  symbol (the sweep's widget debug dylib); `ld_layout_experiments.py`: 9 of 9 cases as Xcode's
  `ld`. `_getCurrentlyParsingParser` was a compiler difference: `.github/clang` 0027 costs ARC
  operations in the inliner as Xcode's (SVGKit keeps its 7 calls). `.github/clang` 0028: no crash
  on the doc comments of methods an `@implementation` includes (the sweep's rocketchat).
- `.github/clang` 0026: arm64e checks lr after `autibsp` before a tail call (`eor`, `tbz`, `brk
  #0xc471`) where Xcode's clang does (`ptrauth-returns` and `ptrauth-auth-traps`, lr spilled);
  `clang_stack_experiments.py`: 56 of 60 objects identical (the cleanup objects all). The alloca
  rounding order: Xcode's rounds before the probe call for 2-, 4- and 8-byte elements counted by an
  `int`; neither the size passed as an extra operand nor the rounding built by the lowering before
  the call sequence reproduces it (left in B-170).
- Xcode's driver defaults (docs/formats/build.md "Clang's driver"): `clang.cfg` gets
  `-fno-assume-unique-vtables` and `-Wno-elaborated-enum-base`; `.github/clang` 0020 (no "@import
  of module in implementation" error), 0021 (array bounds folded to constants in GNU modes), 0022
  (llvm-project 09abecef7bbf reverted), 0023 (fields of the current instantiation stay
  type-dependent) and 0024 (no `-Werror=undef-prefix`), 0021 to 0023 for Apple targets only, as
  Xcode's vendor features. `clang_driver_experiments.py`: 34 of 34 cases as Xcode's (22 with
  swift.org's clang and the new `clang.cfg`). `-fno-odr-hash-protocols` and
  `-Wno-error=allocator-wrappers`: no effect observed.
- `.github/clang` 0025: the arm64e probe call through `l___chkstk_darwin$auth_ptr$ia$0$addr`;
  `clang_stack_experiments.py` gets an arm64e target, 54 of 60 objects identical (the others: the
  alloca scheduling twice, three arm64e differences away from the probe).
- `.github/clang` 0017: `-fstack-check` where Xcode's driver passes it (Apple devices from macOS
  10.15, iOS and tvOS 13, watchOS 6, Mac Catalyst, visionOS) and `___chkstk_darwin` calls as Xcode's
  arm64 and x86_64 backends make them (frames of 4096 bytes or more, every dynamic alloca);
  0018: GlobalISel leaves variable length arrays to SelectionDAG at -O0, as Xcode's.
  `clang_stack_experiments.py`: 24 of 24 driver cases, 31 of 32 objects byte for byte (the other:
  Xcode's scheduler rounds an alloca of 8-byte elements before the call); netnewswire's Minizip has
  Xcode's probed function. 270 of the 274 reference objects calling the probe are Swift's (B-170).
- `.github/clang` 0019: a function with a personality whose stack objects the stack protector
  guards gets Xcode's cleanup landing pad for its calls that may unwind (not tail calls); the
  experiment's 16 C++ objects and RNReanimated's `REACSSPlatformProps.o` (the exception table both
  clangs lacked) are Xcode's byte for byte.
- `.github/clang` 0015: `objc_retain_x<N>`/`objc_release_x<N>` from the AArch64 backend, in the
  shape of Xcode's MIR (a copy into a new register after instruction selection, `gpr64noip` and
  `tcgpr64` orders, the ordinary register mask for retain). netnewswire's RSDatabaseObjC: 7 of 7
  objects call Xcode's ARC entry points, 5 have Xcode's code byte for byte;
  `clang_objc_experiments.py` gets an iOS 17.0 target, 11 of its 12 cases identical.
- `.github/clang` 0016: `-fmodules-cache-path` claimed as Xcode's driver does (a `-Werror` target
  without modules failed); `clang_driver_experiments.py`: 15 of 20 cases as Xcode's with
  swift.org's clang, 20 with the patched one.
- Selector stubs: `.github/clang` 0013 and 0014 backport llvm-project #186293 and #186433, on
  from the linker version, which `clang.cfg` now gives as Xcode's (`-mlinker-version=1166.2`):
  `objc_msgSend$<selector>` calls for arm64 Apple targets, no class-message stubs, as Xcode's.
  The 44 arm64 object cases of `clang_objc_experiments.py` have Xcode's symbols with stubs on
  both sides; RSDatabaseObjC's six objects call Xcode's stubs; lld writes `__objc_stubs` as `ld`.
- `-fcommon` and `-fno-strict-return` in the toolchain's `clang.cfg`, as Xcode's driver passes
  them for every Apple target (a command line's `-fno-common` still wins); C tentative
  definitions are common symbols again. The ARC register entrypoints observed (B-170) and put
  after selector stubs, which change the register choices they depend on.
- `.github/clang` 0012: a block passed to a non-escaping parameter is a stack block with helpers
  and its `__block` variables keep their byref structure, as with Xcode's clang (iOS 12 to 18,
  macOS, Linux, any ABI level); `-Wimplicit-retain-self` still leaves such blocks alone. The block
  cases of `clang_objc_experiments.py` get Xcode's symbols (0 of 8 before); netnewswire's
  `FMDatabase.o` and `FMDatabase+RSExtras.o` import `_NSConcreteStackBlock` as Xcode's do. Their
  code differs as escaping blocks' does with swift.org's clang (backend, ADR 0101).
- The C++ ABI (merged at `a772610`): Xcode's clang and Swift importer follow Clang 4's ABI unasked;
  nomac's toolchain asks swift.org's for it (`clang.cfg`, `-Xcc` in the Swift flags).
- `.github/clang` 0001–0009 backport upstream's constant literals (llvm-project #185130 and its
  follow-ups; adaptations in each header); 0010 (`objc_opt_class`, `_self`, `_new`,
  `_isKindOfClass`, `_respondsToSelector` from iOS 13) and 0011 (`this` without `nonnull`,
  `dereferenceable`, `align` for Apple targets) are written from Xcode's output. clang reports
  21.0.0 as swift.org's does (the source says 21.1.6). Where no patch applies it writes swift.org
  clang-21's bytes.
- libclang is needed too: Swift Build's dependency scan runs clang's driver from the toolchain's
  `libclang.so`, so with swift.org's the compiles got the cc1-level patches but no literals.
- `.github/lld` 0009: the literals' six sections in `__DATA_CONST`, as Xcode's `ld` puts them.
- `clang_objc_experiments.py`: 28 of 36 arm64 cases identical to Xcode's (9 with swift.org's
  clang); the 8 others are -Os optimizer differences both clangs share.
- On Linux, rn-bare Release 2/12 identical and 3 equivalent → 2 and 6; expo-default Release 1/35
  and 15 → 1 and 18. Xcode's own products use literals or `objc_opt_` calls in 6 of rn-bare's 33
  objects and binaries and 34 of expo-default's 880. In the corpus's Xcode references, literals in 33
  objects and binaries of 8 apps and the four `objc_opt_` calls (`_self` left out, Swift calls it) in
  65 of 11; wikipedia on Linux 22 different, 12 equivalent → 20 and 14 (`CocoaLumberjack.o`,
  `SDWebImage.o`). Reproduce: `~/nomac-out/clang-exp/verify-corpus.sh` (the Linux-corpus
  workstream's `verify.sh` in this volume, `DEVDIR=devdir-patched`, or for the baseline a developer directory installed from `/work/tools-patched` without `clang` and `libclang.so`). What remains: selector stubs (230 of
  expo-default's), the ARC entrypoints, the stack checks, other driver defaults and one missing
  exception table that both clangs share (B-170).

## Next actions

1. The linker differences of the next Linux corpus round (measured with lld 0001 to 0027).
2. The alloca rounding order (B-170): find an observable of Xcode's DAG order (other shapes, `-O1`,
   `-mllvm` scheduler options Xcode's release clang accepts) before another construction.
3. arm64e's -O0 register choices (`ldrsw x10` for `ldrsw x9` in leaf functions).
4. Remeasure the corpus with the Linux-corpus workstream once this batch is on main.

## Reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/clang_abi_experiments.py xcode <out>                # Mac
python3 .github/scripts/clang_objc_experiments.py xcode <out>
python3 .github/scripts/clang_stack_experiments.py xcode <out>
python3 .github/scripts/clang_driver_experiments.py xcode <out>
CLANG=1 JOBS=14 .github/scripts/build-llvm-tools.sh <llvm-out>             # Linux, in Docker
nomac toolchain install <swift.org usr> --llvm-tools <dir with lld, dsymutil, clang, libclang.so, cctools'>
python3 .github/scripts/clang_abi_experiments.py run <out> <developer-dir>  # Linux, an installed toolchain
python3 .github/scripts/clang_objc_experiments.py run <out> <developer-dir>
python3 .github/scripts/clang_stack_experiments.py run <out> <developer-dir>
python3 .github/scripts/clang_driver_experiments.py run <out> <developer-dir>
```

The `nomac-clang` Docker volume (about 13 GB) holds nomac's Linux build at `/work/build` (copy the
Mac's `.build/repositories`, `checkouts` and `workspace-state.json` into it for an offline build
after main changes its packages), the patched LLVM source and build tree at `/work/lld-work`
(3.5 GB; a header-only patch change rebuilds nothing), `/work/tools-patched` (lld, dsymutil,
cctools' tools, the patched clang and libclang) and `/work/devdir-patched`, a developer directory
installed from them. The pristine source and the app checkouts were deleted to save disk: before a
patch change copy the pristine tree back from the `nomac-build` volume
(`/ref/lld-work/llvm-project-swift-6.4.0-RELEASE.orig`); rn-bare and expo-default need their
checkouts again (docs/state/react-native.md "Reproduce"). Do not sync `/work/src` while
`build-llvm-tools.sh` runs from it.

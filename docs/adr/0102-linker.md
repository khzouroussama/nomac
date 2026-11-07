# ADR 0102: Linking with swiftlang's lld, and Xcode's other tools on Linux

- Status: accepted
- Date: 2026-10-22

## Context

Swift Build links with `clang`, which runs `ld`; it also runs `dsymutil`, `tapi stubify` and the
App Intents tools (`appintentsmetadataprocessor`, `appintentsnltrainingprocessor`) for every
Swift framework. Xcode's versions are macOS binaries, and most are closed. Under ADR 0101
(option A), compiled outputs must be equivalent to Xcode's (same symbols and structure, every
difference documented) and nothing may fake a tool's version.

Observed while building retro-rampage's `Engine` (Release, generic iOS) in `swift:6.4.1-noble`
(arm64) and on the owner's Mac with Xcode 27.0 (27A266a):

1. **Linkers.** swift.org's `ld64.lld` refuses every Apple platform (a "Swift LLVM fork downstream
   change" in `lld/MachO/InputFiles.cpp`). Rebuilt without that check (swiftlang/llvm-project at
   `swift-6.4.0-RELEASE`), and upstream LLVM 21.1.8's, it stops on the iOS 27.0 SDK's stubs:
   TextAPI does not know `arm64e.x1`. Xcode's clang gives `-arch arm64e.x1` objects CPU type
   `CPU_TYPE_ARM64` and subtype `0x8000000c` (`arm64e` is `0x80000002`). With `arm64e.x1` added to
   TextAPI's architecture table as subtype 12, lld links `arm64` against the SDK's
   `arm64e`-only stubs by its same-CPU-type rule, as ld64 does.
2. **lld on Xcode's own objects.** With Xcode's Ld command, lld links Xcode's 30 objects of
   `Engine`. Against Xcode's binary: the same 785 exports and the same libraries (unpatched, lld
   writes other versions for `libswiftDarwin`, item 9); load commands in another order and no
   `LC_SOURCE_VERSION`; `__TEXT,__text` 100,508 bytes for 91,916,
   `__TEXT,__unwind_info` 4,336 for 1,976; lld adds `__TEXT,__literals` and
   `__DATA,__objc_clsrolist` and has no `__TEXT,__objc_methtype`. Xcode's `ld` is `ld-27037.1`, not
   open source; its layout could be studied from ld64's published sources, cctools and
   cctools-port, but a linker that reproduces it only pays off if the objects are Xcode's
   (ADR 0101 rules that out).
3. **clang's link arguments.** Xcode's clang was built with linker version 1166.2 (it passes
   `-target-linker-version 1166.2` to every compile) and gives `ld` `-platform_version ios 15.0.0
   27.0`. swift.org's clang has no linker version and gives `-iphoneos_version_min 15.0.0`, which
   lld rejects. With `-fuse-ld=lld` it gives lld `-platform_version`.
4. **Swift Build's linker probe.** Swift Build asks `ld -version_details` and passes
   `-reproducible` (from ld64 804), `-no_warn_duplicate_libraries` (1015.3) and
   `-add_mergeable_debug_hook` (1217) only to linkers that report those versions (SWBCore
   `LinkerTools.swift`). lld answers `--version` with `LLD 21.1.6`, so Swift Build drops them;
   lld zeroes debug-map timestamps by default (`zeroModTime`), which is what `-reproducible`
   does. A GNU `ld` on the machine would otherwise be taken for the linker.
5. **dsymutil.** LLVM 21.1.6's `dsymutil`, on Xcode's binary and objects, writes Xcode's DWARF and
   relocations byte for byte. Its Info.plist differs: dsymutil reads the bundle identifier and
   versions with Core Foundation only on Apple platforms (`tools/dsymutil/CFBundle.cpp`), so on
   Linux it wrote `com.apple.xcode.dsym.Engine.framework` for Xcode's
   `com.apple.xcode.dsym.com.charcoaldesign.Engine`.
6. **tapi stubify.** Xcode's `tapi` (Apple TAPI 21.0.0, tapi-2100.3.8.1) is closed. LLVM's
   `llvm-readtapi --stubify` finds the same symbols but sorts them into `text` and `data`
   differently and pretty-prints. `.github/scripts/tapi_experiments.py` (22 self-written dylibs)
   shows tapi's rules (docs/formats/tbd.md): compact JSON with sorted keys and a final newline;
   Swift-mangled exports are `data` even when they are functions; a current or compatibility
   version of 1.0.0 is left out, each on its own (`versions-1.0`, `current-1.0`,
   `compatibility-1.0`, and retro-rampage's `Engine`).
7. **App Intents tools.** Closed. For `Engine`, which uses no App Intents, the metadata processor
   writes only an empty strings table and the training processor writes nothing.
8. **Routing tools.** Swift Build finds external tools in the toolchain's `usr/bin` first and runs
   in-process builtins (`builtin-copyStrings`, `builtin-infoPlistUtility`) itself: their specs
   come only from Swift Build's plugins and their task actions are created in-process, so no
   setting, path or spec in the developer directory can replace them.
9. **Libraries renamed by `$ld$previous$`.** In the iOS 27.0 SDK, `libswift_Builtin_float` and
   the `libswift_DarwinFoundation` stubs become `libswiftDarwin` for deployment targets 12.2 to
   18.0, and Foundation.framework moves symbols to `libswiftFoundation` (version 1.0.0) for 12.2
   to 16.0. On `Engine`, lld wrote `libswiftDarwin` 0.0.0 where Xcode's `ld` wrote 428.0.10.
   `.github/scripts/ld_experiments.py` (29 variants of self-written stubs, docs/formats/build.md
   "Libraries renamed by `$ld$previous$`") found Xcode's rule; the third patch gives lld that rule,
   and lld then writes what Xcode's `ld` writes in every variant and on `Engine`. When two
   libraries move symbols to one name, the first loaded gives its versions, and Xcode's `ld` loads
   the frameworks the objects autolink before the libraries, each sorted by name, where lld
   follows the objects' order: flappy-fly-bird's `libswiftCoreGraphics` (moved to from
   CoreGraphics with 1.0.0 and from `libswiftCoreFoundation` without a version) was 1.0.0 in
   Xcode's binary and 120.100.0 in nomac's. The fourth patch loads them as Xcode's `ld` does.
10. **Objective-C metadata.** retro-rampage's app, its objects compiled on Linux, has Xcode's
   Objective-C sections in every object (selector references aside, ADR 0101), but not in the
   image. `.github/scripts/objc_link_experiments.py` links the same self-written Objective-C
   and Swift objects (a class, a category on it and one on `NSObject`; iOS 13.0, 14.0, 15.0,
   17.0 and 26.0) with Xcode's `ld` and with lld, with the same arguments:
   - Xcode's `ld` merges a category into its class when the class is in the image, at every
     target (`__objc_catlist` lists only the category on `NSObject`; `-no_objc_category_merging`
     lists both). lld does the same with `-objc_category_merging`, and not without it.
   - Xcode's `ld` makes the method lists relative from iOS 14.0 (`__TEXT,__objc_methlist`, whose
     lists' first word has the high bit set; `-no_objc_relative_method_lists` keeps them in
     `__objc_const`), clang's and Swift's alike. lld does so from iOS 14.0 too, but only for the
     lists clang emits in their own `__objc_methlist` section and for the lists it merges; a
     Swift class's own list, in `__objc_const`, stays absolute.
   - lld writes class names and method types into `__TEXT,__cstring`; Xcode's `ld` keeps
     `__TEXT,__objc_classname` and `__TEXT,__objc_methtype` (the tenth patch keeps them apart,
     item 15).
   - lld writes `__TEXT,__unwind_info` with second-level pages of 4,096 bytes (4,152 to 4,188
     bytes in every variant, 88 to 288 for Xcode's `ld`).
11. **Chained fixups.** Xcode's `ld` writes dyld's opcodes (`LC_DYLD_INFO_ONLY`, lazy binding
   through `__stub_helper`) instead of chained fixups (`LC_DYLD_CHAINED_FIXUPS`,
   `LC_DYLD_EXPORTS_TRIE`) whenever the link has `-undefined dynamic_lookup` or `-undefined
   suppress`, wherever it is among the arguments and whatever comes later, for dylibs, bundles and
   executables, at every deployment target, and even when nothing stays undefined; `-fixup_chains`,
   before or after, restores chained fixups, and `-U <symbol>` or `-flat_namespace` alone does not
   turn them off. Initializers stay in `__TEXT,__init_offsets` there, as at every target from iOS
   13.4, where chained fixups start for both linkers; only an explicit `-no_fixup_chains` (or a
   target below 13.4) gives `__mod_init_func`. lld wrote chained fixups in all those cases, and
   ties its initializer offsets to them (`ld_experiments.py`'s `fixups-*` and `init-*` variants;
   expo-default's ExpoModulesJSI framework, linked with `-undefined dynamic_lookup` for iOS 15.1).
   The fifth patch gives lld Xcode's rule; it then writes Xcode's load commands, sections,
   rebases, binds and lazy binds in every variant (`dyld_info -fixups`); executables' export tries
   list the same symbols in another order. Under `-flat_namespace`, Xcode's `ld` gives undefined
   symbols library ordinal 0 and lld 254, which dyld ignores without `MH_TWOLEVEL` (B-126).
12. **Pointers to thread-local variables.** For a thread-local variable another image may define
   (a weak definition, or one imported from a library), Xcode's `ld` keeps the pointer to its
   descriptor in `__DATA_CONST,__got` with the other non-lazy pointers; lld wrote a
   `__DATA,__thread_ptrs` section (`ld_experiments.py`'s `tlv-*` variants; expo-default's
   ExpoModulesJSI framework). The sixth patch puts them in `__got`, as Xcode's `ld` does.
13. **Debug maps through relocatable objects.** Swift Build links each Swift package product into
   a relocatable object (`clang -r`); Xcode's `ld` and cctools' `ld64` leave the inputs' DWARF
   out of it and write stabs naming them (`SO`, `OSO`, `FUN`, `STSYM`, `GSYM`). Xcode's `ld`
   carries those groups into the image, `static` functions included, so dsymutil reads the
   original objects; lld wrote stabs only for inputs with DWARF, and expo-default's nested
   ExpoModulesJSI framework got an empty debug map and a dSYM without DWARF. The seventh patch
   emits each input stab group's object, with its source, path and modification time, and the
   output addresses of the symbols it names; `ld_experiments.py`'s `stabs-relocatable` then
   gives Xcode's debug map (`dsymutil --dump-debug-map`) and the same DWARF in the dSYM, the
   UUID aside. The stabs keep lld's own layout (one `SO` with the full path, no `BNSYM`/`ENSYM`,
   no leading empty `SO`), which Xcode's `ld` writes for DWARF inputs too.
14. **Weak imports of moved symbols.** A symbol a library's `$ld$previous$` moves to another
   library is a weak import in Xcode's `ld` whenever the library that moves it is weakly linked
   (`LC_LOAD_WEAK_DYLIB`: every import of its own symbols weak, or `-weak-l`), whatever the
   references to the moved symbol; lld kept it strong. flappy-fly-bird's binary imports CGFloat's
   descriptor, which `libswiftCoreFoundation` moves to `libswiftCoreGraphics` below iOS 16.0,
   weakly in Xcode's build: its other imports from `libswiftCoreFoundation` are the weak
   `__swift_FORCE_LOAD_$_swiftCoreFoundation`. `.github/scripts/ld_weak_experiments.py` (9
   variants) found the rule; the eighth patch gives lld that rule, and lld then writes Xcode's
   imports and load commands in all 9 (5 before) and in flappy-fly-bird's binary.
15. **C-string sections and literals.** Xcode's `ld` keeps every C-string literal section under
   its own name: `__cstring`, `__objc_methname`, `__objc_classname` and `__objc_methtype` with
   equal strings merged across objects, `__oslogstring` and any other (a custom
   `__nomac_strs`) with every string kept; it writes 16-byte literals into `__TEXT,__const`, one
   copy for equal ones. lld wrote every C-string section but `__objc_methname` into one
   deduplicated `__cstring` and the literals into `__TEXT,__literals`
   (`ld_experiments.py`'s `sections-*` variants; rn-bare Debug's stub executor, whose
   `__oslogstring` and `__const` were Xcode's only). The tenth patch gives each C-string section
   its own output section with Xcode's merging, and names the literals' section `__const` when
   the image has no `__TEXT,__const` of input sections, which lld cannot mix with them; with
   one, both images have `__const` and lld's `__literals` stays its own. Literals that carry
   symbols (no compiler emits them) Xcode's `ld` keeps one per object, lld merges.
16. **Dead-stripped class references.** With `-dead_strip`, Xcode's `ld` drops an
   `__objc_classrefs` entry, and the class's import, with the code that uses it, although clang
   marks the section `no_dead_strip`; it keeps `__objc_selrefs`, also `no_dead_strip`, and writes
   no `__cstring` when every string in it is dead. lld kept both reference sections and wrote an
   empty `__cstring` (`ld_experiments.py`'s `dead-strip-classrefs`: unreferenced code that uses
   `NSObject`, a selector and a string; the RN holdout's rn-native widget, whose
   `GeneratedAssetSymbols.swift` calls `Bundle(for:)` from code nothing references, imported
   `NSBundle` on Linux only). The eleventh patch roots `no_dead_strip` sections but class references,
   and writes a C-string section only when a string in it is live.
17. **Libraries only dead code used through moved symbols.** With `-dead_strip`, Xcode's `ld` counts
   a reference to a symbol `$ld$previous$` moves to another install name only if dead stripping
   keeps the code or data that makes it; a library is still recorded for any reference to its own
   symbols, dead or not, and an explicitly linked library nothing resolved through is kept. So a
   library whose only use was resolving such symbols for dead code is dropped, autolinked or
   explicit; with a live reference its load command has the moved symbol's versions
   (`ld_experiments.py`'s `autolink-*` and `explicit-*` variants: a child, re-exported by `libP`
   and allowed only to it, that moves `_c` to `libP`, as SwiftUICore moves SwiftUI's `Color` to
   SwiftUI below iOS 18.0). rn-bare's executable: `GeneratedAssetSymbols.o` autolinks SwiftUI and
   calls `Color.init(_:bundle:)` only from dead code, and Xcode's binary does not load SwiftUI. lld
   decided before dead stripping and kept it. The twelfth patch records the dylibs that relocations
   of live sections reference, emits a load command for a moved symbol's install name only for live
   references, and none for a dylib whose only use was resolving moved symbols.
18. **Bindings to re-exported dylibs.** A dylib loaded as another's re-export binds its symbols
   through that umbrella unless it is public (in `/usr/lib`, or a framework's own binary in
   `/System/Library/Frameworks`) and allows every client; loaded directly as well, autolinked or
   explicit, Xcode's `ld` binds them to the dylib itself, if the image may link it
   (`ld_experiments.py`'s `binding-*` variants: Swift objects autolink `libswift_Builtin_float`,
   which `libswiftDarwin` re-exports from `/usr/lib/swift`). Whether the image may is decided by
   the client name, the install name's leaf without `lib` up to its first `.` or `_` (an executable's
   comes from its output file unless `-client_name` says otherwise, docs/formats/extensions.md; lld
   does not do that yet, B-313), which must begin one of the dylib's allowable clients: SwiftUICore allows `AppKit`, so a debug dylib `App.debug.dylib` binds its SwiftUI
   imports to SwiftUICore and `MyApp.debug.dylib` to SwiftUI (the macros workstream's app). lld
   bound such symbols through the umbrella, and took the client name from the output file's name.
   The thirteenth patch rebinds a re-exported dylib's symbols when it is loaded directly and
   allowed, and derives the client name as Xcode's `ld` does. Xcode's `ld` also resolves an
   autolinked library name to an already loaded re-export when no search path has it, which lld
   does not (B-133).
## Decision

- **Linker:** `ld64.lld` from swiftlang/llvm-project at the tag of the installed Swift
  (`swift-6.4.0-RELEASE` for Xcode 27.0) with the thirteen patches in `.github/lld`: without the
  fork's platform check, with `arm64e.x1` in TextAPI, with Xcode's versions for libraries
  that `$ld$previous$` renames, with Xcode's order for loading autolinked libraries (item 9),
  with Xcode's dyld opcodes for links that leave symbols to dyld's lookup (item 11), with
  pointers to thread-local variables in `__got` (item 12), with the debug maps of
  relocatable inputs (item 13), with Xcode's weak imports of moved symbols (item 14), with
  constant Objective-C literals' sections in `__DATA_CONST` (ADR 0170), with Xcode's C-string
  sections and literals (item 15), with Xcode's dead stripping of class references (item 16), with
  the libraries only dead code used through moved symbols left out (item 17), and with Xcode's
  bindings to re-exported dylibs (item 18).
  `.github/scripts/build-llvm-tools.sh` builds it with `dsymutil`, patching a pristine copy of the source again whenever the patches change. A nomac linker that reproduces Xcode's layout is not built (B-102
  records when it would be). The script writes the SHA-256 of `.github/lld`'s patches next to lld
  (`lld.patches.sha256`), and `build-cctools.sh` that of `.github/cctools`'
  (`cctools.patches.sha256`); `nomac toolchain install` refuses tools built with other patches
  than its own (an lld from before the seventh patch left the expo workstream's package
  frameworks' dSYMs empty).
- `nomac toolchain install <usr> --llvm-tools <dir>` installs `lld` (the toolchain's
  `ld64.lld` link then names it), LLVM's `dsymutil` as `llvm-dsymutil`, `clang.cfg` and
  `clang++.cfg` with `-fuse-ld=lld`, and an `ld` that runs `ld64.lld`, so Swift Build's probe gets
  lld's own identity: lld does not reproduce Xcode's `ld`, so it reports its own version. It also
  adds the `cc` and `c++` links to `clang` that Xcode's toolchain has, which Swift Build runs by
  name (docs/formats/build.md), and the shell script phases run under (ADR 0103). Relocatable
  links (`-r`) go to cctools-port's `ld64` (ADR 0104). Every other link runs lld with
  `-objc_category_merging` before the link's own arguments, as Xcode's `ld` merges by default
  (item 10); the rest of item 10 is lld's own layout, recorded as each difference's cause.
- **Tools nomac reimplements** get a launcher at Xcode's path that runs `nomac <tool>`:
  `tapi` (`tapi stubify` from the observed rules), `dsymutil` (LLVM's, then the dSYM's Info.plist
  from the binary's bundle as dsymutil finds it on macOS), `appintentsmetadataprocessor` and
  `appintentsnltrainingprocessor` (targets without App Intents). Command lines therefore name
  Xcode's paths. The resources workstream's `actool`, `ibtool`, `mapc`, `momc` and
  `xcstringstool` get launchers at `Contents/Developer/usr/bin`, where Xcode keeps them, and so
  does `xcrun`, which macOS keeps in `/usr/bin` (docs/formats/build.md "xcrun"). Xcode's `codesign` is `/usr/bin/codesign`, outside the developer directory, so its
  launcher goes in the toolchain's `usr/bin` and builds off macOS synthesize `CODESIGN=codesign`,
  which Swift Build looks up there (`CodesignToolSpec`). They also sign ad hoc
  (`AD_HOC_CODE_SIGNING_ALLOWED=YES`, `PROVISIONING_PROFILE_REQUIRED=NO`, as packaging's
  `signing_experiments.py` makes xcodebuild sign, and the identity `-` in nomac's answer to Swift
  Build's provisioning question for any target whose `CODE_SIGN_IDENTITY` is not empty), since
  Linux has no Apple-issued identity (B-302); a target with an empty identity signs nothing, as
  with Xcode (`signing_identity_experiments.py`, B-186), and the command line overrides all of it.
  Install builds' `chown` and `chmod` run scripts the toolchain install writes into
  `usr/libexec/nomac` (`CHOWN`, `CHMOD`; docs/formats/build.md "Owner, group and mode").
- **Tool probes.** Before it plans, Swift Build asks some tools what they are (`actool` and
  `ibtool`: `--version --output-format xml1`, decoding `com.apple.<tool>.version`). A tool nomac
  reimplements answers with the version of the Xcode tool whose behavior it reproduces (Xcode
  27.0's actool and ibtool: bundle version 25098, short version 27.0), and adds its own under a
  `nomac` key where the format allows (the xml1 answers; Swift Build reads only its key). This
  is compatibility negotiation, as a User-Agent string is: it tells Swift Build which command
  lines the tool understands, and it ends up in no output. Tools nomac does not reimplement
  (lld, the swift.org compilers) report their own versions.
- **In-process builtins** (strings copy, Info.plist and other property lists) cannot be routed;
  their Linux differences are fixed in Swift Build: the owner's fork carries the upstream patches
  (docs/upstream/swift-build.md, ADR 0005), with the resources workstream's B-253.

## Consequences

- `Engine` builds on Linux: 30 of Xcode's 78 files are identical, `Engine.tbd` and the dSYM's
  Info.plist among them; the binary has Xcode's exports, libraries and sections but for the three
  lld section differences above. The `build` check (docs/VERIFICATION.md "Build products")
  documents each lld difference it accepts; on Linux it also finds that lld imports
  `dyld_stub_binder` and marks imports of weak definitions `N_REF_TO_WEAK`. With the third patch,
  `Engine`'s binary is equivalent to Xcode's.
- The Ld command line lacks `-Xlinker -reproducible` and `-Xlinker -no_warn_duplicate_libraries`
  (and in Debug `-add_mergeable_debug_hook`); compiles lack `-target-linker-version`. Both are
  recorded differences, not faked capabilities.
- The patched lld must be built per Swift release (about 2,000 compile steps). Upstreaming the
  patches to swiftlang/llvm-project would remove that (B-102).
- The comparisons behind these decisions run with `.github/scripts/build_compare.py` (Xcode's
  reference build, file lists, build requests, Mach-O sections), whose outputs stay outside the
  repository.

## Versions in outputs nomac reproduces (decided by the owner, 2026-10-22)

Some outputs nomac reproduces byte for byte embed an Xcode or Apple tool version. The owner
decided that they are identical to Xcode 27.0's, version strings included, so that App Store
submission sees what Xcode would produce. The values live in the Xcode profile (ADR 0012):

- The app's and frameworks' `Info.plist`: `DTXcode` (`2700`), `DTXcodeBuild` (`27A266a`),
  `DTCompiler`, `DTPlatformBuild` and `DTSDKBuild` (the SDK's build), and `BuildMachineOSBuild`
  (the Mac's build), which Swift Build computes from the developer directory and the host
  identity (`ProcessInfoPlistFile`). Off macOS the Mac's identity is the reference's (B-060).
- `Assets.car`: its header's CoreUI version (1010), main version string
  (`@(#)PROGRAM:CoreUI  PROJECT:CoreUI-1010 [LAR]`) and version string
  (`Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime`) (docs/formats/asset-catalog.md).
- The asset catalog compiler's dependency info (`actool-25098`), an intermediate.
- The versions the resources and packaging workstreams' reproduced outputs record (compiled
  nibs and storyboards, Core Data models, code signatures), as their format docs list them.

Answers to Swift Build's tool probes stay as "Tool probes" above. Compiled outputs are not
covered: the compiler and linker nomac runs are not Xcode's, and ADR 0101 keeps their own
identities (the DWARF producer, `LC_BUILD_VERSION`'s tool versions), which no decision so far
asks to change.

`tapi stubify` and the App Intents tools stop with an error, naming the BACKLOG item, on inputs
the experiments have not observed (B-106, B-107).

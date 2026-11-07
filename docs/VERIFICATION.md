# Verification

nomac is measured against Xcode, never against expectations. This document describes how a
comparison is made, where it runs and how to reproduce it. The contract is fixed by ADR 0004,
ADR 0006, ADR 0009 and ADR 0010; ADR 0008's Linux verification on Linux runners is withdrawn.

## What is compared today

| Check kind | Xcode side | nomac side | Rule |
|---|---|---|---|
| `pif` | `xcodebuild -dumpPIF` | `nomac pif` | byte-identical after root rewrites, package projects in GUID order (ADR 0010), signature canonicalization and synchronized-folder GUID canonicalization, the GUIDs Xcode draws at random for some synchronized variant groups and for the build files of lifted variant children included (docs/formats/pif.md, ADR 0009) |
| `settings` | `xcodebuild -showBuildSettings <args>` for every target × configuration, and every scheme × configuration with `-destination generic/platform=iOS` | `nomac inspect <same args>` | the settings blocks are byte-identical after root rewrites. The `Command line invocation:` and package preambles are not compared. The `-json` capture of each invocation is compared byte for byte. A capture whose only difference is the order of the blocks of an autocreated extension scheme's apps, when it builds several, is equivalent: xcodebuild changes that order from one run to the next (loader-experiments `autocreate-hosts`; vlc), so it is compared again in the capture's order and the report names those targets. So is a capture of a scheme whose name several targets or schemes have that matches one of the others: targets of several projects, a target and a local package's product, or shared or per-user schemes of several containers asked for by their common name; xcodebuild builds one of them from one run to the next, nomac the first (loader-experiments `project-reference-names`, `workspace-names`, `scheme-name-clashes`, `user-schemes-workspace`; envelope-experiments `same-name-targets`). Where xcodebuild failed, nomac must fail with the same exit status |
| `build` | the `build` capture's products (`build/Products`, `capture_reference.py` without `--skip-build`) | `nomac verify --build`: `nomac build` with the capture's xcodebuild arguments, at its derived-data path | one check per product: its compiled files equivalent ("Build products" below, ADR 0101), every other file byte-identical; and one check that nomac's build succeeds where Xcode's did |
| `strings`, `nib`, `assets`, `coredata`, `coreml` | the tasks of the build capture's log (`build/build.log`) that run `builtin-copyStrings`, `xcstringstool`, `ibtool`, `actool`, `momc`, `mapc` or `coremlc` (under `sandbox-exec`, which the check leaves out), and the files they wrote | the same command line run with nomac's tool of that name, on the same inputs | one check per task: every file Xcode's tool wrote byte-identical to nomac's after root rewrites ("Tool checks" below) |
| `signing`, `export` | the archive capture (`capture_reference.py --archive`): each codesign step of an ad-hoc `xcodebuild archive`, its product before and after, and the archive's `debugging` export | `nomac codesign` with the step's arguments on the product as it was before; `nomac export` of the captured archive with its export options | one check per step: the product's files, links and permissions as codesign left them, its output and exit status; one check for the export: every file but `Packaging.log` byte-identical, the IPA once entry times, owner ids and `Payload/`'s permissions are set aside ("Signing and export checks" below) |
| `archive`, `ipa` | the archive capture's `xcodebuild archive` (`archive/archive.log.cmd`), its `.xcarchive` and its `debugging` export | `nomac verify --build`: `nomac archive` with the capture's arguments (its `-archivePath` in the scratch folder, nomac's codesign for the capture's recording wrapper), then `nomac export` with its `ExportOptions.plist` | the archive's `Info.plist` but `CreationDate`; each product, dSYM and signature record, and each item of the IPA's `Payload`, by the build products' rules and the signing rules below; the export's other files but `Packaging.log` byte for byte, the IPA's entries by name and mode in order ("Archives that nomac built") |
| `envelope` | the other checks | `nomac check` of the checkout for the loader domain, whose outputs the other checks compare, with the packages verification checked out | fails when every feature of the app is inside the envelope and another check differs: a verified feature then hides a difference (ADR 0011). Otherwise it lists the features outside the envelope; when every other check is identical, the unknown ones are those the app's comparison verifies |

Where nomac cannot load the container or generate its PIF (an objectVersion Xcode refuses, a
local package not on disk), each command xcodebuild ran must have failed with nomac's exit
status: the `pif`, `list` and `settings` checks compare the statuses. A capture records a command
a signal stopped as Python does, `-<signal>`, which matches the status a shell reports,
`128 + <signal>` (a `dstSubfolder` name Xcode does not know aborts it: `-6`, 134). Where
xcodebuild's `-dumpPIF` failed and nomac wrote a PIF, the `pif` check differs.

## Progress

`progress` in corpus/corpus.json maps each line of the progress list (docs/PROGRESS.md) to its weight and
the check kinds that measure it; `nomac corpus results` computes each line from the reports,
never by estimate, and the overall figure as the weighted mean of the lines.

| Line | Kinds | Measure |
|---|---|---|
| Project loader | `pif`, `list`, `settings` | `apps`: the share of corpus apps whose every check of these kinds passes |
| Build driver | `build` | `checks`: the share of the kinds' checks across the corpus that pass, from reports written on Linux only (`"host": "Linux"`) |
| Asset catalogs | `assets` | `checks` |
| Storyboards and xibs | `nib` | `checks` |
| Strings and localization | `strings` | `checks` |
| Core Data models | `coredata` | `checks` |
| Packaging and signing | `signing`, `export` | `checks` |
| Extensions; device workflow; distribution; rare file types; Metal and Core ML | none yet | 0%, printed as "no check kind yet" |
| Verification harness | none | `reports`: the share of corpus apps with a report |

A check passes when it is identical, or equivalent where its kind documents equivalence (build
products, ADR 0101). Refused, different and unsupported checks count against their line;
reference-failed ones (Xcode failed, or the capture did not keep the files) are left out. A line
measured by checks covers the apps whose references have such checks, which the progress line
names (`… checks in N apps`): only references with an Xcode build capture have tool checks.
The loader keeps the per-app measure: one differing setting breaks an app's build, and the
thousands of settings captures would hide it in a share of checks.

Each report records where `nomac verify` ran (`host`: `system` `macOS` or `Linux`, `toolchain`
`xcode` or `nomac`): on a Mac, `nomac build` runs the developer directory's compilers and tools,
Xcode's; on Linux, the swift.org toolchain, the LLVM tools and nomac's own tools that
`nomac toolchain install` puts there. The goal is a build on Linux, so the build-driver line and
the header's "apps build" count only Linux reports; the Mac's `build` checks are printed beside
them ("… on the Mac with Xcode's compilers"), and corpus/RESULTS.md has a column and a row for
each. An app may have one report per system: a line with a host reads that system's report, every
other line the app's report from the Mac, so no check counts twice. Reports written before `host`
was recorded count for no host.

## Build products

`nomac verify --build` removes the capture's derived-data folder, as the capture does, and
builds the app there with `nomac build` and the capture's xcodebuild arguments
(`build/build.log.cmd`), the reference checkout's path replaced by `--source`'s. After the build
it restores the git checkout as the capture does (the tracked files the build changed checked out,
the files it added removed, each line at the end of the build log), so the archive build starts
from the checkout the archive capture started from: expo-default's script phases switch prebuilt
xcframeworks in `Pods` to their release copies, and an archive in the switched checkout keeps dSYM
source maps that Xcode's archive, switching again, drops. Each entry of
`Build/Products/<configuration>-<platform>` is a `build` check (with `--continue-building-after-errors`,
the build runs what does not depend on a failed task, so a tool another workstream has not
finished does not hide the rest): identical when all its files
are, equivalent when each is identical or equivalent, different otherwise (a file on one side
only is a difference). Compiled files are equivalent to Xcode's when their structure is the
same and every difference is a documented one (ADR 0101); every other file must be identical.
Off macOS the products built for the build machine (macros and the other host tools the build
runs, such as swiftfin's 46 from its macro packages) are Linux's, in
`<configuration>-linux-<arch>`, where the reference has its Mac's, in `<configuration>`: neither
folder is compared, and the `build` check notes each with its number of files.

| Files | Compared | Not compared |
|---|---|---|
| Mach-O (images, a dSYM's DWARF file) | the header; load commands by kind, and the order of each kind's first one; sections by name and order; `LC_ID_DYLIB`, the libraries (command, versions), `LC_RPATH`s, `LC_BUILD_VERSION`, `LC_SOURCE_VERSION`; the export trie's names and flags (without a trie, the symbol table's defined external symbols); the symbol table's undefined external symbols, with their library's name, `N_WEAK_REF` and `N_REF_TO_WEAK` | section contents, sizes and addresses, `LC_UUID`, the code signature, local symbols, fixups |
| `.swiftdoc`, `.swiftsourceinfo` | every record of the LLVM bitstream | the control block's `METADATA` blob (the compiler's version); in `.swiftsourceinfo`'s `SOURCE_FILE_LIST`, the files' modification times (swift's `emitFileListRecord`) |
| `.swiftmodule` (binary) | the `.abi.json` beside it, which must be identical | the binary: it records the compiler's version, its Clang modules' hashes and its search and plugin paths, and its offsets follow them (B-117) |
| `<module>-Swift.h` | every line | lines starting with `// Generated by ` |
| a dSYM's `Relocations/*/*.yml` | the lines before `relocations:` | the relocations, which follow the compiler's code |
| `Assets.car`, and icon PNGs drawn from an Icon Composer icon | as the tool checks do ("Asset catalogs" below): every block of the BOM store and its layout; every PNG chunk but the image data | actool's run-to-run variations (ADR 0203) and rendered pixels (ADR 0204) |
| a static library (`ar`, as `libtool -static` writes it) | the members' names, order and header fields; each Mach-O member as a Mach-O file above, every other member byte for byte; the ranlib table's symbols and the member each names | member sizes, and the ranlib table's offsets, which follow them |

The documented differences, from retro-rampage's `Rampage` scheme built by nomac on the Mac
(Xcode's compiler and linker) and its `Engine` built on Linux, against Xcode 27.0's builds at
the same paths:

| Difference | Cause |
|---|---|
| no `LC_SOURCE_VERSION`; load commands in another order | lld (ADR 0102) |
| `LC_BUILD_VERSION`'s tools | the linker that wrote the file: Xcode's `ld` 27037.1, or lld 21.1.6, never faked (ADR 0101, ADR 0102) |
| `__TEXT,__literals` (literals in an image that also has `__TEXT,__const` input sections) and `__DATA,__objc_clsrolist` only in nomac's; sections in another order | lld (ADR 0102 items 10 and 15) |
| `__TEXT,__objc_methlist` only in Xcode's | Xcode's `ld` makes Swift classes' method lists relative from iOS 14.0, lld only clang's (ADR 0102) |
| `__TEXT,__objc_stubs` only in Xcode's | the linker writes it for the compiler's selector stubs, which open-source Swift does not emit (ADR 0101) |
| `__DATA,__objc_data` only in nomac's, where Xcode's has the `__TEXT,__objc_methlist` nomac's lacks | the Objective-C method list of a Swift class that is not itself an Objective-C class (an actor's `@objc` methods, netnewswire's ErrorLog): both compilers put it in `__objc_data`, Xcode's `ld` makes it relative in `__objc_methlist` and lld keeps it (`swift_codegen_experiments.py`'s `actor`, ADR 0102) |
| the libraries in another order | lld; imports are compared by library name, not ordinal |
| `___chkstk_darwin` imported only by Xcode's | on Linux with swift.org's frontend, which has no `-stack-check`; the frontend `build-swift-frontend.sh` builds (ADR 0106) and nomac's swift-driver (docs/upstream/swift-driver.md) call it as Xcode's do, on the Mac too |
| `dyld_stub_binder` imported only by nomac's | lld imports it whenever libSystem exports it (`referenceStubBinder` in `lld/MachO/Driver.cpp`) |
| `_objc_msgSend$<selector>` imported only by Xcode's; `objc_msgSend` and `__DATA,__objc_selrefs` only in nomac's (SwiftSoup's relocatable object) | Xcode's compiler calls Objective-C methods through selector stubs (`-fobjc-msgsend-selector-stubs`), open-source Swift through `objc_msgSend` and selector references (ADR 0101) |
| `N_REF_TO_WEAK` on imports of weak definitions (`Engine`'s `operator new` and `delete`) only in nomac's | lld sets it (`lld/MachO/SyntheticSections.cpp`), Xcode's `ld` did not |
| the compiler's version in `.swiftdoc` and `.swiftsourceinfo` | ADR 0101 |
| source modification times in `.swiftsourceinfo` | the checkout's, and the build's for generated sources (`GeneratedAssetSymbols.swift`) |
| `// Generated by` in `<module>-Swift.h` | names the compiler (ADR 0101) |
| a dSYM's relocations | follow the compiler's code (ADR 0101) |
| `_objc_retain_x<N>` and `_objc_release_x<N>` imported for other registers `N` | the register-specific ARC entry points follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101) |
| no `LC_LINKER_OPTIMIZATION_HINT`, where the file also lacks `___chkstk_darwin` | every hint of Xcode's object was a stack check's `adrp` and `ldr` (expo-default's Debug Swift objects) |
| a static library's ranlib table (`__.SYMDEF`) | records each symbol's member by offset, which follows the compiled members' sizes (expo-default's Swift pods on the Mac: their objects differ only by `___chkstk_darwin`) |
| a static library's ranlib table naming other private external symbols (`N_PEXT`), its members identical or equivalent | the table also lists the members' private externals, which follow the compiler's code: Swift's metadata caches `…GMR`, `…GMd` in Xcode's, `…GMD` in swift.org's (expo-default's `libExpoKeepAwake.a` on Linux) |
| `__TEXT,__objc_methname` and `__DATA,__objc_selrefs` only in nomac's objects, with an `LC_LINKER_OPTIMIZATION_HINT` | open-source clang loads selectors where Xcode's calls selector stubs; Xcode's clang with `-fno-objc-msgsend-selector-stubs` writes both the section and the hints (ADR 0101) |
| `_objc_retain` and `_objc_release` imported by nomac's, the register-specific `_objc_retain_x<N>` and `_objc_release_x<N>` by Xcode's | Xcode's compilers call the register-specific ARC entry points (ADR 0101) |
| `_swift_retain` and `_swift_release` imported by nomac's, the register-specific `_swift_retain_x<N>` and `_swift_release_x<N>` by Xcode's | Xcode's Swift compiler calls them from iOS 17.0 (none at 16.4); swift.org's has no such lowering, its `-enable-direct-retain-release` calls `swift_retainDirect` instead (netnewswire's frameworks, ADR 0101) |
| `_swift_conformsToProtocol2` imported by Xcode's, `_swift_conformsToProtocol` by nomac's | Xcode's Swift compiler checks protocol conformances with the newer entry point from iOS 17.0 (none at 16.0); swift.org's uses the older one at every target, `-target-sdk-version` or not (swiftfin's frameworks, ADR 0101) |
| `_objc_opt_class`, `_objc_opt_isKindOfClass`, `_objc_opt_new` and `___kCFBooleanFalse` imported only by Xcode's | Xcode's clang calls the Objective-C runtime's entry points and refers to `@NO` as a constant; open-source clang sends `objc_msgSend`, whatever `-fobjc-runtime` (ADR 0101) |
| `___NSArray0__struct` and `___NSDictionary0__struct` in Xcode's, `___NSArray0__` and `___NSDictionary0__` in nomac's | the empty collection constants' names in Xcode's clang and in open-source clang (ADR 0101) |

## Tool checks

When a reference has an Xcode build capture (`capture_reference.py` without `--skip-build`, or
`--build` added later to a reference taken with `--skip-build`), `nomac verify` reads its log and,
for each task of these rules, runs the logged command with nomac's tool of the same name
(`nomac actool …` for `…/usr/bin/actool …`), in the logged directory, with the logged `export`
variables:

| Rule | Tool | Kind | Xcode's outputs compared |
|---|---|---|---|
| `CopyStringsFile` | `builtin-copyStrings` | `strings` | `--outdir`/`--outfilename` (or each input's name) |
| `CompileXCStrings` | `xcstringstool compile` | `strings` | `<--output-directory>/*.lproj/<catalog>.strings` and `.stringsdict` |
| `GenerateStringSymbols` | `xcstringstool generate-symbols` | `strings` | the file the header names |
| `CompileStoryboard` | `ibtool` | `nib` | `<--compilation-directory>/<name>.storyboardc`, `--output-partial-info-plist` |
| `CompileXIB` | `ibtool` | `nib` | `--compile`, `--output-partial-info-plist` |
| `LinkStoryboards` | `ibtool --link` | `nib` | each `.storyboardc` in `--link`, in its `.lproj` folder |
| `CompileAssetCatalogVariant`, `CompileAssetCatalog`, `GenerateAssetSymbols` | `actool` | `assets` | the results actool printed in the log (`/* com.apple.actool.compilation-results */`: the `.car`, icons, partial Info.plist, asset symbols) and, when it compiles, `--export-dependency-info` (generating asset symbols it writes the symbol files only: retro-rampage's command line run alone; the build's `assetcatalog_dependencies` is LinkAssetCatalog's copy of the thinned one) |
| `DataModelCompile` | `momc` | `coredata` | `<output folder>/<model>.momd` (`.mom` for one version) |
| `MappingModelCompile` | `mapc` | `coredata` | the `.cdm` |
| `CoreMLModelCompile` | `coremlc compile` | `coreml` | `<output folder>/<model>.mlmodelc` and the partial Info.plist; equivalent when only the order of the model's user metadata entries differs, which Xcode's coremlc changes from run to run |
| `CoreMLModelCodegen` | `coremlc generate` | `coreml` | the files of the generated classes' folder |

The derived-data root of the capture (`-derivedDataPath` in `build/build.log.cmd`) is replaced by a
scratch folder, the checkout's and the developer directory's roots by `--source`'s and
`--developer-dir`'s. Inputs inside the derived data are copied there first from the capture
(`build/Intermediates` for `Build/Intermediates.noindex`, `build/Products` for `Build/Products`;
package checkouts under `SourcePackages` from the capture's derived data while it is on disk),
so each tool is judged on Xcode's own inputs, never on another nomac tool's output. Output
folders and the task's working directory (a package's checkout for package targets) are created
first, as Swift Build's `MkDir` tasks and the checkout would have them.

Every file of Xcode's outputs and every file nomac's tool wrote is compared byte for byte, with the
scratch and local roots in nomac's files written back as the capture's (they appear in actool's
dependency info). A check is *identical* when every file is; *equivalent* when the only other
files are an asset symbol header or index whose declarations or entries are the same in another
order (actool orders sets sharing their last path component differently from run to run,
docs/formats/asset-catalog.md "Asset symbols"), or an `Assets.car` or icon PNG that "Asset
catalogs" below calls equivalent, an `.omo` identical once each SQL column-name list is sorted
(ADR 0230), each entity's family list sorted (ADR 0232) and each lookup table reduced to its keys,
every key reaching its slot (ADR 0231),
a `.momd`'s `VersionInfo.plist` of the same values (B-235), or a nib identical once the elements
of each `NSSet` and `NSMutableSet` are sorted (ADR 0252) and its outlet collections of several
sources are taken in one order (ADR 0260), or once each settled constraint tie is in one order (ADR 0253); *different* when a file differs otherwise, is
missing from nomac's outputs or is only in them; *refused* when nomac's tool exits with an error
(it names the input or option it does not reproduce yet, with its BACKLOG item);
*reference failed* when Xcode's task failed (`The following build commands failed:`), or the
capture did not keep an input or output. The tools' messages are not compared.

### Asset catalogs

An `Assets.car` that is not byte-identical to Xcode's is read as a BOM store on both sides
(`AssetCatalogComparison`); each file must be laid out as docs/formats/asset-catalog.md
describes, with the same variables and the same number of blocks, and every block must be
identical after actool's run-to-run variations are put aside: the appearance-key blocks in name
order (ADR 0200), and for an Icon Composer icon the end of its rendered images' names
(`_<UUID>-<digits>-<16 hex digits>.png`) and its facet's part, 220 or 245 (ADR 0203). The only
other difference accepted is the rendered pixels ADR 0204's table lists: an Icon Composer icon's
rendered images (their length and compressed pixels), and the icon PNGs drawn from it (their
`IDAT` chunks and `iDOT`'s last offset; every other chunk identical), the images rasterized
from SVG files (CSI flag 0x4) and their atlases, and the images of PNGs whose color profile is
not sRGB IEC61966-2.1 (their payloads and their atlases'), found in the
task's input catalogs, for `build` checks in the source checkout. The same comparison applies
to `build` checks, for `Assets.car` and the icon PNGs beside it.

A failed Xcode build still gives the checks of the tasks that ran before it stopped. `--build`
and `--archive` build in the reference's checkout, which every verify of that app reads, then
restore the tracked files the build changed and remove the files it added (netnewswire's script
phase writes `SecretKey.swift`, which git ignores and the loader would then list; home-assistant's
build tools fill `.build` folders). Run them only when no other session verifies the app, or
capture a reference of your own under another `--work`.

The capture keeps the `GeneratedStringSymbols_*.swift` files GenerateStringSymbols writes into
`DerivedSources`. Build captures taken before it did get them with `capture_reference.py <app>
<output> --refill-string-symbols`, which runs the log's GenerateStringSymbols tasks again with
the same Xcode on the checkout at the reference's commit (the tool reads only the catalog) and
keeps what they write where the capture would have; without it those checks are *reference
failed*.

## Signing and export checks

`capture_reference.py --archive` archives the build scheme with ad-hoc signing
(`CODE_SIGN_IDENTITY=-`, the project's team and signing style cleared) and a `CODESIGN` wrapper
that keeps, for every codesign step, its arguments, entitlements, output and exit status and the
product before and after (as `.github/scripts/signing_experiments.py` does), then exports the
archive with the `debugging` method. The export runs offline under `sandbox-exec` (with an Apple
account in Xcode, an export otherwise asks Apple's developer services about the team). The
archive build cannot: Swift macro expansion (SwiftUI's `@State` is a macro in Xcode 27's SDK) runs
in a plugin server that applies its own sandbox, which cannot be nested in `sandbox-exec`'s (a
SwiftUI view with `@State`, built under `sandbox-exec`: "external macro implementation type
'SwiftUIMacros.StateMacro' could not be found", exit 65; without it, the build succeeds), so
`--archive`'s and `--build`'s builds run unsandboxed and record every internet socket their
processes open (lsof, sampled each second) in `archive/archive.network.log` and
`build/network.log`, which should stay empty. Experiments that build self-written apps under
`sandbox-exec` (`signing_experiments.py`) use no macros. `nomac verify` replays the
steps in the order they ran, each on a copy of the product as it was before, with the captured
entitlements file. An ad-hoc signature has no signing time, so the product must be codesign's
byte for byte; a step nomac's codesign stops on is *refused*. The export check runs
`nomac export` on the captured archive with its `ExportOptions.plist` and compares every file of
the export but `Packaging.log` (times and the machine); in an IPA, the DOS times and the `UX`
fields of the entries (times and owner ids) and the permissions of `Payload/` (they follow the
umask) are set aside, as in the packaging workstream's own comparison.

## Archives that nomac built

With `--build`, a reference with an archive capture is also archived by nomac as xcodebuild
archived it, and exported (`ArchiveBuildVerification`, B-188). Its binaries differ from Xcode's
as build products do (ADR 0101), and signing follows: the code signature of a binary covers its
pages, `Info.plist` and `_CodeSignature/CodeResources`, which holds a hash of every other file
of the bundle. The signing checks show that `nomac codesign` signs the same bytes with the same
options as codesign does, byte for byte, so with the capture's options a signature differs from
Xcode's only through what it signs. Two rules follow, and nothing else is set aside:

- A signed binary judged equivalent stays equivalent when its code directories' version, flags,
  hash type and size, page size, platform, special slot count, identifier, team and executable
  segment flags, and its requirements, entitlements and CMS blobs, are Xcode's; its hashes, code
  slot count, code limit and executable segment limit follow its bytes.
- A `CodeResources` with the same rules and the same files is equivalent when each hash that
  differs is a file's (or nested code's) that the comparison itself found to differ; a hash that
  differs for an identical file makes it different.

An IPA is read entry by entry (`ZipArchive`: the stored and deflated entries `ditto -c -k`
writes), its entries' names and modes compared in order, then extracted and compared as the
archive's products are, per item of `Payload`.

Where the capture's `xcodebuild archive` failed, `nomac archive` runs with the same arguments
(without continuing after errors, as xcodebuild ran) and the `archive` check is identical when
it exits with the same status and prints the same error lines, sorted, with the source folder
(with or without `/private`) as `<source>`; there is no `ipa` check. netnewswire's ad hoc
capture is one: Xcode refuses the app and its two extensions, whose entitlements files need a
provisioning profile (status 65).

## The only rewrites

Both outputs are rewritten before comparison, replacing these absolute path roots with symbols:

| Symbol | Reference side | nomac side |
|---|---|---|
| `<SOURCE_ROOT>` | the checkout path in `source.json` | the checkout nomac reads |
| `<DEVELOPER_DIR>` | `developerDirectory` in `host.json` | `--developer-dir` (and its resolved path) |
| `<USER_CACHE_DIR>` | `userCacheDirectory` in `host.json` | `DARWIN_USER_CACHE_DIR` on a Mac, the temporary directory elsewhere |
| `<SWIFT_BUILD_RESOURCES:plugin>` | the plugin's resources inside Xcode's `SwiftBuild.framework` | `SwiftBuild_<plugin>.bundle` next to nomac |

The derived-data root (`<DERIVED_DATA>` in ADR 0004) never needs rewriting: nomac computes it
from the reference's home directory, which it presents to Swift Build through
`--host-identity`. Remote Swift packages are checked out there too
(`DerivedData/<workspace>-<hash>/SourcePackages`), so their paths in the PIF match.

Values that *hash* a path, such as `SDK_STAT_CACHE_PATH` (`$(SDKROOT:__md5)`) and the
DerivedData folder name, only match when the paths are identical. CI therefore runs nomac at
the reference's own paths.

## Where it runs

- **macOS runner (`reference` workflow).** The `capture` job records Xcode's outputs. The
  `verify` job checks out the app again at the same path, runs `nomac verify` against the
  installed Xcode, and uploads a JSON report. For retro-rampage it also replays verification
  with Xcode replaced, at its own path, by the subset `nomac sdk install` keeps, which proves
  the subset is sufficient. The `results` job renders `corpus/RESULTS.md` and the README
  progress section. The workflow runs only when started from the Actions tab; while the
  repository is private, a run without an app list covers only retro-rampage, tofu,
  netnewswire and icecubes, the last two for Swift packages (the workflow's
  `PRIVATE_SMOKE_APPS`).
- **Linux CI (`ci` workflow).** Builds and runs the test suite, including Swift Build loading
  nomac's PIF against a self-authored synthetic developer directory. No Linux job uses Apple
  software: Linux runs against Xcode's SDK happen in Docker on a Mac (below).

## Without CI: on your own Mac

The macOS workflows are manual (the Actions tab), because each run is billed at 10x. Everything
they do also runs on an Apple silicon Mac with Xcode 27.0 (27A266a), installed as
`/Applications/Xcode_27.app` next to any other Xcode. Experiment and capture outputs are
Xcode's and stay outside the repository (`~/nomac-out` below).

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
xcodebuild -version                     # Xcode 27.0, Build version 27A266a

# Experiments on self-written projects (one output folder each; loader-experiments and
# pif-experiments take experiment names after the folder to run only those).
python3 .github/scripts/loader_experiments.py ~/nomac-out/loader-experiments
python3 .github/scripts/package_experiments.py ~/nomac-out/package-experiments
python3 .github/scripts/pif_experiments.py ~/nomac-out/pif-experiments
python3 .github/scripts/pif_stability.py netnewswire ~/nomac-out/pif-stability
# Asset catalogs: actool's outputs, and with --nomac a comparison with nomac's (docs/formats/asset-catalog.md).
python3 .github/scripts/assets_experiments.py ~/nomac-out/assets-experiments --nomac .build/debug/nomac

# References of a corpus app, and nomac's comparison against them on the Mac.
python3 corpus/scripts/capture_reference.py icecubes ~/nomac-out/reference --skip-build
# Add an Xcode build to that reference later, for the tool checks (and `nomac verify --build`),
# and an ad-hoc archive with its export, for the signing and export checks.
python3 corpus/scripts/capture_reference.py icecubes ~/nomac-out/reference --build
python3 corpus/scripts/capture_reference.py icecubes ~/nomac-out/reference --archive
swift build -c release
.build/release/nomac verify ~/nomac-out/reference/icecubes --developer-dir "$DEVELOPER_DIR" \
    --report ~/nomac-out/icecubes-macos.json
```

With `DEVELOPER_DIR` exported, `swift build` and `swift test` use Xcode 27.0's Swift 6.4 and
nomac evaluates package manifests with its toolchain (through `xcrun`), as Xcode does.

**Keeping the checkouts.** References name their checkout by path (`source.json`), so local
captures leave the apps in `/tmp/nomac-corpus/<app>`, and the tool checks read Swift packages'
sources from the build's `/tmp/nomac-corpus/<app>-DerivedData/SourcePackages`. macOS deletes
them: `/usr/libexec/tmp_cleaner` (launchd, daily at 0:00) removes every file under `/tmp` whose
access, modification and change times are all over 3 days old, then empty directories whose
modification time is (2026-10-30: every corpus and holdout checkout). A user LaunchAgent keeps
them by refreshing access times twice a day and after each login (`crontab` is refused without
Full Disk Access):

```sh
cat > ~/Library/LaunchAgents/local.nomac.keep-tmp-checkouts.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>local.nomac.keep-tmp-checkouts</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>for d in /tmp/nomac-corpus /tmp/nomac-holdout; do [ -d "$d" ] &amp;&amp; find "$d" -type f -exec touch -a {} + &amp;&amp; find "$d" -type d -empty -exec touch -m {} +; done</string>
	</array>
	<key>StartCalendarInterval</key>
	<array>
		<dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>17</integer></dict>
		<dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>17</integer></dict>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LowPriorityIO</key>
	<true/>
	<key>Nice</key>
	<integer>10</integer>
</dict>
</plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.nomac.keep-tmp-checkouts.plist
```

A deleted checkout comes back with `capture_reference.py <app> <scratch> --clone-only --work
/tmp/nomac-corpus` (holdout: `--manifest <holdout.json> --work /tmp/nomac-holdout`), and its
packages with `xcodebuild -resolvePackageDependencies` given the reference build's container,
`-scheme` and `-derivedDataPath` (`build/build.log.cmd`).

**Another Xcode.** Every experiment suite, the corpus captures, the fuzzer and the survey also
run with a new Xcode through `.github/scripts/xcode_upgrade.py`, which reports what changed
against the current Xcode's runs: docs/UPGRADING.md. nomac warns when a developer directory is
not the profile's Xcode (`nomac sdk profile`), and `--strict-xcode` refuses it.

**Differential fuzzing.** `.github/scripts/fuzz_experiments.py` checks nomac on projects no
corpus app has. From each seed it writes a random project: odd group and file names, many file
types, synchronized folders with exception sets, most product types, dependencies, phases and
rules. It adds extra configurations, xcconfig files, conditional and macro settings, shared,
user and autocreated schemes, test plans, workspaces, project references and local packages.
It records Xcode's `-dumpPIF`, `-list` and a sample of `-showBuildSettings` captures in
`capture_reference.py`'s layout. Then it runs `nomac verify` on them, and `nomac list` for the
`-list` text. Differences are grouped into classes: a differing PIF path, a `-list` entry, or
the first differing setting of a capture. A case whose only differences `nomac verify` reports
as equivalent (what xcodebuild changes from one run to the next, "What is compared today") counts
apart from the different ones. The most frequent classes are minimized by removing
parts of the generated project while the class still shows. The ranked list goes to
`FINDINGS.md` in the output folder, with the hypotheses written in its `hypotheses.json`.
PIF differences are compared after the rewrites of `nomac verify` (docs/adr/0009-synchronized-folder-identifiers.md),
the GUIDs Xcode draws at random for some variant groups and their build files included, but
with every synchronized GUID replaced by one token, so this diff does not see the order of
synchronized members. Projects and outputs stay in the output folder (passing cases keep only their spec). The
script removes the DerivedData folders its own runs create. It stops when the disk has under
4 GB free or its folder passes 1 GB.

```sh
python3 .github/scripts/fuzz_experiments.py run --cases 300     # ~/nomac-out/fuzz, nomac from ~/nomac-out/bin/wip1
python3 .github/scripts/fuzz_experiments.py run --cases 60 --start 1000 --focus sync,odd-names --nomac .build/release/nomac
python3 .github/scripts/fuzz_experiments.py case 17 --focus sync   # one case, all files kept
python3 .github/scripts/fuzz_experiments.py findings                # rewrite FINDINGS.md
```

The Linux side runs in the container CI uses, `swift:6.4.1-noble`, natively on Apple silicon
(arm64; CI's Linux runners are x86_64). Docker Desktop shares only `/Users`, `/Volumes`,
`/private`, `/tmp` and `/var/folders` by default, so `/Applications/Xcode_27.app` cannot be
mounted; and a checkout bind-mounted from the Mac sits on its case-insensitive file system
(case-preserving inside the container), as Xcode's does. In a volume, which tells cases apart,
`nomac build` finds the files an app names in another case than the disk itself (cwa,
moonlight; `nomac check`'s `PBXFileReference.path=case-mismatch`; docs/formats/build.md "Names
in another case", BACKLOG B-062).
So nomac is cloned into a named volume (case-sensitive) and built there, the Mac's
`nomac sdk install` picks the subset (as the `sdk-capture` job does) and the Linux nomac copies
it into the volume, and each check runs at the reference's own paths:

- the subset at the reference's Xcode path (`/Applications/Xcode_27.app`), so that values that
  hash a path can match and `--developer-dir` is the reference's;
- the app at the reference's checkout path (`source.json`), cloned with
  `capture_reference.py <app> /tmp/unused --clone-only --work <its parent>`, without
  `--source`, so that DerivedData folder names (a hash of the project path) match;
- for references captured on a Mac under `/tmp` (local captures; CI's are under
  `/Users/runner/work/_temp`), the checkouts under `/private/tmp` and `/tmp` a link to it, as on
  macOS: Xcode writes the resolved path (`/private/tmp/...`) where SwiftPM's PIF builder
  resolves links (package source groups).

```sh
docker volume create nomac-linux
docker build -t nomac-linux:6.4.1-noble - <<'EOF2'
FROM swift:6.4.1-noble
# file: CocoaPods' frameworks script asks it whether a framework's binary is a dynamic library
# (GNU file says "dynamically linked shared" for a Mach-O dylib, as macOS's does).
RUN apt-get update -q && apt-get install -y -q --no-install-recommends libsqlite3-dev python3 file \
 && rm -rf /var/lib/apt/lists/*
# Through Docker Desktop's proxy GitHub sometimes answers git's HTTP/2 requests with 103 then
# 401, and noble's git 2.43 fails the fetch ("could not read Username").
RUN git config --system http.version HTTP/1.1 && git config --system --add safe.directory '*'
EOF2
docker run --rm -v "$PWD":/src:ro -v nomac-linux:/work -w /work nomac-linux:6.4.1-noble \
    bash -c 'mkdir -p corpus && git clone -q /src src && cd src \
             && swift build --build-tests --scratch-path /work/build -debug-info-format none \
             && swift test --skip-build --scratch-path /work/build -debug-info-format none'
NOMAC_HOME=/tmp/nomac-sdk .build/debug/nomac sdk install /Applications/Xcode_27.app
docker run --rm -v /tmp/nomac-sdk/xcode/27A266a/Xcode.app:/macsdk/Xcode.app:ro -v nomac-linux:/work \
    -e NOMAC_HOME=/work/nomac-home nomac-linux:6.4.1-noble bash -c \
    '/work/build/debug/nomac sdk install /macsdk/Xcode.app && mv /work/nomac-home/xcode/27A266a/Xcode.app /work/Xcode_27.app'
docker run --rm -v nomac-linux:/work -v ~/nomac-out:/out \
    --mount type=volume,src=nomac-linux,dst=/Applications/Xcode_27.app,volume-subpath=Xcode_27.app,readonly \
    --mount type=volume,src=nomac-linux,dst=/private/tmp/nomac-corpus,volume-subpath=corpus \
    nomac-linux:6.4.1-noble bash -c 'rm -rf /tmp && ln -s private/tmp /tmp \
    && python3 /work/src/corpus/scripts/capture_reference.py icecubes /tmp/unused --clone-only --work /tmp/nomac-corpus \
    && /work/build/debug/nomac verify /out/reference/icecubes --developer-dir /Applications/Xcode_27.app/Contents/Developer \
       --report /out/icecubes-linux.json'
```

Disk: the image takes 4.2 GB, the debug build with tests 2.1 GB (without debug information),
the subset 0.5 GB on Linux (Xcode's files are compressed on the Mac), and an app's checkout and
`SourcePackages` up to about 4.5 GB (nextcloud's packages 4.2 GB, home-assistant's 2.2 GB,
swiftfin's 2.0 GB, of which SwiftPM's bare mirrors are 1.4 GB).

## Reproducing a comparison

On a Mac with the reference Xcode selected:

```sh
python3 corpus/scripts/capture_reference.py retro-rampage /tmp/reference --skip-build
swift build -c release
.build/release/nomac verify /tmp/reference/retro-rampage --developer-dir "$(xcode-select -p)"
```

With an artifact downloaded from the `reference` workflow, on Linux with your own Xcode
installed through `nomac sdk install`:

```sh
python3 corpus/scripts/capture_reference.py retro-rampage /tmp/unused --clone-only --work /tmp/corpus
nomac verify reference-retro-rampage-xcode-27A266a/ --source /tmp/corpus/retro-rampage
```

On Linux, Swift Build's insecure hash is MD5 as on a Mac: the owner's fork carries the upstream
patch (docs/upstream/swift-build.md section 2, ADR 0005), so `SDK_STAT_CACHE_PATH` and every other
hashed value are a Mac's. `nomac verify` lists every difference by setting.

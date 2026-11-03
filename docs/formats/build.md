# Builds: request, log and dSYM

What `xcodebuild build` hands Swift Build and prints, as `nomac build` reproduces it (module
`NomacBuild`). Observed with Xcode 27.0 (27A266a) on retro-rampage's `Engine` scheme, icecubes'
`Models` scheme and `.github/scripts/build_experiments.py`; compared with
`.github/scripts/build_compare.py`.

## The build request

Swift Build records each request in
`Build/Intermediates.noindex/XCBuildData/<id>.xcbuilddata/build-request.json`. xcodebuild's has:

- `configuredTargets`: the targets the scheme builds for running, in scheme order, without
  parameters of their own. A package product entry is its product's PIF target,
  `PACKAGE-PRODUCT:<package identity>_<product>.<product>` (`Models`; `local-packages`: `Plain`,
  `MultiA`).
- `containerPath`: the `.xcodeproj` or `.xcworkspace`, absolute.
- `useParallelTargets`, `useImplicitDependencies`: true (schemes with Xcode's defaults, B-111);
  `hideShellScriptEnvironment` false; `showNonLoggedProgress` true; `buildCommand` build,
  `schemeCommand` launch.
- `generatePrecompiledModulesReport`: true only with `-showBuildTimingSummary`
  (`app-without-packages`), which nomac does not take (B-108).
- `continueBuildingAfterErrors`: false; true with the user default
  `-IDEBuildingContinueBuildingAfterErrors=YES`, which changes nothing else in the request
  (`app-without-packages`; retro-rampage's `Engine`, where nomac's request is then xcodebuild's).
  `nomac build` takes it, and `nomac verify --build --continue-building-after-errors` passes it.
- `parameters.activeRunDestination` for `generic/platform=iOS`: platform and SDK variant
  `iphoneos`, SDK by canonical name (`iphoneos27.0`), target architecture `undefined_arch`,
  supported architectures `armv4t armv5 armv6 armv7 armv7f armv7s armv7k arm64 arm64e`,
  only-active-arch disabled.
- `parameters.arenaInfo`: the derived data paths, with the index data store at
  `<DerivedData>/Index.noindex/DataStore` and enabled.
- `parameters.overrides.synthesized`: `ACTION=build`, `ENABLE_PREVIEWS=NO`,
  `ENABLE_XOJIT_PREVIEWS=YES`; `commandLine`: the `KEY=VALUE` arguments.

Off macOS `nomac build` adds settings Xcode's request does not have: the reference Mac's host
settings, ad hoc signing ("Signing ad hoc"), and `OTHER_SWIFT_FLAGS = $(inherited) -Xfrontend
-enable-cross-import-overlays` (after the command line's value when it sets one). Xcode 27.0's
compiler loads cross-import overlays though its driver passes no flag, for iOS and macOS, and with
`-disable-cross-import-overlays` fails on `@Query`, which `_SwiftData_SwiftUI` declares, as
swift.org 6.4.0's does by default (`.github/scripts/cross_import_experiments.py`). The driver gets
the flag, since Swift Build's in-process dependency scan must find the overlays too.

The compiles for the build machine itself (Linux targets: macro and host tool packages, which
Swift Build passes neither `-sdk` nor `-sysroot`) get `OTHER_SWIFT_FLAGS[sdk=linux*]`: the
toolchain's `lib/nomac/swift` resource directory, which has swift.org's headers where `lib/swift`
keeps the SDK's (ADR 0100), and an implicit import of `NomacHostFoundation`, a module of nomac's
that imports Foundation. On a Mac swift-syntax's `SwiftSyntaxBuilder` imports OSLog, which loads
Foundation, so its members are visible to every macro target using it, and macro packages rely on
it (swiftfin's StatefulMacro: `String.trimmingCharacters(in:)` with only swift-syntax imported).
The module loads Foundation the same way: its members become visible, its names do not, and a
package that imports Foundation `@preconcurrency` on Linux keeps that import (xctest-dynamic-
overlay); importing Foundation itself into those compiles broke it.

## Signing ad hoc

Swift Build asks the client for each target's signing identity. For `CODE_SIGN_IDENTITY=-`,
Xcode 27.0 answers identity `-`, shown as "Sign to Run Locally", with no entitlements: the
framework `Engine` and an app without an entitlements file are signed with
`codesign --force --sign - --timestamp=none --generate-entitlement-der <product>`, with no
`.xcent` (`build_experiments.py`'s `App`). nomac answers the same. With an entitlements file
(`signing_experiments.py`, archived ad hoc):

- holding an empty dictionary (`entitlements-empty`, as expo-default's): the same answer; Swift
  Build writes an empty `.xcent` and signs the app with `--entitlements` it;
- holding an app group, `aps-environment` or a keychain group (`entitlements-groups`, `-push`,
  `-keychain`): Xcode refuses the target, `<project>.xcodeproj: error: "App" requires a
  provisioning profile. Enable development signing and select a provisioning profile in the
  Signing & Capabilities editor. (in target 'App' from project 'Signing')`, and the archive
  fails with status 65. nomac answers the same error (a description and a recovery suggestion,
  which Swift Build joins) for any entitlement, and prints settings diagnostics of a target at
  its project with the target named, as xcodebuild does.

An empty identity signs nothing, ad-hoc signing allowed or not: Xcode's package projects set
`CODE_SIGN_IDENTITY = ""`, and a package's dynamic product built by its scheme is not signed,
nor an app built with `CODE_SIGN_IDENTITY=` (`signing_identity_experiments.py`). Off macOS,
`nomac build` signs ad hoc with `nomac codesign` every target whose identity is not empty, since
there is no keychain to take an Apple-issued identity from (ADR 0102, B-302), unless
`--keychain` gives the identity (manual signing, docs/formats/ipa.md).
nomac's Swift Build pin adds `--strip-disallowed-xattrs`, which Xcode 27.0 did not (B-115).

## The log

Each task, when it finishes: its rule, ` (in target '<target>' from project '<project>')` for a
target's task, a newline, Swift Build's command-line display (`    cd <dir>`, any
`    export K=V` lines, `    <command>`), the task's output, then an empty line. Output outside
a task is printed as it comes. After the tasks: `** BUILD SUCCEEDED **` and an empty line on
standard output, or `** BUILD FAILED **` (`** ARCHIVE FAILED **`) and an empty line on standard
error, followed there by the failure summary (`.github/scripts/failure_experiments.py`: a compile
error and a planning error, for a project, a workspace and a Swift package's folder by scheme and
a project by target and by neither, built and archived; retro-rampage's `Engine` with a failing
Ld):

    <empty line>
    The following build commands failed:
    \t<rule of each failed task> (in target '<target>' from project '<project>')
    \tBuilding <project|workspace> <name> with scheme <scheme> and configuration <configuration>
    (<n> failures)

- The failed tasks come in the order they failed; one Swift compile error fails two tasks
  (`SwiftCompile normal arm64 <file>` and `SwiftCompile normal arm64 Compiling\ <file> <file>`),
  in either order from one run to the next.
- The scheme's line names `project <name>` for a project opened alone and `workspace <name>` for a
  workspace or a Swift package's folder (the package's name); an archive's is `Archiving
  <project|workspace> <name> with scheme <scheme>`. A build by `-target`, or by neither
  `-scheme` nor `-target`, has none.
- `<n>` counts the lines above it, `(1 failure)` for one. A failure while planning, with no failed
  task, leaves the scheme's line alone, and for a build without a scheme no summary at all.

nomac's log matches a task's completion to its start by the task's ID: Swift Build may complete a
task under another signature than it started it with (rn-bare's SDK explicit-module tasks on
Linux), whose failure nomac's summary otherwise lost.

## The dSYM's Info.plist

`dsymutil` (LLVM's) writes `Contents/Info.plist` from a fixed template
(`tools/dsymutil/dsymutil.cpp`, `createPlistFile`): tab-indented XML with
`CFBundleDevelopmentRegion` `English`, `CFBundleIdentifier` `com.apple.xcode.dsym.<id>`,
`CFBundleInfoDictionaryVersion` `6.0`, `CFBundlePackageType` `dSYM`, `CFBundleSignature` `????`,
`CFBundleShortVersionString` (left out when empty), `CFBundleVersion` and, with `--toolchain`,
`Toolchain`. The identifier and versions come from the nearest directory above the binary whose
Info.plist has a `CFBundleIdentifier` (Core Foundation's bundle lookup, which dsymutil does on
macOS only); without one, the identifier is the dSYM's name without `.dSYM` and the versions are
`1` and `1.0`. Xcode's `Engine.framework.dSYM` has `com.apple.xcode.dsym.com.charcoaldesign.Engine`,
`1.0` and `1`; nomac writes the same off macOS (`DSYMInfoPlist`).

## Libraries renamed by `$ld$previous$`

A stub's `$ld$previous$<install name>$<version>$<platform>$<from>$<to>$<symbol>$` applies when
the deployment target is in `[from, to)`. With an empty symbol it renames the whole library;
with a symbol it moves that symbol to a library of the given name. A version, when given, is
both versions of the renamed or moved library. Xcode 27.0's `ld` then writes one load command
per install name, with these versions (`.github/scripts/ld_experiments.py`, 29 variants of a
library `libP` 5.0.0 and a stub `libC` that `$ld$previous$` sends to `libP`):

| Case | Versions |
|---|---|
| a renamed library, and `libP` itself loaded (linked or autolinked, used or not) | `libP`'s own (5.0.0, compatibility 1.0.0) |
| a renamed library, `libP` not loaded | the renamed library's (its own, or the directive's) |
| a moved symbol, `libP` used or linked | `libP`'s own |
| a moved symbol, `libP` only autolinked and unused, or not loaded | the moved symbol's (the stub's, or the directive's) |
| a renamed library whose new name no other library has | its own, under the new name |

`libP` without a symbol in use and only autolinked gets no load command, as without any rename.
When two libraries move symbols to one name, one with a version and one without (the iOS SDK's
`libswiftCoreGraphics`: CoreGraphics.framework's moves say 1.0.0, `libswiftCoreFoundation`'s
none), the library loaded first gives its versions (variants `two-owners-*`). Libraries on the
command line load in their order; the ones the objects autolink (`LC_LINKER_OPTION`) load after
them, the frameworks first, then the libraries, each sorted by name whatever order the objects
list them in. flappy-fly-bird's objects autolink `swiftCoreFoundation` before CoreGraphics, and
Xcode's binary records `libswiftCoreGraphics` 1.0.0.
On `Engine` (deployment target 15.0) this gives `libswiftDarwin` 428.0.10 (compatibility 1.0.0)
though only its renamed stubs' symbols are used, and `libswiftFoundation` 1.0.0 (compatibility
1.0.0) from Foundation.framework's moved symbols though `libswiftFoundation.tbd` (120.100) is
autolinked. lld took the first library with the install name; nomac's third lld patch
(`.github/lld/0003-ld-previous-install-name-versions.patch`, ADR 0102) applies this table, and
the fourth (`0004-autolink-load-order.patch`) loads autolinked libraries in Xcode's order.

A symbol moved this way is a weak import whenever the library that moves it is weakly linked:
when every import bound to that library's own symbols is weak (it then gets
`LC_LOAD_WEAK_DYLIB`), or it is linked with `-weak-l`. The moved symbol's own references and the
other moved symbols do not count for the library, and its destination keeps its own load command
(`LC_LOAD_DYLIB` unless every reference to it is weak). Outside the directive's range the symbol
is the library's own and follows its references (`.github/scripts/ld_weak_experiments.py`, 9
variants; lld's eighth patch, `0008-weak-imports-of-moved-symbols.patch`). Swift objects
reference each library they import through a weak `__swift_FORCE_LOAD_$_<module>`, so a
library of which nothing else is used, such as flappy-fly-bird's `libswiftCoreFoundation`, is
weakly linked, and CGFloat's descriptor, moved from it, is a weak import.

## Chained fixups, thread-local pointers and debug maps

Xcode 27.0's `ld` links with dyld's opcodes (`LC_DYLD_INFO_ONLY`) instead of chained fixups
(`LC_DYLD_CHAINED_FIXUPS` and `LC_DYLD_EXPORTS_TRIE`) when its arguments contain `-undefined
dynamic_lookup` or `-undefined suppress`, anywhere and whatever `-undefined` comes later, for any
output kind and deployment target, unless they also contain `-fixup_chains`
(`.github/scripts/ld_experiments.py`, `fixups-*` variants). `-U <symbol>`, `-flat_namespace` and
`-undefined error` keep chained fixups. Initializers go to `__TEXT,__init_offsets` whenever the
deployment target has chained fixups (iOS 13.4 and later), with those links too, and to
`__mod_init_func` below it or with `-no_fixup_chains` (`init-*` variants). lld's fifth patch
(`.github/lld/0005-undefined-dynamic-lookup-opcodes.patch`, ADR 0102 item 11) applies this rule.

Pointers to thread-local variables another image may define (weak or imported) go to
`__DATA_CONST,__got` with the other non-lazy pointers, never to a `__thread_ptrs` section (`tlv-*`
variants); lld's sixth patch (`0006-thread-local-pointers-in-got.patch`) does the same.

An image linked from a relocatable object (a Swift package product, `clang -r`) names in its
debug map the objects the relocatable object's stabs name, with their modification times and
the symbols of each, `static` ones included (`stabs-relocatable`); lld's seventh patch
(`0007-stabs-of-relocatable-inputs.patch`) writes them.

With `-dead_strip`, a reference to a symbol `$ld$previous$` moves to another install name counts
only from code that dead stripping keeps; a library whose only use was resolving such symbols
for dead code gets no load command, autolinked or explicit (rn-bare's executable and SwiftUI,
through SwiftUICore's moved `Color`), while a reference to a library's own symbols keeps it even
from dead code (`autolink-*` variants; lld's twelfth patch, `0012-dead-moved-symbol-references.patch`).

## Script phases and tools by name

Swift Build runs a script phase as `/bin/sh -c <script>`, the script starting with
`#!<shellPath>`, so the phase's `shellPath` is the shell that runs it. Off macOS, `nomac build`
points the phases whose `shellPath` is `/bin/sh` at the shell `nomac toolchain install` writes,
bash in POSIX mode with `xpg_echo`, as macOS's `/bin/sh` is (ADR 0103). Swift Build runs some tools by name from the toolchain's `usr/bin`: the Info.plist's
`Preprocess` task (`INFOPLIST_PREPROCESS`) runs `cc -E -P -x c`, and Xcode 27.0's toolchain has
`cc` and `c++` as links to `clang`, which `nomac toolchain install` adds (tofu's
`Preprocessed-Info.plist` is then Xcode's, byte for byte).

### xcrun

Script phases run `xcrun --sdk macosx swift <script> <arguments>` (swiftfin's "Generate
Strings") and `xcrun -sdk macosx swift <script> ...` (netnewswire); macOS has `xcrun` in
`/usr/bin`, after the developer directory's `usr/bin` in the phases' `PATH`, where
`nomac toolchain install` puts a launcher for `nomac xcrun`. Xcode 27.0's xcrun
(`.github/scripts/xcrun_experiments.py`, a fixed environment, `DEVELOPER_DIR` naming the Xcode):

- Options come before the tool's name, `--sdk` and `-sdk` alike; everything after the name is the
  tool's.
- The SDK is `--sdk`'s, else `SDKROOT`'s (a path, or a name such as `iphoneos`), else macOS's.
  A path names itself; a name, with or without its version (`iphoneos`, `iphoneos27.0`), is
  printed with the version, `.../iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk`; without either,
  `.../MacOSX.platform/Developer/SDKs/MacOSX.sdk`. An unknown SDK ends with
  `xcrun: error: unable to lookup item 'Path' in SDK '<name>'`, status 1.
- `--show-sdk-version` is SDKSettings.json's `Version`, `--show-sdk-build-version` the SDK's
  `System/Library/CoreServices/SystemVersion.plist` `ProductBuildVersion` (`24A430`),
  `--show-sdk-platform-path` the `.platform` folder, `--show-sdk-platform-version` its Info.plist's
  `Version`.
- `--find` and `-f`, and the tool xcrun runs: the toolchain's `usr/bin` (`swift`, `clang`, `ld`),
  then the developer directory's (`actool`, `xcodebuild`), then `PATH`, whatever the SDK. A tool
  found nowhere gives two lines, `xcrun: error: sh -c '<developer>/usr/bin/xcodebuild -sdk <sdk>
  -find <tool> 2> /dev/null' failed with exit code 17664: (null) (errno=Undefined error: 0)` and
  `xcrun: error: unable to find utility "<tool>", not a developer tool or in PATH`, status 72; an
  unknown option `xcrun: error: unrecognized option: <option>` and a usage text, status 64.
- The tool's environment: `SDKROOT` is `--sdk`'s SDK, even over an inherited one; without `--sdk`
  an inherited `SDKROOT` is kept, and without either it is macOS's, with `CPATH=/usr/local/include`
  and `LIBRARY_PATH=/usr/local/lib`. `MANPATH` is the SDK's, the platform's, the developer
  directory's and the toolchain's `usr/share/man`, then the inherited value. The arguments reach
  the tool as given.

`nomac xcrun` gives the same answers to every case on the Mac. It does not print the usage text
after an unknown option, nor xcodebuild's lines before an unknown SDK's (they carry a time and a
result bundle's path), and takes none of xcrun's other options (B-123). Off macOS the tools of
macOS's SDK run for the build machine, which is not a Mac: they get no `SDKROOT` (ADR 0103).

Xcode's clang without a target compiles for the SDK, where off macOS clang would compile for the
build machine: `<arch>-apple-<os><version>`, the architecture `-arch`'s, else the machine's, the
version `<PLATFORM>_DEPLOYMENT_TARGET`'s, else the SDK's (`xcrun --sdk iphoneos|macosx clang -x c -
-dynamiclib -v`: `arm64-apple-ios27.0.0`, `arm64-apple-macosx27.0.0`, LC_BUILD_VERSION minos 27.0;
minos 16.4 and 13.0 with `IPHONEOS_DEPLOYMENT_TARGET=16.4` and `MACOSX_DEPLOYMENT_TARGET=13.0`;
`arm64e-apple-ios27.0.0` with `-arch arm64e`). Off macOS `nomac xcrun` gives clang, clang++, cc and
c++ that `-target` and the SDK as `-isysroot` for iPhoneOS's SDK, and for macOS's only when the
output is one a Mach-O link makes (`-dynamiclib`, `-bundle`, `-install_name`): Expo's
`create-stub-xcframework.sh`, which `pod install` runs, makes such a dylib with `xcrun --sdk macosx
clang`, and needs macOS's `libSystem` stubs, which `nomac sdk install` keeps by default.

### xcodebuild

A script phase may run `xcodebuild` itself: Expo SDK 58's `[CP-User] Build ExpoModulesJSI
xcframework` runs `xcodebuild -version`, then, with `env -i`, in the folder of a Swift package
with no project, `xcodebuild build -scheme ExpoModulesJSI -sdk iphoneos -destination
generic/platform=iOS -derivedDataPath <dd> -configuration Release -quiet
-disableAutomaticPackageResolution -skipPackagePluginValidation -skipMacroValidation
-parallelizeTargets SYMROOT=… OBJROOT=… <settings>` (`expo_experiments.py nested`, which replays
the phase with the environment Xcode's log recorded and an `xcodebuild` that records each call).
Observed with Xcode 27.0:

- `-version` prints `Xcode 27.0` and `Build version 27A266a`.
- A folder with a `Package.swift` and neither a workspace nor a project is the container: the
  workspace `<folder>/.swiftpm/xcode/package.xcworkspace`, named after the package's manifest
  (`ExpoModulesJSI`; the folder is `apple`), whose one project is the package's, and the build
  request's `containerPath` is the folder. `-list` lists the package's scheme; the PIF builder's
  delegate installs the root package's dynamic products (`SKIP_INSTALL = NO`,
  `INSTALL_PATH = /usr/local/lib`). `-showBuildSettings` prints no target ("Supported platforms
  for the buildables in the current scheme is empty").
- `-sdk iphoneos` sets the command-line override `SDKROOT` to the SDK's canonical name
  (`iphoneos27.0`); `TOOLCHAINS` in the environment becomes both an override and the request's
  `toolchainOverride`. `-parallelizeTargets` gives `useParallelTargets`, which nomac's requests
  have anyway; `-quiet` prints only diagnostics.
- The request also has the synthesized `CLANG_COVERAGE_MAPPING = YES`,
  `CLANG_PROFILE_DATA_DIRECTORY` and `ONLY_ACTIVE_ARCH = YES` of the package's autocreated scheme,
  which nomac's lacks (B-122, B-184); the command line sets `CLANG_COVERAGE_MAPPING = NO`.

Off macOS, `nomac toolchain install` puts an `xcodebuild` launcher in the developer directory's
`usr/bin` that runs `nomac xcodebuild`: `-version` as above, and a build as `nomac build`, with
the developer directory of `DEVELOPER_DIR` or of the launcher. On the Mac with Xcode's tools,
nomac's nested build writes Xcode's 5 products: 2 identical (`ExpoModulesJSI-Cxx.o`, the module),
3 equivalent (`nomac products`).

### Scripts a phase runs by path

A script a phase runs by path is run by the kernel with the interpreter its `#!` line names.
Off macOS, nomac's shell preloads `usr/libexec/nomac/libnomac-exec.so`, which starts nomac's
shell for a script whose `#!` line names `/bin/sh` (with the line's argument, then the script and
its arguments, as the kernel passes them) and for `/bin/sh` itself, by that path or found as `sh`
on `PATH` (ADR 0180). `shell_experiments.py --nested`: on macOS such scripts behave as
`/bin/sh -c` does, `$0` aside; on Linux dash is like them in 4 of 20 constructs, nomac's shell in
19.

### ditto

`ditto <source> <destination>` (`.github/scripts/ditto_experiments.py`, macOS 27.0.1), which
CocoaPods' "Copy generated compatibility header" phases run for each Swift pod's `-Swift.h` and
module map; `nomac ditto` behind the toolchain's `usr/bin/ditto`:

| Case | ditto |
|---|---|
| a file to a path whose folders are missing | creates them (`0755`), copies the file with its permission bits and modification time |
| a file onto a file | replaces it |
| a file onto a folder | copies it into the folder, under its name; the folder's other files stay |
| a folder | merges its contents into the destination, created when missing: files replaced or added, symbolic links copied as links, empty folders copied |
| a symbolic link as the source | follows it: the destination is a file with the target's contents and permission bits |

`ditto -c -k --norsrc <folder> <archive>` writes the archive of docs/formats/ipa.md. Other forms
are refused.

### derq

`ProcessProductPackagingDER` runs macOS's `/usr/bin/derq query -f xml -i <entitlements> -o <der>
--raw` on a Mac; off macOS Swift Build looks `derq` up through its tool search paths
(docs/upstream/swift-build.md section 5) and finds `nomac derq` (`NomacSigning.Entitlements`,
`.github/scripts/derq_experiments.py`) behind the toolchain's `usr/bin/derq`.

## AppleDouble files in xcframeworks

An archive made on a Mac carries each file's extended attributes as a `._<name>` file, which an
xcframework unpacked elsewhere keeps (swiftfin's `libvlc.xcframework`). ProcessXCFramework copies
none of a slice's `._*` files into the products (`.github/scripts/xcframework_copy_experiments.py`,
Xcode 27.0): AppleDouble or not, with their file or without, and applies none as extended
attributes; a directory named `._*` would be copied. That is Darwin's Foundation, whose
`contentsOfDirectory(atPath:)` and `enumerator(atPath:)` leave such files out of Swift Build's
listings; Swift Build's sixth patch does the same off Darwin (docs/upstream/swift-build.md
section 6).

## Names in another case

A Mac's default file system finds a name in any case, so projects built there may name files in
another case than the disk: cwa's project a `PDFGeneration` folder that is `PdfGeneration` on
disk, moonlight's sources `#include <openssl/evp.h>` from an `OpenSSL.framework`. On a file
system that tells cases apart (nomac checks the container's: its name with every letter's case
swapped names nothing), `nomac build` does two things (BACKLOG B-062):

- The PIF Swift Build loads names each such file reference by its path on disk (pif.md
  "Unicode"); Swift Build stops at a file reference it cannot open ("Build input file cannot be
  found") before any compiler runs.
- Clang and the Swift compiler get a virtual file system overlay, `case-sensitive: false`
  (`-ivfsoverlay` in `OTHER_CFLAGS`, `-vfsoverlay` in `OTHER_SWIFT_FLAGS`, before the project's
  flags), written to the scratch folder (`CaseInsensitiveOverlay`). It lists every header
  (`.h`, `.hpp`, `.modulemap`, `.apinotes` and the like) under the outermost project folders and
  the package checkouts, and for each framework the build produces or copies (the targets'
  framework products, the frameworks of xcframeworks there and in the package artifacts) a
  `directory-remap` of that framework onto itself in each products folder. Observed on Linux with
  a self-written app (Xcode 27.0's SDK): an overlay that only remaps a root folder onto itself
  does not help, the rest of the path being looked up on the real file system; one listing the
  files does (`#include <openssl/evp.h>` against `OpenSSL.framework/Headers/evp.h` builds; without
  it, "'openssl/evp.h' file not found"); a `directory-remap` entry naming a framework matches it
  in any case once the build has put it there.

The compilers then record the on-disk spelling where Xcode's record the project's (cwa's
`ENA.swiftmodule/Project/arm64-apple-ios.swiftsourceinfo` and its dSYM's file names), a known
difference: `nomac build` warns how many folders and files it concerns, and `nomac verify` calls
a `.swiftsourceinfo` whose source paths differ only in case equivalent (`swift.source-path-case`).
`nomac build --case-aliases` instead links each folder or file the project spells in another case
to its sibling on disk (`PDFGeneration` -> `PdfGeneration`) for the build's duration, so Swift
Build and the compilers use the project's paths (observed on Linux: `Gen.o` and the
`.swiftsourceinfo` files record `PDFGeneration` only). It writes into the checkout, so it is off
by default, refused when a folder that would hold a link is not writable, and removes its links
after the build, failed or not (BACKLOG B-062).

## Build tool plugins

Before it hands the build to Swift Build, xcodebuild applies the build tool plugins that package
targets use (`.github/scripts/build_plugin_experiments.py`, Xcode 27.0, a self-written package
whose library applies a plugin that runs the package's own tool):

1. **Compile.** Each plugin is compiled once, by SwiftPM's script runner, into
   `$(BUILD_DIR)/PluginExecutables/<plugin>` with its `-state.json`, `.dia` and `.dSYM`: Xcode's
   `swiftc -L <PluginAPI> -lPackagePlugin -Xlinker -rpath -Xlinker <PluginAPI> -target
   arm64-apple-macos14.0 -plugin-path <toolchain>/usr/lib/swift/host/plugins/testing -sdk
   <MacOSX27.0.sdk> -g -swift-version <n> -package-description-version <tools version> -I
   <PluginAPI> -sdk <MacOSX27.0.sdk> -parse-as-library -j<n> -Xfrontend
   -serialize-diagnostics-path -Xfrontend <dia> <sources> -o <executable>`, where `<PluginAPI>` is
   `Contents/SharedFrameworks/SwiftPM.framework/SharedSupport/PluginAPI` and the deployment target
   the `PackagePlugin` library's own.
2. **Apply.** Each plugin runs once per target that uses it, in the package's folder, with the
   build's environment, and is given the work directory
   `$(OBJROOT)/BuildToolPluginIntermediates/<package identity>.output/<target>/<plugin>` and, for a
   tool built from the package's sources, the path `/${BUILD_DIR}/${CONFIGURATION}/<tool>`, which
   the build expands.
3. **Process the results.** A build command becomes one of the target's PIF `customTasks`:
   `/usr/bin/sandbox-exec -p <profile> <executable> <arguments>`, its environment the command's
   own (none by default), its inputs the executable, its outputs the command's, not sandboxed by
   Swift Build and preparing for indexing; the outputs join the target's sources. The profile is
   SwiftPM's for a writable temporary directory, with the package's folder read-only and the work
   directory, with its item-replacement directory (`<temporary directory>/TemporaryItems`),
   writable. Swift Build logs the task as `CustomTask <display name> <hash>`.

The log has `Compile plug-in “<plugin>” in package “<identity>”`, SwiftPM's `[debug]:` lines
for the compile and two empty lines; then `Apply build tool plug-in “<plugin>” to target
“<target>” in package “<identity>”` and an empty line for each target; then `Process build tool
plug-in results`, which xcodebuild follows with a dump of its own objects (with their memory
addresses, which nomac does not print), and an empty line.

A prebuild command whose executable is a tool built from source fails the build with SwiftPM's
`a prebuild command cannot use executables built from source, including executable target
'<tool>'` on standard output, and on standard error `** BUILD FAILED **` with the failed
commands: the `Apply build tool plug-in` line, the package as Base64 of
`{"blueprintProvider_providerFilePathString":<the package's folder>,"type":{"blueprintProvider":{}}}`,
and `Building workspace <name> with scheme <scheme>`, with no configuration (exit status 65).

A target of an Xcode project that applies a package's plugin (a `plugin:<product>` dependency;
`build_plugin_experiments.py` project and project-quoting) gets the plugin's
`createXcodeProjectBuildToolCommands` message: the project with the wire ID `0`, its name, its
folder, the files its groups reference but the build products, and each native target with its
product (`application`, `executable`, `framework`, `library` or the product type) and the files of
its build phases (`source`, `resource`, `header`, else `unknown`); no dependency. The work
directory is `$(OBJROOT)/BuildToolPluginIntermediates/<project>.output/<target>/<plugin>` and the
log line `Apply build tool plug-in “<plugin>” to target “<target>” in project “<project>”`. Each
command becomes a shell-script phase of the target, before its other phases and in order, named
after the command, with `alwaysOutOfDate`, `alwaysRunForInstallHdrs`, no environment emitted,
`sandboxingOverride` `forceDisabled`, the command's inputs and outputs, and a new 24-digit object
ID for each build, whose MD5 is the phase's GUID. Its script is the command's environment as
`export <name>=<value>` lines, then `/usr/bin/sandbox-exec -p <profile>`, the executable and the
arguments, each word bare when it has only letters, digits and `+,-./=_`, else in double quotes
with `"` and `\` escaped and `$` and the backtick left as they are. The outputs join the target's
sources phase (`PBXBuildFile-<path>`) and the end of the project's group tree as files at their
absolute path (`sourceTree` `<absolute>`).

`nomac build` and `nomac archive` do the same through SwiftPM's plugin runner, the PIF
builder's custom tasks and `BuildToolPluginPhases` (`BuildToolPluginStep`, `BuildToolPlugins`;
an Xcode target's plugin links Apple's `XcodeProjectPlugin` on a Mac). Off macOS, the plugins are
compiled with the toolchain that evaluates the manifests, for the build machine, their tools are
those Swift Build builds for it (`/${BUILD_DIR}/${CONFIGURATION}-linux-<architecture>/<tool>`), and
the commands run without macOS's sandbox (`Sandbox` leaves them unwrapped there, as ADR 0103 does
script phases). Off macOS, an Xcode project target's plugin links nomac's `PackagePlugin` and
`XcodeProjectPlugin` (ADR 0105), and its scripts run the command without `sandbox-exec`. Prebuild
commands of vended tools are not run yet (BACKLOG B-009).

A plugin without an `XcodeBuildToolPlugin` conformance applied to an Xcode project's target
(`build_plugin_experiments.py` project-package-only) fails with `PackagePlugin`'s `Plugin
doesn't support Xcode projects (it doesn't use the XcodeProjectPlugin library)` and the failed
commands of a prebuild refusal, the `.xcodeproj` in the Base64 line, `Building project <name>
with scheme <scheme>` last.

## SwiftPM in script phases

A script phase can build and run a package's tool with SwiftPM: home-assistant's
`env -u SDKROOT "${SRCROOT}/Tools/build_tool" swiftgen` runs `swift run --package-path
BuildTools …`. With the build's `SDKROOT` removed, Xcode's `swift run` builds the tool for the Mac
and runs it (`.github/scripts/script_swiftpm_experiments.py`: the tool's output in the app);
with it, the manifest fails for the iOS SDK. Off macOS the toolchain's SwiftPM commands
(`swift-build`, `swift-run`, `swift-package`, `swift-test` and the other names of the
`swift-package` binary) are launchers for the swift.org toolchain nomac was installed from
(`LinuxToolchain.swiftPMCommands`), which builds for the build machine; the toolchain's own copies
would compile with its `lib/swift`, which lacks the build machine's headers ("missing required
module 'SwiftShims'").

## Swift stack checks

Xcode 27.0's swift-driver adds `-stack-check` to a Swift compile's frontend job for macOS 10.15,
iOS and tvOS 13, and arm64 and arm64e watchOS 6 and later (never arm64_32), visionOS and its
simulator, Mac Catalyst (the primary target decides, not `-target-variant`) and Apple firmware;
not for iOS and tvOS 12, macOS 10.14, the iOS, tvOS and watchOS simulators, DriverKit, bare-metal
Mach-O or other systems, nor for Embedded Swift or with any `-sanitize=`, whatever the
optimization level, debug information, whole-module mode, library evolution or explicit modules.
The driver options `-stack-check` and `-no-stack-check` override that, the last one winning,
for any target and with a sanitizer; `-no-stack-check` is not passed on. `-stack-check` follows
`-enable-objc-interop` in the job. The driver also adds `-disable-clang-spi` to every compile job,
after `-module-name` (and `-package-name`, `-disable-all-autolinking`) and before the flags it
saves from unknown driver options, but not to explicit modules' `-emit-pcm` jobs. Neither is
recorded in a `.swiftinterface`'s `swift-module-flags`
(`.github/scripts/swift_stack_experiments.py`). With `-stack-check`, wherever it is among the
frontend's options, the frontend gives every function it makes, those the module defines and the
Swift functions it declares, the attribute `"probe-stack"="__chkstk_darwin"`, on 64-bit targets
(x86_64 included, without x86's extra underscore; not for i686, armv7, armv7k, arm64_32 or wasm32);
the frontend takes `-no-stack-check` too, and it changes nothing there. Without `-stack-check`,
Swift's functions have no probe; the functions Clang emits (declarations such as `malloc_size`, and
the SwiftShims functions an `-O` build inlines, which pass the attribute on to the function they are
inlined into) have it where Clang's own rule puts it, for Apple devices from iOS 13, whatever the
frontend's options. The backend then calls `___chkstk_darwin`, through its GOT entry, before frames
of 4096 bytes or more and before dynamic allocations (2 calls in the experiment's `-O` object, 4 at
`-Onone`).

swift.org's frontend has no `-stack-check` ("unknown argument"), and swift.org's LLVM stops on the
attribute ("Unsupported stack probing method"); the LLVM of the clang workstream's patches
(`.github/clang` 0017 and 0025, ADR 0170) compiles swift.org's IR with the attribute added to the
same probe calls as Xcode's objects. nomac's swift-driver passes both as Xcode's does, through the
patch of docs/upstream/swift-driver.md, so with Xcode's frontend nomac's Swift objects call the
probe as Xcode's do. On Linux, the swift-frontend `build-swift-frontend.sh` builds with
`.github/swift` against that LLVM (ADR 0106) takes the option and gives functions the attribute as
Xcode's frontend does (the experiment's 16 IR cases: the same probe on every function both make, and
on every declaration), and nomac's Engine build of retro-rampage calls the probe as Xcode's in all 31
objects (7 calls); without it, swift.org's frontend gets only `-disable-clang-spi`.

## Stub executables

A sticker pack (`com.apple.product-type.app-extension.messages-sticker-pack`) has no code: its
executable is the platform's `Library/Application Support/MessagesApplicationExtensionStub/
MessagesApplicationExtensionStub` (`arm64` and `arm64e`), which CopyAndPreserveArchs thins to the
target's architectures, `lipo <stub> -output <appex>/<name> -extract arm64` for a Debug build
(`.github/scripts/sticker_stub_experiments.py`, Xcode 27.0). `nomac sdk install` keeps that folder
and `MessagesApplicationStub` (a Messages app's) for the payload platforms (`XcodeSubset`), and
Swift Build's seventh patch names the stub's slices off Darwin (docs/upstream/swift-build.md
section 7).

## Static libraries

Swift Build makes a static library with `libtool -static -arch_only <arch> -D -syslibroot <sdk>
-L<dir> -filelist <list> -dependency_info <file> -o <archive>`. Xcode 27.0's `libtool`
(`cctools_ld-27037.1`) writes BSD `ar`: each name after its header as `#1/<length>`, padded with
NULs; the ranlib table first as `__.SYMDEF`, mode `100644`; with `-D`, dates, owners and groups
`0`; each member's mode its file's permission bits (`st_mode & 0777`: `600`, `755`, and `755` and
`644` for files with modes `04755` and `01644`), with or without `-D`
(`.github/scripts/libtool_experiments.py`, ADR 0181). cctools-port's `libtool` with
`.github/cctools/0001-libtool-member-modes.patch` writes the same bytes for the same objects
(expo-default's 19 static libraries).

## Objective-C references, archive members and hints in the linked image

What Xcode 27.0's `ld` links otherwise than lld, on the same objects
(`.github/scripts/ld_layout_experiments.py`: 44 of 44 cases as Xcode's with `.github/lld` 0014 to
0027):

- Class, protocol and superclass references (`__objc_classrefs`, `__objc_protorefs`,
  `__objc_superrefs`) are in `__DATA_CONST` from iOS and tvOS 17.4, macOS 14.4, watchOS 10.4 and
  visionOS 1.1 (simulators and Mac Catalyst too, arm64 watchOS always), in `__DATA` before;
  selector references stay in `__DATA`. From iOS and tvOS 18, macOS 15, watchOS 11 and visionOS 2
  there are no class references: a load of one (`adrp` and `ldr`, x86_64 `movq`) becomes a GOT
  load of the class, a bound `__got` entry for a class of a dylib and `adrp` and `add` of the class
  for a class of the image. The corpus's Xcode images follow the same thresholds (moonlight,
  netnewswire and nextcloud at 17.0 in `__DATA`, wikipedia at 17.6, kickstarter at 18.0 and
  swiftfin at 18.6 in `__DATA_CONST` without class references). lld put all three in `__DATA` and
  kept the class references (0014). The address of a class reference (`adrp` and `add`, as Swift
  takes it) becomes the address of the class's GOT slot, which a class of the image then gets too
  (rebased), and a function that takes it keeps its loads of that reference on the slot; loads of a
  class of the image elsewhere stay `adrp` and `add` of the class. 0014 folded only loads, so
  swiftfin's Swift packages kept `__objc_classrefs` (0026).
- Archive members: Xcode's `ld` loads the members for the undefined symbols in sorted name order,
  round by round, the undefined symbols of the members a round loads waiting for the next round,
  and for one name the first member in the archive. lld fetched a member as soon as a symbol it
  defines was referenced. With a strong definition in one member and a weak one in a member that
  also defines a symbol named earlier, Xcode's keeps the weak one: swiftfin's
  `_vlc_thread_set_name` from `libvlc.a`, exported with the weak-definition flag (0015). The
  members are laid out at the archive's place on the command line, in the archive's order, whatever
  order they were loaded in (two archives around an object file; the profile runtime, whose
  `__cstring`, `__bss` and `__common` order follows from it); lld laid them out after every object
  file, in load order (0027).
- Linker optimization hints: Xcode 27.0's `ld` applies none, for any target (iOS 12 to 18, macOS,
  the simulator): `adrp` and `add` stay, and relaxed GOT loads stay `adrp`, `add` and `ldr`, where
  lld wrote `adr` and `nop`, and `nop` and a literal `ldr`, in every arm64 image (0016).
- `-alias` of a symbol a dylib defines, as Xcode links an app extension's debug dylib (`-alias
  _NSExtensionMain ___debug_main_executable_dylib_entry_point`): the alias is a re-export in the
  export trie (`_NSExtensionMain` from Foundation), an indirect symbol (`N_INDR`) among the
  external definitions, and the image references `_NSExtensionMain`; lld stopped with "TODO:
  support aliasing to symbols of kind 3" (0017).

- Section order in `__DATA_CONST` and `__DATA`: first the sections Xcode's `ld` knows, in
  one fixed order across both segments (`__la_symbol_ptr`, `__mod_init_func`, `__const`,
  `__cfstring`, `__objc_classlist`, `__objc_nlclslist`, `__objc_catlist`, `__objc_catlist2`,
  `__objc_nlcatlist`, `__objc_protolist`, `__objc_imageinfo`, `__objc_const`, `__objc_selrefs`,
  `__objc_protorefs`, `__objc_classrefs`, `__objc_superrefs`, `__objc_ivar`, `__objc_data`), then
  the other sections in input order (`__data`, the literal sections, custom sections), then
  `__thread_vars`, the sections created for `section$start` and `section$end` symbols in name
  order (the profile runtime's `__llvm_prf_bits`, `__llvm_prf_vns`, `__llvm_prf_vtab`), `__got`,
  `__thread_data`, `__thread_bss`, and the zerofill sections, `__common` among them, in input
  order. Self-written images (iOS 18 in two input orders, iOS 12 with initializers, a profiled
  image) and the corpus's Xcode images follow it; lld wrote `__got` first, the rest in input order
  and `__common` before every other zerofill section (0018).
- Objective-C categories are merged by default (iOS 15 and 18): those on a class of the image go
  into the class, those on one class of a dylib into one category whose method lists hold all
  their methods. A category with `+load` is merged only into a class of the image, and only when
  the class and its categories have one `+load` method between them; the class is then listed in
  `__objc_nlclslist`. The categories on a dylib's class are not merged at all when one of them has
  `+load` (iOS 18: one or two `+load` categories on `NSObject`, `NSString` and `NSArray`, with and
  without plain ones) (0019, 0020). Merging into a class rewrites only the lists the categories add
  to (`__OBJC_$_CLASS_METHODS_Own3`, `__OBJC_$_PROP_LIST_P5` and `__OBJC_CLASS_PROTOCOLS_$_P5`
  stay); categories merged into one keep the first one's body, name and list slot
  (`__OBJC_$_CATEGORY_NSObject_$_A`, named `A`). The merged lists, at the end of `__objc_const` or
  in `__objc_methlist`, are named `<prefix><class>(<categories>)`: `__OBJC_$_INSTANCE_METHODS_`,
  `__OBJC_$_CLASS_METHODS_` and `__OBJC_CLASS_PROTOCOLS_$_` for a category as for a class, with no
  null pointer after the protocols; the property lists have no symbol. lld wrote a new category
  named `A|B` in `__cstring`, rewrote all of the class's lists, kept the replaced ones and named
  the lists `__OBJC_$_INSTANCE_METHODS_(C)` and `__OBJC_$_CATEGORY_CLASS_METHODS_...` (0025).
- `__objc_methlist` holds the method lists of the classes, categories and protocols, relative,
  ordered by their symbols' names whatever the input order, each at a multiple of 8 bytes, a
  protocol method's missing implementation as offset 0. lld left the protocols' lists in
  `__objc_const` and kept input order (0025).
- `__TEXT`: `__text`, `__stubs`, `__stub_helper`, `__objc_stubs`, `__init_offsets` and
  `__objc_methlist` first, then the other sections in input order, then `__unwind_info`,
  `__eh_frame` and `__oslogstring` last (self-written images, and the corpus's mattermost,
  netnewswire, moonlight, gomap and swiftfin). lld placed `__objc_methlist` and `__oslogstring` in
  input order (0023).
- `__literal4`, `__literal8` and `__literal16` go into `__TEXT,__const` in input order, each literal
  at its first occurrence with its own alignment, the later equal ones dropped; lld wrote them all
  into a `__TEXT,__literals` section of its own, by size (0024).
- The GOT is ordered by the slots' ordinals read as unsigned, then by name: the image's own
  symbols (globals, private externs and locals together), each dylib's in load order (`-lSystem
  -lc++` puts libSystem's first), the weak definitions (`<weak-def-coalesce>` binds and hidden
  weak definitions, which are rebased), then the flat-namespace lookups (`-undefined
  dynamic_lookup`, seen with `dyld_info`). netnewswire's and swiftfin's GOTs follow it, their
  hidden weak Swift descriptors after the dylib binds; iOS 12 images (bind opcodes) too. lld kept
  the order of first reference (0022).
- `__unwind_info` (iOS 18, 1 to 6001 entries): only the encodings of more than one entry, counted
  after equal neighbours fold, are common, by descending count then ascending encoding (at most
  127); the others go into each page's own table. The index reserves an entry per 511 entries and
  two more, the unused ones zero; the pages follow the LSDA index, each starting where the
  previous one's entries end, rounded up to 8 bytes; the sentinel is one byte past the last
  function. A page is compressed unless a regular one holds more entries (local encodings used
  up, a function more than 16 MiB on). lld made every encoding common, ordered ties descending,
  gave each page 4096 bytes and put the sentinel at the end (0021).

## Stripping

Swift Build's Strip task runs `strip -D` (`STRIP_DETERMINISTIC_MODE`), then `-S` (`STRIP_STYLE =
debugging`), `-x` (`non-global`) or nothing (`all`), and `-T` when `STRIP_SWIFT_SYMBOLS` and the
dSYM ask for it. Off macOS it runs cctools-port's `strip`, which writes Xcode 27.0's `strip`'s bytes
but for the export trie of an executable stripped of all symbols (ADR 0181).

## C++ types in library-evolution modules

swift.org 6.4.0's compiler rejects, in a module compiled with `-enable-library-evolution`, a public
use of a C++ type other than a C-like struct (one declared `class`, or with a member function or
constructor): "cannot use struct 'CppError' in an extension with public or '@usableFromInline'
members; C++ types from imported module '__ObjC' do not support library evolution". Xcode 27.0's
compiler accepts the same sources (a header in a Clang module and a public extension of its type:
of seven type shapes, swift.org's accepts only the C-like struct, Xcode's all seven). swift.org's accepts
them with `-enable-experimental-feature AssumeResilientCxxTypes`, which `nomac build` passes off
macOS (`LinuxCompiler`). In Xcode's compiler that feature changes no symbol or section (16 bytes
of an options hash in the object), but every library-evolution module's interface then lists it in
`// swift-module-flags:`, C++ or not.

## Clang's C++ ABI

Xcode 27.0's clang follows Clang 4's C++ ABI without being asked: its driver passes no
`-fclang-abi-compat`, yet at every target (iOS, the x86_64 simulator, macOS, Linux) its output is
the output it gives with `-fclang-abi-compat=4.0` and differs from what it gives with any later
level. Its Swift compiler's Clang importer runs with `-fclang-abi-compat=4.0` among the arguments
it adds itself (`-Xfrontend -dump-clang-diagnostics`; ADR 0101), so C++ that Swift code
instantiates follows the same rules. swift.org 6.4.0's clang and importer follow the latest
rules. `.github/scripts/clang_abi_experiments.py` compiles self-written C++ with Xcode's clang at
its default and at each level, and with swift.org's as nomac installs it:

| What | Xcode 27.0 (Clang 4's rules) | swift.org 6.4.0 (rule since) |
|---|---|---|
| A pointer to an array's first element as a template argument, at the top level | `Node<Name>`: `XadL_Z4NameE` | `XadsoKcL_Z4NameEE` (Clang 12) |
| Constrained template parameters and `auto`, member-like constrained friends, concept-ids in expressions | `_Z2ctIiEvT_` | `_Z2ctITk1CiEvT_` (Clang 18) |
| A template parameter where its argument alone would be ambiguous (libc++'s `__shared_ptr_emplace` constructor) | `…ES5_Li0EEE…` | `…ES5_TnNS_9enable_ifIX…EiE4typeELi0EEE…` (Clang 18) |
| `enable_if` arguments, `__alignof__`, dependent template names, nested-name substitutions | Clang 11's and 14's forms | the later forms |
| A class whose copy and move constructors are deleted, passed by value | in registers | in memory (Clang 5) |
| An unnamed bit-field in an otherwise empty class; `packed` on a class with bases | still empty; the base packed too | not empty; the base keeps its alignment (Clang 7) |

The levels 3.8 and 4 give the output of Xcode's default, no later level does; 3.8 differs from 4
only on x86_64 Linux and FreeBSD. With `-fclang-abi-compat=4.0`, swift.org's clang writes Xcode's
symbols and Xcode's code and data at `-O1` in every case, arm64 and x86_64, and swift.org's
importer writes Xcode's C++ symbols. nomac installs the flag in the toolchain's `clang.cfg` and
`clang++.cfg`, which clang reads for every compile, script phases' included (an option from a
configuration file draws no unused-argument warning when clang only links, assembles or
preprocesses), and adds `-Xcc -fclang-abi-compat=4.0` to `OTHER_SWIFT_FLAGS` off macOS
(`LinuxCompiler`). The importer of the installed swift-frontend reads `clang.cfg` too, but the
level is part of a module's configuration, and with the flag only in `clang.cfg` rn-bare's Swift
compiles could not load the SDK's modules built for them ("version of Clang that we should attempt
to be ABI-compatible with differs in precompiled file"); with the Swift flag as well they do.
`nomac build` refuses a developer directory whose `clang.cfg` an earlier nomac installed.

Xcode's clang and its importer also call the unsized `operator delete(void *)` (`__ZdlPv`) where
swift.org's call the sized one (`__ZdlPvm`): C++ compiles off macOS get `-fno-sized-deallocation`
in `OTHER_CPLUSPLUSFLAGS`, and Swift compiles `-Xcc -fno-sized-deallocation`, with which the
experiment's interop source (a `new` and `delete` in an inline function) has Xcode's C++ symbols
(expo-default's nested ExpoModulesJSI imported `__ZdlPvm` without it).

Without the flag, rn-bare's `libReactCodegen.a` and `libreact-native-safe-area-context.a` built on
Linux define and reference other symbols than Xcode's (the first and third forms above); with
it, neither has a C++ symbol Xcode's does not (B-170 has the Objective-C differences left).

The six `-clang-vendor-feature=` flags Xcode's driver passes play no part in this: Xcode's clang
gives the same symbols with any of them turned off (`-Xclang -clang-vendor-feature=-<name>`).
`thisNoNullAttr` and `thisNoAlignAttr` take `nonnull`, `dereferenceable` and `align` off `this`,
so Xcode's code keeps a `this == nullptr` test that swift.org's removes; swift.org's clang has no
option for that (B-170).

## The reference Mac's TMPDIR

A build with a host identity (`--host-identity`) hands Swift Build the reference Mac's
environment, so its tasks run with that Mac's `TMPDIR` (`/var/folders/…/T/`), where the compilers
and linkers write temporary files; the path stays the Mac's, as settings and outputs name it.
Off macOS the folder does not exist, and links failed in it ("could not create a temporary
file"), so `nomac build` creates it there first (`HostTemporaryDirectory`), and says so when it
cannot.

## Owner, group and mode

An install build (`xcodebuild archive`) sets its products' owner, group and mode with
`$(CHOWN) -RH $(INSTALL_OWNER):$(INSTALL_GROUP) <product>` (`SetOwnerAndGroup`) and
`$(CHMOD) -RH $(INSTALL_MODE_FLAG) <product>` (`SetMode`): Xcode 27.0's archives of rn-bare and
of `signing_experiments.py`'s app run `/usr/sbin/chown -RH <user>:staff` and
`/bin/chmod -RH u+w,go-w,a+rX`. `INSTALL_OWNER` and `INSTALL_GROUP` default to `$(USER)` and
`$(GROUP)`, the building user's, so on the Mac the files keep their owner. Off macOS a build runs
as the reference Mac's user and group (its host identity), which the machine lacks, so `chown`
failed; and GNU chmod has no `-H` (BSD's `-RH` follows the symbolic links named on the command
line, as GNU's `-R` does), so `chmod` failed too. `nomac toolchain install` writes two scripts
into the developer directory's `usr/libexec/nomac`, which builds off macOS name in `CHOWN` and
`CHMOD` (`InstallAttributes`): `chown` leaves out a user or group the machine does not have and
changes nothing when neither is left, `chmod` passes `-RH` to GNU chmod as `-R`. Swift Build runs
both tasks with an environment of its own, not nomac's, so the scripts cannot be told the reference
identity. With them, `signing_experiments.py`'s app archives on Linux.

`SymLink` tasks (an install build's links from `BuildProductsPath` to the installed products)
show `/bin/ln -sfh <target> <link>` as their command, an option GNU `ln` lacks, but Swift Build
lowers them to llbuild's built-in `symlink` command (`BuildDescription.addSymlinkCommand`), so no
`ln` runs: rn-bare's archive on Linux makes its 7 links.

## Objective-C literals, runtime entrypoints and `this`

What Xcode 27.0's clang compiles otherwise than swift.org 6.4.0's beyond the C++ ABI, observed
with `.github/scripts/clang_objc_experiments.py` (self-written sources, iOS 12.0 to 15.1, arm64
and the x86_64 simulator, -O0 and -Os). The clang `build-llvm-tools.sh` builds with `CLANG=1`
has `.github/clang`'s patches for all three (ADR 0170), and so has the libclang it builds with it.
Both are needed: Swift Build's dependency scan runs clang's driver in its own process from the
toolchain's `libclang.so`, and the compiles run the cc1 command lines that scan plans. With
swift.org's libclang and the patched clang, rn-bare's objects got the runtime entrypoints and Xcode's
`this` (decided in cc1) but no constant literals (enabled by driver options the scan did not add).

**Constant literals.** From iOS 14 (macOS 11, watchOS 7; tvOS and visionOS as iOS), an array,
dictionary or number literal whose elements are constants is a constant object: classes
`NSConstantArray`, `NSConstantDictionary`, `NSConstantIntegerNumber`, `NSConstantDoubleNumber`
and `NSConstantFloatNumber`, in sections such as `__objc_arrayobj`, `__objc_arraydata`,
`__objc_dictobj` and `__objc_intobj`, and such a literal may initialize a file-scope variable.
Below iOS 14, and for a literal with a non-constant element, the collection is built at run
time, as swift.org's clang always does. Xcode's driver passes no option for this; upstream LLVM's
implementation (llvm-project #185130 and its follow-ups, backported as `.github/clang` 0001 to
0009) passes `-fobjc-constant-literals` and one option per kind from its driver, at the same
deployment targets. Clang writes the literals' sections (`__objc_arraydata`, `__objc_arrayobj`,
`__objc_dictobj`, `__objc_intobj`, `__objc_doubleobj`, `__objc_floatobj`) in `__DATA`, and Xcode's
`ld` moves all six to `__DATA_CONST`, as lld does with `.github/lld` 0009 (lld orders `__got`,
`__objc_selrefs` and `__objc_imageinfo` otherwise, with or without literals; ADR 0102).

**Messages to runtime entrypoints.** From iOS 13 (tvOS 13, macOS 10.15, watchOS 6, every
visionOS, Mac Catalyst), Xcode's clang calls a runtime function instead of sending five
messages, whatever the receiver (an object, a class, `nil`, even a constant one), with
`-fobjc-arc` or without, at every optimization level:

| Message | Function | Only when the method is declared |
|---|---|---|
| `class` | `objc_opt_class(id)` | returning `Class` |
| `self` | `objc_opt_self(id)` | returning `id` or `instancetype` |
| `new`, to a class | `objc_opt_new(Class)` | returning `id` or `instancetype` |
| `isKindOfClass:` | `objc_opt_isKindOfClass(id, Class)` returning `bool` | returning `bool`, taking a `Class` |
| `respondsToSelector:` | `objc_opt_respondsToSelector(id, SEL)` returning `bool` | returning `bool`, taking a `SEL` |

A root class whose methods of those names return `int`, `void`, `signed char`, `Class` for `self`
or `new`, `id` or another class for `class`, or take an `id` keeps the message; so do messages to
`super`, `new` sent to an instance, and every other selector (`isMemberOfClass:`,
`conformsToProtocol:`, `copy`, `hash`, `isEqual:`, `superclass`, `instancesRespondToSelector:`).
The calls are plain (no attributes), and the result is handled under ARC as the message's would be.
`-fno-objc-convert-messages-to-runtime-calls` turns them off; it leaves `objc_alloc_init`, which
upstream clang already calls from iOS 12.2. No open-source clang has these calls: `.github/clang`
0010 is written from these observations.

**`this`.** For Apple targets Xcode's driver passes `-clang-vendor-feature=+thisNoNullAttr` and
`+thisNoAlignAttr` (not for Linux targets), and `this` then has none of `nonnull`,
`dereferenceable` and `align`, in definitions and at call sites, constructors and destructors
included; a `this ? … : …` test stays. `.github/clang` 0011 gives the same for Apple targets.

**Register-specific ARC entry points.** For arm64, arm64e and arm64_32 targets from iOS, tvOS and
Mac Catalyst 16, watchOS 9 and every visionOS (never macOS, 13 to 27, nor x86_64), above -O0, Xcode's
compilers call `objc_retain_x<N>` and `objc_release_x<N>` (N 1 to 15 and 19 to 28, libobjc's), which
take the object in x<N>, `objc_retain_x<N>` returning it in x0. Its MIR after instruction selection
(`-stop-after=finalize-isel`) shows how: the object is copied into a new register, of class
`gpr64noip` for a call (`BL_DIRECTREG`, allocation order from x8) and `tcgpr64` for a tail call
(`TCRETURN_DIRECTREG`, from x0), and the register allocator picks it; a call to `objc_retain` keeps
the ordinary register mask, not upstream's this-return one, and later code takes the result from x0.
`.github/clang` 0015 does the same in swiftlang's AArch64 backend (with x16 and x17, which have no
entry point, left out). netnewswire's RSDatabaseObjC (Xcode's flags, iOS 17.0): the seven objects call
the same ARC entry points as Xcode's (0 of 7 without the patch, every Xcode object calling some
`_x<N>`), five have Xcode's code and data byte for byte, and one differs by a jump table;
`clang_objc_experiments.py`'s iOS 17.0 cases have Xcode's code in 11 of 12 (blocks at -O0 aside).

**Non-escaping blocks.** A block passed to a non-escaping parameter (`NS_NOESCAPE`,
`__attribute__((noescape))`; `enumerateKeysAndObjectsUsingBlock:` among Foundation's) is, for
Xcode's clang, any other block: `_NSConcreteStackBlock`, flags `0xC2000000` (signature, extended
layout, copy and dispose helpers), at iOS 12 to 18, macOS and Linux targets, every ABI level, with
ARC or without; a `__block` variable it captures keeps its byref structure and its
`_Block_object_dispose`. Its compiler still knows the block does not escape:
`-Wimplicit-retain-self` warns about the escaping block's `self` only. swiftlang's clang gives
such a block `_NSConcreteGlobalBlock`, `BLOCK_IS_NOESCAPE | BLOCK_IS_GLOBAL` and no helpers, and
keeps the `__block` variable on the stack; `.github/clang` 0012 compiles both as Xcode's and leaves
the warning alone. Measured: the block cases of `clang_objc_experiments.py` (8, arm64) get Xcode's
symbols with it and none without; their code still differs as escaping blocks' does with swift.org's
unpatched clang (the backend lays out -O0 and -Os code around blocks and ARC calls otherwise, ADR
0101). netnewswire's `FMDatabase.o` and `FMDatabase+RSExtras.o` (RSDatabaseObjC) import
`_NSConcreteStackBlock` as Xcode's do.

**Measured.** On `clang_objc_experiments.py`'s 36 arm64 cases (iOS 12.0 to 15.1, -O0 and -Os),
swift.org's clang writes Xcode's symbols, sections, code and data in 9 (its file-scope literals do
not compile), the patched clang in 28; the other 8 are -Os code that differs at iOS 12 too, where
both clangs write the same bytes (the optimizer difference of ADR 0101). Where no patch applies (C,
C++, Objective-C below iOS 13), the patched clang writes swift.org's bytes. On Linux, `nomac
verify --build` with the patched clang, libclang and lld: rn-bare Release from 2 of 12 products
identical and 3 equivalent to 2 and 6, expo-default Release from 1 of 35 identical and 15
equivalent to 1 and 18 (`libreact-native-safe-area-context.a`, `libReactCodegen.a`,
`libRNGestureHandler.a`, `libRNWorklets.a` become equivalent), and no product's comparison mentions
constant literals, `objc_opt_` calls or `this` checks any more. In the corpus, Xcode's products use
constant literals in 33 objects and binaries of 8 apps and those four `objc_opt_` calls in 65 of 11
(of 4,546 in Xcode's references; `objc_opt_self`, which Swift code calls too, left out); wikipedia
on Linux goes from 22 products different, 12 equivalent and 7 identical to 20, 14 and 7
(`CocoaLumberjack.o` and `SDWebImage.o` become equivalent), with no difference about literals or
`objc_opt_` calls left.

### Clang's driver

For `arm64-apple-ios15.1`, Xcode's driver gives cc1 options that swift.org's does not, and the
other way round (`-###` for a C, a C++ and an Objective-C file; the same for all three):

| Only Xcode's | In swiftlang's cc1 |
|---|---|
| `-fno-strict-return` (no `noundef` on return values) | yes |
| `-fcommon` (C tentative definitions are common symbols) | yes |
| `-fno-assume-unique-vtables`, `-fno-sized-deallocation`, `-target-linker-version` | yes |
| `-fobjc-msgsend-selector-stubs` (`objc_msgSend$<selector>` calls, arm64 targets only) | no; the patched clang has it (`.github/clang` 0013) |
| `-fstack-check` (calls to `___chkstk_darwin`, "Stack checks") | no; the patched clang has it (`.github/clang` 0017) |
| `-mdarwin-stkchk-strong-link`, `-fno-odr-hash-protocols` | no |
| `-Wno-elaborated-enum-base` | yes |
| `-Wno-error=allocator-wrappers`, the six vendor features | no |

swift.org's adds `-fcompatibility-qualified-id-block-type-checking` and `-Werror=undef-prefix`
(with `-Wundef-prefix=TARGET_OS_`, which both pass). nomac passes `-fno-sized-deallocation` for
C++ (`LinuxCompiler`) and `-fclang-abi-compat=4.0`; the rest is below and in B-170.

Xcode's driver passes `-fcommon` and `-fno-strict-return` for every Apple target (iOS, the
x86_64 simulator, macOS) and every C-family language, none of them for Linux targets, and leaves
`-fcommon` out when the command line has `-fno-common`. The toolchain's `clang.cfg` has both
(`LinuxCompiler.appleDriverDefaults`): a configuration file's options come before the command
line's, so Swift Build's `-fno-common` for `GCC_NO_COMMON_BLOCKS = YES` still wins, as it would
not from `OTHER_CFLAGS`; Linux-target compiles get them too. Self-written C with tentative
definitions and a function that falls off its end (`clang_abi_experiments.py`'s `defaults-c.c`):
swift.org's clang writes other symbols (no common symbols) and code; with the configuration,
Xcode's symbols, code and data, arm64 and x86_64.

Xcode's clang was built for linker version 1166.2: every compile gets `-target-linker-version
1166.2`, and its `objc_msgSend$<selector>` calls follow from it, for every arm64, arm64e and
arm64_32 Apple target (iOS from 12, the arm64 simulator, macOS, watchOS, visionOS), not x86_64 or
Linux, as upstream LLVM's selector stubs do from linker version 811.2 (llvm-project #186293,
backported as `.github/clang` 0013; its class-message stubs need 1250, so they stay off, as in
Xcode's objects: 0014). `clang.cfg` has `-mlinker-version=1166.2` (`XcodeTools.clangLinkerVersion`),
which both clangs take and which changes no argument clang gives `ld64.lld`; lld writes the stubs
in `__TEXT,__objc_stubs` as Xcode's `ld` does (3 stubs, 0x60 bytes in both). With selector stubs on
both sides, `clang_objc_experiments.py`'s 44 arm64 object cases have Xcode's symbols, and
netnewswire's RSDatabaseObjC objects call the same stubs as Xcode's (20, 118, 25, 7, 61 and 14).

Xcode's LLVM lowers matrix intrinsics by default (LLVM's `-enable-matrix`), while the matrix types
stay off (`-fenable-matrix`): its `-print-pipeline-passes` runs `lower-matrix-intrinsics<minimal>`
at -O0, and `lower-matrix-intrinsics` and an `early-cse` after `lower-constant-intrinsics` from -O1
to -Oz, for Apple and Linux targets alike (`clang_driver_experiments.py`). The extra `early-cse`
merges an address computed after a loop into the loop's own, which can keep the loop vectorizer
from vectorizing it: moonlight's `ConnectionTester.c` at -Os, whose object has `__literal16` and
`__literal8` only with swift.org's pipeline, and a self-written search loop (`scan.c`). The patched
clang has the same default (`.github/clang` 0029): `ConnectionTester.o` is byte-identical to
Xcode's at -Os and -O2.

Xcode's driver accepts `-fmodules-cache-path` silently where it does not use it: in C, C++ and
Objective-C compiles without modules, with `-fno-modules` and with `-fno-implicit-modules`
(`.github/scripts/clang_driver_experiments.py`). Swift Build passes it to every compile, so with
swift.org's clang, which reports it unused there as upstream LLVM does, a `-Werror` target without
modules fails ("argument unused during compilation"). Its other module-only options
(`-fimplicit-modules-lock-timeout`, `-fprebuilt-implicit-modules`, `-fprebuilt-module-path`,
`-fmodules-validate-input-files-content`, `-fmodules-search-all`) are reported by both, and
`-fobjc-arc` in a C++ compile by neither. The patched clang claims it (`.github/clang` 0016); no
configuration file can claim one option, and `-Wno-unused-command-line-argument` would silence the
others too, so swift.org's clang keeps the failure (B-170).

What the other defaults change, observed with `.github/scripts/clang_driver_experiments.py`'s
source cases (self-written files compiled by both clangs, exit status, diagnostics, allocas and
calls); Xcode's driver passes them all for Apple targets and, of them, only the `@import` feature
and the `allocator-wrappers` setting for Linux targets:

- `-fno-assume-unique-vtables`: a `dynamic_cast` to a final class calls `__dynamic_cast`, where
  swift.org's clang compares the vtable pointer.
- `-Wno-elaborated-enum-base`: `typedef enum E : int F;` compiles in C++; swift.org's clang
  reports an error.
- No `-Werror=undef-prefix`: an `#if` on an undefined `TARGET_OS_` macro is a warning (an error
  with the command line's `-Werror`); swift.org's clang reports an error.
- `+disableAtImportPrivateFrameworkInImplementationError`: a file of module Foo's implementation
  (`-fmodule-name=Foo`, which Swift Build passes for framework targets) may `@import Foo` or
  `@import Foo_Private`; swift.org's clang reports "@import of module 'Foo_Private' in
  implementation of 'Foo'; use #import".
- `+enableAggressiveVLAFolding`: in GNU modes, an array bound that is not an integer constant
  expression but can be evaluated (`const int n = 16; char buf[n];` in C) makes a constant array,
  with `-Wgnu-folding-constant`, where swift.org's clang makes a variable length array (a dynamic
  alloca, and a stack probe); not with `-std=c11` or `-std=c99`.
- `+revert09abecef7bbf`: a name that an elaborated-type-specifier of a local class introduces
  (`struct X { struct H *f(); };` in a block) is not visible in the enclosing block, as before
  llvm-project 09abecef7bbf; swift.org's clang accepts a later use of `H` there.
- `+disableNonDependentMemberExprInCurrentInstantiation`: an operator on a field of a class
  template (`m = "x"`, `this->m + "x"`, `S::m = "x"` with `int m`) is checked when the template is
  instantiated; swift.org's clang reports the error at the definition. Member access on such a
  field (`m.foo()`) is checked at the definition by both.
- `+thisNoNullAttr`, `+thisNoAlignAttr`: "Objective-C literals, runtime entrypoints and `this`".
- `-fno-odr-hash-protocols`, `-Wno-error=allocator-wrappers`, `-mdarwin-stkchk-strong-link`: no
  effect observed; swiftlang's clang has no `allocator-wrappers` warning, so nothing it reports
  fails, and two modules defining one protocol differently are an error with both clangs.

The toolchain's `clang.cfg` has `-fno-assume-unique-vtables` and `-Wno-elaborated-enum-base`
(`LinuxCompiler.appleDriverDefaults`; Linux-target compiles get them too). The rest needs the
patched clang (`.github/clang` 0020 to 0024; 0021 to 0023 for Apple targets only): no configuration
file can remove the driver's `-Werror=undef-prefix` without also keeping a command line's `-Werror`
from it. With the patched clang and this `clang.cfg`, the experiment's 34 cases are Xcode's; with
swift.org's clang and the same `clang.cfg`, 22 (the five `-fmodules-cache-path` cases and the
`TARGET_OS_`, folding, local class, template field and `@import` cases differ). In the corpus's
Xcode build logs, moonlight has five folded arrays (`CryptoManager.m`, `WakeOnLanManager.m`,
`SettingsViewController.m`), whose objects swift.org's clang compiles with variable length arrays.

### Stack checks

Xcode's driver passes `-fstack-check` unasked to Apple devices from macOS 10.15, iOS and tvOS 13
(arm64e too), watchOS 6, Mac Catalyst and visionOS; not to simulators, DriverKit, arm64_32,
`-ffreestanding` compiles or older versions, and not with `-fno-stack-check`; an explicit
`-fstack-check` reaches cc1 for any target (`.github/scripts/clang_stack_experiments.py`, 24 driver
cases). Every function of such an Apple compile gets `"probe-stack"="__chkstk_darwin"`
(`"___chkstk_darwin"` on x86_64), and the backends call Apple's probe:

- arm64: a frame whose locals (after the callee saves, without realignment padding) are 4096 bytes
  or more is probed after the callee saves and the frame record: `mov w9, #size`, then `adrp x16,
  ___chkstk_darwin@GOTPAGE`, `ldr x16, [x16, ___chkstk_darwin@GOTPAGEOFF]`, `blr x16`, with an
  `AdrpLdrGot` linker optimization hint at every optimization level, after the function's other
  hints. A function that does not save lr keeps it around the call (`str x30, [sp, #-16]!` …
  `ldr x30, [sp], #16`), and a prologue that shrink-wrapping moved out of the entry block keeps x9 to
  x12 (`stp x9, x10` and `stp x11, x12`). Every dynamic alloca calls the probe with the unrounded
  size in x9 (GlobalISel's rounded one at -O0), then takes the rounded size from sp; x9 to x11, x16,
  x17 and lr are not kept across the call, the other registers are. For arm64e the call goes through
  an authenticated pointer: `adrp x17, l___chkstk_darwin$auth_ptr$ia$0$addr@PAGE`, `add x17, x17,
  …@PAGEOFF` (an `AdrpAdd` hint), `ldr x16, [x17]`, `blraa x16, x17`, the slot in
  `__DATA,__auth_ptr` holding `___chkstk_darwin@AUTH(ia,0,addr)`.
- x86_64: a frame of 4096 bytes or more is probed as upstream LLVM does with a named probe (`movl
  $size, %eax`, `callq ____chkstk_darwin`, `subq %rax, %rsp`), with `pushq %rax` and `popq %rax`
  around the call when the callee saves leave the stack misaligned for it; every dynamic alloca
  calls the probe with the unrounded size in rax, rounds it after the call and subtracts it; the call
  keeps the callee-saved and vector registers only; a leaf frame below 4096 bytes still uses the red
  zone.

`-mdarwin-stkchk-strong-link`, which Xcode's driver passes too, changes nothing observed (the probe
is an ordinary undefined symbol). swiftlang's clang ignores `-fstack-check` with a warning, and its
AArch64 backend stops on a named probe ("Unsupported stack probing method"). The patched clang does
as Xcode's (`.github/clang` 0017, and 0025 for arm64e): of the experiment's 40 objects with large
frames, dynamic allocas, shrink-wrapped prologues and values live across the probe (arm64 iOS 15.1
and 12.0, the arm64 simulator, x86_64 macOS, arm64e; -O0 and -Os), 36 are Xcode's byte for byte. In
two (arm64, arm64e), an alloca of 8-byte elements, Xcode's scheduler rounds the size before the
call and the patched clang's after it: Xcode's does so for arrays of 2-, 4- and 8-byte elements
counted by a 32-bit `int` (`zext`, then a shift), not for bytes, 64-bit counts or counts the source
multiplies, and its instruction selection orders them the same otherwise; where its DAG puts the
rounding is not visible from outside, so it stays B-170. The two other arm64e ones are -O0
register choices that differ without any probe too (`ldrsw x10` for `ldrsw x9` in a leaf function;
B-170). netnewswire's Minizip (`zip.c`, `unzip.c`, `ioapi.c`, compiled by both with Xcode's options) has
the same probed function; one loop elsewhere in `zip.o` differs, as with swift.org's clang. In the
corpus's Xcode references, 274 objects call the probe, 270 of them Swift objects: Xcode's Swift
compiler passes `-stack-check` too, which swift.org's Swift compiler and LLVM do not have (B-170).

At -O0, Xcode's GlobalISel leaves functions with `llvm.stackrestore` (variable length arrays) to
SelectionDAG ("unable to legalize instruction: G_STACKRESTORE"); swiftlang's lowers it, which gives
other -O0 code for every such function. The patched clang falls back as Xcode's (`.github/clang`
0018).

### Exception tables of stack-protected functions

Xcode's clang gives a function with a personality whose stack objects the stack protector guards
(an array or, with `-fstack-protector-strong` or `-all`, any protected object; a guard alone is not
enough) one cleanup landing pad that resumes, and every call outside landing pads that may unwind,
except calls marked `tail`, unwinds to it, in its exception handling preparation before instruction
selection (arm64, x86_64 and Linux targets, -O0 to -Os). A function whose landing pads the optimizer
removed keeps an exception table, `___gxx_personality_v0` and `_Unwind_Resume`, and the call-site
tables of functions with landing pads list these calls; swiftlang's clang has neither. React
Native's `REACSSPlatformProps.o` (RNReanimated, Objective-C++ with an array passed to
`CGColorCreate`) has such a function. The patched clang does as Xcode's (`.github/clang` 0019):
the experiment's objects of C++ functions with and without arrays, guards, cleanups, tail and
noreturn calls (`-fstack-protector` and `-strong`, the five targets, -O0 and -Os) are Xcode's byte
for byte, and so is `REACSSPlatformProps.o`,
preprocessed with Xcode's clang and compiled by both with Xcode's code generation options
(Objective-C++, ARC, C++20, -Os).

### arm64e tail calls

For arm64e, a function that signs its return address (`pacibsp` where it spills lr, the
`ptrauth-returns` scheme) checks the authenticated lr before a tail call when it also has
`ptrauth-auth-traps` (both default for arm64e): `autibsp`, `eor x16, x30, x30, lsl #1`, `tbz x16,
#62, 1f`, `brk #0xc471`, `1: b callee`. Without either attribute
(`-fno-ptrauth-returns`, `-fno-ptrauth-auth-traps`) there is no check, and a function that does not
spill lr has neither `pacibsp` nor a check. swiftlang's LLVM checks only for ELF and its own
return-address signing; the patched clang checks as Xcode's (`.github/clang` 0026): the experiment's
arm64e C++ objects with tail calls (`clang_stack_experiments.py`, cleanups at -Os) are Xcode's byte
for byte.

### Inlining of ARC code

Xcode 27.0's inliner charges every Objective-C ARC operation that becomes a runtime call as a
call: `objc_retain`, `objc_release`, `objc_autoreleaseReturnValue`, `objc_loadWeakRetained`,
`objc_destroyWeak` and the others 30 (the call penalty, 25, and 5 for the argument),
`objc_initWeak` and `objc_storeStrong` 35, `objc_autoreleasePoolPush` 25, and 30 for the
`objc_retainAutoreleasedReturnValue` an attached-call bundle becomes (`-Rpass-missed=inline` on
self-written functions: one with three messages, two releases and an autoreleased return costs
235 against swiftlang's 55, at the -Os threshold of 75). swiftlang's counts them as free
intrinsics and inlines small ARC functions that Xcode's clang calls: SVGKit's
`getCurrentlyParsingParser`, whose seven calls Xcode's `SVGKParser.o` keeps, was inlined into all
of them on Linux, so the linker stripped the function that Xcode's image exports (swiftfin). The
patched clang costs them as Xcode's (`.github/clang` 0027): the costs of the self-written cases are
Xcode's, and `SVGKParser.m` keeps the seven calls.

### Comments of declarations in included files

An `@implementation` can `#include` a header with method definitions (expo-modules-core's
`SwiftUIVirtualViewObjC.mm`). At its end, swiftlang's clang searched the comments of the group's
first file for every declaration, the header's too; with `-Wdocumentation` and the main file's last
comment not attached yet, offsets into the header read past its buffer and clang crashed
(rocketchat). Xcode's compiles such a file and checks the doc comments of both files. The patched
clang searches each declaration's own file (`.github/clang` 0028): a self-written file with that
shape (`clang_driver_experiments.py`'s `comments.m`), which crashes swiftlang's clang at the same
frame, compiles with Xcode's two warnings.

## The archive build

`xcodebuild archive` (Xcode 27.0; retro-rampage's `Rampage`, tofu, `build_experiments.py`
`app-without-packages` and `autocreate-names`, archived ad hoc) hands Swift Build the request of a
build of the scheme, with these differences:

- `configuredTargets`: the entries the scheme builds for archiving; the configuration is the
  Archive action's (`Release` for retro-rampage), or for a project target's autocreated scheme
  the project's default one (tofu's `Release`, `autocreate-names`' `Beta`).
- `schemeCommand` `archive`, `buildCommand.style` `buildAndRun`, `parameters.action` `install`.
- `parameters.overrides.synthesized`: `ACTION=install` with `ENABLE_PREVIEWS=NO` and
  `ENABLE_XOJIT_PREVIEWS=YES`, `DEPLOYMENT_LOCATION=YES`, `DEPLOYMENT_POSTPROCESSING=YES`,
  `EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE=NO`, `ENABLE_SIGNATURE_AGGREGATION=YES`,
  `INDEX_ENABLE_DATA_STORE=NO`, and, under `<intermediates>/ArchiveIntermediates/<scheme>`:
  `DSTROOT` (`InstallationBuildProductsLocation`), `ASSET_PACK_FOLDER_PATH` (its
  `OnDemandResources`), `OBJROOT` (`IntermediateBuildFilesPath`), `SHARED_PRECOMPS_DIR`
  (`PrecompiledHeaders`), `SYMROOT` (`BuildProductsPath`) and, in it,
  `ASSETCATALOG_COMPILER_FLATTENED_APP_ICON_PATH` (`ProductIcon.png`),
  `MESSAGES_APPLICATION_EXTENSION_SUPPORT_FOLDER_PATH`, `MESSAGES_APPLICATION_SUPPORT_FOLDER_PATH`,
  `SIGNATURE_METADATA_FOLDER_PATH` (`Signatures`), `SWIFT_STDLIB_TOOL_UNSIGNED_DESTINATION_DIR`
  (`SwiftSupport`) and `WATCHKIT_2_SUPPORT_FOLDER_PATH` (`WatchKitSupport2`). A scheme's code
  coverage adds nothing (tofu); autocreated schemes also get `ONLY_ACTIVE_ARCH=YES`, as in their
  builds (B-122).
- The arena paths are the build's.

After Swift Build's tasks the log has `** ARCHIVE SUCCEEDED **` and a blank line; the archive
itself is assembled without a log line (docs/formats/xcarchive.md). A failed archive prints
`** ARCHIVE FAILED **`, then the summary of a build ending with `Archiving project <project> with
scheme <scheme>` (no configuration), exits with 65, and writes no archive.

`nomac archive` makes the same request (retro-rampage's: identical to xcodebuild's) and then
`nomac xcarchive`'s archive. Against Xcode's, on the Mac with Xcode's tools, its archive has the
same 45 files; `Info.plist` differs by `CreationDate`, the binaries and dSYMs as compiled outputs
(ADR 0101), and the app's `CodeResources` by the hash of the embedded `Engine.framework`.

## Scheme actions

xcodebuild runs a scheme's shell script actions (`ShellScriptAction`) only when it builds a scheme
(`-scheme`; with `-target` none run), as `nomac build` and `nomac archive` now do
(`.github/scripts/scheme_action_experiments.py`, `Sources/NomacBuild/SchemeActions.swift`):

- Order: the build action's pre-actions under `Run pre-actions` right after the command-line
  settings, before packages are prepared; the build; its post-actions under `Run post-actions`
  after a successful build, or after any with `runPostActionsOnFailure = "YES"`. An archive then
  runs the archive action's pre-actions before the `.xcarchive` is written and its post-actions
  after, printing neither. Every action of a list runs, after a failed one too.
- Each action's script goes to `<TMPDIR>/SchemeScriptAction-XXXXXX.sh` and runs as `/bin/sh -c
  <file>` from TMPDIR, whatever its `shellToInvoke`. The log prints `SchemeAction <title, spaces
  escaped> <file>`, `cd <TMPDIR>/`, one `export` per variable sorted by name (bare when the value
  has only letters, digits and `+,-./=_`, else in double quotes with `"` and `\` escaped), the
  command, then the script's output.
- Environment: xcodebuild's own, `PATH` with `<developer>/usr/bin` first, `MANPATH`,
  `SCHEME_ACTION_NAME` (the title), `SCHEME_NAME`, `WORKSPACE_PATH` (a project's
  `project.xcworkspace`), and for `generic/platform=iOS` `DEVICE_NAME` and `RUN_DESTINATION_*`.
  With an environment buildable Xcode adds every build setting of that target as its own settings
  model evaluates them (1,625 for a one-app project: `arch=undefined_arch`, `BUILD_STYLE`, settings
  `-showBuildSettings` does not export); nomac adds the target's `-showBuildSettings` settings
  (B-175).
- A failed action fails the build (65). The failure summary lists, for each, `Run custom shell
  script '<title>'` and the base64 of `{"blueprintProvider_providerFilePathString":"<the scheme's
  project, slashes escaped>","type":{"blueprintProvider":{}}}`; after a failed pre-action nothing
  is built and the scheme's `Building …` line is left out.
- A file a pre-action writes into a Swift package is compiled only from the next build on: the
  package's sources are read before the actions run (`pre-generates-package-source`).


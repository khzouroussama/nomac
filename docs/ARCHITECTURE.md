# Architecture

This document explains how nomac turns an Xcode project into an iOS app on Linux: which
upstream projects do which job, what nomac writes itself, and how data flows between them.
It is updated with every component that lands. Sections marked *planned* describe the design
of work that has not landed yet. Their status is in docs/STATE.md.

## The one-paragraph version

Xcode is a GUI and a few closed command-line tools around an open-source build engine, Swift
Build. Xcode turns `.xcodeproj` and `.xcworkspace` files into Swift Build's input format, the
PIF (Project Interchange Format), and Swift Build does everything else. That includes
resolving build settings, ordering targets and planning compiler, linker and resource tasks.
Some of those tasks invoke closed tools (`actool`, `ibtool`, `momc`, `codesign`). nomac
supplies the closed pieces: a project loader that produces the same PIF Xcode produces, a
developer directory extracted from the user's own Xcode, and replacements for the closed
tools. It then runs the real Swift Build on Linux.

```
.xcodeproj / .xcworkspace / .xcscheme
        │  NomacProject: parse (XcodeProj; project.xcproj via xcode-project-format)
        ▼
  project model (XcodeProj's PBXProj graph, schemes)
        │  NomacPackages: resolve Swift packages (SwiftPM), package projects (SwiftPM's builder)
        │  NomacPIF: generate PIF exactly as `xcodebuild -dumpPIF` does
        ▼
  PIF (JSON)            developer directory (nomac sdk install / link)
        │                       │
        ▼                       ▼
  NomacBuildService: Swift Build, in-process ──► build settings (nomac inspect)
        │
        ├─► compile / link: swift.org swiftc and clang in Xcode's toolchain layout (ADR 0100),
        │                    swiftlang's patched ld64.lld (ADR 0102); equivalent code (ADR 0101);
        │                    Apple's macros: nomac's swift-syntax plugins (NomacMacros, ADR 0150) [partial];
        │                    packages' build tool plugins, Xcode projects' through nomac's XcodeProjectPlugin
        │                    off macOS (NomacPluginAPI, ADR 0105)
        ├─► resources: nomac's builtin-copyStrings, xcstringstool, ibtool (xibs);
        │              actool (colors, data, images, icons, sprites, symbols); momc, storyboards [partial]
        └─► sign: nomac codesign (NomacSigning); IPA: nomac export (NomacPackaging)
                │
                ▼
              .ipa ──► device (NomacDevice, ADR 0400)
                └──► App Store Connect, TestFlight: nomac upload (NomacDistribution, ADR 0460)
```

## Upstream projects and how nomac uses them

| Project | Role in nomac | How it is used |
|---|---|---|
| swiftlang/swift-driver, through the owner's fork | The driver Swift Build plans Swift compiles with, with the patch of docs/upstream/swift-driver.md (Xcode's `-stack-check` and `-disable-clang-spi`) | Linked in-process through Swift Build and SwiftPM; the root dependency on the fork replaces theirs (ADR 0002) |
| swiftlang/swift-llbuild, through the owner's fork | The build engine Swift Build runs tasks with, with the patch of docs/upstream/swift-llbuild.md | Linked in-process through Swift Build and SwiftPM; the root dependency on the fork replaces theirs (ADR 0002) |
| swiftlang/swift-build | Build-setting resolution, dependency graph, task planning and execution, all `.xcspec` tool specs | Linked in-process. See "Driving Swift Build" below |
| Swift toolchain (swift.org) | `swiftc`, `clang` for `arm64-apple-ios`, the release swift.org pairs with the reference Xcode (6.4.0 for Xcode 27.0, `XcodeProfile.pins`); its swift-syntax (`lib/swift/host`) and `swift-plugin-server` for nomac's macro plugins | Copied into the developer directory's `XcodeDefault` toolchain (ADR 0100), invoked by Swift Build tasks; its `clang.cfg` and the Swift flags nomac adds give clang and the Clang importer Xcode's C++ ABI (`-fclang-abi-compat=4.0`, ADR 0170); the macro plugins are compiled with it (ADR 0150); optionally its `swift-frontend` and dependency scanner rebuilt with `.github/swift` against the patched LLVM and Clang (`.github/scripts/build-swift-frontend.sh`, ADR 0106) |
| swiftlang/llvm-project | `ld64.lld` (twenty-eight patches, `.github/lld`), `dsymutil`, and with `CLANG=1` clang and libclang (thirty patches, `.github/clang`; ADR 0170), at the installed Swift's tag | Built by `.github/scripts/build-llvm-tools.sh`, copied into the `XcodeDefault` toolchain (ADR 0102) |
| tpoechtrager/cctools-port | Apple's classic `ld64` (APSL 2.0), for relocatable links (`-r`) only; `bitcode_strip`; `libtool` for static libraries, patched to write members' modes as Xcode's does, and `ld64` to leave optimization hints, empty sections and Swift module hashes out of relocatable objects | Built by `.github/scripts/build-cctools.sh` at a pinned commit with the patches in `.github/cctools`, copied into the toolchain with its licenses (ADR 0104, ADR 0181) |
| tuist/XcodeProj + apple/xcode-project-format | Parse `.pbxproj`, Xcode 27 `project.xcproj`, workspaces, schemes | Linked library |
| swiftlang/swift-package-manager | Package graph, resolution and checkouts; the package PIF builder Xcode uses | Linked library; the builder is vendored (ADR 0010) |
| saagarjha/unxip | Expand `Xcode.xip` | Subprocess (ADR 0003) |
| 7-Zip and XZ Utils (`7z`, `xz`) | Extract the Developer Disk Image from Xcode's `XcodeSystemResources.pkg` at `nomac sdk install` (xar, cpio, UDIF, HFS+; xz chunks of the pbzx payload) | Subprocess, optional (ADR 0403) |
| xtool-org/xtool (XKit) | Certificates, profiles, device registration | Linked library [planned] |
| apple/swift-nio-ssl | TLS for lockdownd's sessions (BoringSSL) | Linked library (ADR 0401) |
| apple/swift-crypto | SHA-1, SHA-256 and RSA for code signing (CryptoKit and Security on Apple platforms, BoringSSL elsewhere) | Linked library, at SwiftPM's pin (ADR 0300) |
| pymobiledevice3, go-ios | Install, launch, logs, XCTest on device | References for `.github/scripts` experiments only; nomac speaks the protocols itself (ADR 0400) |
| App Store Connect API (Apple, public) | TestFlight and App Store upload: build uploads, authenticated with an API key | HTTPS from `NomacDistribution` (ADR 0460); Apple's Transporter is not used |

## Modules

| Module | Responsibility |
|---|---|
| `nomac` | Command-line front end (swift-argument-parser). It parses arguments and calls the library modules; it contains no logic of its own. |
| `NomacCore` | The Xcode profile (`XcodeProfile`, ADR 0012): the one Xcode build nomac reproduces and every value taken from it, which the other modules read, and nomac's version (`NomacVersion`). Errors with Xcode-style rendering, property list, file-system (paths found in any Unicode normalization form, as on a Mac, and Xcode's decomposed spellings) and subprocess helpers, MD5, SHA-256, Foundation's string hash and JSON writer (`FoundationJSON`), protocol buffers read and written field by field (`ProtobufMessage`), Mach-O build versions, the location of Swift Build's resource bundles, the subprocess-tool registry. |
| `NomacSDK` | `nomac sdk`: the Xcode subset definition (`XcodeSubset`, ADR 0003), the store under `$NOMAC_HOME`, and the check of an Xcode's build against the profile (`XcodeBuildCheck`) for `sdk install`, `sdk link` and `--developer-dir`. |
| `NomacProject` | Loads `.xcodeproj` (both formats), `.xcworkspace`, the projects they reference, and schemes (shared and the user's own, from projects, workspaces and packages, and autocreated). The autocreation rules that read evaluated target settings (Info.plists, test hosts) ask for them as `TargetSettingsQuery`s, which `NomacInspect` evaluates with Swift Build. |
| `NomacPIF` | Generates the PIF Xcode generates (docs/formats/pif.md), serialized byte for byte as `-dumpPIF` writes it. Synchronized folders are read from disk (`SynchronizedFolder`) and typed with the `FileType` specifications Swift Build ships (`FileTypeRegistry`). |
| `NomacPackages` | Swift packages as Xcode loads them (ADR 0010): finds package references, resolves them with SwiftPM into `SourcePackages`, evaluates manifests with the Mac's answers to host conditions, and builds each package project with the vendored builder and Xcode's delegate answers. Reads Mach-O build versions and SDK version maps from the developer directory. |
| `VendoredPackagePIFBuilder` | SwiftPM's package PIF builder from `swift-6.4.1-RELEASE`, with the changes listed in its `UPSTREAM.md`. |
| `NomacBuildService` | Hosts Swift Build in-process; loads PIF; evaluates build settings; host identity. |
| `NomacBuild` | `nomac build`: runs Swift Build's build operation for the targets `nomac inspect` resolves, with xcodebuild's log and failure summary (`BuildOperation`); off macOS, the `MAC_OS_X_*` settings Swift Build only computes on a Mac, from the required `--host-identity` (`MacHostSettings.buildOverrides`, in `NomacInspect`; B-060). `nomac toolchain install` puts the swift.org toolchain, swiftlang's patched `lld` and LLVM's `dsymutil` into the developer directory's `XcodeDefault` toolchain with launchers at Xcode's tool paths (`LinuxToolchain`, ADR 0100, ADR 0102). Everything that changes how a project's tools run is in `ProjectFixes/`, a table of data with one entry point (`ProjectFixRun`), told to the user by a `note:`, a summary and `nomac check`, and off with `--no-project-fixes` (ADR 0184, docs/PROJECT-COMPATIBILITY.md). Among them, off macOS, the Mach-O macro plugins a project's flags name, built for the build machine from the Swift package beside them and loaded first (`MacroPluginPackages`, ADR 0151); nomac's shell for script phases (`ScriptShell`, ADR 0103) and the exec interposer it preloads, which gives the `#!/bin/sh` scripts a phase starts the same shell (`ExecInterposer`, ADR 0180). Xcode's tools reimplemented from observation: `tapi stubify` (`TAPIStub`, `MachODylib`), macOS's `what` (`WhatStrings`, which Swift Build's patch 10 runs for coremlc's version), the dSYM Info.plist of `dsymutil` (`DSYMInfoPlist`), the App Intents tools (`AppIntentsTools`; `AppIntentsMetadata` writes `Metadata.appintents` from the Swift compiler's constant values, `AppShortcutsTraining` App Shortcuts' `root.ssu.yaml` and `nlu/` with `FlatBufferBuilder` and NomacLZFSE, docs/formats/app-intents.md); Swift Build's provisioning question for manual development signing (`ManualSigning`, `--keychain`, `--provisioning-profiles`) |
| `NomacInspect` | `nomac inspect` semantics: maps xcodebuild invocations (target, scheme, destination, DerivedData) to Swift Build requests; the complete workspace PIF with packages (`WorkspacePIF`), settings written with macros or SDK conditions, and the signing identities of targets that set no provisioning style, evaluated by Swift Build; `nomac verify` (`ReferenceVerifier`). |
| `NomacVerify` | Output formats and comparisons: `-showBuildSettings` text, path-root normalization, PIF comparison, nibs whose sets alone are in another order (`NibSetComparison`, ADR 0252), whose settled constraint ties are (`NibTieComparison`, ADR 0253) or whose outlet collections of several sources are (`NibConnectionComparison`, ADR 0260), xcodebuild build logs and the tool checks that rerun their resource tasks with nomac's tools (`ToolVerification`), the signing and export checks that replay an archive capture (`ArchiveVerification`), verification reports, corpus results and the progress model of corpus.json. |
| `NomacSigning` | `nomac codesign`: code signatures as Xcode's codesign writes them, ad-hoc or with a certificate (docs/formats/code-signature.md): the Mach-O layout (`MachOImage`), code directory and blobs (`CodeSignature`), XML and DER entitlements, `_CodeSignature/CodeResources`, identities from PEM files (`SigningIdentity`), provisioning profiles and whether Apple signed them (`ProvisioningProfile`, `ProfileSignature`), the CMS signature (`CMSSignature`), universal files (`MachOContainer`), designated requirements as `-r- --display` prints them (`RequirementText`), and codesign's command line (`CodesignArguments`); a link named `codesign` runs it, for Swift Build's `CODESIGN`. |
| `NomacPackaging` | IPAs as `xcodebuild -exportArchive` writes them (docs/formats/ipa.md): `nomac export` (`ArchiveExporter`: copy, with an identity the profiles each bundle embeds, for app-store-connect the Info.plists written again (`ExportedInfoPlist`, with `NomacPlist`), `Symbols` and `SwiftSupport`, re-sign nested code then the app, `ExportOptions.plist`, `DistributionSummary.plist`), archives as `xcodebuild archive` assembles them from Swift Build's intermediates (`XCArchive`, `nomac xcarchive`, docs/formats/xcarchive.md), `nomac check`'s `signing:` domain (`SigningDomain`, `SigningEnvelope`, ADR 0011), copies as `ditto <source> <destination>` makes them (`DittoCopy`, `nomac ditto`), zip archives as ditto writes them (`DittoArchive`, APFS name order, deflate from the system zlib through the `CZlib` module), and the `.symbols` files of app-store-connect exports (`SymbolsFile`, `nomac symbols`, docs/formats/symbols.md) from a dSYM's Mach-O (`MachOFile`) and DWARF (`DWARF`), with libc++'s sort (`IntroSort`).; app thinning's variants from the user's Xcode's `device_traits.db` (`AppThinning`, SQLite through `CSQLite`); crash reports (`.ips`) symbolicated as `atos -i` does (`CrashReport`, `Symbolicator` over the dSYM readers, `Demangler`, `nomac atos`, docs/formats/crash-report.md) |
| `NomacCoreML` | Core ML models (ADR 0240, docs/formats/coreml.md): the public specification read and written again field by field (`ModelSpecification`, `ModelFeature`, with `NomacCore`'s `ProtobufMessage`); `nomac coremlc compile` for the types stored as `spec` archives (`CoreMLModelCompiler`: the archive, `analytics/coremldata.bin`, `metadata.json` in Foundation order with `FoundationJSON` and `FoundationHashTable`) and ML programs (`MILText` prints the program as `model.mil`, `MILOperations` names operations as Core ML counts them); `nomac coremlc generate --language Swift` (`SwiftClassGenerator`); `nomac check`'s `coreml:` domain (`CoreMLDomain`); `nomac verify`'s `coreml` tool checks rerun a reference build's CoreMLModelCompile and CoreMLModelCodegen tasks (`ToolVerification`, `CoreMLComparison` in `NomacVerify`) and the files of a given type in targets' phases and synchronized folders (`ProjectFiles`), which the `metal:` domain (`MetalDomain`, in `nomac`) also reads. |
| `NomacDevice` | `nomac device`, `nomac install`, `nomac uninstall`, `nomac launch`, `nomac stop` (ADR 0400): usbmuxd's protocol (`USBMux`, docs/formats/usbmux.md) over a Unix or TCP socket (`StreamSocket`); lockdownd's framing, requests and sessions (`PropertyListMessages`, `Lockdown`, `PairRecord`, docs/formats/lockdown.md) with TLS through swift-nio-ssl (`TLSStream`, ADR 0401); AFC and installation_proxy (`AFC`, `InstallationProxy`, `DeviceSession`, docs/formats/afc.md); the provisioning checks a device applies to a signed app (`InstallCheck`, TN3125); the CoreDevice tunnel (`CoreDeviceTunnel`, TCP in userspace in `TunnelNetwork`, ADR 0402), RemoteXPC (`XPC`, `RemoteXPC`) and the app service's launch, with the app's console (`CoreDeviceService`, `ProcessConsole`, docs/formats/remotexpc.md); the Developer Disk Image's personalization and mount (`Personalization`, `DeveloperDiskImage`, `MobileImageMounter`, ADR 0403, docs/formats/ddi.md); crash reports over crashreportmover and crashreportcopymobile (`CrashReports`, docs/formats/crash-report.md) |
| `NomacDeviceTest` | `nomac test` (ADR 0430): DTX messages and channels (`DTX`, docs/formats/dtx.md), keyed archives written and read without Foundation's archiver (`KeyedArchive`), testmanagerd's IDE and driver sessions (`TestManager`, `DeviceTestSession`, docs/formats/xctest-device.md), the `.xctestrun` read and written (`XCTestRun`, `XCTestRunWriter`, docs/formats/xctestrun.md) |
| `NomacDistribution` | `nomac upload` (ADR 0460, docs/formats/app-store-connect-upload.md): App Store Connect API keys and their ES256 tokens (`AppStoreConnectKey`), JSON:API requests over a swappable transport (`AppStoreConnectClient`, `HTTPTransport`, `DryRunTransport`), the app's values read from an IPA (`IPAInfo`) and the build upload's reserve, send, commit and wait (`BuildUploader`) |
| `NomacPlist` | Property lists as Xcode's tools write them (XML, and binary as Swift Build's builtins write it), readers for the text formats and `bplist00` (docs/formats/property-lists.md, ADR 0250), and the iteration order of Foundation's hash tables (docs/formats/foundation-collections.md). |
| `NomacNib` | Interface Builder documents: `NIBArchive` writer, the nib encoder and the UIKit classes observed so far; refuses anything not observed (docs/formats/nib.md, ADR 0251). |
| `NomacCoreData` | `nomac momc`: compiles `.xcdatamodel` and `.xcdatamodeld` into the `.mom` files, `VersionInfo.plist` and the current version's `.omo` (`OptimizedModel`, column-name lists sorted: ADR 0230; lookup positions of its own: ADR 0231; families sorted: ADR 0232) Xcode 27.0's momc writes, and its notes and warnings (docs/formats/coredata.md, ADR 0270). A model reader that refuses what is not observed, Core Data's version hashes, `NSKeyedArchiver` with Core Foundation's binary writer and the object identities momc's process has (interned and tagged strings), and the encoding of each Core Data class as a recording `NSCoder` saw it. `CodeGenerator` writes the Swift or Objective-C classes of `momc --action generate`; `MappingCompiler` the `.cdm` of `nomac mapc` from an `.xcmappingmodel`; `CoreDataDomain` is `nomac check`'s `coredata:` domain, reporting the models nomac's momc refuses. |
| `NomacStrings` | Localization resources: `builtin-copyStrings` (`StringsFileCopy`), `xcstringstool compile` (`StringCatalogCompiler`) and `generate-symbols` (`StringSymbolGenerator`), reproduced from observed outputs (docs/formats/strings.md). |
| `NomacIntents` | `nomac intentbuilderc generate`: the Swift classes Xcode 27.0's intentbuilderc writes for an `.intentdefinition` (`IntentDefinition`, `IntentCodeGenerator`; docs/formats/intents.md). `compile` waits on its hash (BACKLOG B-232). |
| `NomacEnvelope` | `nomac check`: the features a project uses, read from its files as written, and the envelope of features verified against Xcode (ADR 0011, docs/formats/check.md). Each workstream adds a `FeatureDomain`; the loader's is here. |
| `NomacAssets` | `nomac actool`: compiles asset catalogs into `Assets.car`, the partial Info.plist and the dependency info as Xcode 27.0's actool does (docs/formats/asset-catalog.md, ADR 0200). `nomac copypng` copies loose PNGs as Xcode's copypng does. A BOM store writer (`BOMNumberTree` builds `BITMAPKEYS` with actool's leaf splits), the CAR tables with actool's block creation orders and name identifiers, and one compiler per asset type (color, data and image sets, multi-size app icon sets with their CgBI PNGs (`AppIconSet`, `IconPNG`), launch image sets without files, sprite atlases (`SpriteAtlas`); images through `Atlas` and `Deepmap2`, app icons through `PlainImagePayload`). `AssetSymbols` writes the Swift, Objective-C and index files of Swift Build's `GenerateAssetSymbols` task for color and image sets. `AssetsDomain` is `nomac check`'s `assets:` domain (ADR 0011).; thinning a compiled catalog for one device as assetutil does (`CARThinning`, `nomac assetutil`) |
| `NomacLZFSE` | LZFSE and LZVN encoders: a Swift port of Apple's open-source reference encoder, byte-identical to it and to the streams actool writes, through libcompression's buffer and stream APIs (ADR 0201, `UPSTREAM.md`); and a decoder written from the format the encoders write (`LZFSEDecoder`), which `nomac verify` uses for App Shortcuts' `nlu.lzfse`. |
| `NomacMacros` | Apple's macro plugins reimplemented (ADR 0150, docs/formats/macros.md): their Swift sources, one directory per plugin module (`Plugins/PreviewsMacros`, `Plugins/SwiftUIMacros`, `Plugins/SwiftDataMacros`, `Plugins/AppIntentsMacros`, `Plugins/FoundationModelsMacros`, `Plugins/TipKitMacros` with swift-foundation 6.3's predicate translation vendored, and swift-foundation's `Plugins/FoundationMacros`, vendored), are resources that `MacroPlugins` compiles with the installed toolchain against its own swift-syntax and installs in each platform's plugin directory, with links to the toolchain's `swift-plugin-server` and open-source plugins (`nomac toolchain install`). |
| `NomacPluginAPI` | The libraries build tool plugins link off macOS (ADR 0105): SwiftPM's open-source `PackagePlugin`, vendored with its entry point to `XcodeProjectPlugin` made callable (`PluginAPI/PackagePlugin/UPSTREAM.md`), and nomac's `XcodeProjectPlugin`, built at first use by the plugins' compiler under nomac's home. |
| `NomacTestSupport` | Test fixtures, including a self-authored synthetic developer directory. |

## One Xcode per release

Each nomac release reproduces one Xcode build (ADR 0012): `nomac --version` prints
`nomac 27.0.4 (Xcode 27.0, 27A266a)`, and every value that changes with Xcode (pins, tool
versions written into outputs or answered to probes, SDKs, the reference Mac, the Mac's answers
to manifest conditions, the `objectVersion`s Xcode reads) is in `XcodeProfile.current`, printed by
`nomac sdk profile`. Moving to another Xcode observes these values, and the experiments behind
nomac's rules, again with `.github/scripts/xcode_upgrade.py` (docs/UPGRADING.md).

## Driving Swift Build

Swift Build is a service with a message protocol. Xcode runs it as a separate process
(`SWBBuildService.bundle`). nomac links it as a library and starts it in-process, which is
also what SwiftPM does:

1. **Start the service.**
   `SWBBuildService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint))`.
   All platform plugins (`SWBApplePlatform`, `SWBUniversalPlatform`, ...) are statically
   registered, because SwiftPM builds Swift Build with `USE_STATIC_PLUGIN_INITIALIZATION`.
   Their `.xcspec` files are SwiftPM resources and load from the `*.resources` bundles next
   to the executable.
2. **Create a session for a developer directory.**
   `service.createSession(name:developerPath:...)` with the path of an Xcode-shaped
   `Contents/Developer` directory. Swift Build's `Core` then reads:
   - `../version.plist`: Xcode version and build (`XCODE_VERSION_ACTUAL`,
     `XCODE_PRODUCT_BUILD_VERSION`). Missing means "99.99.99"; present but older than 16.2 is
     rejected.
   - `Toolchains/*.xctoolchain/ToolchainInfo.plist`: toolchain identity.
   - `Platforms/*.platform/Info.plist` and `version.plist`: platform identity, `DefaultProperties`.
   - `Platforms/*.platform/Developer/SDKs/*.sdk/SDKSettings.(json|plist)`: SDK identity,
     `DefaultProperties`, `CustomProperties`, `SupportedTargets`.
   It also searches `/Library/Developer/Toolchains`, `~/Library/Developer/Toolchains` and
   `$EXTERNAL_TOOLCHAINS_DIR` for extra toolchains.
3. **Load the workspace.** `session.loadWorkspace(containerPath:)` with the path of a JSON PIF
   file. When given an `.xcodeproj`, Swift Build itself shells out to
   `xcrun xcodebuild -dumpPIF`, which only works on a Mac. That command is also how the
   reference workflow captures Xcode's own PIF for comparison.
4. **Describe the host.** `session.setSystemInfo` (OS version and build, native architecture)
   and `session.setUserInfo` (user, group, ids, home, environment). These become settings
   such as `USER`, `UID`, `HOME` and, on macOS, `MAC_OS_X_VERSION_ACTUAL`. nomac
   reports the real user by default, on the real machine on macOS and on the profile's
   reference Mac elsewhere (`HostIdentity.default()`, B-060), or a recorded reference host when
   comparing (`--host-identity`).
5. **Ask questions.** `session.allExportedMacroNamesAndValues(level: .target(guid),
   buildParameters:)` returns every exported setting, computed by the same function
   (`computeScriptEnvironment`) Xcode uses for `xcodebuild -showBuildSettings` and for
   shell-script build phase environments. `SWBBuildParameters` carries the action,
   configuration, run destination, build locations ("arena") and command-line overrides.
6. **Build.** `session.createBuildOperation(request:delegate:)` with an `SWBBuildRequest` whose
   parameters are the settings request's and whose configured targets are the ones `-scheme` or
   `-target` selects, as in SwiftPM's `SwiftBuildSystem` (`NomacBuild.BuildOperation`). The
   tools Swift Build plans are looked up in the `XcodeDefault` toolchain first; on Linux that is
   where `nomac toolchain install` puts the swift.org toolchain, the linker and launchers for
   the tools nomac reimplements (ADR 0100, ADR 0102). Compiled outputs are equivalent to Xcode's,
   everything else identical (ADR 0101).
7. **Close the session, then the service.** Swift Build stops the process when a session is
   released without `session.close()`, so nomac's sessions exist only inside
   `SwiftBuildEngine.withWorkspace` (and `BuildSettingsInspector.with`), which close the
   session and the service whether their body returns or throws.

This sequence is exercised on Linux by `Tests/NomacBuildServiceTests/EngineSmokeTests.swift`
and `Tests/NomacPIFTests/PIFGeneratorTests.swift` against the synthetic developer directory,
and on macOS against Xcode 27 by the `reference` workflow (docs/VERIFICATION.md).

### Engine differences between platforms

Swift Build is the same code everywhere, with two differences that matter to nomac:

- Its "insecure hash" (`InsecureHashContext`, `String.md5()`, the `:md5` macro operator) is MD5
  on Apple platforms and SHA-256 elsewhere. nomac therefore computes PIF identifiers with its
  own MD5 (`NomacCore.MD5`); Swift Build hashes with MD5 on Linux too, since the owner's fork
  carries the upstream patch (docs/upstream/swift-build.md section 2, ADR 0005).
- It takes the host operating system and architecture from the machine it runs on, not from
  `SWBSystemInfo`: `HOST_PLATFORM`, `NATIVE_ARCH*` and the `MAC_OS_X_*` settings, and through
  them `HOST_ARCH` and the default `SDKROOT` of a target that sets none. Off macOS, nomac
  evaluates settings with a Mac's values among the synthesized overrides (`MacHostSettings`,
  docs/formats/show-build-settings.md "Settings of the machine"). A build takes only the
  `MAC_OS_X_*` ones: Swift Build also builds host tools for `HOST_PLATFORM` and `NATIVE_ARCH`,
  and those run on the machine (B-061).

## Settings requests: from xcodebuild arguments to Swift Build

| xcodebuild | Swift Build request |
|---|---|
| no `-target`/`-scheme` | first target of the project; project default configuration; no run destination; no arena, so products go to `<project>/build` |
| `-target T` / `-alltargets` | those targets; otherwise as above |
| `-scheme S` | the scheme's build-for-running entries; Launch configuration unless `-configuration`; arena `~/Library/Developer/Xcode/DerivedData/<name>-<hash>` (`DerivedData.folderName`, `DerivedData.folderHash`) |
| `-destination generic/platform=iOS` | run destination `iphoneos`, target architecture `undefined_arch`, supported `arm64 arm64e armv7 armv7s`, only-active-arch disabled |
| `-derivedDataPath P` | arena root `P` |
| `KEY=VALUE` | command-line overrides table |

## Install layout

`swift build` produces `nomac` plus one `<package>_<module>.resources` directory per Swift
Build module that has resources (the `.xcspec` files). The executable finds them next to
itself, so an installation is the executable plus those directories, copied together.

## Verification

See ADR 0004 for the contract and corpus/README.md for the corpus. In short: the macOS
`reference` workflow records what Xcode does, nomac reproduces it from the same inputs, and
`nomac verify` diffs the two after rewriting three machine-specific path roots.

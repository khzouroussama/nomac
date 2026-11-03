# Workstream: packaging and signing

IPA, entitlements, code signatures, dSYM, extensions. Branch `pack/signing`; BACKLOG B-300–B-399,
ADRs 0300–0399. Goal: from a built `.app`, nomac produces what Xcode 27.0 produces, the signed
`.app` and the IPA, byte for byte where Xcode is deterministic.

## Current step

Ad-hoc code signing (`nomac codesign`, docs/formats/code-signature.md) reproduces every signing
step of Xcode 27.0 archives of self-written apps (frameworks, extensions, re-signed embedded
frameworks, apps, also under umask 002) byte for byte, and `nomac export` reproduces
`xcodebuild -exportArchive` of ad-hoc archives (methods `debugging`, `release-testing`,
`enterprise`, and the exports xcodebuild refuses): the IPA byte for byte once entry times, owner
ids and the umask-dependent mode of `Payload/` are set aside, `ExportOptions.plist` and
`DistributionSummary.plist` byte for byte. Signing with a certificate (other than Apple's)
matches codesign byte for byte for the same signing time. `nomac symbols` writes the
`Symbols/*.symbols` files of app-store-connect exports byte for byte (docs/formats/symbols.md).
Universal files, iOS 15 page sizes, Swift's back-deployment libraries (their linked-in
Info.plist, the signature space Apple's signature leaves) and `-r- --display` match codesign,
so `nomac codesign` replays every signing step of the experiments' archives (135 of 135, and
the 17 of the watch and App Clip experiments) and is Swift Build's `CODESIGN` through a link named
`codesign`. Watch apps (32-bit arm64_32 slices, SHA-1 code directories) and App Clips (left out
of non-App Store exports) are signed and exported as Xcode does, and `nomac symbols` writes a
watch app's `.symbols` files (one per slice of its universal dSYM). `nomac export` also does
app-store-connect exports (B-309), install manifests and on-demand resources (embedded,
hosted beside the IPA, or in an app-store-connect export): all 69 of the experiments' exports
(and the 8 of `alone` and `entitlements-empty`) are identical to Xcode's. `nomac xcarchive`
assembles the `.xcarchive` from an archive build's intermediates as xcodebuild does
(docs/formats/xcarchive.md). Apple Development (iOS) chains sign as codesign does, and `nomac export` does development exports with an identity and a
profile. What is left waits on the owner's identity or on an observation (below).

## What's left and what it needs

- **Waiting on the owner's identity (B-302).** Distribution identities and methods
  (release-testing, enterprise, app-store-connect with a certificate), exports with a profile
  other than the archive's, how a project's entitlements merge with a profile's, App Clips
  (their product type needs a profile), detached signatures of asset packs with a certificate
  (B-303), and the `signing:` envelope's identity, profile and entitlements entries. Needs an
  identity and profile the owner provides for nomac (a wildcard development profile, or a
  distribution identity and profile), never the company apps'; then manual signing, offline,
  outputs private, as for development. Automatic signing also asks Apple's services, so it
  stays unverified unless the owner allows that.
- **The build driver's side.** Development profiles are answered (2026-10-30, the device
  workstream): `nomac build` and `nomac archive` with `--keychain <PEM>` and
  `--provisioning-profiles <folder>` sign with the identity `CODE_SIGN_IDENTITY` names under
  `CODE_SIGN_STYLE=Manual`, as observed (docs/formats/ipa.md), and `nomac archive` runs
  `nomac xcarchive` after the build. Left: a tool's entitlements (Swift package
  `application-identifier` `""`, "Just finished" below), and entitlements files merged with a
  profile (B-302).
- **Observations without an account that no corpus app needs yet**, one self-written
  experiment each on the Mac: bundles without `CFBundleIdentifier` (B-303) and Zip64 IPAs
  (B-306, a 4.5 GB resource) and the rarer on-demand resources shapes (B-312), all three
  refused naming the item; file names outside ASCII (B-304), whose order rules are checked for
  ASCII and `é` only; frameworks embedded without code signing on copy, unverified in
  `nomac check`. macOS-style bundles and SHA-1-only deployment targets (B-305) are outside the
  iOS scope.

## Just finished

- The archive's dSYMs at any depth of the products folder (`archive-nested-dsyms`,
  docs/formats/xcarchive.md): CocoaPods' prebuilt pods' dSYMs under `XCFrameworkIntermediates`
  were missing from nomac's archives (six in expo-default's); `nomac xcarchive` over Xcode's
  expo-default products now archives the same seven dSYMs, the pods' byte for byte. The 19 earlier
  archive experiments replay identical.
- (Device workstream, 2026-10-31) B-302 with the nomac development identity in a temporary
  keychain file for offline experiments (decided by the integrator under the owner's
  delegation): ad hoc archives exported with a profile, entitlements files merged with a profile
  (and Xcode's refusal of an entitlement it lacks), detached bundles signed with a certificate;
  each reproduced, checked privately against Xcode's and codesign's outputs.
- (Device workstream, 2026-10-31) Static frameworks: a non-Mach-O binary signs detached as
  "generic", `--generate-pre-encrypt-hashes` gives the version 0x20500 detached code directory,
  and the embedded copy's linker signature leaves no metadata to preserve (signing experiments
  `framework-static`, `framework-codeless`; docs/formats/code-signature.md).
- (Device workstream, 2026-10-30) The build's side of development signing: `nomac build` and
  `nomac archive --keychain <PEM> --provisioning-profiles <folder>` with manual signing answer
  Swift Build as observed (docs/formats/ipa.md), so a nomac-built archive carries the identity's
  signature and the profile and `nomac export` exports it. Under ad hoc, an empty entitlements
  file signs as Xcode does and one holding entitlements fails with Xcode's "requires a
  provisioning profile" (signing-experiments `entitlements-*`; B-114 closed).
- An item signed with an empty entitlements dictionary needs no profile: `nomac export` refused
  expo-default's ad-hoc archive ("requires a provisioning profile", 70) because it tested the
  entitlements blob's bytes, a whole property list, for emptiness; xcodebuild exports it.
  Experiment `entitlements-empty` (an app signed with `<dict/>`) shows it for all four methods;
  `ArchiveExporterTests.exportsAnAppWithEmptyEntitlements` covers it. expo-default's export is
  now identical to Xcode's (IPA, summary, options).
- An app that embeds nothing gets no `embeddedBinaries` in `DistributionSummary.plist`; nomac
  wrote an empty array (since 046364f), which `nomac verify`'s export checks showed for tofu,
  flappy-fly-bird and uncloudnotes. Every app of the experiments embedded a framework, so
  `compare-export` never saw the case: experiment `alone` (an app without frameworks or
  extensions) shows it for all four methods, and `ArchiveExporterTests` covers it
  (`summarizesAnAppEmbeddingNothing`, observed through `synthetic-export`). `compare-export`:
  4 of 4 for `alone`, 57 of 57 for the other experiments' outputs on this Mac.
- B-311 done: an archive of one app beside any other installed product (a framework, a static
  library, a tool in `usr/local/bin` or `/opt/nomac`: `archive-products-installs-framework`,
  `-app-library`, `-app-tool`, `-app-tool-opt`) or of nothing is generic, an app's asset packs
  keep `ApplicationProperties`; `compare-archive`: 19 of 19. Swift package
  dynamic products, ExtensionKit extensions (App Intents) and XPC services are signed,
  archived and exported as Xcode does (a loadable bundle in the app's resources is an item of
  the export too). Two `.symbols` rules from an App Intents extension's async code: a former
  `N_PEXT` marks every deduplicated function, and line rows inside them are left out.
- The OTA install manifest (`manifest.plist`), byte for byte for the three methods, and the
  IPA's name (the app's `CFBundleName`).
- On-demand resources (`odr`, `odr-three`), all three ways: embedded in the app
  (`AssetPackManifest.plist` written from the template keeping its object sharing), beside it
  for app-store-connect (pack Info.plists written again with the app's versions), and hosted
  (zipped beside the IPA in Apple's pack zip format with its metadata plist). Asset packs get
  codesign's detached signature (a bundle without an executable, 0x20100 code directory).
- `nomac check`'s `signing:` domain (ADR 0011): for every native target, read as written for
  the configuration archives use, the product kind, identity, style, entitlements file,
  profile, embedded code, the deployment targets that change signatures, dSYMs and on-demand
  resources; its envelope cites the experiments for what nomac reproduces and B-302 for the
  rest. Registered in `CheckCommand.domains`.
- Archives of every product kind (item 1 of the integrator's list; B-311 in part): one project
  with an app, a second app, a framework, a static library, a tool and a loadable bundle,
  archived by scheme. Framework, library and tool archives, and the archive of two apps, are
  generic (no `ApplicationProperties`); every dSYM the build makes is collected (bundles and
  tools too; a static library has none). `nomac xcarchive` assembles all nine experiments'
  archives as xcodebuild does; `compare`: 90 of 90 signing steps (a bundle, a tool).
  For the build driver: Swift Build signs an ad-hoc iOS tool with an `.xcent` holding
  `application-identifier` `""` and `keychain-access-groups` `[""]` (the provisioning
  inputs' `signedEntitlements` for a tool), where nomac answers none today.
- B-302, Apple-issued identities: chains to Apple's root (Apple Root CA) get the iOS designated
  requirement (`anchor apple generic`, the leaf's common name, the intermediate's iOS marker)
  and the leaf's OU as team identifier in the code directory; other roots name the last
  certificate with the leaf's organization (`DRMaker::nonAppleAnchor`). Checked privately with
  the owner's Apple Development identity without exporting its key: nomac's signature of a
  self-written file, given codesign's RSA value and signing time, is codesign's byte for byte,
  and `codesign --verify` and `openssl cms -verify` accept it (and reject it a second later).
  `SigningIdentity` now takes the RSA signing as a function, which the check used. A
  certificate signature of a watchOS file below 12.0 (SHA-1 and SHA-256 code directories)
  matches codesign's with a self-made identity: the CMS signs the SHA-1 directory and names
  both in its hash-agility attributes.
- A development profile observed privately (archive and `debugging` export, manual signing,
  offline): the embedded profile, the entitlements of each signing step, and the summary's
  certificate, entitlements and profile fields (docs/formats/ipa.md). `nomac export` now does
  such exports (`--keychain <PEM>`, `--provisioning-profiles <folder>`): checked privately
  with each item's signing time and Xcode's RSA values, every signed attribute set was
  Xcode's and the IPA, `DistributionSummary.plist` and `ExportOptions.plist` are identical;
  `nomac xcarchive` assembles that archive again identically (its `SigningIdentity` and
  `Team`). `ProfileExportTests` encodes the rules with a self-made identity and profile.
- Archives (item 5): what `xcodebuild archive` does after Swift Build's archive build,
  observed with derived data kept: `Products` is the build's installation location, moved;
  `dSYMs` copies every dSYM of every platform's products folder with its times (empty without
  dSYMs); `SwiftSupport` is copied; `Info.plist` names the scheme (`Name`, `SchemeName`) and the
  app's path, architectures and versions, with an empty `Team` for ad-hoc signatures even with
  `DEVELOPMENT_TEAM`. `nomac xcarchive` does the same (docs/formats/xcarchive.md); the
  experiments now keep `BuildProductsPath`, and `compare-archive` finds 4 of 4 archives
  identical, file times included. The dSYMs themselves are the build driver's (`nomac dsymutil`).
- app-store-connect exports of archives without dSYMs (an empty `Symbols` folder) and under
  umask 002 (`Symbols` follows the umask, rewritten Info.plists keep their mode), observed.
- The app-store-connect export (B-309): Info.plists written again in their own format (binary
  in Foundation's order, XML as Core Foundation writes it), not those of frameworks; `.symbols`
  files for every dSYM slice, recording the archive's path with symbolic links resolved;
  `SwiftSupport` copied beside `Payload`; the method's options and `symbols` in every summary
  entry. NomacPlist gained a `bplist00` reader, and `foundationData` now orders the top
  dictionary as the export's shallow mutable copy does: a self-written Info.plist whose key
  wraps around the 23-bucket table showed it (`AppStoreExportTests`), where the experiments'
  plists did not. An archive without dSYMs gets an empty `Symbols` folder
  (`writesAnEmptySymbolsFolderWithoutDSYMs`), and under umask 002 `Symbols` follows the umask
  while the rewritten Info.plists keep their mode (`umask` experiment, now also exported for
  app-store-connect). `compare-export`: 41 of 41 and 12 of 12, app-store-connect with and
  without symbols included.
- Universal dSYMs (B-310): the app-store-connect export writes one `.symbols` file per slice of
  a watch app's dSYM; the arm64_32 one is a 32-bit Mach-O (`nlist`, `LC_SEGMENT`) with 4-byte
  DWARF addresses, and keeps the file's addresses where 64-bit files are made relative to
  `__TEXT`. `compare-symbols`: 13 of 13 on the watch and App Clip experiments, 34 of 34 on the
  others; `writesSymbolsForEachSliceOfAUniversalDSYM` matches xcodebuild's export of a
  self-written universal dSYM.
- Watch apps and App Clips (experiments `watch`, `appclip-script`, `watch-appclip-script`; the
  refusals `appclip`, `watch-appclip`, `appclip-entitlements`, `appclip-no-entitlements`,
  `appclip-unsigned`): a watch app is built, signed once and copied into `Watch/`; its
  executable has an arm64 slice (watchOS 26.0) and a 32-bit arm64_32 one (11.0). codesign hashes
  4 KB pages below watchOS 9.0 and adds a SHA-1 code directory (slot 0, SHA-256 in 0x1000)
  below 12.0, in every slice of the file when one slice needs it; the main slice is arm64 and ARM
  slices are written aligned to 16 KB. Xcode will not archive an App Clip ad hoc (its product
  type adds an entitlement that needs a profile, B-302), so the experiments sign a stand-in in a
  script phase. Exports sign `AppClips/` and `Watch/` apps as nested items in path order;
  `debugging`, `release-testing` and `enterprise` remove App Clips and add
  `distributionBundleIdentifier`. `compare`: 17 of 17; `compare-export`: 9 of 9;
  `leavesAppClipsOut` matches xcodebuild's export of a self-written archive with a clip.
- Universal files (B-301): each slice signed as alone with the file's identifier, from the
  arm64e slice; slices re-laid at their alignment. Codesign hashes 4 KB pages for iOS below
  16.0 (16 KB from 16.0), takes a lone file's identifier and slot -1 from its linked-in
  Info.plist, and leaves the old file's bytes in the unused signature space.
- Back-deployed Swift libraries (B-308): the `span` experiments (from the B-308 notes) show
  `libswiftCompatibilitySpan.dylib` embedded below iOS 26, signed by `swift-stdlib-tool`
  between two `-r- --display` probes; `nomac codesign` prints what codesign prints for them.
  `nomac export` signs `.dylib` files among the bundles in bytewise path order and lists
  libraries in `DistributionSummary.plist` except Swift's runtime ones
  (`com.apple.dt.runtime.`). `compare-export`: 30 of 30, the span experiments included.
- B-302 started (owner's approval of 2026-10-22, manual signing only, xcodebuild offline,
  outputs under `wt-scratch/pack/private`): the first observation of an Apple Development
  signature, written since (above).
- For the build driver, provisioning on Linux: Swift Build asks the client for each configured
  target's provisioning inputs (`GET_PROVISIONING_TASK_INPUTS_REQUEST`, answered by nomac's
  `PlanningDelegate`, today only for `-`). For a manual development profile Xcode's build
  shows (private archive above): the app signed with `--force --sign <identity SHA-1>
  --entitlements <App.app.xcent> --generate-entitlement-der`, the `.xcent` being
  `application-identifier` `<team>.<bundle id>`, `com.apple.developer.team-identifier`
  `<team>` and `get-task-allow` true, the profile embedded byte for byte; a framework signed
  with `--force --sign <identity SHA-1> --generate-entitlement-der`, without entitlements or
  profile; no `--timestamp=none`. So the answer is, for the app: `identityHash` the SHA-1
  (upper case), `identityName` the certificate's common name, `profileName`, `profileUUID`
  and `profilePath` of the installed profile, `signedEntitlements` those three entitlements;
  for a framework: `identityHash` and `identityName` only. From Swift Build's source, not
  seen in Xcode's outputs: `appIdentifierPrefix` and `teamIdentifierPrefix` are `<team>.`,
  and `keychainPath` becomes `CODE_SIGN_KEYCHAIN`, which adds `--keychain <path>` to codesign:
  give the PEM file there, as `nomac codesign` needs it on Linux. NomacSigning's
  `ProvisioningProfile` reads installed profiles and `SigningIdentity` the PEM identity
  (`certificateSHA1`, `commonName`). How an entitlements file of the project merges with the
  profile's is not observed (B-302).
- For the build driver: Swift Build runs `$(CODESIGN)` with `--force --sign <id>
  [--entitlements <file>] [--timestamp=none] [--preserve-metadata=…]
  --generate-entitlement-der <path>`, `--force --sign <id> --verbose [--keychain <k>] <lib>`
  and `-r- --display <lib>`; a symlink named `codesign` to `nomac` accepts them all.
- `.symbols` files (B-307): the format decoded from Xcode's exports (`adhoc`, `nested` and the
  new `symbols` experiment with C, Objective-C, C++ and eight static functions of one name) and
  from copies of a self-written dSYM run through the `symbols` tool; `SymbolsFile` reads the
  dSYM's Mach-O and DWARF 4/5 (units, ranges, line tables) and lays out segments, sections,
  symbols, inlined calls (breadth first), line rows, two name indexes (libc++'s `std::sort`,
  whose order shows for equal names) and the strings. `compare-symbols`: 12 of 12 identical;
  `writesTheSymbolsXcodeWrites` checks a self-written dSYM against the file Xcode's export wrote.
- The experiments' xcodebuild runs offline (`sandbox-exec`): with an Apple account in Xcode,
  app-store-connect exports asked Apple's developer services about the team (`viewDeveloper`,
  read-only; both attempts failed and the exports succeeded). Nothing was changed or uploaded.
- The review of the first six commits: `--identifier` no longer needs `LC_UUID`, and a file
  without it gets codesign's default identifier (SHA-1 of its header and load commands);
  identities are found by name as codesign finds them (exact or only partial match, ignoring
  case, ambiguity message); `_CodeSignature` and `CodeResources` keep existing modes and are
  made 0755 and 0644; archives that need Zip64 stop with the B-306 error instead of trapping;
  the export test no longer depends on the umask; ADR 0300 records why CMS and X.509 are
  written by hand.
- Every rule is re-observable with the committed script: `synthetic` builds a throwaway
  keychain per certificate case from the test's identity file and also converts property lists
  with plutil; new cases cover the `execSegFlags` entitlements, `MH_BUNDLE`, DER without
  `--generate-entitlement-der`, entitlement integers, identifier stems, files without `LC_UUID`
  and identity names. New experiments: `refusals` (no team, entitlements) and `umask` (002).
  `DittoArchiveTests` has a file stamped 23:59:59 that ditto writes as 00:00:00 of the next day.
- `compare`: every captured signing step identical (`adhoc`, `nested`, `refusals`, `umask`);
  `compare-export`: debugging, release-testing and enterprise of `adhoc` and `nested`,
  debugging of `umask` and both refusals identical.

## Next actions

1. Stopped until the owner provides an identity and profile for nomac (B-302, pending; above):
   the company apps must never be used, so the private profile experiment's outputs are
   deleted and not repeated. Then manual signing, offline, outputs under
   `wt-scratch/pack/private`, nothing identifying in the repository, `leak_scan.py` before
   every commit.
2. For the build driver (its state file): after an archive build (Swift Build's install build
   into `ArchiveIntermediates/<scheme>`), `nomac xcarchive --intermediates
   <ArchiveIntermediates/<scheme>> -archivePath <path> -scheme <scheme>` makes the archive.

## How to reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/signing_experiments.py ~/nomac-out/wt-scratch/pack/exp   # every experiment
swift build -j 4
python3 .github/scripts/signing_experiments.py compare ~/nomac-out/wt-scratch/pack/exp .build/debug/nomac
python3 .github/scripts/signing_experiments.py compare-export ~/nomac-out/wt-scratch/pack/exp .build/debug/nomac
python3 .github/scripts/signing_experiments.py compare-symbols ~/nomac-out/wt-scratch/pack/exp .build/debug/nomac
python3 .github/scripts/signing_experiments.py compare-archive ~/nomac-out/wt-scratch/pack/exp .build/debug/nomac
# re-observe the values NomacSigningTests expect (certificate cases import the test identities
# into a throwaway keychain, listed only while codesign runs, then deleted)
NOMAC_SIGNING_OBSERVE=/tmp/observe swift test --filter NomacSigningTests
python3 .github/scripts/signing_experiments.py synthetic /tmp/observe
NOMAC_PACKAGING_OBSERVE=/tmp/observe swift test --filter NomacPackagingTests   # /tmp/observe: the
python3 .github/scripts/signing_experiments.py synthetic-export /tmp/observe     # .symbols path
shasum -a 256 /tmp/observe/ditto.zip   # the digest DittoArchiveTests expects
```

On the Mac, build and test with Xcode 27.0's Swift 6.4 (`DEVELOPER_DIR` as above): the default
Swift 6.2 of `/Applications/Xcode.app` fails to type-check some expressions of other modules
under load. On Linux, the suite runs in a `swift:6.4.1-noble` container (`nomac-pack`) on a copy of the
tree made with `COPYFILE_DISABLE=1 tar --no-xattrs` (otherwise macOS adds `._` files that break
the scheme fixtures), with the Mac's SwiftPM mirrors copied into the container's cache and
`git config --system http.version HTTP/1.1`, as the integrator's gate does.

# IPA

What `xcodebuild -exportArchive` of Xcode 27.0 (27A266a) writes, and how nomac (module
`NomacPackaging`, `nomac export` and `nomac zip`) reproduces it. Observed with
`signing_experiments.py` (self-written apps, exported with ad-hoc signing for the methods
`debugging`, `release-testing`, `enterprise` and `app-store-connect`, with and without
symbols, with install manifests and with on-demand resources; `compare-export` runs
`nomac export` on the same archives: all 69 identical), with xcodebuild on self-written
archives (`ArchiveExporterTests`, `AppStoreExportTests`) and with ditto on self-written folders
(`DittoArchiveTests`).

## The export pipeline

`Packaging.log` in the export folder lists the steps. For an ad-hoc signed archive:

1. `ditto -V <archive>/Products/Applications/App.app <tmp>/Root/Payload/App.app`. For
   `debugging`, `release-testing` and `enterprise` of an archive whose app has `AppClips/`, the
   copy comes from a copy of the archive without that folder (`AppClipRemoverSupport` in the
   log): the IPA, `CodeResources` and `DistributionSummary.plist` have no App Clip, and
   `ExportOptions.plist` gets `distributionBundleIdentifier`, the app's `CFBundleIdentifier`
   (`appclip-script` and `watch-appclip-script` experiments; `ArchiveExporterTests`, observed
   through `synthetic-export`, whose clip needs a `CFBundleName`: "exportArchive Reformatter
   could not discover target bundle name" otherwise). `app-store-connect` keeps and signs it.
2. The provisioning profile step is skipped for ad-hoc signing.
3. Each item is signed again, nested code first in bytewise path order, libraries (`.dylib`)
   among the bundles (`AppClips/Clip.app`, `Extensions/Intents.appex`, `Frameworks/Alpha.framework`,
   `Kit.framework`, `Pack.framework` (a Swift package's dynamic product), `Zed.framework`,
   `libswiftCompatibilitySpan.dylib`, `zeta.framework`, `PlugIns/Action.appex`, `Share.appex`,
   `Plugin.bundle` (a loadable bundle in the app's resources; bundles without code are
   resources), `Watch/Watch.app`, `XPCServices/Helper.xpc`, then the app; a watch app is one
   item, signed as `Mach-O universal (arm64 arm64_32)`), with the entitlements of its current signature written to a
   file (`{}` without any):
   `codesign -f -s - --entitlements <file> --preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints --generate-entitlement-der --strip-disallowed-xattrs -vvv <item>`.
4. `app-store-connect` only, before the signing of step 3:
   - The `Info.plist` of the app, its extensions, App Clips and watch apps written again, not
     those of frameworks or of what they hold ("is a framework or embedded in a framework"):
     the same values in the file's own format. A binary one (as Swift Build writes them) gets
     its dictionaries in Foundation's order (docs/formats/property-lists.md "Dictionary key
     order by tool"); an XML one is written as Core Foundation writes XML, keys sorted and tabs
     (an unsorted XML Info.plist indented with spaces, through xcodebuild). The file keeps its
     mode under any umask, while `Symbols` and its files follow it (0775 and 0664 under umask
     002, `umask` experiment).
   - One `Symbols/<UUID>.symbols` per slice of each DWARF file of the archive's dSYMs
     (docs/formats/symbols.md; binaries without a dSYM log "Upload Symbols Failed" and get
     none, and an archive without dSYMs gets an empty `Symbols` folder), recording the archive's path with symbolic links resolved (an archive given as
     `/tmp/x.xcarchive` is recorded as `/private/tmp/x.xcarchive`), copied into `Root` with
     `rsync -8aPhhE`. Without `uploadSymbols` (false) there is no `Symbols` folder, and
     `ExportOptions.plist` and every `DistributionSummary.plist` entry say `false` (`symbols`
     experiment).
   - The archive's `SwiftSupport` folder, when it has one, copied to `Root/SwiftSupport` with
     `ditto` (the toolchain's back-deployment libraries, Apple-signed, never signed again; the
     file keeps the toolchain file's time; `span` experiments).
5. `ditto -V -c -k --norsrc <tmp>/Root <tmp>/Packages/App.ipa`.
6. The export folder gets `App.ipa`, `DistributionSummary.plist`, `ExportOptions.plist` (the
   options with Xcode's defaults filled in) and `Packaging.log`.

Without a team in the archive the export stops with status 70 ("No Team Found in Archive");
any `teamID` in the options lets an ad-hoc export continue. An item whose signature has
entitlements stops it too (`"App.app" requires a provisioning profile.`, status 70); both
messages and their notes are compared by `compare-export` (`refusals` experiment). An empty
entitlements dictionary does not (`entitlements-empty`, every method; expo-default's app). The method
names `development`, `ad-hoc` and `app-store` give the same export as `debugging`, `release-testing`
and `app-store-connect`, whose name `ExportOptions.plist` holds; xcodebuild logs `Command line name
"development" is deprecated. Use "debugging" instead.` and nomac warns the same (observed with an ad
hoc archive, 2026-11-07). An
archive whose app lacks `CFBundleSupportedPlatforms`, `DTPlatformName`, `MinimumOSVersion` and
`UIDeviceFamily` is taken for a macOS one (methods `developer-id`, `mac-application`).
`validation` only accepts `destination` `upload`.

`nomac export` does the same for `debugging`, `release-testing`, `enterprise` and
`app-store-connect` with `signingCertificate` `-`; it refuses `validation` and the `upload`
destination, which send the app to App Store Connect (`nomac upload` sends an IPA,
docs/formats/app-store-connect-upload.md). The IPA is named after the app's
`CFBundleName`, else its file name (`App.app` named `Named` gives `Named.ipa`, whatever the
scheme; `ArchiveExporterTests`).

## On-demand resources

The archive holds the asset packs in `Products/OnDemandResources/<bundle id>.<tag>-<hash>.assetpack`
and the app the build's `OnDemandResources.plist` and `AssetPackManifestTemplate.plist` (`odr`
and `odr-three` experiments, two and three tagged resources). `debugging`, `release-testing` and
`enterprise` exports embed the packs, also with `embedOnDemandResourcesAssetPacksInBundle` true:
- the packs are copied into `App.app/OnDemandResources/` before the app is signed (its
  `CodeResources` seals them; they get no signature of their own);
- `App.app/AssetPackManifest.plist` replaces the template: the same objects as Foundation
  writes again what it read, each resource's `URL` now `OnDemandResources/<pack>` and its
  `isStreamable` the integer 0, the other values (`bundleKey`, `primaryContentHash`,
  `uncompressedSize`) the template's; every dictionary in Foundation's order; what the template
  shared stays shared and what it did not stays apart (Swift Build writes the `isStreamable`
  key once per resource, a self-written template once, `AppStoreExportTests`), the new URLs
  are objects of their own and integers are shared by value;
- `ExportOptions.plist` gains `embedOnDemandResourcesAssetPacksInBundle`, the string `true`
  (also when given as a boolean).
With a `manifest`, the install manifest is the same as without packs.

`app-store-connect` puts the packs in `Payload/OnDemandResources/` instead: each pack's
Info.plist is written again like the app's, with the app's `CFBundleShortVersionString` and
`CFBundleVersion` added; the app loses the template and gets no manifest; after the app, each
pack is signed in path order with `-f -s - --preserve-metadata=entitlements,identifier,flags,…
--generate-entitlement-der --strip-disallowed-xattrs -vvv`, a detached signature
(docs/formats/code-signature.md), and is not listed in `DistributionSummary.plist`.

With `onDemandResourcesAssetPacksBaseURL` (`release-testing-hosted`), the packs are signed the
same way beside the app, the app's `AssetPackManifest.plist` names each at `<base URL>/<pack>`
with `isStreamable` 1, and then each pack leaves the IPA as a zip in an `OnDemandResources`
folder beside it, with a copy of that manifest; `ExportOptions.plist` gets
`embedOnDemandResourcesAssetPacksInBundle` `false`. The zip (`AssetPackZip`): stored entries,
sizes and CRC in the local header, version needed 20 and made by 0x031e, the UTF-8 flag on
every name but the metadata's; `META-INF/` and `META-INF/com.apple.ZipMetadata.plist` first,
dated 1980-01-01, then the pack's contents in ditto's order; external attributes
`mode << 16 | 0x4000`; a local "UX" field on every entry (access and modification times, user
and group, the user's id twice for `META-INF`), a central one (the two times) only for a file
whose access time is not its modification time. The metadata is a binary property list of
`StandardDirectoryPerms` 0o40755, `Version` 2, `TotalUncompressedBytes` (the files' sizes),
`RecordCount` (the entries outside `META-INF`) and `StandardFilePerms` (0o100644 as a signed
16-bit number, -32348), in that order. The packs' times, owners and those central fields depend
on the machine and are set aside in comparisons, as for the IPA (`compare-export`,
`AppStoreExportTests`).

Further shapes (signing experiments `odr-shapes`, the `odr` archive exported by Xcode 27.0):

- A base URL ending in `/` gets no second one between it and the pack's name; `ExportOptions.plist`
  keeps it as given.
- With a base URL and `embedOnDemandResourcesAssetPacksInBundle` true, embedding wins: the packs go
  into the app (`OnDemandResources/<pack>`, as without a base URL) and `ExportOptions.plist`
  keeps both options, the embedding as `"true"`.
- An app-store-connect export ignores a `manifest`: no `manifest.plist`, and the key is not in
  `ExportOptions.plist`.
- In a hosted pack's zip, an entry whose mode is neither 0644 (files) nor 0755 (folders) — a
  file of another mode, a symbolic link (0120755, its target as data, counted in
  `TotalUncompressedBytes`) — has an "SZ" extra field (0x5a53, two bytes: the 16-bit mode)
  before "UX" in its local header; the metadata's standard modes stay the same.
- An asset pack's XML Info.plist stays XML in an app-store-connect export, with the app's
  version strings added, written as Core Foundation writes XML.

## App thinning

With `thinning` `<thin-for-all-variants>`, debugging, release-testing and enterprise exports write
`Apps/`, `app-thinning.plist` and `App Thinning Size Report.txt` instead of the IPA; with a product
type (`iPhone12,3`), that device's variant alone (app-store-connect ignores the option).
`distribution_experiments.py` `thinning` exports the adhoc app; a copy with a self-written asset
catalog and one value of each property list type in its Info.plist (also thinned for one iPhone
and one iPad); that copy declaring iOS 12.0 or 18.5, with catalogs in its extension and framework
too, or with a 2.3 or 3 MB resource; and signing_experiments' watch, App Clip and on-demand
resources apps. `nomac export` writes the same (`--developer-dir`, or the `nomac sdk` install,
which keeps `device_traits.db`): `compare-thinning`, variants matched by their descriptors, finds
all ten cases identical but the two nomac refuses (the iOS 12.0 app, the watch app).

- `Apps/App.ipa`, the universal variant, is the IPA of the same export without thinning, byte
  for byte (entry times aside).
- The device descriptors are the rows of the platform's `usr/standalone/device_traits.db` (in the
  user's Xcode, `Platforms/iPhoneOS.platform`) whose deployment target is the app's
  `MinimumOSVersion` or later: `DeploymentVariant` (deployment target, board), the board's
  `Devices.ProductType` as `device` and the deployment target as `os-version`; 291 for iOS 18.0
  in Xcode 27.0 (18.0, 26.0, 27.0), Mac and Vision Pro products included. A minimum the table does
  not list counts as the last version before it: an app declaring 18.5 gets 18.0's descriptors
  and catalogs thinned for 18.0, the same variants as an 18.0 app.
- They are grouped by the renditions every `Assets.car` of the app keeps for their trait set (the
  app's and those at the top of the bundles of its code: extensions, frameworks; docs/formats/
  asset-catalog.md "Thinning"): one variant for an app without catalogs; with the thinning
  experiment's catalog, pad @2x, phone @3x and phone @2x (80, 35 and 4 products, 291 descriptors
  together). Each group's catalogs are thinned for one of its trait sets, with the variant's
  minimum as the deployment target. Which one is not known: `Packaging.log` shows the export
  comparing the group's trait sets with `assetutil -L` and then "coalescing" them to one; in
  every iOS group observed it is the trait set of the first descriptor by product type in byte
  order, then OS version (`MacFamily20,1` at 18.0 for the iPad group), which nomac uses, but in a
  watch group it is not (below). An app declaring iOS 12.0 splits further by OS: 12.x
  descriptors form groups of their own, thinned for 12.0 (`deployment- 3`), the later ones for
  13.0 (`deployment- 5`) up to 27.0; nomac refuses minimums below 13.0.
- Each variant is `Apps/<IPA name>-<UUID>.ipa`: the universal IPA with the catalogs thinned, the
  app's Info.plist written again, and each bundle whose catalog changed, then the app, signed
  again (other bundles and their Info.plists unchanged). The Info.plist becomes XML: each
  dictionary's keys in the order of a Foundation dictionary created with them in the binary
  file's order (Swift Build's files list them sorted; one `plutil` rewrote lists them otherwise,
  `catalog-185`), `DTAppStoreToolsBuild` (Xcode's build, `27A266a`) and `UISupportedDevices` (the
  group's product types in byte order) after the top one's, indented by two spaces (`<dict>` under
  `<plist>` too), `<dict/>` and `<array/>` when empty, `<true/>`, `<false/>`, `<real>2.5</real>`,
  `<date>2026-11-03T12:00:00Z</date>`, data as base64 on a line of its own between `<data>` and
  `</data>` at column 0, `&`, `<` and `>` escaped and UTF-8 kept (`AppThinningTests` checks the
  bytes of one variant's file). nomac refuses an XML Info.plist, not observed.
- Thinning for one device writes that device's group's variant (the one the all-variants export
  makes, thinned for the group's first descriptor) as `<IPA name>-<UUID>.ipa` beside the plists,
  without `Apps/` or the universal IPA, keyed by its file name alone in `app-thinning.plist`.
- An App Clip is left out of these exports before thinning (above), so its app thins as one
  without. On-demand resources are embedded in the app, and each variant keeps them.
- `app-thinning.plist` (XML as Core Foundation writes it): `variants`, keyed `Apps/<file>`, each
  with `limitUncompressedInitialPrefetchedODR` (2147483648), `onDemandResourcesAssetPacks` (each
  embedded pack by its folder name: `identifier`, its Info.plist's `CFBundleIdentifier`,
  `limitUncompressed` 536870912, `sizeUncompressed`, its files' sizes, `tags`, its Info.plist's
  `Tags`; `{}` without packs), `sizeCompressedAppAndODR` (the IPA's size), `sizeUncompressedAppAndODR`
  (its entries' sizes), `sizeUncompressedODR` (the packs'), `sizeUncompressedApp` (the rest),
  `sizeUncompressedInitialPrefetchedODR` (0), `…ExceedsLimit` (false),
  `tagsUncompressedInitialPrefetchedODR` (`[]`), and without packs also `sizeCompressedApp` (the
  IPA's size) and `sizeCompressedODR` (0); but for the universal one, `variantDescriptors`
  (`device`, `os-version`).
- The size report: an empty line, `App Thinning Size Report for All Variants of <IPA name>`, an
  empty line, then per variant in file name order `Variant: <file>`, `Supported variant
  descriptors: [device: …, os-version: …], …, and [device: …, os-version: …]` (or `Universal`),
  `App + On Demand Resources size: <compressed> compressed, <uncompressed> uncompressed`, `App
  size: <compressed> compressed, <uncompressed> uncompressed` (with packs `App size: <app's>
  uncompressed`), `On Demand Resources size: Zero KB compressed, Zero KB uncompressed` (with packs
  `<packs'> uncompressed`), two empty lines between variants. Sizes: `Zero KB` for 0, bytes below
  1000 (`314 bytes`), kilobytes of 1000 bytes rounded (`23 KB`), megabytes with one decimal and no
  `.0` (`2.4 MB`, `3 MB`); larger sizes are not observed and nomac refuses them.
- `DistributionSummary.plist` and `ExportOptions.plist` are those of the same export without
  thinning, `thinning` kept.
- From one run to the next the variants' UUIDs, and so the report's variant order, and the order
  of their descriptors change (the same export twice); everything else is the same. nomac lists
  descriptors in the order above and derives each UUID from the variant's descriptors, so the
  same export names its variants the same.
- A watch app (`watch`, `watch-build`, `watch-catalog`, `watch-9`: signing_experiments' watch
  app, for watchOS 11.0 with an arm64 slice for 26.0 and an arm64_32 one for 11.0, another
  `BuildMachineOSBuild`, a catalog of images and a watchOS app icon, `MinimumOSVersion` 9.0):
  - The iPhone variants keep an empty `Watch/` and have, instead of the watch app,
    `com.apple.WatchPlaceholder/Watch.app/Info.plist` (0644, the folders 0755): the watch app's
    Info.plist with `CFBundleExecutable` `Executable`, and `MIPlaceholderArchitectures` (each
    slice's `CPUType` and `CPUSubtype`, in the file's order: 16777228 and 0, 33554444 and 1)
    and `CF_MIPlaceholderConstructorVersion` (the exporting Mac's build, `26A434`, also when the
    watch app's `BuildMachineOSBuild` is another) inserted; binary, as Foundation writes a
    dictionary created with the file's keys in the file's order and the two inserted after,
    `CPUType` before `CPUSubtype` (`AppThinningTests` checks the bytes).
  - The watch app gets variants of its own, `Apps/<IPA name>-<UUID>.ipa` with `Payload/Watch.app`
    alone: the watchOS descriptors (`Platforms/WatchOS.platform/usr/standalone/device_traits.db`)
    from the watch app's minimum on, grouped by the slice each watch runs (its
    `TargetArchitecture`; arm64e and arm64e.x1 watches at 27.0 run the arm64 slice: 41
    descriptors, the arm64_32 ones at 11.0 and 26.0: 43) and what the watch catalog keeps. The
    executable is that slice of the archive's executable, as it was before the export signed
    the universal file again (the space after its new signature is zeros), then signed again;
    the watch Info.plist is written as the iPhone variants' (XML, the two keys, the group's watch
    product types), with `MinimumOSVersion` the group's earliest descriptor OS when that is later
    (26.0 for the arm64 variant, 11.0 kept for the arm64_32 one). The slices' own minimums play
    no part: declaring 9.0 gives the arm64_32 group the watches at 9.0 to 10.4 too (140
    descriptors, still one variant) and keeps 9.0 below its slice's 11.0. The catalog is
    thinned for that minimum
    (`deployment- 12` and `- 11` in watchOS's numbering). nomac writes all of it identically,
    but for the trait set the watch catalog is thinned for: Xcode's are subtype 446 (Watch7,8,
    7,10, 7,17, 7,19) for the arm64 group and Watch6,10's or 6,12's row for the arm64_32 group,
    nomac's the first descriptor's (Watch7,1, Watch6,1), so the thinning arguments in the
    catalog and the signature over it differ (B-465).
  - `DistributionSummary.plist` changes from one run to the next: the summary of the export
    without thinning, the same without the watch app, or one entry for the watch arm64 variant's
    app alone (all three in six runs); nomac writes the first.
  - An Assets.car in the watch app is sealed with SHA-1 and SHA-256 hashes, as codesign seals a
    watchOS 11.0 bundle (docs/formats/code-signature.md).

nomac refuses (B-465) apps declaring iOS below 13.0, watch apps declaring watchOS below 9.0 or
with code of their own bundles or slices other than arm64 and arm64_32, thinning for one device
of an app with a watch app, packs hosted beside the IPA, an install manifest, catalogs elsewhere
than at the top of the app and of its code's bundles, iOS code with any slice but one arm64, an
XML Info.plist, catalogs whose renditions depend on more than idiom and scale, and variants of a
gigabyte or more.

## The install manifest

With a `manifest` export option, `debugging`, `release-testing` and `enterprise` exports also
write `manifest.plist` (`manifest` experiment, the same for the three methods; with an app
whose bundle name, display name, file name and scheme differ, `ArchiveExporterTests`, observed
through `synthetic-export`), XML as Core Foundation writes it: `items`, one item with `assets`
(`{kind: software-package, url: <appURL>}`, `{kind: display-image, url: <displayImageURL>}`,
`{kind: full-size-image, url: <fullSizeImageURL>}`, in that order) and `metadata`
(`bundle-identifier`, `bundle-version` the app's `CFBundleShortVersionString`, `kind`
`software`, `platform-identifier` `com.apple.platform.iphoneos`, `title` the app's file name
without `.app`). `ExportOptions.plist` keeps the option as given. A manifest without the two
image URLs makes xcodebuild refuse the options ("Couldn't load -exportOptionsPlist The data
couldn’t be read because it is missing.", status 70); nomac refuses it the same way, and a
manifest with `app-store-connect` (B-312).

## `ExportOptions.plist` and `DistributionSummary.plist`

Both in CoreFoundation's XML format (docs/formats/code-signature.md). `ExportOptions.plist` is
the options the method uses, with Xcode's defaults filled in (`distribution_experiments.py`
`option-grid`: each documented option alone, for each method; `export-options`): `method`,
`destination` (`export`), `signingStyle`, `signingCertificate`, `teamID`, `provisioningProfiles`
and `stripSwiftSymbols`, written true even when given false (the binaries are not stripped
either way: an archive built with `STRIP_INSTALLED_PRODUCT=NO` exports its symbols unchanged);
for `app-store-connect` also `generateAppStoreInformation` (false), `manageAppVersionAndBuildNumber`
(true), `testFlightInternalTestingOnly` (false) and `uploadSymbols` (true); for the other methods
`thinning` (`<none>`) and `manifest`. Other options are left out, unknown ones too:
`distributionBundleIdentifier`, `embedOnDemandResourcesAssetPacksInBundle`,
`onDemandResourcesAssetPacksBaseURL`, `iCloudContainerEnvironment` and
`installerSigningCertificate` for every method (the ODR options and `distributionBundleIdentifier`
are written when the archive has packs or App Clips, below and above), the App Store ones and
`thinning` where they do not apply. `testFlightInternalTestingOnly` true adds
`TFInternalTestingOnly` true to the app's rewritten Info.plist (not its extensions'). A `thinning`
other than `<none>` makes `debugging`, `release-testing` and `enterprise` exports write a variant
of the app per device (`Apps`, `app-thinning.plist`, `App Thinning Size Report.txt`), which nomac
refuses (B-465).

`DistributionSummary.plist` maps the IPA's name to one entry for the app: `architectures` (of
its executable), `buildNumber` (`CFBundleVersion`), `certificate` (`SHA1` and `dateExpires`
empty, `type` `Sign to Run Locally`), `embeddedBinaries` (the same entry for each item the
bundle itself holds, in signing order, so a watch app's entry lists its widget and an extension's
its framework, not the app's: extension experiments `watch-widget`, `watch-framework`,
`extension-framework`; no key for a bundle that embeds nothing: signing-experiments `alone` for every method, tofu, flappy-fly-bird and uncloudnotes;
an app whose only nested code is Swift's runtime libraries is not observed), `name` (the
bundle's file name),
`team` (`id` the team, `name` empty) and `versionNumber` (`CFBundleShortVersionString`); a
watch app is an entry like the others, with both `architectures` (`arm64`, `arm64_32`). A
library has `architectures` (in slice order), `certificate`, `name` and `team`; Swift's runtime
libraries (identifier `com.apple.dt.runtime.…`) are left out, other identifiers (also
`com.apple.dt.…`, `com.apple.…`) are listed (`ArchiveExporterTests`, observed through
`synthetic-export`).
`app-store-connect` adds `symbols` to each, libraries included: `uploadSymbols`' value, also
for bundles without a dSYM.

## Signing with an identity and a profile

Observed privately (B-302): a self-written app with a framework, built under the bundle
identifier of an installed development profile of the owner's, archived with manual signing
(`CODE_SIGN_STYLE=Manual`, the identity by its SHA-1, the profile by
`PROVISIONING_PROFILE_SPECIFIER` on the app target) and exported for `debugging` with
`signingStyle` `manual`, `signingCertificate` the identity's SHA-1 and `provisioningProfiles`
`{<bundle id>: <profile UUID>}`, xcodebuild offline. Below, `<team>`, `<bundle id>` and the
others stand for the values. The owner has since ruled out using their company apps: this
observation is not repeated, its outputs are deleted, and further ones wait on an identity and
profile the owner provides for nomac (B-302).

- The archive's app holds `embedded.mobileprovision`, the installed profile byte for byte
  (mode 0644). Swift Build signs it with `--force --sign <SHA-1> --entitlements
  <App.app.xcent> --generate-entitlement-der`, the framework without `--entitlements`; the
  app's entitlements are `application-identifier` (`<team>.<bundle id>`),
  `com.apple.developer.team-identifier` and `get-task-allow` (true), not the profile's other
  entitlements (keychain and app groups, push, …) when the app asks for none.
- The export's `IDEDistributionEmbedProfileStep` skips the framework; the IPA's
  `embedded.mobileprovision` is the profile named in the options (here the same). Each item is
  signed with the ad-hoc export's arguments and `-s <SHA-1>`, with the entitlements written
  for it: `{}` for the framework, the three above for the app.
- `ExportOptions.plist`: the given options and the method's defaults, as for ad-hoc exports.
- `DistributionSummary.plist`: every entry's `certificate` is `SHA1` (the identity's, upper
  case), `dateExpires` (the certificate's end, `M/d/yy`) and `type` (`Apple Development`);
  `team` keeps an empty `name`. The app's entry adds `entitlements` (its entitlements) and
  `profile` (`UUID`, `dateExpires` the profile's `ExpirationDate` as `M/d/yy`, `name` its
  `Name`); the framework's has neither. Both dates fall on the same day in UTC and in the
  Mac's time zone (UTC+1), so which one Xcode uses is not known; nomac writes UTC's.

`nomac build` and `nomac archive` do the build's side (`ManualSigning`): with `--keychain
<PEM>` and `--provisioning-profiles <folder>` (default: Xcode's folders), under
`CODE_SIGN_STYLE=Manual`, Swift Build's provisioning question gets the identity
`CODE_SIGN_IDENTITY` names (its SHA-1 and common name), the profile `PROVISIONING_PROFILE_SPECIFIER`
names for a product that takes one, and the three entitlements above; a framework gets the
identity alone. The PEM file is the answer's keychain, so each CodeSign command carries
`--keychain <PEM>` where Xcode's has none; on the Mac `CODESIGN` is then a link to nomac,
whose codesign reads it. Swift Build also exports the answer's keychain to script phases as
`CODE_SIGN_KEYCHAIN` (and the identity's SHA-1 as `EXPANDED_CODE_SIGN_IDENTITY`), so scripts
that run `codesign --sign` themselves, as CocoaPods' frameworks script does, sign with the same
identity: `nomac codesign` without `--keychain` reads `CODE_SIGN_KEYCHAIN`. Checked on the signing experiments' app with a self-made identity and
profile: the commands, the `.xcent`, the signed entitlements and the embedded profile (byte
for byte, mode 0644) are as observed. A UI test target's `AppUITests-Runner.app` and its
`.xctest` are signed with one `.xcent` holding the three, for the runner's identifier
(`<bundle id>.xctrunner`), and `keychain-access-groups` naming that identifier, which its product
type adds (`xctest_experiments.py` `build-for-testing`; nomac's `.xcent` for the same project and
profile holds the same values). Refused, with the reason: automatic signing (it asks
Apple's services), profiles without `get-task-allow`, and a product type's other entitlements
under a profile that allows them (not observed, B-302). Xcode's own refusals, observed with the export's
profiles in a build with manual signing (`distribution_experiments.py` `apple-profile`), each a
target's error with Swift Build's ` (in target '<target>' from project '<project>')`: a profile
not signed by Apple is not installed (`No profile for team '<DEVELOPMENT_TEAM>' matching
'<specifier>' found: Xcode couldn't find any provisioning profiles matching
'<team>/<specifier>'. Install the profile (by dragging and dropping it onto Xcode's dock item)
or select a different one in the Signing & Capabilities tab of the target editor.`); the app ID
and certificate errors are the export's, both when both hold; and a target that takes no profile
(a framework) given `PROVISIONING_PROFILE_SPECIFIER` fails with `<target> does not support
provisioning profiles. <target> does not support provisioning profiles, but provisioning profile
<specifier> has been manually specified. Set the provisioning profile value to "Automatic" in the
build settings editor.` An entitlements file's entitlements join the three when the
profile allows them, `$(AppIdentifierPrefix)` and `$(TeamIdentifierPrefix)` expanded to the
team's prefix and `$(PRODUCT_BUNDLE_IDENTIFIER)` to the bundle's identifier (a keychain group:
`<team>.<bundle id>`); an empty file adds nothing; an entitlement the profile lacks fails the
target with `Provisioning profile "<name>" doesn't include the <key> entitlement.`. A product
type's entitlement the profile lacks (an App Clip's `com.apple.developer.on-demand-install-capable`
under a wildcard development profile) fails it with `Entitlement <key> not found and could not
be included in profile. This likely is not a valid entitlement and should be removed from your
entitlements file.`. Xcode names a capability for some (`App Groups`, `App Clip`: `… doesn't
include the <capability> capability.`) and lists the capabilities first, then the product type's
entitlements, then the file's (observed privately for B-302 with the nomac development identity and profile in a
temporary keychain: the `.xcent`s and the error lines identical to Xcode's).

An ad hoc archive exported for `debugging` with the identity and a profile (observed the same
way): every bundle but frameworks gets the profile (`embedded.mobileprovision`, 0644) and is
signed with the development entitlements the profile gives (`application-identifier` of the
profile's team and the bundle's identifier, the team identifier, the profile's
`get-task-allow`); frameworks get the identity alone. Given Xcode's signing times, nomac's IPA
has every file identical to Xcode's and the same entries, `DistributionSummary.plist` and
`ExportOptions.plist` identical.

`nomac export` does this for `debugging` with `signingStyle` `manual` and an Apple Development
identity named by `signingCertificate` (its SHA-1 or name, from the PEM file `--keychain`),
the profiles of `provisioningProfiles` (by UUID or name, from `--provisioning-profiles` or
Xcode's folders under the home folder). Each bundle but frameworks needs one that includes the
identity's certificate and is the profile the archive embeds, or the archive embeds none (an ad
hoc archive, above); another profile than the archive's, other methods and identities are
refused (B-302). Checked privately against the export above, with nomac given
each item's signing time and Xcode's RSA values: every signed attribute set nomac built was
Xcode's, and the IPA (entry times aside), `DistributionSummary.plist` and
`ExportOptions.plist` are identical. `ProfileExportTests` encodes the rules with a self-made
identity and profile.

Which installed profiles xcodebuild uses (`distribution_experiments.py`, offline; nomac's
export gives the same refusals, `distribution_experiments.py compare`: 11 of 11): only a profile
whose CMS signature verifies and chains to Apple Root CA. The nomac development profile as Apple
issued it is found; xcodebuild ignores, as if not installed, the same bytes of content signed by
a self-signed certificate, signed (with SHA-1, as Apple signs) by a self-made chain bearing the
names of Apple's ("Apple iPhone OS Provisioning Profile Signing", "Apple iPhone Certification
Authority", "Apple Root CA"), and the issued file with one character of its content changed.
Apple's chain is in the profile (RSA, SHA-1 digests); nomac checks the signature and each link
up to a root whose SHA-256 is Apple Root CA's (`ProfileSignature`); validity dates are not
checked, as no expired chain has been observed. For each bundle that takes a profile:

- none installed: `No "<kind>" profiles for team '<teamID>' matching '<specifier>' are
  installed.` with the note `Install a profile (by dragging and dropping it onto Xcode's dock
  item) or specify a different profile in your Export Options property list.`; the kind is the
  method's (`iOS App Store`, `iOS Ad Hoc` for release-testing, `iOS In House` for enterprise,
  `iOS App Development`), the specifier the UUID or name as given; for every method, before
  anything about the identity's kind;
- a profile whose app ID (`application-identifier` without the team) does not cover the bundle
  identifier: `Provisioning profile "<name>" has app ID "<app ID>", which does not match the
  bundle ID "<bundle ID>".`; one that does not list the identity's certificate: `Provisioning
  profile "<name>" doesn't include signing certificate "<common name>".`; both when both hold.

Every error of every bundle is printed, status 70, in an order that changes from one run to the
next (the same export run three times gave two orders); nomac prints them in signing order.
Distribution signing cannot be observed with throwaway identities; it needs an Apple
Distribution certificate and an App Store profile from Apple (B-460).

## The archive format (ditto)

Names keep their bytes: a precomposed name stays precomposed in the IPA (signing experiments
`names`); nomac creates the copied tree with the names' own bytes, since Foundation on macOS
would decompose them.

PKWARE's APPNOTE.TXT records, with these choices (all observed, `DittoArchive`):

- Entries are `Root`'s contents, depth first, each folder before its contents; the names in a
  folder in the order a case-insensitive APFS volume lists them: increasing CRC-32C (initial
  value 0xffffffff, not inverted) of the name in NFD, case-folded, as UTF-32LE, low 22 bits
  (Apple File System Reference, `j_drec_hashed_key_t`). The same order is in every folder of
  the IPAs observed and in ditto's own copy log.
- Folders (`name/`) and empty files: stored, version needed 1.0, no flags, no data.
- Other files: raw deflate as zlib 1.2.12 at level 6 (window 15, memory level 8, default
  strategy) writes it, also when the result is larger (200,000 random bytes become 200,065);
  version needed 2.0, flag 0x8; the local header has CRC and sizes zero, a data descriptor
  `PK\7\8` with CRC and sizes follows the data.
- Symbolic links: stored, version 1.0, the target as data, CRC and sizes in the local header,
  no extra field, mode `0120755`.
- Version made by 0x0315 (Unix, 2.1); external attributes `st_mode << 16 | 0x4000`; internal
  attributes 0; names as their bytes on disk, without the UTF-8 flag; no comments.
- Extra field 0x5855 (Info-ZIP "UX"): access time and modification time (32-bit Unix times),
  then, in the local header only, the owner's user and group ids (16-bit).
- DOS time and date: the modification time in the local time zone, odd seconds rounded up
  (23:59:59 becomes 00:00:00 of the next day).
- End of central directory without Zip64 or comment.

## Not reproducible byte for byte

The times in each entry (the export's clock for the files codesign rewrites, the files' access
times, the time zone), the owner's user and group ids, and the mode of `Payload/`, which the
export creates under the process's umask (Xcode's is 040775 under umask 002, `umask`
experiment; nomac does the same): they depend on the machine and the moment of the export. An
archive nomac writes on the same files with the same times, ids and time zone is byte-identical
to ditto's (`DittoArchiveTests`); an IPA of `nomac export` is byte-identical to Xcode's once
these fields are cleared on both sides (`compare-export`, `ArchiveExporterTests`), on macOS and
on Linux.

## Not covered yet

Zip64 (B-306), exports with other profiles than the archive's, other methods with an identity,
and distribution signing (B-302), `Packaging.log` (its
lines carry the times and temporary paths of the export; nomac does not write it).

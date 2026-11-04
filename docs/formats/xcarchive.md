# Archives (`.xcarchive`)

What `xcodebuild archive` of Xcode 27.0 (27A266a) makes once Swift Build's archive build is
done, and how `nomac xcarchive` (module `NomacPackaging`, `XCArchive`) makes the same from the
build's intermediates. The build itself (an install build with the archive's paths) is Swift
Build's and not logged as part of this step. Observed with `signing_experiments.py`, whose
experiments keep the build's `BuildProductsPath` beside each archive: `compare-archive`
assembles `archive-names`, `archive-nodsym`, `span-nested`, `watch-appclip-script` and the
`archive-products-*` experiments (one project with an app, a second app, a framework, a static
library, a command-line tool and a loadable bundle, archived by the schemes `App`, `Apps`, `Kit`,
`Store` and `Tool`, also with `SKIP_INSTALL=NO` and with nothing to install, and by `AppTool`
and `AppStore`, the app with the tool, also installed in `/opt/nomac`, or with the library),
`archive-package` (a local Swift package's dynamic and static products), `archive-extensionkit`
(an App Intents extension), `archive-xpc` (an XPC service), `manifest`, `odr` and `odr-three`
(on-demand resources) again and finds all nineteen identical to xcodebuild's, file times
included.

## Inputs

The build works in `<derived data>/Build/Intermediates.noindex/ArchiveIntermediates/<scheme>`:
`InstallationBuildProductsLocation` (the installed products: `Applications/App.app`, the app
signed and stripped), `BuildProductsPath/<configuration>-<platform>` (each target's products and
dSYMs: `Release-iphoneos`, `Release-watchos` for a watch app) and `BuildProductsPath/SwiftSupport`
(the Swift back-deployment libraries the app embeds, `span` experiments).

## Layout

- `Products`: `InstallationBuildProductsLocation`, moved (it is gone from the intermediates
  afterwards; its files keep their times), whatever it holds: `Applications/App.app`,
  `Library/Frameworks/Kit.framework` (a framework scheme with `SKIP_INSTALL=NO`),
  `usr/local/lib/libStore.a`, `usr/local/bin/Tool`, the asset packs of on-demand resources in
  `OnDemandResources/<bundle id>.<tag>-<hash>.assetpack`; empty when the build installed
  nothing.
- `dSYMs`: a copy of every entry named `*.dSYM` at any depth under every
  `BuildProductsPath/<configuration>-<platform>` folder, content, modes and times kept (the
  `.symbols` files of an app-store-connect export record the DWARF file's time). The search goes depth first in directory order (APFS order), into
  bundles and into the dSYMs it collects, and does not follow links; a link named `*.dSYM` is
  copied as the link, an empty folder or a file so named as it is, whether or not a product
  holds its binary; nothing outside the products folder is collected. A name already taken gets
  ` 1`, ` 2` before `.dSYM`, in the search's order (`archive-nested-dsyms`). CocoaPods' `[CP] Copy XCFrameworks` puts a
  prebuilt pod's dSYMs in `XCFrameworkIntermediates/<pod>/` or `<pod>/dSYMs/`, so they are
  archived (expo-default's six). The products' own dSYMs are at the top of the folder: apps,
  app extensions, frameworks, watch apps (universal),
  App Clips, loadable bundles (`Plugin.bundle.dSYM`, the bundle in the app's resources), tools
  (`Tool.dSYM`), ExtensionKit extensions (`Intents.appex.dSYM`), XPC services
  (`Helper.xpc.dSYM`) and Swift package dynamic products (`Pack.framework.dSYM`, beside the
  app's own in the products folder); a static library or a static package product has none. The folder is there, empty, when the build
  made no dSYMs (`DEBUG_INFORMATION_FORMAT=dwarf`, `archive-nodsym`, or a static library's
  archive).
- `SwiftSupport`: a copy of `BuildProductsPath/SwiftSupport` with its times, when there is one.
- `Info.plist`, XML as Core Foundation writes it:
  - `ApplicationProperties`, only when the products are one app in `Applications`, alone or
    beside its `OnDemandResources`; a framework's, a library's or a tool's archive, one that
    installs nothing, one of two apps (the aggregate scheme `Apps`) and one of an app beside an
    installed framework, static library or tool (`usr/local/bin`, or `/opt/nomac` by
    `INSTALL_PATH`) are generic, without it: `ApplicationPath` (`Applications/<app>.app`), `Architectures`
    (the app executable's, in slice order), `CFBundleIdentifier`,
    `CFBundleShortVersionString` and `CFBundleVersion` (the app's Info.plist), and for ad-hoc
    signatures `SigningIdentity` and `Team` empty (also with `DEVELOPMENT_TEAM` set: the team
    comes from the signature); for an Apple Development signature the certificate's common name
    and the code directory's team (observed privately, the archive assembled again identical);
  - `ArchiveVersion` 2;
  - `CreationDate`, the time the archive was made, in whole seconds;
  - `Name` and `SchemeName`: the scheme's name, also when the app's product is named otherwise
    (`archive-names`: `Shop.app` archived by the scheme `App`) and whatever the archive's file
    name.

## Signatures

`Signatures` holds the signature records of the xcframeworks the build used
(docs/formats/code-signature.md "Signature records"), and exists only when there is one: an archive
without an xcframework has no such folder. xcodebuild fills it from the whole of
`BuildProductsPath`, whatever wrote there (`signature_record_experiments.py`, `collect`):

- it starts as a copy of `BuildProductsPath/Signatures` if the build made that folder, other files
  included (`collect-root`);
- then every entry named `*.signature` at any depth, `SwiftSupport` included, goes into the one flat
  folder: a file with its mode and time, a folder whole and searched too, a link as a link. Links
  are not followed;
- the entries stay in `BuildProductsPath`;
- a name already taken stops the archive with exit status 70, leaving no `Info.plist`: `xcodebuild:
  error: “same.signature” couldn’t be copied to “Signatures” because an item with the same name
  already exists.: The operation couldn’t be completed. File exists` (`collect-same`, and
  `collect-root` for a record in the build's own `Signatures`).

No record reaches a `debugging` export: neither the IPA nor the export folder has one. An
`app-store-connect` export is not observed, as it can call Apple's services once an account is in
Xcode.

## Not covered yet

Apps signed with certificates other than Apple Development ones: BACKLOG B-302.

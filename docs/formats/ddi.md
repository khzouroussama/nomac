# The Developer Disk Image

The image that gives a device its developer services (the CoreDevice app service that
`nomac launch` uses among them). Observed on Xcode 27.0 (27A266a) and an iPhone on iOS 27.0.1
(2026-11-02); the decision to personalize it with Apple's server is ADR 0403. nomac implements it
in `Sources/NomacDevice/Personalization.swift`, `DeveloperDiskImage.swift` and
`MobileImageMounter.swift`.

## Where it comes from

Xcode ships it in `Contents/Resources/Packages/XcodeSystemResources.pkg`, whose payload holds
`Library/Developer/CoreDevice/CandidateDDIs/iOS_DDI.dmg` (with the tvOS, watchOS and visionOS
ones), and installs it on a Mac to `/Library/Developer/DeveloperDiskImages/iOS_DDI`:
`version.plist` (`ProductBuildVersion` 27A266a) and `Restore/` with `BuildManifest.plist`,
`Restore.plist`, two disk images (`022-20190-411.dmg`, `022-20231-411.dmg`) and in `Firmware/`
their trust caches, the second one's `.cryptex_info` and `.root_hash`. The package is a xar
archive whose `Payload` is pbzx (xz chunks) around a cpio archive; `iOS_DDI.dmg` is a
zlib-compressed UDIF image (UDZO, one partition) of an HFS+ volume (named
`Xcode_iOS_DDI_Personalized`) whose files carry no HFS+ compression. The pbzx payload has both
xz chunks and stored ones.

`nomac sdk install` extracts it into the store's `<build>/DeveloperDiskImages/iOS_DDI` with
7-Zip 23.01 and xz 5.4.5 (`7z x -txar` for `Payload`, nomac's pbzx reader with `xz -dc` per xz
chunk, `7z x -tcpio` for `iOS_DDI.dmg`, `7z x` for the volume's files): on Ubuntu 24.04 the nine
files of `Restore/` and `version.plist` are byte for byte those Xcode installs on a Mac
(2026-11-02). 7-Zip guesses another format for the package unless told `-txar`.

## The build identity

`BuildManifest.plist` has 141 `BuildIdentities`: 140 with a `PersonalizedDMG` (the first disk
image) and a `LoadableTrustCache`, and one "Developer Disk Image Cryptex" identity with
`Cryptex1,*` components. The identity for a device is the one whose `ApBoardID` and `ApChipID`
(hexadecimal strings, `0x0E`, `0x8140`) are the device's `BoardId` and `ChipID`; its
components' `Info.Path` name the files, relative to `Restore/`, and their `Digest` (48 bytes,
SHA-384) is what the ticket signs. The trust cache's `Info.RestoreRequestRules` set `EPRO` and
`ESEC` from the production and security modes.

## mobile_image_mounter

Over lockdownd's `com.apple.mobile.mobile_image_mounter` (docs/formats/lockdown.md), each
request a dictionary with `Command`:

| Command | Request keys | Reply |
|---|---|---|
| `CopyDevices` | | `EntryList`: one dictionary per mounted image; the cryptex image Xcode 27.0 mounts is `DiskImageType` `Personalized` |
| `QueryPersonalizationIdentifiers` | `PersonalizedImageType` `DeveloperDiskImage` | `PersonalizationIdentifiers`: `BoardId`, `ChipID`, `UniqueChipID` (the ECID), `SecurityDomain`, `Ap,SikaFuse`, `CertificateProductionStatus`, `CertificateSecurityMode`, `EffectiveProductionStatusAp`, `EffectiveSecurityModeAp` |
| `QueryPersonalizationManifest` | `PersonalizedImageType`, `ImageType` `DeveloperDiskImage`, `ImageSignature` (the image's SHA-384) | `ImageSignature`: the ticket the device stores; without one an error, and the device closes the connection |
| `QueryNonce` | `PersonalizedImageType` `DeveloperDiskImage` | `PersonalizationNonce` (data) |
| `ReceiveBytes` | `ImageType` `Personalized`, `ImageSize`, `ImageSignature` (the ticket) | `Status` `ReceiveBytesAck`; then the image's bytes, answered `Status` `Complete` |
| `MountImage` | `ImageType` `Personalized`, `ImageSignature`, `ImageTrustCache` | `Status` `Complete` |

A refusal carries `Error` (and sometimes `DetailedError`).

## The TSS request

An XML property list POSTed to `https://gs.apple.com/TSS/controller?action=2` (plain HTTP
answers the same) with `Content-Type: text/xml; charset="utf-8"` and `User-Agent: InetURL/1.0`:
`@ApImg4Ticket` and `@BBTicket` true, `@HostPlatformInfo` `mac`, `@VersionInfo`
`libauthinstall-1033.0.2`, `@UUID`, `ApBoardID`, `ApChipID`, `ApECID` (integers), `ApNonce`,
`SepNonce` (20 zero bytes), `ApProductionMode`, `ApSecurityMode` true, `ApSecurityDomain` 1,
`UID_MODE` false, the device's `Ap,` identifiers, and each trusted component of the identity
without its `Info`, with `EPRO` and `ESEC`. The reply is text:
`STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=<plist>` whose `ApImg4Ticket` is the ticket, an IM4M
(DER, `IM4M`; 3053 bytes for the iPhone above); a refusal is `STATUS=<n>&MESSAGE=<text>` (94,
"This device isn't eligible for the requested build." for an empty request).

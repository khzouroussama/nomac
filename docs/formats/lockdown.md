# lockdownd and installation_proxy

lockdownd listens on the device's port 62078, reached through usbmuxd's `Connect`
(docs/formats/usbmux.md). It reports the device's values, opens sessions with a paired host
and starts the services an install uses. Sources: libimobiledevice (`lockdown.c`,
`property_list_service.c`, `installation_proxy.c`) and pymobiledevice3 (`lockdown.py`,
`service_connection.py`, `services/installation_proxy.py`). nomac implements it in
`Sources/NomacDevice/Lockdown.swift`, `PropertyListMessages.swift`,
`InstallationProxy.swift` and `PairRecord.swift`.

## Framing

Every message, both ways, is a big-endian 32-bit length and a property list of that many
bytes. nomac sends XML; it reads XML or binary (`bplist00`) replies.

## lockdownd's requests

Each request is a dictionary with `Label` (the client's name, `nomac`) and `Request`; the reply
repeats `Request`, and has `Error` (a name such as `InvalidHostID`, `PasswordProtected`,
`InvalidService`, `SessionInactive`) when the request fails.

| Request | Fields | Reply |
|---|---|---|
| `QueryType` | | `Type`: `com.apple.mobile.lockdown` |
| `GetValue` | `Domain`, `Key`, both optional | `Value`; before a session, only some values |
| `StartSession` | `HostID`, `SystemBUID` from the pair record | `SessionID`, `EnableSessionSSL` |
| `StartService` | `Service` (and `EscrowBag` from the pair record, which pymobiledevice3 sends only for backups: with it, iOS 27.0.1 started AFC on a port that refused the connection) | `Port`, `EnableServiceSSL` |

After a `StartSession` reply with `EnableSessionSSL` true, the rest of the connection is TLS:
the host's certificate and key from the pair record, the device's certificate not verified,
TLS 1.2 to 1.3 (ADR 0401). A started service accepts one connection on its port, through
usbmuxd's `Connect`, with TLS first when `EnableServiceSSL` is true.

## The pair record

usbmuxd keeps the host's side of each pairing; `ReadPairRecord` with `PairRecordID` (the
UDID) answers `PairRecordData`, a property list with `HostID`, `SystemBUID`, `HostCertificate`
and `HostPrivateKey` (PEM), `RootCertificate`, `DeviceCertificate`, `WiFiMACAddress` and
`EscrowBag`. nomac holds it in memory only.

Two values the device workflow reads in a session: `ProductVersion` (the CoreDevice tunnel
needs iOS 17.4) and, in the domain `com.apple.security.mac.amfi`, `DeveloperModeStatus` (true
when Developer Mode is on).

## mobile_image_mounter

`com.apple.mobile.mobile_image_mounter` uses the same framing. `CopyDevices` answers
`EntryList`, one dictionary per mounted image with `DiskImageType` (`Personalized` for the
Developer Disk Image since iOS 17) and `IsMounted`; pymobiledevice3 found `LookupImage` giving
an empty signature for a mounted personalized image on iOS 27.0, so nomac asks `CopyDevices`.
`QueryPersonalizationManifest` (`PersonalizedImageType` and `ImageType` `DeveloperDiskImage`,
`ImageSignature` the image's SHA-384) answers `ImageSignature`, the personalization manifest
(an IM4M) the device stores for that image, or an error after which the device closes the
connection (`nomac device images --image`).

## installation_proxy

`com.apple.mobile.installation_proxy` uses the same framing. Installing a package is two
services: AFC writes it under `PublicStaging` in the media folder (docs/formats/afc.md), then
installation_proxy installs it.

| Command | Fields |
|---|---|
| `Install` | `PackagePath` (relative to the media folder), `ClientOptions` |
| `Uninstall` | `ApplicationIdentifier` (the bundle identifier), `ClientOptions` |
| `Lookup` | `ClientOptions`: `BundleIDs` (an array), `ReturnAttributes` (`CFBundleIdentifier`, `Path`); the reply's `LookupResult` maps each installed bundle identifier to its attributes, `Path` the app's folder under `/private/var/containers/Bundle/Application` |

The service answers with progress messages, `Status` (a stage name) and `PercentComplete`,
until `Status` is `Complete`; a failure is `Error` with `ErrorDescription`.

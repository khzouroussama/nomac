# lockdownd and installation_proxy

lockdownd listens on the device's port 62078, reached through usbmuxd's `Connect`
(docs/formats/usbmux.md). It reports the device's values, opens sessions with a paired host
and starts the services an install uses. Sources: libimobiledevice (`lockdown.c`,
`property_list_service.c`, `installation_proxy.c`) and pymobiledevice3 (`lockdown.py`,
`service_connection.py`, `services/installation_proxy.py`). nomac implements it in
`Sources/NomacDevice/Lockdown.swift`, `Pairing.swift`, `PropertyListMessages.swift`,
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

## Pairing

`nomac device pair`, from libimobiledevice's `lockdown.c` and `userpref.c` and pymobiledevice3's
`lockdown.py` and `ca.py`; the requests of libimobiledevice 1.3.0's `idevicepair pair`, recorded
against a scripted device (`first_run_experiments.py` `pair-reference`), and nomac's are the same.
No iPhone has answered nomac's yet (B-407).

1. `GetValue` of `DevicePublicKey` before a session: an RSA key in PEM, which both sources read as
   `RSA PUBLIC KEY` or `PUBLIC KEY`. `ReadBUID` from usbmuxd, `GetValue` of `WiFiAddress`.
2. Three certificates, each X.509 v3 with empty subject and issuer, signed by the root's new RSA
   2048 key, valid ten years: a root (`basicConstraints` critical `CA:TRUE`), the host's for a new
   RSA 2048 key and the device's for its key (`basicConstraints` critical `CA:FALSE`, `keyUsage`
   critical `digitalSignature, keyEncipherment`; the device's also `subjectKeyIdentifier`, the
   SHA-1 of the key's bits). libimobiledevice writes serial number 0 and, not knowing the device's
   version at this point, SHA-1; pymobiledevice3 writes 1 and SHA-256; nomac follows pymobiledevice3,
   and starts the validity a minute early as it does.
3. `Pair` with `PairRecord` (`DeviceCertificate`, `HostCertificate`, `RootCertificate` as PEM in
   data, `HostID` a new upper-case UUID, `SystemBUID`), `ProtocolVersion` `2` and `PairingOptions`
   `{ExtendedPairingErrors: true}`. The answers: `Error` `PairingDialogResponsePending` (the
   dialog is up), `PasswordProtected` (locked), `UserDeniedPairing`, or success with `EscrowBag`.
   Asked again every second, as pymobiledevice3 does; each attempt a new connection.
4. `SavePairRecord` to usbmuxd with the request's fields plus `HostPrivateKey`, `RootPrivateKey`,
   `EscrowBag` and `WiFiMACAddress`, the nine keys libimobiledevice saves.

In a session's TLS pymobiledevice3 and nomac present the host's certificate and libimobiledevice the
root's. OpenSSL's verifier calls a certificate with an empty name "self-signed" unless it alone is
trusted (error 18), so a server built on it refuses the host's against the root; in TLS 1.3 the client
learns that on its first read, which is why a session makes one request before it counts as started.

## Developer Mode

`com.apple.amfi.lockdown`, with the same framing, takes `{action: <n>}` and answers `success`, or
`Error`. Action 0 shows Developer Mode in Settings, where it may be hidden until a developer tool
has connected (libimobiledevice's `idevicedevmodectl reveal`, pymobiledevice3's
`reveal_developer_mode_option_in_ui`); actions 1 and 2 turn it on and are refused with a passcode set
("Device has a passcode set"). `nomac device developer-mode` sends only action 0, and only when the
mode is off. Not yet run on an iPhone.

## Values

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

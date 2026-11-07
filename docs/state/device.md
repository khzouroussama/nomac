# Workstream: device and distribution

Install, launch and test on a device, then TestFlight. Branch `device/linux-first-run` from
`origin/main` (worktree `~/nomac-out/wt/linux`); BACKLOG B-400–B-459, ADRs 0400–0459. Goal: an IPA nomac built installs and launches on the owner's
iPhone, first through `xcrun devicectl` on the Mac (the demo route), then with
`nomac install` and `nomac run` from Linux (ADR 0400).

## Current step

The Linux route works on the owner's iPhone (iOS 27.0.1, USB, 2026-10-30): from a Linux
container, through a loopback-only forward of the Mac's usbmuxd and the Mac's pair record,
`nomac device status`, `nomac uninstall`, `nomac install` and `nomac launch` ran against the
device, with nomac's own lockdown, TLS, AFC, installation_proxy, CoreDevice tunnel, userspace
TCP, RemoteXPC and app service. Two apps were installed and launched that way and stayed up:
the demo app (signed in Linux by `nomac codesign` with the nomac development identity) and
rn-bare, built, archived, signed and exported by nomac in Linux by the React Native workstream.
Next: expo-default the same way, then the network route (B-404) and mounting the Developer Disk
Image (B-403).

## Inventory (2026-10-30, read-only)

- Device: one iPhone 16 Pro Max (iPhone17,2), iOS 27.0.1, Developer Mode enabled, paired with
  the Mac (`manualPairing`); not attached by USB at the time, no tunnel, so usbmuxd listed no
  device and the Developer Disk Image services were not available.
- Identities (`security find-identity -v -p codesigning`): three Apple Development
  identities. One belongs to the owner's own paid individual team (its profiles live 365 days);
  its certificate expires on 2026-11-04. The other two belong to a company team and are never
  used.
- Profiles: one development profile of the owner's team, for an explicit App ID of another
  app of the owner's (not a wildcard), with the iPhone among its three devices, Xcode-managed,
  expiring on 2026-11-04 with the certificate. No wildcard development profile. The other seven
  installed profiles are a company's and are never used.
- docs/state/packaging.md (B-302): certificate signing with an Apple Development identity and
  `nomac export` with development profiles already match Xcode's, checked privately; what is
  missing is an identity and profile the owner provides for nomac, never the company apps'.

## Owner decision (2026-10-30)

- Identity: a new Apple Development certificate for nomac, its RSA 2048 key made by openssl
  (nomac writes no certificate signing request yet) in `~/nomac-out/device/identity` with mode
  600, outside the keychain and the repository.
- Profile: an iOS App Development profile for the wildcard App ID of the owner's team, with the
  iPhone, downloaded to `~/nomac-out/device/profiles`.
- Installs: a self-written app, then rn-bare, then expo-default, signed with that identity,
  installed and launched by `devicectl`, then uninstalled.
- The Linux route may read the Mac's pair record (read-only) and reach usbmuxd through a
  loopback-only forward.

## Just finished

- `.xcresult`: `nomac test -resultBundlePath` writes a bundle `xcresulttool get test-results`, `get
  object --legacy` and `get content-availability` read, with failures and skips from XCTest's printed
  lines (docs/formats/xcresult.md; what it lacks, B-408). Tested with supplied results; no device run.
- A project set up for automatic signing, measured on Linux (2026-11-07, one small project with a
  team, with and without entitlements, nomac built in a container): `build` and `archive` sign ad hoc,
  `install` refuses with the next step; entitlements stop the build with Xcode's message, and export
  without `signingCertificate` stopped with no next step: both now say what to do. `nomac export` also
  refused `development`, `ad-hoc` and `app-store`, which Xcode takes as deprecated names: it takes them
  now. `nomac install` of an ad hoc IPA asked the device: it now says why first, as for a `.app`.
  docs/INSTALL-ON-IPHONE.md has a section on it. The Mac's unsigned result is left: low priority.
- `.xctestrun` of code coverage and test plans (the former B-433, B-434): `nomac build
  build-for-testing` no longer refuses such schemes, which include every scheme with
  `shouldAutocreateTestPlan`. Rules from `xctest_experiments.py` `xctestrun-coverage-*`,
  `-plan-*`, `-autocreated-plan*` (docs/formats/xctestrun.md); the options are those the corpus's
  plans use, another stops with its name (B-408). `nomac test` runs each configuration and a plan's
  selected and skipped tests, and warns about repetition, random order, parallel tests and timeouts.
  Not run on a device.
- The UI test runner signed (B-302): `nomac build ... build-for-testing --keychain ...` of
  `xctest_experiments.py`'s full project on the Mac, with Xcode's compilers: `AppUITests-Runner.app`
  and its `.xctest` signed as Xcode signs them (the same `.xcent`), `codesign -vv` valid on disk and
  satisfying the Designated Requirement, `nomac device check` installable, the `.xctestrun` the same
  as Xcode's. Not run on a device, and not built on Linux yet.
- A first run with no Mac (ADR 0404), as far as it goes without a phone: `nomac device pair`,
  `nomac device developer-mode`, `nomac signing request`, `identity` and `check`; messages for each
  state of usbmuxd and for a device the kernel does or does not see; docs/INSTALL-ON-IPHONE.md
  rewritten as the route from a Linux laptop, free and paid accounts said plainly. Checked by
  `.github/scripts/first_run_experiments.py`: libimobiledevice's usbmuxd and tools in a container
  and `fake_device.py` in place of an iPhone, with nomac and `idevicepair` sending the same requests
  and each using the other's pair record; `signing identity` on the owner's real certificate gives
  the same chain as the identity that installed on the iPhone. **No iPhone has been on a Linux
  machine's USB** (B-407).
- `nomac test` passed on the iPhone from Linux (2026-11-03): 2 unit tests of the self-written
  app, built and signed by nomac; XCTest's output barriers removed. `nomac install` stops a
  running copy of the app first. Next, without the phone: the `.xcresult` bundle, then signing
  the UI test runner (B-302).
- Tests on a device (ADR 0430): the xctest workstream's uncommitted `nomac test` and
  `build-for-testing` (`device/xctest`: DTX, keyed archives, testmanagerd's sessions, the
  `.xctestrun`) ported onto the device branch; its unit tests pass. Next: the first run on the
  iPhone with Xcode's products of `xctest_experiments.py`'s project, then nomac's own, from Linux.
- The console stopped after about 30 seconds without output (nomac-expo-2's RN demo): the
  device resets an idle tunnel connection after three unanswered keepalive probes, and nomac's
  userspace TCP did not acknowledge segments without data. It does now (traced and confirmed on
  the iPhone); a console that fails says whether the app still runs (`listprocesses`).
  `nomac stop` was confirmed on the iPhone (the RN demo's process gone; a second stop says it
  is not running); the crash demo's `--device` run: 6 of 6 app frames as `atos -i`.
- `nomac stop <bundle id>`, launch's counterpart: installation_proxy's `Lookup` gives the app's
  path, the app service's `listprocesses` its processes, `sendsignaltoprocess` the signal
  (docs/formats/remotexpc.md); confirmed on the iPhone.
- Debugging a crashing app from Linux alone (docs/formats/crash-report.md): `nomac atos` prints
  what Xcode's `atos -i` prints, byte for byte on 14,645 addresses of seven dSYMs and the
  synthetic one (`symbolicate_experiments.py`); `nomac device symbolicate` prints a `.ips`
  report with the app's frames symbolicated from the build's dSYM; `nomac device crashes`
  lists and copies the device's reports (crashreportmover, crashreportcopymobile over AFC);
  `nomac launch --console` and `nomac run --console` print the app's standard output and error
  (openstdiosocket). Both device routes were confirmed on the iPhone (2026-11-03), and a
  self-written app's crash went from the device to symbolicated lines with nomac alone.
- The unmount and mount test (2026-11-03, owner's approval): the iPhone refused to unmount
  Xcode's cryptex image ("Failed to unload launchd jobs"), and the Mac's CoreDevice remounts it
  on every connection, so nomac's own mount still awaits a device on a Linux host (B-407).
- B-403 (ADR 0403, the owner's approval of TSS requests): `nomac device personalize` got a
  ticket from Apple's TSS server for the owner's iPhone with the personalized disk image of
  Xcode's `iOS_DDI`; `nomac device mount` uploads and mounts it, and `nomac launch` and
  `nomac run` mount it when the device has none. The mount awaits a restarted iPhone (Xcode's
  cryptex image stays mounted until then). Xcode ships the image in
  `XcodeSystemResources.pkg`; `nomac sdk install` extracts it on Linux with 7-Zip and xz,
  byte for byte the files Xcode installs on a Mac (docs/formats/ddi.md).
- B-407 groundwork, no device: libimobiledevice's usbmuxd 1.1.1 in an Ubuntu container answers
  `device_experiments.py` as macOS's usbmuxd does (`ListDevices`, `ReadBUID`, `ReadPairRecord` of
  a planted record as XML, an unknown request), but a missing record is `Result` 2 there and 22
  on macOS; `nomac device list` read it at `/var/run/usbmuxd`. nomac now says "usbmuxd holds no
  pair record" for both instead of "bad device" or "result 22".
- USB session (2026-11-01, iOS 27.0.1): from the Linux container through the forward,
  `nomac device status` passed every step (Developer Mode on, the personalized image mounted,
  85 RemoteServiceDiscovery services with the app service); the all-Linux expo-default IPA
  (built, signed and exported by nomac in Linux) installed in 9 s and launched with `nomac
  install` and `nomac launch`, and was still running minutes later. On the Mac path,
  `nomac run` of the demo app archived, signed, checked, installed and launched it in one
  command (its process stayed up). Neither of the two Restore disk images of Xcode's `iOS_DDI`
  has a manifest stored on the device (`nomac device images --image`, read-only): the mounted
  image is the cryptex one (B-403b).
- `nomac run` checks, before archiving, what `nomac device status` does: usbmuxd lists the
  device, a lockdown session as this host's pair record, Developer Mode, and (unless
  `--no-launch`) the mounted Developer Disk Image. docs/INSTALL-ON-IPHONE.md is the one-page
  route for users, from the signing material to `nomac run`.
- `nomac run` on a corpus app on the Mac path, short of the device: a copy of retro-rampage
  with its bundle identifiers under the owner's prefix and the profile on the app target,
  archived by `nomac archive` with `--keychain`, `--provisioning-profiles` and manual signing
  (app and both frameworks signed with the development identity, the profile embedded);
  `nomac device check` finds it installable and warns that it has no scene manifest (TN3187).
  `nomac run` now asks usbmuxd for the device and its pair record before archiving, so a
  missing device or pairing stops it at once instead of after the build.
- The all-Linux run (above). The only fix it needed: lockdownd's `StartService` without the
  pair record's escrow bag (with it, AFC's port refused usbmuxd's connection); devicectl's install
  and launch of the same IPAs on the Mac agreed. The first demo app crashed in UIKit's check for
  apps without the scene lifecycle (an app-delegate-only UIKit app built with the iOS 27 SDK);
  the demo is now a SwiftUI app with a generated scene manifest.
- Ready for the iPhone: `nomac device status --device <UDID>` walks usbmuxd, the device, the
  pairing, a lockdown session, the iOS version, Developer Mode, the mounted Developer Disk Image
  and the CoreDevice tunnel, and stops at the first failure with what to do; usbmuxd, lockdownd
  (locked device, Trust dialog, lost pairing, missing service) and installation_proxy errors
  carry the same hints. `nomac install` takes a signed `.app` too: it runs the checks of
  `nomac device check` first and packs the IPA with nomac's ditto.
- `nomac device check` compares the signature's entitlements with the profile's (B-405).
- The launch path, from pymobiledevice3's sources (docs/formats/remotexpc.md): the CDTunnel
  handshake, TCP in the tunnel in userspace (ADR 0402), XPC objects, RemoteXPC over HTTP/2,
  RemoteServiceDiscovery and the app service's launch (`nomac launch`), checked against
  recorded frames and a scripted device only.
- The demo app (the signing experiments' app with `Kit.framework`, `org.nomac.signing`)
  archived by nomac with Xcode's compilers, ad hoc, under `~/nomac-out/device/apps`.
- Lockdown, TLS, AFC and installation_proxy from libimobiledevice's and pymobiledevice3's
  sources (docs/formats/lockdown.md, afc.md): `nomac device query`, `nomac install`,
  `nomac uninstall`; `TLSStream` checked against swift-nio-ssl's server (with verification
  `.none` its client never finishes the handshake in an embedded channel, so a callback accepts
  the device's certificate, ADR 0401).
- ADR 0400 (proposed): two routes, the demo through `devicectl`, the Linux route in Swift over
  usbmux, lockdown, AFC, installation_proxy and the CoreDevice tunnel, learned from public
  sources; pymobiledevice3 and go-ios only as references in experiments; Docker reaches the
  Mac's usbmuxd through a loopback TCP forward named by `USBMUXD_SOCKET_ADDRESS`.
- `nomac device list` against macOS's usbmuxd, directly and through a TCP forward:
  `{DeviceList: []}` with no device attached; an unknown request gets `Result` 1.
- `ProvisioningProfile` reads `ProvisionedDevices` and `ProvisionsAllDevices` and gives the
  `application-identifier`.

## Apps with capabilities under the wildcard profile

The owner's own Expo app may be installed for testing (approved 2026-10-30; its builds and
results stay outside the repository) with another bundle identifier, so the installed app is
not replaced. A wildcard development profile authorizes only `application-identifier`,
`com.apple.developer.team-identifier`, `get-task-allow` and `keychain-access-groups` (the
team's prefix); capabilities such as push (`aps-environment`), associated domains, app groups
and Sign in with Apple need an explicit App ID. The signing script
(`~/nomac-out/device/scripts/sign_for_device.py --bundle-id`) renames the app and its nested
bundles, keeps the entitlements the profile allows and lists the dropped ones; the app then
installs and launches, and the dropped features fail at run time. `nomac device check` names
any entitlement the profile does not allow.

## Plan: mounting the Developer Disk Image (B-403)

`nomac launch` needs the image mounted; Xcode mounts it when it prepares a device, and a device
Xcode never saw lists no app service. From pymobiledevice3's `mobile_image_mounter.py` and
`cryptexd.py`, and what the Mac holds:

1. The image: not inside Xcode.app; Xcode 27.0 installs it to
   `/Library/Developer/DeveloperDiskImages/iOS_DDI` (`version.plist` naming 27A266a,
   `Restore/BuildManifest.plist`, the disk images, firmware and trust cache, 32 MB). On Linux
   it comes from the user's own Xcode the way the SDK subset does (`nomac sdk install` adds it,
   never redistributed; pymobiledevice3's download of a GitHub copy is not an option).
2. Reuse before asking Apple: `QueryPersonalizationManifest` (`PersonalizedImageType`
   `DeveloperDiskImage`, the image's SHA-384) returns the manifest the device already stores for
   an image Xcode personalized on it; then `ReceiveBytes` (upload) and `MountImage` with that
   manifest, the trust cache and the image's info, all over mobile_image_mounter, no network.
3. Otherwise a TSS request to Apple (`gs.apple.com`): `QueryPersonalizationIdentifiers` and
   `QueryNonce` from the device, the build identity matching its board and chip from the build
   manifest, `ApECID`, `ApNonce`, the image digests; the reply's `ApImg4Ticket` is the manifest.
   This is a request to Apple per device and needs the owner's approval.
4. From iOS 27, pymobiledevice3 installs the image as a Cryptex1 through `cryptexd` in the
   CoreDevice tunnel (the PersonalizedDMG over mobile_image_mounter remains its fallback).
   Observed read-only (2026-10-31, `devicectl device info ddiServices`): Xcode 27.0 installed it
   on the owner's iPhone as a cryptex (`isCryptexDDI` true, build 27A266a), which
   mobile_image_mounter's `CopyDevices` lists as `Personalized`. The build manifest has both: 140
   identities with `PersonalizedDMG` and `LoadableTrustCache`, one "Developer Disk Image
   Cryptex" identity with the `Cryptex1,*` components. So the cryptex route is Xcode's; the
   PersonalizedDMG may still mount where cryptexd cannot (pymobiledevice3 keeps it as fallback).
   Open question for the owner: pymobiledevice3's `cryptexd.py` states that some of its facts
   (nonce domains, handles) come from inspecting Apple's binaries (`cryptexd`, CryptexKitHost);
   nomac's rule is to learn from outputs and public documentation only, so whether nomac may
   follow those parts is the owner's call; the PersonalizedDMG route does not depend on them.
5. Checked on the owner's iPhone only with approval: mounting changes the device's state, and
   testing needs the image unmounted first (or a device Xcode has not prepared).

## Next actions

Phone use only when the owner asks. Mac disk: heavy Docker jobs wait for 25 GB free.

1. With the phone, when the owner allows: the UI tests with `nomac test`; the mixed project
   (failing, skipped, expected failure: status and output against Xcode's `test-mixed`).
2. B-403 mount on a device: needs a restart on a host whose CoreDevice does not remount the
   image (a Linux host, B-407); the iPhone refuses to unmount Xcode's cryptex image.
3. B-404: the network route (pairing over Wi-Fi, no USB).

Staged for these: nomac-built unit-test products in `~/nomac-out/device/apps/xctest-unit`, the
iOS_DDI copy in `~/nomac-out/device/apps/iOS_DDI`, the crash demo archive in
`~/nomac-out/device/apps/crashdemo`; the usbmuxd forwarder (PID 63372) still runs.

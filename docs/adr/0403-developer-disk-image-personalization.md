# ADR 0403: Personalizing and mounting the Developer Disk Image

- Status: accepted (owner's decision, 2026-11-02; extends ADR 0400)
- Date: 2026-11-02

## Context

`nomac launch` reaches the app service, which the device lists only while its Developer Disk
Image is mounted (B-403). A restart unmounts it, and until now only Xcode or `devicectl` on a
Mac mounted it again, so a phone used only from Linux could install apps but not launch them.

Since iOS 17 the image is personalized: Apple's TSS server signs the image's digests for one
device (its ECID, board, chip and a nonce the device gives), and the device mounts the image
only with that ticket. Xcode 27.0 installs the image as a cryptex through `cryptexd` in the
CoreDevice tunnel (`devicectl device info ddiServices`: `isCryptexDDI`); the image's
`BuildManifest.plist` also has 140 build identities for the older route, a personalized disk
image (`PersonalizedDMG`) with a loadable trust cache, mounted through lockdownd's
`mobile_image_mounter`.

## Decision

1. **nomac contacts Apple's TSS server** (`https://gs.apple.com/TSS/controller?action=2`) to
   personalize the image, as Xcode does: the owner approved it on 2026-11-02. The request
   names the device by its ECID, board, chip, security settings and nonce, and lists the
   image's digests. nomac asks only when the device stores no ticket for the image
   (`QueryPersonalizationManifest`), and only for `nomac device personalize`,
   `nomac device mount`, or a launch that needs the image.
2. **The image is the user's Xcode's**, never redistributed: on a Mac the folder Xcode installs
   (`/Library/Developer/DeveloperDiskImages/iOS_DDI`); elsewhere the same files from the user's
   Xcode, which ships them in `Contents/Resources/Packages/XcodeSystemResources.pkg`
   (`CandidateDDIs/iOS_DDI.dmg`, an HFS+ volume in a zlib-compressed UDIF image, docs/formats/ddi.md).
   `nomac sdk install` extracts it once with 7-Zip and xz, run as subprocesses like unxip,
   when they are installed; nomac itself reads only the pbzx chunk framing.
3. **The personalized disk image route first**, over `mobile_image_mounter`:
   `QueryPersonalizationIdentifiers`, `QueryNonce`, the TSS request, `ReceiveBytes` and
   `MountImage` with the ticket and the trust cache. The cryptex route (Xcode's) stays B-403b:
   its messages travel inside the CoreDevice tunnel, which needs a packet capture on the Mac
   (root) to observe, and the only public description of it says it came from inspecting
   Apple's binaries, which nomac does not follow.
4. **Sources**: what the device and Apple's server answer (nomac's requests are checked by
   their replies: the server signs or refuses, the device mounts or refuses), public
   descriptions of the TSS protocol, and the MIT-licensed `idevice` crate as a reference for
   the message names. No code is copied from GPL or LGPL projects (pymobiledevice3,
   libimobiledevice).

## Consequences

- A device can be prepared for launching from Linux after a restart, with one request to Apple
  per image and nonce; offline, only a device that stores a ticket can mount.
- The request's host tags are the ones public descriptions give for Xcode's library
  (`@HostPlatformInfo` `mac`, `@VersionInfo`); Apple's server signs with them from Linux too.
- If a future iOS refuses the personalized disk image route, launching needs B-403b. A board the
  image's manifest does not list has only the cryptex image (pymobiledevice3's troubleshooting guide):
  such a device cannot mount with nomac yet, and says so.
- Off macOS the request goes over plain HTTP, since a Linux trust store refuses the server's chain
  (docs/formats/ddi.md): the ECID crosses the network in the clear. The ticket stays checked by the
  device. Pinning Apple's private root over TLS would hide the ECID, and is open.

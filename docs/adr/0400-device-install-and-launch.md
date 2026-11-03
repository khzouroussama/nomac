# ADR 0400: Installing and launching on a device, in Swift over Apple's device protocols

- Status: proposed
- Date: 2026-10-30

## Context

The goal is `nomac install` and `nomac run` from Linux, with no Mac: an IPA nomac built
installs and launches on an iPhone. ARCHITECTURE.md planned pymobiledevice3 as a subprocess.

What an install needs, in two parts:

- **A signature the device accepts.** A device installs only an app signed with a certificate
  its embedded provisioning profile lists, whose App ID covers the bundle identifier and whose
  devices include it, unexpired (TN3125, "Inside Code Signing: Provisioning Profiles"). Linux
  builds sign ad hoc today (ADR 0300); certificate signing with an Apple Development identity
  and a development profile is in place and matches codesign (docs/state/packaging.md, B-302),
  given the identity's private key.
- **A connection to the device.** Since iOS 17 the host side has two layers, both documented
  by open-source implementations (libimobiledevice and usbmuxd, pymobiledevice3, go-ios):
  - usbmuxd multiplexes TCP connections to the device's ports over USB (and lists Wi-Fi
    devices). lockdownd (port 62078) starts services: `com.apple.afc` (files),
    `com.apple.mobile.installation_proxy` (install), `com.apple.mobile.mobile_image_mounter`.
    Sessions use TLS with the host's pair record (certificates and key exchanged when the user
    trusts the host). Installing still works at this layer on iOS 17 and later.
  - Developer services (launching, debugging, XCTest) moved to CoreDevice: a tunnel to the
    device (lockdown's `com.apple.internal.devicecompute.CoreDeviceProxy` over usbmux since
    iOS 17.4, or RemotePairing over the network), carrying IPv6, in which RemoteServiceDiscovery
    lists RemoteXPC services (HTTP/2 framing, XPC messages), launching through
    `com.apple.coredevice.appservice`. They need the personalized Developer Disk Image mounted,
    which Xcode carries and Apple's TSS server personalizes per device.

## Decision

1. **Two routes, the demo first.**
   - (a) Demo route: an IPA nomac built (first on the Mac with Xcode's compilers, then on
     Linux) is signed with a development identity and profile, checked with
     `nomac device check`, and installed and launched by `xcrun devicectl` on the Mac. It
     proves the IPA, not the transport.
   - (b) Linux route: nomac speaks usbmux, lockdown, AFC and installation_proxy itself for
     `nomac install`, then the CoreDevice tunnel and RemoteXPC for `nomac run`.
2. **In Swift, in `NomacDevice`**, as ADR 0001 asks, not a pymobiledevice3 subprocess (which
   would make Python and its packages a runtime dependency). The protocols are learned from
   public documentation and the open-source implementations above, never from Apple's
   binaries; pymobiledevice3 and go-ios serve as references in `.github/scripts` experiments,
   where an exchange is observed against a device before nomac reproduces it. Each format is
   written down in docs/formats/ (`usbmux.md` first).
3. **Testing without USB in Docker.** Docker Desktop on macOS passes no USB device through. A
   container reaches the Mac's usbmuxd through a TCP forward of `/var/run/usbmuxd` bound to the
   loopback interface, named by `USBMUXD_SOCKET_ADDRESS` as libusbmuxd reads it
   (`<host>:<port>`, here `host.docker.internal:<port>`). Everything above the USB driver
   (lockdown, AFC, installation_proxy and the CoreDeviceProxy tunnel, which lockdown starts)
   then runs as on Linux. The rest is checked on a Linux machine with USB and libimobiledevice's
   usbmuxd, or over the network once a RemotePairing route exists.
4. **Signing for a device stays with the owner.** No private key leaves the Mac's keychain
   without the owner's approval and no Apple account change is made by nomac's agents. Until
   the owner provides an identity for nomac, the demo route signs through Apple's `codesign`
   with the keychain's identity, and the Linux route waits for an identity nomac holds.

## Consequences

- `NomacDevice` starts with usbmux (`nomac device list`) and the provisioning checks
  (`nomac device check`); lockdown, TLS, AFC, installation_proxy, the tunnel and RemoteXPC
  follow, each observed on the owner's iPhone first (B-400 to B-405).
- Lockdown sessions need TLS with the pair record on Linux, which Foundation does not offer:
  a dependency decision (B-401, ADR 0002).
- Launching needs the Developer Disk Image from the user's own Xcode, extracted like the SDK
  and never redistributed, and a request to Apple's TSS server per device, as Xcode makes.
- ARCHITECTURE.md's pymobiledevice3 subprocess is replaced by `NomacDevice`.

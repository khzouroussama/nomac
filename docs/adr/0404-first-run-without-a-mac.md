# ADR 0404: A first run with no Mac: pairing and signing material in nomac

- Status: accepted for what ships; the sign-in route stays the owner's decision (B-004)
- Date: 2026-11-06

## Context

The route of ADR 0400 was run with a Mac's usbmuxd and pairing, and an identity whose key was made
by hand. Read as someone with a Linux laptop and no Mac, docs/INSTALL-ON-IPHONE.md assumed:

| Step | What it assumed | Now |
|---|---|---|
| Pairing | libimobiledevice's `idevicepair`, a second package, or usbmuxd's own pairing, which waits for a dialog that a locked iPhone may not show | `nomac device pair` |
| usbmuxd missing or stopped | "start libimobiledevice's usbmuxd" | a message per state: not installed (with each distribution's package), installed and waiting for a device, a stopped daemon's socket, no write permission |
| No device | `nomac device list` printed nothing | what the kernel sees on USB, and what to do |
| Developer Mode | that Settings lists it, which needs a developer tool to have connected; Ubuntu 24.04's libimobiledevice 1.3.0 has no `idevicedevmodectl` to reveal it | `nomac device developer-mode` |
| Identity | three OpenSSL steps by hand and a certificate file name that does not exist (`AppleRootCA.cer`, 404; the root is at `/appleca/AppleIncRootCertificate.cer`) | `nomac signing request`, `nomac signing identity` |
| Profile against identity and device | found out at the end of a build | `nomac signing check`, with the build settings to pass |

## Decision

nomac pairs by itself, with the requests of libimobiledevice 1.3.0's `idevicepair pair` recorded
against a scripted device, and pymobiledevice3's certificate fields where they differ (serial
number 1, a validity starting a minute early, SHA-256). The pair record goes to usbmuxd, so
libimobiledevice's tools and nomac share it; both directions were checked against the real tools.

The signing material stays what the Mac route used, an RSA key and a PEM file outside any keychain;
`nomac signing request` writes the request OpenSSL writes, byte for byte. Apple's two public
certificates are downloaded from apple.com and checked against digests in the source; none is
stored in the repository. Only an issuer that has been observed (WWDR G3) is fetched: another
stops with a message and `--chain`.

Developer Mode is revealed, not turned on: with a passcode set AMFI refuses to turn it on from the
host, and it stays the user's decision on the device.

Three things the no-device experiments showed, now rules:

- `SavePairRecord`'s `Result` says nothing. libimobiledevice's usbmuxd answers 2 with the record
  written on Ubuntu 24.04 and 25.10 and Debian 13, and 0 on Ubuntu 22.04, Debian 12, Fedora 43, Arch
  and openSUSE Tumbleweed. Whether a session starts decides.
- In TLS 1.3 a peer that refuses the client's certificate does so after the client's handshake
  ended, so a lockdown session makes one request before it counts as started; a failed connection
  is no longer taken for a device that does not report Developer Mode.
- On Linux usbmuxd pairs by itself once the user taps Trust (`preflight.c`), racing `nomac device
  pair`. Whichever record starts a session serves.

## Not decided: signing in to Apple

A free Apple ID gets its certificate and profile only from Apple's developer services after a
sign-in, which is what Xcode, xtool and AltStore do. nomac does not, and this ADR does not add it:
it is B-004 and the owner's decision. docs/INSTALL-ON-IPHONE.md says plainly that nomac needs a paid
membership today.

## Consequences

- A first run needs usbmuxd only, not libimobiledevice's tools.
- None of this has met an iPhone on a Linux machine's USB (B-407). The first such run tests
  `nomac device pair`, `nomac device developer-mode` and the Developer Disk Image's mount together.

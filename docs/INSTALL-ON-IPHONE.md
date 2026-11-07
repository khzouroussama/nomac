# Install on your iPhone from Linux

The whole route from a Linux machine, an iPhone, a cable and an Apple account, with no Mac and
no Xcode running anywhere. The protocols behind it are in docs/formats/ (usbmux.md, lockdown.md,
afc.md, remotexpc.md) and ADRs 0400 and 0404.

**What has been checked and what has not.** An iPhone on iOS 27.0.1 by USB installed and launched
nomac's builds with nomac in a Linux container, through a forward of a Mac's usbmuxd and that
Mac's pairing (B-407). **No iPhone has been tested on a real Linux machine's USB yet.** The parts
only a first run from Linux uses, `nomac device pair`, `nomac device developer-mode` and mounting
the Developer Disk Image on a phone Xcode never prepared, have run against libimobiledevice's
usbmuxd and a scripted device (`.github/scripts/first_run_experiments.py`), never against an
iPhone. The certificate request and the identity file are checked against OpenSSL and against the
identity that installed on that iPhone.

You need nomac and your Xcode's SDK installed first (docs/INSTALL.md): install 7-Zip and xz before
`nomac sdk install` so that it also extracts the Developer Disk Image (step 5).

## Which Apple account

| | Free Apple ID | Apple Developer Program (paid) |
|---|---|---|
| developer.apple.com's Certificates, Identifiers & Profiles | No: Apple gives it with enrollment | Yes |
| On your own iPhone | Only by signing in inside Xcode or a tool that signs in for you: 3 devices, 10 App IDs and profiles that expire after 7 days, 3 apps per device | Yes, with a profile valid for a year |
| **With nomac today** | **No.** The certificate and the profile come from Apple's services after a sign-in, and nomac does not sign in to Apple for you | **Yes, this page** |
| TestFlight and the App Store | No | Yes (`nomac upload`) |

The limits are Apple's own (developer.apple.com/support/compare-memberships). So this page needs
a paid membership. nomac never asks for your Apple ID's password: you do the steps at
developer.apple.com in your browser, on any machine.

## 1. Reach the iPhone

nomac talks to usbmuxd, which owns the USB connection. Install it:

```sh
sudo apt-get install -y usbmuxd    # Debian, Ubuntu
sudo dnf install -y usbmuxd        # Fedora
sudo pacman -S usbmuxd             # Arch
sudo zypper install usbmuxd        # openSUSE
```

Plug the iPhone in and unlock it; udev starts usbmuxd when it sees the iPhone (without systemd,
`sudo usbmuxd`). Then:

```sh
nomac device list                  # prints the UDID, which every step below uses
nomac device pair --device <UDID>  # tap Trust on the iPhone and enter its passcode
```

`nomac device pair` waits two minutes for you; usbmuxd keeps the pairing in `/var/lib/lockdown`.
Nothing else from libimobiledevice is needed.

Turn on Developer Mode:

```sh
nomac device developer-mode --device <UDID>
```

It says whether Developer Mode is on, and when it is off it makes the switch appear, since
Settings may not list it on an iPhone that has never met a developer tool. On the iPhone:
Settings > Privacy & Security > Developer Mode, turn it on. The iPhone restarts; unlock it and
confirm Turn On.

## 2. Register the iPhone

At [Devices](https://developer.apple.com/account/resources/devices/add), add the UDID from
`nomac device list`, with any name.

## 3. Your signing identity

```sh
nomac signing request              # writes development.key and development.csr
```

At [Certificates](https://developer.apple.com/account/resources/certificates/add): Apple
Development, upload `development.csr`, download `development.cer`. Then:

```sh
nomac signing identity development.cer --key development.key    # writes identity.pem
```

This checks that the key is the certificate's, adds Apple's intermediate and root from apple.com
(checked against their published digests; offline, pass them with `--chain`) and prints your team.
`development.key` and `identity.pem` are readable only by you: keep them out of any repository.
The certificate lasts a year; a new one from the same `development.csr` works with the same key.

## 4. Your provisioning profile

1. At [Identifiers](https://developer.apple.com/account/resources/identifiers/add/bundleId), an
   App ID. A wildcard one (`<prefix>.*`) covers every app without capabilities; capabilities (App
   Groups, push, iCloud) need an explicit App ID.
2. At [Profiles](https://developer.apple.com/account/resources/profiles/add): iOS App Development,
   the App ID, your certificate and your iPhone. Download the `.mobileprovision` into a folder of
   its own, `profiles` below.
3. Check the three together, which also prints the settings step 6 takes:

```sh
nomac signing check --keychain identity.pem --provisioning-profiles profiles \
    --device <UDID> --bundle-id <your app's bundle identifier>
```

A device registered after the profile was made is not in it: edit the profile, select the device
and download it again.

## 5. Check the way to the iPhone

```sh
nomac device status --device <UDID>
```

`status` walks usbmuxd, the pairing, a lockdown session, the iOS version, Developer Mode, the
Developer Disk Image and the CoreDevice tunnel, and stops at the first problem with what to do.

Launching needs the iPhone's Developer Disk Image mounted; it stays mounted until the iPhone
restarts. `nomac launch` and `nomac run` mount it when they need it (`nomac device mount` by
itself): nomac personalizes your Xcode's image for the iPhone with Apple's server (`gs.apple.com`,
ADR 0403), uploads it and mounts it. On Linux that request goes over plain HTTP, because Linux trust
stores refuse the server's certificate chain, so your iPhone's identifiers (its ECID) cross the
network in the clear; Apple signs the answer and the iPhone checks it. An iPhone model your Xcode's
image does not list cannot mount with nomac yet, and says so. `nomac sdk install` extracts the image from your Xcode when
7-Zip and xz are installed (`sudo apt-get install -y 7zip xz-utils`); `--ddi` names any `iOS_DDI`
folder (B-403). The mount has not run on an iPhone yet; if it fails, `--no-launch` installs without
launching.

## 6. Build, install and launch

```sh
nomac run -project App.xcodeproj -scheme App -destination generic/platform=iOS \
    --device <UDID> --keychain identity.pem --provisioning-profiles profiles \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" \
    DEVELOPMENT_TEAM=<team> "PROVISIONING_PROFILE_SPECIFIER=<profile name>"
```

The app's bundle identifier must fall under the profile's App ID: add
`PRODUCT_BUNDLE_IDENTIFIER=<identifier>` to the command if it does not.

`nomac run` checks the device first, archives the scheme as `nomac archive` does, signs it with
the identity and the profile, checks the app as `nomac device check` does (signature, profile,
device, profile expiry, entitlements), installs it and launches it.

The steps also run one by one:

```sh
nomac archive ... -archivePath App.xcarchive          # same arguments as above
nomac device check App.xcarchive/Products/Applications/App.app --device <UDID>
nomac install App.xcarchive/Products/Applications/App.app --device <UDID>   # or an .ipa
nomac launch <bundle identifier> --device <UDID>
nomac stop <bundle identifier> --device <UDID>        # SIGTERM; --signal KILL
nomac uninstall <bundle identifier> --device <UDID>
```

## A project set up for automatic signing

Most projects are (`CODE_SIGN_STYLE=Automatic`, a team), and automatic signing asks Apple's services,
which nomac does not. What you get on Linux without the arguments of step 6, measured on a small
project:

- `nomac build` and `nomac archive` succeed and sign the app **ad hoc**, which is enough to check
  that it builds but installs on no device. `nomac install` and `nomac run` say so.
- With entitlements in the project (push, App Groups), they stop with `requires a provisioning
  profile`. `CODE_SIGN_ENTITLEMENTS=` on the command line builds it ad hoc without them.
- `nomac export` stops without `signingCertificate` in the export options, and says what to set.
  `signingCertificate` `-` gives an ad hoc IPA, which `nomac install` refuses for the same reason.

To install, pass `--keychain`, `--provisioning-profiles`, `CODE_SIGN_STYLE=Manual` and the settings
`nomac signing check` prints (step 6). The project's files stay as they are.

## When it fails

Every message below says the next step too.

- `usbmuxd is not installed` or `installed but not running`: step 1. usbmuxd stops when the last
  device is unplugged, so `nomac device list` needs the iPhone plugged in first.
- `the kernel sees no iPhone on USB`: unlock it; some cables only charge. `the kernel sees iPhone
  on USB but usbmuxd lists nothing`: `sudo systemctl restart usbmuxd`; `journalctl -u usbmuxd` says
  why.
- `usbmuxd holds no pair record`, `InvalidHostID`: `nomac device pair`, which also pairs again a
  device that forgot this host.
- `UserDeniedPairing`: you tapped Don't Trust. Unplug it and plug it in again for the dialog to
  come back. To forget an earlier decision: Settings > General > Transfer or Reset iPhone > Reset >
  Reset Location & Privacy.
- `Developer Mode is off`: step 1.
- `the device would refuse the app`: it lists why (not signed for a device, the profile lacks the
  device or the bundle identifier, an expired profile); for a `.app`, `nomac device check` also
  compares its entitlements with the profile's.
- The iPhone says Untrusted Developer when you open the app: on the iPhone, Settings > General >
  VPN & Device Management, select your certificate and trust it.
- The app starts and closes at once: an app built with the iOS 27 SDK needs the scene lifecycle
  (`UIApplicationSceneManifest`, TN3187); `nomac archive`, `nomac install` and `nomac device check` warn when it is missing.

## By hand, with OpenSSL

`nomac signing` writes what these do, byte for byte for the request:

```sh
openssl genrsa -out development.key 2048
openssl req -new -key development.key -subj "/CN=nomac development/C=US" -out development.csr
chmod 600 development.key
# after downloading development.cer, and from https://www.apple.com/certificateauthority/
# the Worldwide Developer Relations G3 certificate and https://www.apple.com/appleca/AppleIncRootCertificate.cer
openssl x509 -inform der -in development.cer -out development.pem
openssl x509 -inform der -in AppleWWDRCAG3.cer -out wwdr.pem
openssl x509 -inform der -in AppleIncRootCertificate.cer -out root.pem
cat development.key development.pem wwdr.pem root.pem > identity.pem
chmod 600 identity.pem
```

## From a container on a Mac

Docker Desktop has no USB. Relay a TCP port on the Mac's loopback interface to `/var/run/usbmuxd`,
for example `socat TCP-LISTEN:27015,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/var/run/usbmuxd`,
and set `USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015` in the container (`UNIX:<path>` names
another socket). The Mac's pairing is used as it is.

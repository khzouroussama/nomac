# Install on your iPhone from Linux

nomac builds, signs, installs and launches an iOS app on an iPhone with no Mac in the loop, with
your own Apple developer account. This page is the whole route; the protocols behind it are in
docs/formats/ (usbmux.md, lockdown.md, afc.md, remotexpc.md) and ADR 0400.

What has been checked: an iPhone on iOS 27.0.1 connected by USB, with nomac in a Linux container
reaching the device through a forward of a Mac's usbmuxd (step 2). A Linux machine's own usbmuxd
speaks the same protocol, but nomac has not been run against one yet (B-407).

## 1. Signing material (once)

You need an Apple Development certificate with its private key, and a development provisioning
profile that lists the iPhone. Both come from developer.apple.com; nothing needs Xcode or a
keychain.

```sh
# A key and a certificate signing request (the common name is free text).
openssl genrsa -out development.key 2048
openssl req -new -key development.key -subj "/CN=nomac development/C=US" -out development.csr
chmod 600 development.key
```

1. Certificates > + > Apple Development: upload `development.csr`, download `development.cer`.
2. Devices > +: register the iPhone's UDID (`nomac device list` prints it, step 3).
3. Identifiers > +: an App ID. A wildcard one (`<prefix>.*`) covers every app without
   capabilities; capabilities (App Groups, push, iCloud) need an explicit App ID.
4. Profiles > + > iOS App Development: the App ID, the certificate and the device; download the
   `.mobileprovision` into a folder of its own.

Put the key, the certificate and its chain into one PEM file, which `--keychain` reads:

```sh
openssl x509 -inform der -in development.cer -out development.pem
# AppleWWDRCAG3.cer and AppleRootCA.cer from https://www.apple.com/certificateauthority/
openssl x509 -inform der -in AppleWWDRCAG3.cer -out wwdr.pem
openssl x509 -inform der -in AppleRootCA.cer -out root.pem
cat development.key development.pem wwdr.pem root.pem > identity.pem
chmod 600 identity.pem
```

Keep `identity.pem` out of any repository. The app's bundle identifier must match the profile's
App ID: change `PRODUCT_BUNDLE_IDENTIFIER` in the project if it does not.

## 2. Reach the device

nomac talks to usbmuxd, which owns the USB connection, at `/var/run/usbmuxd`, or wherever
`USBMUXD_SOCKET_ADDRESS` says (`UNIX:<path>`, or `<host>:<port>`).

- On Linux, libimobiledevice's `usbmuxd` daemon. Pair once with libimobiledevice's
  `idevicepair pair` and tap Trust on the unlocked iPhone; nomac does not pair by itself and uses
  the pair record usbmuxd keeps.
- From a container on a Mac (Docker Desktop has no USB), relay a TCP port on the Mac's loopback
  interface to `/var/run/usbmuxd`, for example
  `socat TCP-LISTEN:27015,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/var/run/usbmuxd`, and set
  `USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015` in the container. The Mac's pairing is
  used as it is.

## 3. Check the device

```sh
nomac device list
nomac device status --device <UDID>
```

`status` walks usbmuxd, the pairing, a lockdown session, the iOS version, Developer Mode, the
Developer Disk Image and the CoreDevice tunnel, and stops at the first problem with what to do.
Turn on Developer Mode in Settings > Privacy & Security > Developer Mode (the iPhone restarts).

Launching needs the device's Developer Disk Image mounted; it stays mounted until the iPhone
restarts. `nomac device mount` mounts it, and `nomac launch` and `nomac run` do when they need
it: nomac personalizes your Xcode's image for the device with Apple's server (`gs.apple.com`,
ADR 0403), uploads it and mounts it. `nomac sdk install` extracts the image from your Xcode when
7-Zip and xz are installed (`sudo apt-get install -y 7zip xz-utils`); on a Mac nomac also finds
the one Xcode installed, and `--ddi` names any `iOS_DDI` folder (B-403). The mount itself has not been run on a
restarted iPhone yet; until it has, `--no-launch` installs without launching.

## 4. Build, install and launch

```sh
nomac run -project App.xcodeproj -scheme App -destination generic/platform=iOS \
    --device <UDID> --keychain identity.pem --provisioning-profiles profiles \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" \
    DEVELOPMENT_TEAM=<team> "PROVISIONING_PROFILE_SPECIFIER=<profile name>"
```

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

## When it fails

- `usbmuxd sees no device`: the cable, or the iPhone is locked; on a container route, the
  forward is not running.
- A pairing or Trust error: unlock the iPhone and pair again (step 2).
- `the device would refuse the app`: `nomac device check` lists why (not signed for a device, the
  profile lacks the device or the bundle identifier, an entitlement the profile does not grant,
  an expired profile).
- The app starts and closes at once: an app built with the iOS 27 SDK needs the scene lifecycle
  (`UIApplicationSceneManifest`, TN3187); `nomac device check` warns when it is missing.

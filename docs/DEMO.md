# Demo: React Native and Expo apps from Linux to an iPhone

Two apps created fresh, unmodified, taken to exported IPAs by nomac on Linux, then signed, installed
and launched on an iPhone by nomac on Linux. Run on 2026-11-03.

## The setup, as it is

- nomac runs in a clean `ubuntu:24.04` Docker container (arm64) on a Mac, installed as docs/INSTALL.md
  says for a build from source: Swift 6.4.1, `nomac sdk install` from a copy of Xcode 27.0
  (27A266a), `nomac toolchain install` with Swift 6.4.0 and nomac's tool download.
- The iPhone (iOS 27.0.1) is attached by USB to that Mac. nomac in the container reaches the
  Mac's usbmuxd over TCP (a loopback-only relay, docs/INSTALL-ON-IPHONE.md step 2) and uses the
  Mac's pairing. A Linux machine's own usbmuxd was not used.
- The Developer Disk Image was already mounted on the iPhone, by Xcode. nomac's own mount
  (`nomac device mount`, B-403) was not exercised here.
- Signing: an existing development profile and its Apple Development certificate. The apps'
  bundle identifier is set on the command line to the profile's (`PRODUCT_BUNDLE_IDENTIFIER=`), a
  build setting, not an edit to the app.
- The container's network reaches npm, CocoaPods' CDN, Maven and rubygems, but GitHub only now
  and then (some clones stall): `pod install` was run again until it completed (below).

Versions: Ubuntu 24.04.5 (aarch64), Node 24.22.2, Ruby 3.2.3, CocoaPods 1.17.0 (1.15.2 through
the React Native template's Gemfile), React Native 0.88.1 (`@react-native-community/cli` 20.2.0),
Expo SDK 58 (`expo` ~58.0.22, `expo-router` ~58.0.29), nomac `55e25df0` (main `371a335f` with the two
fixes below).

## Prerequisites beyond the README's

React Native and Expo need Node and CocoaPods, which the README's install does not list:

```sh
sudo apt-get install -y ruby-full build-essential rsync     # CocoaPods copies local pods with rsync
sudo gem install -N cocoapods bundler
curl -fsSLO https://nodejs.org/dist/v24.22.2/node-v24.22.2-linux-arm64.tar.xz       # Node 24
sudo mkdir -p /opt/node && sudo tar xJf node-v24.22.2-linux-arm64.tar.xz -C /opt/node --strip-components=1
export PATH=/opt/node/bin:$PATH
export LANG=C.UTF-8                                          # CocoaPods needs a UTF-8 locale
# nomac's xcodebuild, xcrun and command, which pod install runs: 'nomac doctor' prints this line.
export PATH=~/.nomac/xcode/27A266a/Xcode.app/Contents/Developer/usr/bin:$PATH
```

As root (a container), CocoaPods also needs `COCOAPODS_ALLOW_ROOT=1`.

## 1. A fresh bare React Native app

```sh
npx @react-native-community/cli@latest init RNDemo
cd RNDemo/ios
bundle install
bundle exec pod install
nomac check RNDemo.xcworkspace
HERMES=$(cd .. && pwd)/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc
nomac build -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO HERMES_CLI_PATH=$HERMES
nomac archive -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS -archivePath RNDemo.xcarchive \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual AD_HOC_CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_REQUIRED=NO DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= HERMES_CLI_PATH=$HERMES
nomac export -archivePath RNDemo.xcarchive -exportPath out -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` is the README's (method `debugging`, team `NOMAC00000`).
`HERMES_CLI_PATH` is the one override the app needs on Linux: React Native's bundle phase runs
`node_modules/hermes-compiler/hermesc/osx-bin/hermesc`, a macOS executable ("Exec format error"
on Linux). `nomac check` reports it (`build:setting=mach-o-executable`) and names the override;
the same package ships `linux64-bin/hermesc`, which writes the same bytecode. That hermesc is an
x86_64 executable: on arm64 Linux it needs user-mode emulation (Docker Desktop has it; elsewhere
`qemu-user-static`).

## 2. A fresh Expo app

```sh
npx create-expo-app@latest expo-demo --yes          # the default template
cd expo-demo
npx expo prebuild -p ios                             # on Linux it does not run pod install
cd ios
pod install
nomac check expodemo.xcworkspace
# build, archive and export as above, with -workspace expodemo.xcworkspace -scheme expodemo
```

One change outside nomac: Expo SDK 58's autolinking skips its `@ExpoModule` scan when Node's
`process.platform` is not `darwin` ("The scanner is a macOS binary"), and the build then stops in
`[Expo] Configure project`: "Scanning for @ExpoModule classes didn't complete … the module classes
of these packages are missing from the modules provider: expo-modules-core". Expo installs the
scanner's Linux build (`@expo/modules-macros-linux-arm64`), so the check only has to accept Linux
too; the demo makes that one-line change in
`node_modules/expo-modules-autolinking/build/platforms/apple/apple.js` (ADR 0182), which belongs in
Expo:

```diff
-    if (process.platform !== 'darwin') {
+    if (process.platform !== 'darwin' && process.platform !== 'linux') {
```

With it, the app builds, archives and exports unmodified otherwise, with `HERMES_CLI_PATH` as for
the bare app.

## 3. Sign, install and launch on the iPhone

```sh
export USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015   # the Mac's usbmuxd, relayed
nomac device list
nomac device status --device <UDID>
nomac archive -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS -archivePath RNDemo-dev.xcarchive \
    --keychain identity.pem --provisioning-profiles profiles \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" DEVELOPMENT_TEAM=<team> \
    "PROVISIONING_PROFILE_SPECIFIER=<profile name>" PRODUCT_BUNDLE_IDENTIFIER=<bundle identifier> \
    HERMES_CLI_PATH=$HERMES
nomac device check RNDemo-dev.xcarchive/Products/Applications/RNDemo.app --device <UDID>
nomac install RNDemo-dev.xcarchive/Products/Applications/RNDemo.app --device <UDID>
nomac launch <bundle identifier> --device <UDID> --console
```

## Results

| Step | Bare React Native | Expo |
|---|---|---|
| Create the app | `init` 116 s | `create-expo-app` 225 s, `prebuild -p ios` 8 s |
| Ruby gems | `bundle install` 26 s | (CocoaPods from the setup) |
| `pod install` on Linux | 106 s, first try | 68 s on the 9th try: the 8 before were GitHub clones cut by the network |
| `nomac check` | 6 of 253 features unverified | 8 of 268 |
| `nomac build` (Release) | 17 s (a second build: the first stopped at `hermesc` after 33 s) | 650 s to the scan's stop, then 57 s |
| `nomac archive` (ad hoc) | 27 s | 432 s |
| `nomac export` | under 1 s: `RNDemo.ipa`, 6.1 MB | 1 s: `expodemo.ipa`, 12.4 MB |
| `nomac archive` (development signing) | 16 s | 233 s |
| `nomac device check`, `nomac install` | installable; installed in 3 s | installable; installed in 3 s |
| `nomac launch --console` | launched; React Native started and evaluated its bundle; still running when checked | the same |

Both apps launched from Linux and kept running (the process list read from the Mac's devicectl),
and the iPhone recorded no crash for either. The two apps share the profile's bundle identifier,
so each install replaces the other on the phone. On the first launches `nomac launch --console`'s
stream stopped after about 30 s ("the device reset TCP port … in the tunnel") while the apps kept
running: nomac's user-space TCP did not acknowledge the device's keepalive probes. With that fix
(main `accd5b09`), the consoles stream for the full 60 s the demo waits, the bare app's:

```
launched <bundle identifier> on <UDID> (process 4101)
2026-11-03 18:21:03.325 RNDemo[4101:551984] _setUpFeatureFlags called with release level 2
WARNING: Logging before InitGoogleLogging() is written to STDERR
W1103 18:21:03.339419 1843294208 ReactInstance.cpp:312] ReactInstance: evaluateJavaScript() with JS bundle
```

A launch right after `nomac install` replaced the same app while it was running ended 3 to 19 s
in, React Native tearing down cleanly (`Scheduler::~Scheduler()`, then "closed its console") and
no crash report, 3 times of 3; launched again without an install, the app kept running. The
replaced process's termination appears to reach the new one; the device workstream has it.

The machine's setup, once: the apt packages 1036 s (a slow mirror), Node 18 s, CocoaPods 38 s, the
two Swift downloads 758 s and 761 s, `swift build -c release` of nomac 551 s, `nomac sdk install`
165 s (4.6 GB in `~/.nomac`), `nomac toolchain install` 33 s.

## What the demo found in nomac, fixed in general code

- `pod install` runs `xcodebuild -version` (React Native's Podfile) and, from Ruby without a
  shell, `command -v ccache`. nomac's `xcodebuild` and `xcrun` launchers are in the developer
  directory's `usr/bin`; `nomac toolchain install` now puts macOS's `command` there too, and
  `nomac doctor` says whether that folder is on `PATH`.
- Expo's `create-stub-xcframework.sh` (run by `pod install`) makes a dylib with
  `xcrun --sdk macosx clang -x c - -dynamiclib`, which on Linux linked an ELF executable. `nomac
  xcrun` now gives clang the target Xcode's clang takes without one (docs/formats/build.md
  "xcrun"), and `nomac sdk install` keeps macOS's SDK by default for its `libSystem` stubs.

## Not nomac's, noted

- Expo's precompiled modules read their tarballs with bsdtar's member globbing (`/usr/bin/tar`
  is GNU tar on Linux): "No XCFramework Info.plist found in ExpoFileSystem.tar.gz" for five pods,
  which Expo then builds from source, as its fallback does.
- RN 0.88's Debug `ip.txt` and the packager need `ipconfig`; a Release build does not.

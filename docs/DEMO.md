# Demo: React Native and Expo apps from Linux to an iPhone

Two apps created fresh and taken to exported IPAs by nomac on Linux, with no change to the app: no edit
to `node_modules`, and no project-specific flag beyond signing. Run on 2026-11-05.

They were also signed, installed and launched on an iPhone by nomac on Linux, on 2026-11-03. That run
still used two manual changes that nomac now makes itself, and the iPhone part has not been repeated
without them (section 3).

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

Versions on 2026-11-05: Ubuntu 24.04.5 (aarch64), Node 24.22.2, Ruby 3.2.3, CocoaPods 1.17.0 (1.15.2
through the React Native template's Gemfile), React Native 0.88.1 (`@react-native-community/cli` 20.2.0),
Expo SDK 58 (`expo` 58.0.23, `expo-modules-autolinking` 58.0.17), nomac from the branch of ADR 0184.
The 2026-11-03 run had `expo` ~58.0.22 and nomac `55e25df0`.

## Prerequisites beyond the README's

React Native and Expo need Node and CocoaPods, which the README's install does not list:

```sh
sudo apt-get install -y ruby-full build-essential rsync python3   # rsync for CocoaPods; python3 for some apps' install scripts
sudo gem install -N cocoapods bundler
curl -fsSLO https://nodejs.org/dist/v24.22.2/node-v24.22.2-linux-arm64.tar.xz       # Node 24
sudo mkdir -p /opt/node && sudo tar xJf node-v24.22.2-linux-arm64.tar.xz -C /opt/node --strip-components=1
export PATH=/opt/node/bin:$PATH
export LANG=C.UTF-8                                          # CocoaPods needs a UTF-8 locale
```

`pod install` runs nomac's `xcodebuild`, `xcrun` and `command`. With nomac linked on `PATH`, as `install.sh`
links it, `nomac toolchain install` writes them beside the link. A source build has no link: add the line
`nomac doctor` prints (docs/INSTALL.md), and put Swift on `PATH` as that page says, for the macro plugin
Expo's pods need. As root (a container), CocoaPods also needs `COCOAPODS_ALLOW_ROOT=1`.

## 1. A fresh bare React Native app

```sh
npx @react-native-community/cli@latest init RNDemo
cd RNDemo/ios
bundle install
bundle exec pod install
nomac check RNDemo.xcworkspace
nomac build -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
nomac archive -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS -archivePath RNDemo.xcarchive \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual AD_HOC_CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_REQUIRED=NO DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
nomac export -archivePath RNDemo.xcarchive -exportPath out -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` is the README's (method `debugging`, team `NOMAC00000`).
React Native's bundle phase runs `node_modules/hermes-compiler/hermesc/osx-bin/hermesc`, a macOS
executable. The same package ships `linux64-bin/hermesc`, which writes the same bytecode, and nomac's
build uses it: the project fix `mach-o-tool-linux-build` prints a `note:` and appears in the summary at
the end of the build (docs/PROJECT-COMPATIBILITY.md). That hermesc is an x86_64 executable: on arm64 Linux
it needs user-mode emulation (Docker Desktop has it; elsewhere `qemu-user-static`, and without it the build
stops with an error that says so).

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

The app builds, archives and exports with no change. Expo SDK 58's autolinking skips its `@ExpoModule`
scan when Node's `process.platform` is not `darwin`, and the build would stop in `[Expo] Configure project`.
Expo installs the scanner's Linux build (`@expo/modules-macros-linux-arm64`), so nomac's project fix
`expo-autolinking-scan` accepts Linux there, in memory while the build runs. The file on disk stays as npm
installed it. The check belongs in Expo, and the fix does nothing once Expo changes that statement.

The end of the Expo build says what nomac changed (docs/PROJECT-COMPATIBILITY.md); the bare app's lists only
the `mach-o-tool-linux-build` line:

```
note: nomac applied 3 project fixes to how this project's tools run; your files on disk are not changed:
note:   expo-autolinking-scan: expo-modules-autolinking/build/platforms/apple/apple.js changed in memory
note:   mach-o-tool-linux-build: HERMES_CLI_PATH is <app>/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc (x86_64, through this machine's user-mode emulation)
note:   macro-plugin-from-package: ExpoModulesMacros built for this machine
note: what they do, what you may have to change yourself, and --no-project-fixes to turn them off: https://github.com/khzouroussama/nomac/blob/main/docs/PROJECT-COMPATIBILITY.md
```

## 3. Sign, install and launch on the iPhone

Run on 2026-11-03 and not repeated since. That run also passed `HERMES_CLI_PATH=<the Linux hermesc>` to the
archive and had the one-line edit in Expo's `apple.js`, which nomac now handles itself. The commands below
leave those out, but this development-signed route has not been run without them.

```sh
export USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015   # the Mac's usbmuxd, relayed
nomac device list
nomac device status --device <UDID>
nomac archive -workspace RNDemo.xcworkspace -scheme RNDemo -configuration Release \
    -destination generic/platform=iOS -archivePath RNDemo-dev.xcarchive \
    --keychain identity.pem --provisioning-profiles profiles \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" DEVELOPMENT_TEAM=<team> \
    "PROVISIONING_PROFILE_SPECIFIER=<profile name>" PRODUCT_BUNDLE_IDENTIFIER=<bundle identifier>
nomac device check RNDemo-dev.xcarchive/Products/Applications/RNDemo.app --device <UDID>
nomac install RNDemo-dev.xcarchive/Products/Applications/RNDemo.app --device <UDID>
nomac launch <bundle identifier> --device <UDID> --console
```

## Results

### With no change to the app (2026-11-05)

| Step | Bare React Native | Expo |
|---|---|---|
| Create the app | `init` 523 s | `create-expo-app` 96 s, `prebuild -p ios` 2 s |
| Ruby gems | `bundle install` 353 s | (CocoaPods from the setup) |
| `pod install` on Linux | 111 s | 436 s, after the network came back |
| `nomac check` | 5 of 253 features outside the envelope | 7 of 269 |
| `nomac build` (Release), first | 30 s | 207 s |
| `nomac archive` (ad hoc) | 23 s | 142 s |
| `nomac export` | under 1 s: `RNDemo.ipa`, 6.1 MB | 1 s: `expodemo.ipa`, 12.4 MB |
| `main.jsbundle` against the manual route, in the same tree | identical, 1,274,308 bytes | identical, 3,675,626 bytes |
| `ExpoModulesProvider.swift` | | identical to the manual route's and to what the Mac writes: 2,587 bytes, 22 modules, SHA-256 `47cedc9a890df329…` |

- The manual route is the 2026-11-03 one: the one-line edit in `apple.js` and `HERMES_CLI_PATH` on the command
  line, built in the same tree and undone afterwards. The bare app's `main.jsbundle` in its IPA is also
  byte-identical to the 2026-11-03 IPA's (1,274,367 bytes), from the same path. Expo's IPA differs from
  that day's: `expo` moved to 58.0.23.
- `apple.js` matches npm's tarball of 58.0.17 before and after the builds. The bare app's `node_modules` has
  no file newer than `pod install`. Expo's has only what its own `[CP-User] Build ExpoModulesJSI xcframework`
  phase writes in `expo-modules-jsi/apple`.
- `nomac check`'s remaining features do not stop an ad hoc archive: signing settings and `ipconfig`, and
  for Expo also an entitlements file and a file reference's encoding. It exits with 1 for them.
- The preload was tried on Node 20.20.2, 22.23.4, 24.22.2 and 26.13.0 with Expo's real `apple.js`, loaded by
  `require` and by an ES module's `import`. Expo and React Native ask for Node `^22.13.0 || ^24.3.0` and newer.
- Expo's Mac provider came from the phase's own command, run on a Mac (Node 24.22.1, darwin-arm64) on a copy
  of the same `node_modules`, with the macOS scanner.
- The error without user-mode emulation was simulated with a Linux `hermesc` whose ELF machine no kernel
  takes: `nomac check` listed it as `build:setting=mach-o-executable`, and the build stopped with the error
  naming `qemu-user-static`, with no "Exec format error".

With `--no-project-fixes`, on the same trees, the builds print no project-fix line and fail as before the
fixes (exit status 65). The bare app stops at `hermesc` with "Exec format error". Expo's pods stop on the macro
plugin ("external macro implementation type 'ExpoModulesMacros.ExpoModuleMacro' could not be found"), and with
`-IDEBuildingContinueBuildingAfterErrors=YES` its `[Expo] Configure project` also gives Expo's own "Scanning for
@ExpoModule classes didn't complete".

### From the release download, as a normal user (2026-11-06)

The runs above were source builds as root, whose limit on open files in Docker is 1048576. A normal user's is
1024, and 27.0.4's fresh Expo archive failed on arm64 with "Too many open files". 27.0.5 raises the limit itself.

27.0.5 then ran on a fresh `ubuntu:24.04`, as a user with sudo, in Docker on a Mac: `curl | bash`, `nomac sdk
install` with a real `Xcode_27.xip`, `nomac toolchain install`, and the two apps created as above.

| | arm64 | x86_64, under emulation |
|---|---|---|
| Bare React Native: `nomac archive`, `nomac export` | succeeded: `RNDemo.ipa`, 6,130,044 bytes | succeeded: `RNDemo.ipa`, 6,130,044 bytes |
| Expo: `nomac archive`, `nomac export` | succeeded: `expodemo.ipa`, 12,442,484 bytes | succeeded: `expodemo.ipa`, 12,442,478 bytes |
| `apple.js` on disk after the build | unchanged | unchanged |
| `pod install` tries, cut by the network (bare, Expo) | 1, 3 | 2, 1 |

These IPAs were not installed on a phone, and no x86_64 Linux machine has run this.

### With the manual changes, to the iPhone (2026-11-03)

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
  `nomac doctor` says whether that folder is on `PATH`. Since ADR 0184 the install also writes all three
  beside a nomac linked on `PATH`.
- Expo's `create-stub-xcframework.sh` (run by `pod install`) makes a dylib with
  `xcrun --sdk macosx clang -x c - -dynamiclib`, which on Linux linked an ELF executable. `nomac
  xcrun` now gives clang the target Xcode's clang takes without one (docs/formats/build.md
  "xcrun"), and `nomac sdk install` keeps macOS's SDK by default for its `libSystem` stubs.

## Not nomac's, noted

- Expo's precompiled modules read their tarballs with bsdtar's member globbing (`/usr/bin/tar`
  is GNU tar on Linux): "No XCFramework Info.plist found in ExpoFileSystem.tar.gz" for five pods,
  which Expo then builds from source, as its fallback does.
- RN 0.88's Debug `ip.txt` and the packager need `ipconfig`; a Release build does not.

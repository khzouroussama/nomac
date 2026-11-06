<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo-dark.png">
    <img src="docs/assets/logo-light.png" alt="nomac" width="420">
  </picture>
</p>

<p align="center"><b>Build iOS apps from Xcode projects on Linux, without a Mac.</b></p>

Early preview. Supports Xcode 27.0 (27A266a), iOS devices only.

## Installation

On Ubuntu 24.04, arm64 or x86_64, with your own Xcode 27.0 download:

```sh
curl -fsSL https://raw.githubusercontent.com/khzouroussama/nomac/main/install.sh | bash
nomac sdk install ~/Downloads/Xcode_27.xip    # or an Xcode.app
nomac toolchain install
nomac doctor
```

Building from source and what the installer does: [docs/INSTALL.md](docs/INSTALL.md).

## Usage

```
$ nomac --help
OVERVIEW: Build, sign and install iOS apps from Xcode projects on Linux.

Commands take xcodebuild's flags; 'nomac <command> --help' shows each one's.
The tools of Xcode that builds run (actool, ibtool, momc and others) are nomac
commands too, not listed here.

USAGE: nomac <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  build                   Build a scheme or target, as 'xcodebuild build'.
  archive                 Archive a scheme, as 'xcodebuild archive'.
  export                  Export an archive to an IPA.
  codesign                Sign bundles and Mach-O files, as 'codesign'.
  check                   List what a project uses that nomac has not verified.
  list                    List targets and schemes, as 'xcodebuild -list'.
  inspect                 Print build settings (-showBuildSettings).

DEVICES AND APP STORE SUBCOMMANDS:
  device                  List and check devices, and read crash reports.
  install                 Install an app on a device.
  uninstall               Remove an app from a device.
  launch                  Launch an installed app on a device.
  stop                    Stop an app running on a device.
  run                     Archive, install and launch on a device.
  test                    Run an .xctestrun's tests on a device.
  atos                    Symbolicate addresses, as 'atos -i'.
  upload                  Upload an IPA to App Store Connect.

SETUP SUBCOMMANDS:
  sdk                     Install and select your Xcode's SDKs.
  toolchain               Install the Swift toolchain nomac builds with.
  doctor                  Check the installed Xcode and tools.

VERIFICATION SUBCOMMANDS:
  verify                  Compare nomac's output for an app with Xcode's.
  products                Compare two Build/Products folders.
  pif                     Write the project as Swift Build reads it (PIF).
  corpus                  Work with the verification corpus.

  See 'nomac help <subcommand>' for detailed help.
```

```sh
# Check what a project uses that nomac does not support yet
nomac check App.xcworkspace

# Build a scheme
nomac build -workspace App.xcworkspace -scheme App -destination generic/platform=iOS

# Archive it
nomac archive -workspace App.xcworkspace -scheme App -destination generic/platform=iOS \
    -archivePath App.xcarchive

# Export an IPA
nomac export -archivePath App.xcarchive -exportPath out \
    -exportOptionsPlist ExportOptions.plist

# Install and launch on an iPhone connected by USB (the first time: docs/INSTALL-ON-IPHONE.md)
nomac device pair --device <UDID>
nomac install out/App.ipa --device <UDID>
nomac launch com.example.App --device <UDID>

# Compare nomac's output with Xcode's
nomac verify <reference> --source . --developer-dir <Xcode.app>/Contents/Developer
```

The commands take xcodebuild's flags. Run `nomac <command> --help` for each one.

## Status

```mermaid
flowchart LR
  loader["Project loading"] --> build["Build"] --> res["Resources"] --> pack["Archive and sign"]
  pack --> device["iPhone"] --> tests["Tests on device"]
  pack --> upload["App Store upload"]
  classDef done fill:#2da44e,color:#fff,stroke:#1a7f37
  classDef wip fill:#bf8700,color:#fff,stroke:#9a6700
  class loader,pack done
  class build,res,device,upload,tests wip
```

Measured on real open-source apps against Xcode 27's output; details in [docs/PROGRESS.md](docs/PROGRESS.md).

Works with React Native and Expo apps: a fresh React Native 0.88 app and a fresh Expo SDK 58 app
build and archive to an IPA on Linux with no change to the app. Both have also run on an iPhone from
Linux, in an earlier run that still made two of those changes by hand ([docs/DEMO.md](docs/DEMO.md)).
Of the first 61 of 106 public React Native and Expo apps, 49 reach an IPA (a partial run).

Where a project's tools assume macOS, nomac changes how a few of them run for the build, without
touching your files. It tells you when it does (a note, and a summary at the end of the build), and
`--no-project-fixes` turns that off. Other projects need a change of their own.
[docs/PROJECT-COMPATIBILITY.md](docs/PROJECT-COMPATIBILITY.md) lists both.

`nomac test` runs an app's unit tests on an iPhone from Linux; UI tests not yet.

Apps nomac never saw:

| Area | | Result |
|---|---|---|
| React Native and Expo apps to an IPA (partial run) | `████████░░` | 49 / 61 |
| Projects read as Xcode reads them | `██████████` | 19 / 19 |

The 20 apps nomac was developed against:

| Area | | Result |
|---|---|---|
| Apps that build end to end on Linux | `█░░░░░░░░░` | 2 / 20 |
| Projects read as Xcode reads them | `██████████` | 19 / 19 measured (signal pending) |
| Build products | `████████░░` | 929 / 1,198 |
| Storyboards and xibs | `████████░░` | 457 / 588 |
| Asset catalogs | `█████░░░░░` | 54 / 99 |
| PDF images | `█████████░` | 1,328 / 1,535 |
| Strings | `██████████` | 3,022 / 3,022 |
| Core Data models | `██████████` | 11 / 11 |
| Signing and export (ad hoc and development only) | `██████████` | 12 / 12 |

Not supported yet:

- Metal shaders: no open-source compiler; `nomac check` reports them
- Core ML pipelines, tree ensembles and neural networks
- Simulator, macOS, tvOS and visionOS builds; watchOS only as a watch app inside an iOS app
- App Store and TestFlight: distribution signing, and an upload has never run against Apple
- On a device: UI tests, `.xcresult`, coverage and test plans
- On-demand resources and other rare asset types
- Verifying a signed xcframework: its signature is read and recorded as Xcode does, but its files and certificates are not checked; a warning says so

## How it works

nomac drives Apple's open-source [Swift Build](https://github.com/swiftlang/swift-build), the
engine inside Xcode. It reimplements the parts Xcode keeps closed, such as reading `.xcodeproj`
files, `actool`, `ibtool` and `momc`, from their observed outputs. It uses patched forks of
[Swift Build](https://github.com/khzouroussama/swift-build) and
[swift-driver](https://github.com/khzouroussama/swift-driver), which SwiftPM fetches by itself.

## How nomac compares

xtool builds SwiftPM-based apps on Linux. zsign, rcodesign and libimobiledevice sign and install
from Linux. EAS Build, Codemagic, Bitrise, GitHub's macOS runners and EC2 Mac run Xcode on rented
Macs. nomac takes your existing `.xcodeproj`, with its storyboards, asset catalogs and CocoaPods,
and builds it on Linux. Details: [docs/COMPARISON.md](docs/COMPARISON.md).

## Legal

nomac includes no Apple software; you use your own Xcode download. It is written from observed
outputs and public documentation, never from decompiling. Apple's Xcode and Apple SDKs Agreement
authorizes Apple's software only on Apple-branded computers running macOS, and you are
responsible for complying with it. nomac was developed and tested on Macs. nomac is not affiliated
with Apple; Xcode, iOS and TestFlight are trademarks of Apple Inc. Read
[docs/LEGAL.md](docs/LEGAL.md).

nomac is provided as is, with no warranty, and you use it at your own risk (LICENSE, sections 7 and 8).
The authors are not responsible for what happens to your apps, your Apple account or your use of
Apple's software. This is not legal advice.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md); AI coding agents start from [AGENTS.md](AGENTS.md).

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md): installation and building from source
- [docs/INSTALL-ON-IPHONE.md](docs/INSTALL-ON-IPHONE.md): signing, installing and launching on an iPhone
- [docs/EXAMPLES.md](docs/EXAMPLES.md): an open-source app from clone to IPA
- [docs/DEMO.md](docs/DEMO.md): a React Native and an Expo app on Linux
- [docs/PROJECT-COMPATIBILITY.md](docs/PROJECT-COMPATIBILITY.md): what nomac changes for you, and what you may have to change yourself
- [docs/PROGRESS.md](docs/PROGRESS.md): what is measured, on which apps
- [docs/COMPARISON.md](docs/COMPARISON.md): other tools
- [docs/LEGAL.md](docs/LEGAL.md): Apple's terms and how nomac is written
- [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md): working on nomac
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits together

## License

Apache License 2.0 (LICENSE). Third-party licenses are in NOTICE.

Uses your own Xcode download; read [docs/LEGAL.md](docs/LEGAL.md).

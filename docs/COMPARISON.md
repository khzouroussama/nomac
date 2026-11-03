# How nomac compares

Checked on 2026-11-03 against each project's own pages (linked); projects change, so check
them again before choosing. "Not described" means the project's page does not say, not that
the feature is missing. nomac's own column is from docs/PROGRESS.md.

nomac takes an existing Xcode project or workspace, with its storyboards, asset catalogs,
packages and CocoaPods, and builds it on Linux into the IPA Xcode would produce. Other tools do
parts of that, and several do things nomac does not.

## Building iOS apps without a Mac

| | nomac | [xtool](https://github.com/xtool-org/xtool) | [Theos](https://theos.dev/docs/) | [swift-sdk-darwin](https://github.com/erikbdev/swift-sdk-darwin) | [Darling](https://github.com/darlinghq/darling) | [xcbuild](https://github.com/facebookarchive/xcbuild) |
|---|---|---|---|---|---|---|
| What it is | An Xcode build replacement for Linux | "Cross-platform Xcode replacement" for SwiftPM apps | Make-based build system, born for jailbreak software | Swift SDK for compiling Darwin code on Linux | A macOS compatibility layer for Linux | Facebook's Xcode-compatible build tool |
| Input | `.xcodeproj`, `.xcworkspace`, Swift packages | A SwiftPM package | Theos makefiles | SwiftPM (`swift build --swift-sdk`) | macOS programs | `.xcodeproj`, `.xcworkspace` |
| Output the same as Xcode's | The goal, measured per file (docs/PROGRESS.md) | Not a goal described | No | No | – | Not described |
| Storyboards, asset catalogs | Own `ibtool`, `actool` (partial, measured) | Not described | Not described | No | – | Not described |
| CocoaPods, React Native, Expo | Yes: 46 of 58 React Native and Expo apps that install reach an IPA | SwiftPM packages only | Not described | SwiftPM only | – | Not described |
| Signing, device install | Yes | Yes, and Apple Developer Services | Not described | No | – | No |
| Status | Early preview | Largely one author's work, by its author's account | Rolling releases | Experimental, last change 2024-12 | "Many CLI tools already functional"; "Xcode itself doesn't run yet" | Archived on 2021-01-02 |
| Apple SDK from | Your Xcode | Your `Xcode.xip` | Its Linux guide points to a repository of patched SDKs | Your extracted Xcode | – | Not described |
| License | Apache-2.0 | MIT | see its repository | MIT | GPL-3.0 | BSD |

Where they do more: xtool talks to Apple Developer Services (certificates, profiles, devices)
and runs on Windows (WSL) and macOS too; Theos builds tweaks and runs on more platforms; Darling
runs many macOS command-line programs.

## Running macOS somewhere else

These run Apple's own Xcode, so their output is Xcode's: the most dependable route to the App
Store today.

| | What it is | Mac hardware | Notes |
|---|---|---|---|
| [GitHub Actions macOS runners](https://docs.github.com/en/billing/reference/actions-runner-pricing) | Hosted CI | Yes | $0.062 a minute for a 3- or 4-core macOS runner, against $0.006 for a 2-core Linux one; standard runners are free for public repositories |
| [EAS Build](https://docs.expo.dev/build/introduction/) | Expo's build service | "Mac mini hosts", a fresh macOS VM per build | "Any native project, whether or not you use Expo and React Native"; images with Xcode 27.0 and 27.1; submits with EAS Submit |
| [Codemagic](https://codemagic.io/pricing/) | Hosted CI | Mac mini M2 and M4 | 500 free macOS M2 minutes a month on the individual plan, then $0.095 a minute |
| [Bitrise](https://bitrise.io/pricing) | Hosted CI | M4 and M2 Pro machines | A free Hobby plan |
| [EC2 Mac](https://aws.amazon.com/ec2/instance-types/mac/) | Rented Macs | Mac mini and Mac Studio | A 24-hour minimum allocation, "to comply with the Apple macOS Software License Agreement" |
| [OSX-KVM](https://github.com/kholia/OSX-KVM), [Docker-OSX](https://github.com/sickcodes/Docker-OSX) | macOS in QEMU/KVM on an x86_64 PC | No | Run Xcode itself; their pages leave Apple's license to you ("It is your responsibility to understand, and accept (or not accept) the Apple EULA", OSX-KVM); Docker-OSX is GPL-3.0 |

nomac differs in running on Linux, without macOS; it is not Xcode, and has not uploaded an app to App Store Connect yet.

## Signing, installing, uploading

| | Runs on | What it does | License |
|---|---|---|---|
| nomac | Linux | Signs as `codesign` does, exports IPAs, installs and launches over USB (iOS 17+ tunnels), uploads with an App Store Connect API key (not run against Apple yet) | Apache-2.0 |
| [zsign](https://github.com/zhlynn/zsign) | macOS, Linux, Windows, Android, FreeBSD | Re-signs `.ipa`, `.app` and Mach-O files with your certificate and profile; bundle edits, dylib injection | MIT |
| [rcodesign (apple-codesign)](https://gregoryszorc.com/docs/apple-codesign/main/) | Linux, Windows, BSDs, macOS | Signs Mach-O files and bundles, notarizes and staples, without Apple software | see its repository |
| [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) | Linux, macOS, Windows, Android | Talks to an iPhone's services: pairing, installing and managing apps, more with a mounted developer image | LGPL-2.1 |
| [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) | Linux, macOS, Windows | The same and much more, including iOS 17+ tunnels and developer tooling | GPL-3.0 |
| [ios-deploy](https://github.com/ios-control/ios-deploy) | macOS with Xcode | Installs and debugs apps; "designed to work on … iOS versions prior to iOS17" | GPL-3.0 |
| [fastlane](https://docs.fastlane.tools/) | macOS (officially), Linux in part | Automates screenshots, signing, builds (with Xcode) and App Store and TestFlight releases | MIT |

Where they do more: zsign and rcodesign are mature signers for files you already have (and
rcodesign notarizes Mac software); pymobiledevice3 covers far more device services than nomac;
fastlane automates the whole release around Xcode.

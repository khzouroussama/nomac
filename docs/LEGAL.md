# Legal

This page states facts about nomac and quotes Apple's published terms. It is not legal advice.
If your use of nomac matters to you or your company, ask a lawyer about your situation.

## What nomac ships

- nomac's source code, under the Apache License 2.0 (LICENSE).
- Release downloads with nomac built for Linux and open-source tools built from source with
  nomac's patches: Apple's open-source cctools and ld64, LLVM's lld and clang, and the Swift
  compiler (docs/RELEASES.md). Every component and its license is listed in NOTICE.

Neither contains Apple software that is not open source: no Xcode, no SDK, no file from an Xcode
`.xip`, and no file Xcode wrote. The repository's tests encode observed facts (for example the
SHA-256 digest of an output), not Xcode's outputs.

## What you supply

You download Xcode from Apple, at [developer.apple.com](https://developer.apple.com/download/all/)
with your own Apple ID, and accept Apple's license for it. `nomac sdk install` then copies the
files nomac needs (the SDKs, Xcode's build specifications, the Developer Disk Image) from that
copy into `~/.nomac` on your machine, unmodified. nomac sends none of them anywhere.

nomac contacts Apple's servers only for what Xcode contacts them for, on your request:
personalizing a device's Developer Disk Image (`gs.apple.com`, when launching an app on an
iPhone) and uploading to App Store Connect with your API key (`nomac upload`).

## How nomac is written

nomac is a clean-room reimplementation of the parts of Xcode that Apple keeps closed, such as
reading `.xcodeproj` files, `actool`, `ibtool` and `momc`. It is not written by decompiling,
disassembling or patching Apple's closed software, and contains no code from it. Each behavior
comes from one of:

- Observation. Experiments (`.github/scripts/*_experiments.py`) generate small projects,
  run Xcode's tools on them on a Mac, and record their outputs; nomac is then written to give
  the same outputs, and the rules are written down in `docs/formats/`. The same is done with the
  open-source apps of `corpus/`. Anyone with Xcode can rerun the experiments.
- Public documentation from Apple and public specifications (CMS, DER, ZIP, the PDF and
  ICC specifications and others).
- Apple's open-source projects, used under their licenses: Swift Build, SwiftPM, swift-driver,
  LLVM and Swift, cctools and ld64, swift-foundation, LZFSE, and the published sources of Apple's
  Security project (docs/adr/0301).

## How nomac was developed and tested

- nomac was developed and tested on Macs: a MacBook and GitHub's macOS runners, Apple hardware
  running macOS.
- Xcode 27's reference outputs and every experiment ran in Xcode on those Macs.
- The Linux builds that used the SDK extracted from Xcode ran in Docker, a Linux virtual
  machine, on the MacBook.
- The iPhone was attached to the MacBook.
- Linux CI jobs use no Xcode, SDK or other closed Apple software; they build Apple's
  open-source cctools and ld64 for the release downloads.

## Third-party licenses

NOTICE lists every open-source component nomac depends on, copies or patches, with its license.
Among them: the Apache License 2.0 with the Runtime Library Exception (Swift, Swift Build,
SwiftPM), the Apache License 2.0 with LLVM Exceptions (lld, clang), and the Apple Public Source
License 2.0 for cctools and ld64, whose changes are published as patches in `.github/cctools` and
in each release download beside the binaries.

## Apple's terms for Xcode and its SDKs

Apple's [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf)
(version EA2002, dated 06/08/2026, read on 2026-11-03) governs Xcode and the SDKs in it. It says:

- Before its first section: "USE OF APPLE SOFTWARE IS GOVERNED BY THIS AGREEMENT AND IS
  AUTHORIZED ONLY FOR EXECUTION ON AN APPLE-BRANDED PRODUCT RUNNING MACOS. ANY OTHER DOWNLOAD
  OR USE OF APPLE SOFTWARE IS NOT AUTHORIZED AND IS IN BREACH OF THIS AGREEMENT."
- Section 2.2 grants a license to install the Apple Software "on Apple-branded computers that
  are owned or controlled by You", and to use the Apple SDKs "solely to test and develop
  Applications that are specifically for use with the applicable Apple-branded products".
- Section 2.5: "You may not alter the Apple Software or Services in any way in such copy, e.g.,
  You are expressly prohibited from separately using the Apple SDKs or attempting to run any
  part of the Apple Software on non-Apple-branded hardware."
- Section 2.7: "The grants set forth in this Agreement do not permit You to, and You agree not
  to, install, use or run the Apple Software or Apple Services on any non-Apple-branded computer
  or device, or to enable others to do so."

The [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
(dated October 29, 2026, read on 2026-11-03), which members of the Apple Developer Program
accept, says in section 2.6: "You agree not to install, use or run the Apple SDKs on any
non-Apple-branded computer, and not to install, use or run iOS, iPadOS, macOS, tvOS, visionOS,
watchOS, and Provisioning Profiles on or in connection with devices other than Apple-branded
products, or to enable others to do so."

Using Apple's SDKs on a computer that is not an Apple-branded product running macOS,
which is what nomac does on Linux, is outside what these agreements authorize. nomac does not
change Apple's terms or grant any right to Apple's software. You are responsible for complying
with the agreements you have accepted. Both agreements also restrict decompiling and reverse
engineering Apple's software; nomac does not do either (above).

## The App Store and TestFlight

Apple's [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) (read
on 2026-11-03) say that since April 28, 2026, "Apps uploaded to App Store Connect must be built
with Xcode 26 or later using an SDK for iOS 26, iPadOS 26, tvOS 26, visionOS 26, or watchOS 26."
nomac builds with the iOS 27 SDK of the Xcode 27.0 you supply and writes the version information
that Xcode 27.0 writes into an app (`DTXcode`, `DTSDKBuild` and the others;
docs/adr/0012-one-xcode-per-release.md), but nomac is not Xcode. No app built by nomac has been
uploaded to App Store Connect yet, so whether Apple accepts one is not known. The Developer
Program License Agreement's rules for apps (section 3.3, for example documented APIs only) and
the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) apply to
an app whatever built it.

## Trademarks

nomac is an independent project, not affiliated with, endorsed or sponsored by Apple Inc. Apple,
Xcode, iOS, iPhone, App Store, TestFlight and macOS are trademarks of Apple Inc. Other names are
the trademarks of their owners and are used only to identify their products.

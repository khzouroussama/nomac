# Installing nomac

nomac runs on Ubuntu 24.04, arm64 or x86_64. It needs your own Xcode 27.0 (27A266a), downloaded
from [developer.apple.com](https://developer.apple.com/download/all/) with your Apple ID: read
docs/LEGAL.md first.

## With the installer

```sh
curl -fsSL https://raw.githubusercontent.com/khzouroussama/nomac/main/install.sh | bash
nomac sdk install ~/Downloads/Xcode_27.xip      # or an Xcode.app copied from a Mac
nomac toolchain install
nomac doctor
```

The release has a download for arm64 and one for x86_64.

`install.sh` does four things, and can be read before it runs:

1. Installs the system packages nomac and Swift need with `apt-get` (with `sudo` unless you are
   root): Swift's own dependencies, curl, 7-Zip and XZ Utils (for the Developer Disk Image a
   device needs), libheif's `heif-dec` (for HEIC images in asset catalogs), and LLVM's C++
   demangler `libc++abi1` (for crash reports), and `liblzma-dev` for unxip.
2. Downloads the release archive for your machine, `nomac-<version>-linux-<arch>.tar.xz`, and
   checks it against its `.sha256`. Given an archive you downloaded (`install.sh <archive>`), or
   run from an extracted archive, it uses that instead.
3. Downloads Swift 6.4.0 for Ubuntu 24.04 from swift.org, the Swift release of Xcode 27.0, which
   nomac builds apps with, and checks it against swift.org's signature with swift.org's
   published keys.
4. Builds [unxip](https://github.com/saagarjha/unxip) 3.3 with that Swift, at the commit the script
   names, for expanding `Xcode.xip`. If that fails it warns and goes on: an `Xcode.app` still works.

Everything goes under `~/.local/share/nomac` (`--prefix <dir>` for elsewhere), and nomac is
linked into `~/.local/bin`:

| Path | What |
|---|---|
| `bin/nomac` and `bin/*.bundle` | nomac, built with the Swift standard library linked in, and the resource bundles it reads beside it |
| `bin/unxip` | unxip, also linked into `~/.local/bin` |
| `tools/` | the patched lld, dsymutil, clang, libclang, swift-frontend and cctools, with their patches, patch stamps and license texts (docs/RELEASES.md) |
| `swift/` | Swift 6.4.0 from swift.org |

Then `nomac sdk install` copies the files nomac needs from your Xcode into `~/.nomac`,
unmodified, and `nomac toolchain install` puts Swift and the tools into that copy's developer
directory (with no arguments it takes them from `swift/` and `tools/`). A source build has no
unxip: `nomac doctor` prints the command that installs it.

Tools that run `xcodebuild` or `xcrun` outside a build, such as CocoaPods' `pod install`, need
nomac's launchers on `PATH`. When nomac runs through a symbolic link on `PATH`, as the installer
links it into `~/.local/bin`, `nomac toolchain install` writes `xcodebuild`, `xcrun` and `command`
beside that link, leaving alone any other program of those names. They run the developer directory's
launchers. A source build has no link, so `nomac doctor` prints the line to add instead:

```sh
export PATH=~/.nomac/xcode/27A266a/Xcode.app/Contents/Developer/usr/bin:$PATH
```

## Building from source

Build nomac yourself to work on it, or on a system the release does not cover. nomac uses
patched forks of [Swift Build](https://github.com/khzouroussama/swift-build) and
[swift-driver](https://github.com/khzouroussama/swift-driver), which SwiftPM fetches by itself.

```sh
# Swift's own dependencies (https://www.swift.org/install/linux/), nomac's, and 7-Zip and XZ
# Utils, with which 'nomac sdk install' extracts the Developer Disk Image a device needs.
sudo apt-get update
sudo apt-get install -y binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
    libpython3-dev libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata unzip \
    zlib1g-dev curl ca-certificates libsqlite3-dev 7zip xz-utils
# For asset catalogs with HEIC images, also libheif's heif-dec.
sudo apt-get install -y libheif-examples
# For crash reports, LLVM's C++ demangler, as Xcode's atos uses ('nomac atos', 'nomac device
# symbolicate').
sudo apt-get install -y libc++abi1

# Swift 6.4.1 builds nomac; Swift 6.4.0, the Swift of Xcode 27.0, is what nomac builds apps with.
for v in 6.4.1 6.4.0; do
  curl -LO https://download.swift.org/swift-$v-release/ubuntu2404-aarch64/swift-$v-RELEASE/swift-$v-RELEASE-ubuntu24.04-aarch64.tar.gz
  mkdir -p ~/swift-$v && tar xzf swift-$v-RELEASE-ubuntu24.04-aarch64.tar.gz -C ~/swift-$v --strip-components=1
done                                  # on x86_64: ubuntu2404/ and ubuntu24.04.tar.gz, without -aarch64
export PATH=~/swift-6.4.1/usr/bin:$PATH

git clone https://github.com/khzouroussama/nomac && cd nomac
swift build -c release
export PATH=$PWD/.build/release:$PATH
nomac --version                       # nomac 27.0.5 (Xcode 27.0, 27A266a)
```

Keep the resource bundles (`*.bundle`) SwiftPM writes beside the executable when you copy it elsewhere.
The patched tools then come from the release's `nomac-tools-…` archive, or from building them
(docs/RELEASES.md "Making them"):

```sh
nomac sdk install ~/Downloads/Xcode_27.xip
nomac toolchain install ~/swift-6.4.0/usr --llvm-tools <the extracted nomac-tools folder>
nomac doctor
```

On a Mac, nomac builds the same way with Xcode 27.0's Swift
(`DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer swift build`); there it is used
for experiments and `nomac verify` against Xcode (CONTRIBUTING.md).

## What was tested

- The installer's archive is installed by `install.sh` on a fresh `ubuntu:24.04` in the
  `release-tools` workflow, for both architectures.
- Building from source runs in the `quickstart` workflow on a fresh `ubuntu:24.04`, x86_64 and
  arm64, from this file's block above.
- On 2026-11-03 a fresh `ubuntu:24.04` (arm64) went from `nomac sdk install` with an `Xcode.app`
  through `nomac toolchain install` to a Retro Rampage IPA with no network.
- On 2026-11-05 27.0.3 went from `curl | bash` on a fresh `ubuntu:24.04`, as a user with sudo, through
  `nomac sdk install` with a real `Xcode_27.xip` and `nomac toolchain install`, to a Retro Rampage IPA
  and one with a Swift package resolved from GitHub. This ran in Docker on a Mac, for arm64 and for
  x86_64 under emulation; no x86_64 Linux machine has run it.
- On 2026-11-06 27.0.5 went the same way as a user with a soft limit of 1024 open files, and then
  built a fresh bare React Native app and a fresh Expo app to IPAs with no change to the app, with
  `pod install` using the launchers `nomac toolchain install` wrote beside nomac (docs/DEMO.md). This
  also ran in Docker on a Mac, for arm64 and for x86_64 under emulation.

Each nomac release reproduces one Xcode build, which `nomac --version` names. With another Xcode
nomac warns that its outputs may differ, and `--strict-xcode` makes it refuse
(docs/adr/0012-one-xcode-per-release.md).

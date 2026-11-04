# Release downloads

On Linux, nomac builds with a swift.org toolchain plus tools it patches so their outputs match
Xcode's: lld, clang and libclang (`.github/lld`, `.github/clang`; ADRs 0102 and 0170), the
swift-frontend and its dependency scanner (`.github/swift`; ADR 0106), and cctools' `ld64`,
`bitcode_strip`, `libtool`, `strip` and `lipo` (`.github/cctools`; ADRs 0104 and 0181). Building them
takes hours, so each release publishes them (the owner's decision of 2026-11-02), built from
open-source code only; no Apple binary is in them.

A release's download for each Linux architecture is `nomac-<version>-linux-<arch>.tar.xz`
(`package-release.sh`): nomac itself, built with the Swift standard library linked in, with the
resource bundles (`*.bundle`) beside it, `install.sh`, NOTICE, LICENSE, and in `tools/` the tools'
archive described next. `install.sh` installs it (docs/INSTALL.md).

## What the tools' archive contains

`nomac-tools-<swift tag>-<stamp>-linux-<arch>.tar.xz`, with its `.sha256`, where `<stamp>` is the
first 8 hexadecimal digits of the SHA-256 of the four patch stamps below. One folder:

| Files | Built by | From |
|---|---|---|
| `lld`, `dsymutil`, `clang`, `libclang.so`, `lld.patches.sha256`, `clang.patches.sha256` | `build-llvm-tools.sh` with `CLANG=1` | swiftlang/llvm-project at the tag, `.github/lld` and `.github/clang` |
| `swift-frontend`, `lib_InternalSwiftScan.so`, `swift-frontend.patches.sha256` | `build-swift-frontend.sh` | swiftlang/swift at the tag, `.github/swift`, against the patched llvm-project |
| `ld64`, `bitcode_strip`, `libtool`, `strip`, `lipo`, `cctools.patches.sha256`, `ld64-licenses/` | `build-cctools.sh` | tpoechtrager/cctools-port at the commit the script pins, `.github/cctools` |
| `licenses/`, `patches/`, `NOTICE`, `README.txt` | `package-toolchain.sh` | the license texts of llvm-project and swift, the patches applied, the file list with SHA-256s |

Each `*.patches.sha256` is the SHA-256 of that patch directory's patches, concatenated in order.
`nomac toolchain install` compares them with the stamps it was built with (`LinuxToolchain`) and
refuses tools built with other patches, so a download only works with the nomac release it was
made for. The stamp in the name tells which.

## Using one

```sh
# The swift.org release paired with the Xcode nomac reproduces (6.4.0 for Xcode 27.0, `nomac sdk profile`).
curl -LO https://download.swift.org/swift-6.4.0-release/ubuntu2404-aarch64/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-ubuntu24.04-aarch64.tar.gz
mkdir -p ~/swift-6.4.0 && tar xzf swift-6.4.0-RELEASE-ubuntu24.04-aarch64.tar.gz -C ~/swift-6.4.0 --strip-components=1
sha256sum -c nomac-tools-*-linux-aarch64.tar.xz.sha256 && tar xJf nomac-tools-*-linux-aarch64.tar.xz
nomac toolchain install ~/swift-6.4.0/usr --llvm-tools nomac-tools-*-linux-aarch64
```

`toolchain install` copies the toolchain's executables and libraries into the `XcodeDefault`
toolchain of the developer directory `nomac sdk install` made, then replaces the toolchain's
clang, libclang, swift-frontend and dependency scanner with the patched ones, adds `ld64.lld`,
`ld64`, `dsymutil` and the cctools, keeps `ld64-licenses/` in `share/ld64`, writes `clang.cfg`, and
compiles nomac's macro plugins with the toolchain. It installs only into a developer directory
without a Swift compiler, so a second install goes into a fresh `nomac sdk install`.

## Making them

On a Linux machine of the target architecture (Ubuntu 24.04, about 60 GB free, `JOBS` cores):

```sh
.github/scripts/build-cctools.sh "$OUT"
CLANG=1 WORK=$WORK/llvm .github/scripts/build-llvm-tools.sh "$OUT"
.github/scripts/build-swift-frontend.sh ~/swift-6.4.0/usr "$WORK/llvm/llvm-project-swift-6.4.0-RELEASE" "$OUT"
.github/scripts/package-toolchain.sh "$OUT" "$WORK/llvm/llvm-project-swift-6.4.0-RELEASE.orig" \
    "$OUT/work/src/swift.orig" "$DIST"
```

`package-toolchain.sh` checks every stamp against the repository's patches and every binary's
architecture, and writes the same bytes for the same inputs (sorted entries, owner 0, mtimes
`SOURCE_DATE_EPOCH` or the commit time of `HEAD`, xz with a fixed block size): two runs on
2026-11-03 gave the same SHA-256.

On GitHub's Linux runners the `release-tools` workflow (started by hand) does the same for x86_64
and arm64, each step in `swift:6.4.1-noble` with the packages the first downloads were built with
(`release-tools.sh`): cctools and the LLVM tools side by side, then the swift-frontend against the
patched llvm-project the LLVM job hands over, then the package, a workflow artifact
`nomac-tools-linux-<arch>` that is attached to the release by hand. A hosted runner has about
14 GB free and 16 GB of memory, so the long jobs first remove preinstalled SDKs and add swap
(`release-tools-runner.sh`); each job stays under the runners' six hours.

## State

| Architecture | Built | Packaged |
|---|---|---|
| linux-aarch64 | the clang workstream's builds in Docker on the owner's Mac (`/ref/llvm-tools`), at main's stamps | `nomac-27.0.2-linux-aarch64.tar.xz` on the release |
| linux-x86_64 | not yet: `release-tools` on the public repository's runners, with only the LLVM targets the frontend takes (B-070) | – |


## Publishing the source

The public repository starts from one commit holding the tree of `main` (the owner's decision of
2026-11-02); this repository keeps its history. `.github/scripts/public_snapshot.py <empty dir>`
makes that commit: `git archive` of the ref, NOTICE written again, `.github/tags` without the tag
lines (their commits are not in the snapshot), then checks (no binary but the logos, no Mach-O,
ELF, archive, property list, asset catalog or signing file, no path in the home folder of the
machine that runs it, no Claude session line or link) and the owner's leak scan
(`--leak-scan`, which reads identifiers kept outside the repository). It never pushes. Later
snapshots go on top of the public main with `--onto <public repository>`: a clone of its main
gets the new tree as one more commit, whose body names the development commit it comes from, so
pushing it is a fast-forward and nothing is ever force-pushed. A push
to a repository whose Actions are on runs the `ci` and `tags` workflows.

## Release notes: v27.0.2

The release's title is "nomac 27.0.2 (Xcode 27.0, 27A266a)". Each release's version follows ADR
0012: `<Xcode major>.<Xcode minor>.<N>`. The text below is its notes, with each download's
SHA-256 from its `.sha256`.

> Early preview. nomac builds iOS apps from `.xcodeproj` and `.xcworkspace` on Linux with your own
> Xcode 27.0 download, then signs, installs and launches them on an iPhone.
>
> Install on Ubuntu 24.04 arm64: see the [README](https://github.com/khzouroussama/nomac#installation).
> The x86_64 download is being built and will be added to this release; until then, [build from source](https://github.com/khzouroussama/nomac/blob/main/docs/INSTALL.md#building-from-source).
>
> Measured on real open-source apps against Xcode 27's output ([docs/PROGRESS.md](https://github.com/khzouroussama/nomac/blob/main/docs/PROGRESS.md)):
> - A fresh React Native 0.88 app and a fresh Expo SDK 58 app (with one line changed in Expo's
>   autolinking) build, install and run on an iPhone from Linux ([docs/DEMO.md](https://github.com/khzouroussama/nomac/blob/main/docs/DEMO.md)).
> - React Native and Expo apps, partial run: 49 of the first 61 of 106 public apps reach an IPA.
> - 19 of 19 holdout apps are read as Xcode reads them.
> - In the 20 apps nomac was developed against: 2 build end to end on Linux; 457 of 588 storyboards
>   and xibs and 1,328 of 1,535 PDF images come out the same or equivalent.
> - `nomac test` runs an app's unit tests on an iPhone from Linux.
>
> Not supported yet: Metal shaders; Core ML pipelines, tree ensembles and neural networks;
> simulator, macOS, tvOS and visionOS builds; distribution signing, and an upload has never run
> against Apple; UI tests, `.xcresult`, coverage and test plans on a device; on-demand resources
> and other rare asset types. nomac stops with a message on what it does not support.
>
> The download holds nomac and open-source tools built from source with nomac's patches (LLVM's lld
> and clang, the Swift compiler, Apple's cctools and ld64), with the patches and license texts
> (NOTICE). nomac contains no closed Apple software; you supply Xcode under Apple's license, whose
> terms authorize Apple's software only on Apple-branded computers running macOS. Read
> [docs/LEGAL.md](https://github.com/khzouroussama/nomac/blob/main/docs/LEGAL.md). nomac is not affiliated with Apple.

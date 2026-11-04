#!/bin/bash
# Builds the swift-frontend nomac installs into the developer directory on Linux
# (docs/adr/0106-a-patched-swift-frontend.md): swiftlang/swift at the tag of the toolchain
# `nomac toolchain install` installs, with the patches in .github/swift, against the LLVM and Clang
# build-llvm-tools.sh patches with CLANG=1 (.github/clang), as swift.org builds it: its version
# strings, its LLVM revision, no assertions.
#
# Usage: build-swift-frontend.sh <toolchain-usr> <llvm-project> <output-dir>
#   <toolchain-usr>  the usr directory of the swift.org toolchain of the tag, whose clang and swiftc
#                    build the compiler and whose libraries it loads
#   <llvm-project>   the patched llvm-project build-llvm-tools.sh made with CLANG=1
#                    (<work>/llvm-project-<tag>), only read
#   SWIFT_TAG  swiftlang tag (default swift-6.4.0-RELEASE, the Swift of Xcode 27.0)
#   JOBS       parallel jobs (default 4)
#   WORK       build directory (default <output-dir>/work)
# Needs curl, git, cmake, ninja, patch, patchelf, rsync, python3 and libuuid's headers. Writes
# <output-dir>/{swift-frontend,lib_InternalSwiftScan.so}, the dependency scanner the driver asks which
# options the frontend takes, and swift-frontend.patches.sha256.
set -euo pipefail
toolchain=$(cd "$1" && pwd)
llvm=$(cd "$2" && pwd)
out=$(mkdir -p "$3" && cd "$3" && pwd)
tag=${SWIFT_TAG:-swift-6.4.0-RELEASE}
jobs=${JOBS:-4}
work=${WORK:-$out/work}
github=$(cd "$(dirname "$0")/.." && pwd)
patches=("$github"/swift/*.patch)
[ -f "$llvm/.nomac-patches" ] || { echo "error: $llvm is not a source build-llvm-tools.sh patched" >&2; exit 1; }
src=$work/src
mkdir -p "$src"
for repository in swift swift-cmark swift-syntax swift-experimental-string-processing swift-corelibs-libdispatch; do
  name=${repository/swift-cmark/cmark}
  pristine=$src/$name.orig
  [ "$name" = swift ] || pristine=$src/$name
  [ -d "$pristine" ] && continue
  for attempt in 1 2 3 4 5; do
    rm -f "$work/$name.tar.gz"
    curl -sSfL -o "$work/$name.tar.gz" "https://codeload.github.com/swiftlang/$repository/tar.gz/refs/tags/$tag" && break
    [ "$attempt" = 5 ] && { echo "error: could not download $repository $tag" >&2; exit 1; }
    sleep 10
  done
  rm -rf "$pristine.partial"
  mkdir "$pristine.partial"
  tar xzf "$work/$name.tar.gz" -C "$pristine.partial" --strip-components=1
  mv "$pristine.partial" "$pristine"
  rm "$work/$name.tar.gz"
done
# As build-llvm-tools.sh does: only the files the patches change get new times.
stamp=$(cat "${patches[@]}" | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
if [ "$(cat "$src/swift/.nomac-patches" 2>/dev/null)" != "$stamp" ]; then
  rm -rf "$src/swift.partial"
  cp -a "$src/swift.orig" "$src/swift.partial"
  for patch in "${patches[@]}"; do
    patch -d "$src/swift.partial" -p1 --forward < "$patch"
  done
  mkdir -p "$src/swift"
  rsync -rlpgoD --checksum --delete --exclude .nomac-patches "$src/swift.partial/" "$src/swift/"
  rm -rf "$src/swift.partial"
  echo "$stamp" > "$src/swift/.nomac-patches"
fi
rsync -rlpgoD --checksum --delete "$llvm/" "$src/llvm-project/"
# swift.org's frontend names the tag's llvm-project commit in its version strings, and the tag as its
# compiler tag (`-print-target-info`'s swiftCompilerTag); the tarballs have no git metadata.
revision=
for attempt in 1 2 3 4 5; do
  revision=$(git ls-remote https://github.com/swiftlang/llvm-project.git "refs/tags/$tag" | cut -f1) && [ -n "$revision" ] && break
  sleep 10
done
[ -n "$revision" ] || { echo "error: no llvm-project $tag" >&2; exit 1; }
build=$work/build
# build-script configures as swift.org does (its standard library too, which the configuration
# needs), and only the frontend and the scanner are built of Swift.
PATH=$toolchain/bin:$PATH TOOLCHAIN_VERSION=$tag SWIFT_BUILD_ROOT=$build python3 "$src/swift/utils/build-script" \
  --release --no-assertions --build-subdir=nomac --skip-build \
  --host-cc="$toolchain/bin/clang" --host-cxx="$toolchain/bin/clang++" --bootstrapping=hosttools \
  --llvm-targets-to-build="AArch64;X86" \
  --llvm-cmake-options="-DLLVM_FORCE_VC_REVISION=$revision -DLLVM_FORCE_VC_REPOSITORY=https://github.com/swiftlang/llvm-project.git -DLLVM_PARALLEL_LINK_JOBS=4" \
  --skip-early-swift-driver --swift-include-tests=0 --llvm-include-tests=0 --skip-build-benchmarks \
  --swift-enable-ast-verifier=0
PATH=$toolchain/bin:$PATH ninja -C "$(ls -d "$build"/nomac/cmark-linux-*)" -j "$jobs"
swift=$(ls -d "$build"/nomac/swift-linux-*)
llvm_build=$(ls -d "$build"/nomac/llvm-linux-*)
# Of the LLVM tree, only what Swift's two targets take from it: the whole tree (clangd, clang-tidy and
# every other tool) is more than a hosted runner's six hours. Files the configure wrote have no rule
# in the LLVM build. The tablegen targets are the generated headers Swift's sources include.
mapfile -t needed < <(PATH=$toolchain/bin:$PATH ninja -C "$swift" -t inputs swift-frontend libSwiftScan | sed -n "s|^$llvm_build/||p" \
  | grep -Fxf <(PATH=$toolchain/bin:$PATH ninja -C "$llvm_build" -t targets all | sed 's/: .*//'))
[ "${#needed[@]}" -gt 0 ] || { echo "error: Swift's targets name nothing in $llvm_build" >&2; exit 1; }
PATH=$toolchain/bin:$PATH ninja -C "$llvm_build" -j "$jobs" "${needed[@]}" intrinsics_gen clang-tablegen-targets
PATH=$toolchain/bin:$PATH ninja -C "$swift" -j "$jobs" swift-frontend libSwiftScan
# The run paths of the toolchain's own files, so that they load the toolchain's libraries, not the
# build's or the build machine's.
for files in bin/swift-frontend:bin/swift-frontend lib/lib_InternalSwiftScan.so:lib/swift/host/compiler/lib_InternalSwiftScan.so; do
  built=${files%%:*} installed=${files#*:}
  cp "$swift/$built" "$out/$(basename "$built")"
  patchelf --set-rpath "$(patchelf --print-rpath "$toolchain/$installed")" "$out/$(basename "$built")"
done
echo "$stamp" > "$out/swift-frontend.patches.sha256"
ls -la "$out"

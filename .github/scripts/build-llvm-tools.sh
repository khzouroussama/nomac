#!/bin/bash
# Builds the LLVM tools nomac installs into the developer directory on Linux
# (docs/adr/0102-linker.md): ld64.lld and dsymutil from swiftlang/llvm-project at
# the tag of the toolchain `nomac toolchain install` installs, with the patches in .github/lld,
# and with CLANG=1 clang too, with the patches in .github/clang (docs/adr/0170-xcodes-clang-abi-and-a-patched-clang.md).
#
# Usage: build-llvm-tools.sh <output-dir>
#   LLVM_TAG  swiftlang/llvm-project tag (default swift-6.4.0-RELEASE, the Swift of Xcode 27.0)
#   JOBS      parallel jobs (default 4)
#   WORK      build directory (default <output-dir>/work)
#   CLANG     1 to build clang as well, for arm64 and x86_64 targets
#   CLANG_VERSION  the version clang reports (default 21.0.0, as the swift.org toolchain of the tag's does,
#             though the tag's source says 21.1.6; `__clang_minor__` and `__clang_patchlevel__` show it)
# Needs curl, cmake, ninja, clang, patch, rsync and python3. Writes <output-dir>/{lld,dsymutil}, and clang
# and libclang.so, the library Swift Build's dependency scan runs clang's driver from.
set -euo pipefail
out=$(mkdir -p "$1" && cd "$1" && pwd)
tag=${LLVM_TAG:-swift-6.4.0-RELEASE}
jobs=${JOBS:-4}
work=${WORK:-$out/work}
github=$(cd "$(dirname "$0")/.." && pwd)
patches=("$github"/lld/*.patch "$github"/clang/*.patch)
mkdir -p "$work"
src=$work/llvm-project-$tag
pristine=$src.orig
if [ ! -d "$pristine" ]; then
  for attempt in 1 2 3 4 5; do
    # codeload does not resume downloads, so each attempt starts over.
    rm -f "$work/$tag.tar.gz"
    curl -sSfL -o "$work/$tag.tar.gz" "https://codeload.github.com/swiftlang/llvm-project/tar.gz/refs/tags/$tag" && break
    [ "$attempt" = 5 ] && { echo "error: could not download llvm-project $tag" >&2; exit 1; }
    sleep 10
  done
  rm -rf "$pristine.partial"
  mkdir "$pristine.partial"
  tar xzf "$work/$tag.tar.gz" -C "$pristine.partial" --strip-components=1
  mv "$pristine.partial" "$pristine"
  rm "$work/$tag.tar.gz"
fi
# The source is the pristine tree with the patches, made again when they change. Only the files
# whose contents change are copied over the previous source, the others keep their times, so the
# build recompiles only what the patches change.
stamp=$(cat "${patches[@]}" | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
if [ "$(cat "$src/.nomac-patches" 2>/dev/null)" != "$stamp" ]; then
  rm -rf "$src.partial"
  cp -a "$pristine" "$src.partial"
  for patch in "${patches[@]}"; do
    patch -d "$src.partial" -p1 --forward < "$patch"
  done
  mkdir -p "$src"
  rsync -rlpgoD --checksum --delete --exclude .nomac-patches "$src.partial/" "$src/"
  rm -rf "$src.partial"
  echo "$stamp" > "$src/.nomac-patches"
fi
build=$work/build-$tag
mkdir -p "$build"
projects=lld targets=AArch64 tools=(lld dsymutil) outputs=(bin/lld bin/dsymutil) version=()
if [ "${CLANG:-}" = 1 ]; then
  projects="lld;clang" targets="AArch64;X86" tools+=(clang libclang) outputs+=(bin/clang lib/libclang.so)
  IFS=. read -r major minor patchlevel <<< "${CLANG_VERSION:-21.0.0}"
  version=(-DCLANG_VERSION_MAJOR="$major" -DCLANG_VERSION_MINOR="$minor" -DCLANG_VERSION_PATCHLEVEL="$patchlevel")
fi
cmake -S "$src/llvm" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS="$projects" \
  -DLLVM_TARGETS_TO_BUILD="$targets" -DLLVM_ENABLE_ASSERTIONS=OFF -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF "${version[@]}" >/dev/null
ninja -C "$build" -j "$jobs" "${tools[@]}"
for output in "${outputs[@]}"; do
  cp "$build/$output" "$out/$(basename "$output")"
done
# The patches lld and clang were built with, which `nomac toolchain install` checks against its own.
digest() { cat "$@" | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'; }
digest "$github"/lld/*.patch > "$out/lld.patches.sha256"
if [ "${CLANG:-}" = 1 ]; then
  digest "$github"/clang/*.patch > "$out/clang.patches.sha256"
fi
ls -la "$out"

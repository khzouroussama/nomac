#!/bin/bash
# Builds the tools of Apple's cctools and ld64 that the swift.org toolchain lacks, as
# tpoechtrager/cctools-port ports them to Linux (docs/adr/0104-relocatable-links.md): the classic
# ld64, for the relocatable links Swift Build makes (`clang -r`), which ld64.lld cannot,
# bitcode_strip, which Swift Build hands its Swift library copies, libtool, which makes static
# libraries, strip, which Swift Build's Strip tasks run, and lipo, which scripts run
# (docs/adr/0181-static-libraries.md), with the patches in .github/cctools. All are
# Apple's open source under the Apple Public Source License 2.0; the licenses and cctools-port's
# notices are copied next to the binaries.
#
# Usage: build-cctools.sh <output-dir>
#   CCTOOLS_COMMIT  cctools-port commit (default: branch 1030.6.3-ld64-956.6 on 2026-04-03)
#   JOBS            parallel jobs (default 4)
#   WORK            build directory (default <output-dir>/work)
# Needs curl, make, clang, patch and the Swift toolchain's libdispatch and BlocksRuntime (/usr/lib/swift).
# Writes <output-dir>/ld64, <output-dir>/bitcode_strip, <output-dir>/libtool, <output-dir>/strip,
# <output-dir>/lipo and <output-dir>/ld64-licenses/.
set -euo pipefail
out=$(mkdir -p "$1" && cd "$1" && pwd)
commit=${CCTOOLS_COMMIT:-904de2a71d4da6a9b30d2efaf912a10ddc7d9ddb}
jobs=${JOBS:-4}
work=${WORK:-$out/work}
swift=${SWIFT_LIBRARIES:-/usr/lib/swift}
patches=$(cd "$(dirname "$0")/../cctools" && pwd)
mkdir -p "$work"
pristine=$work/cctools-port-$commit-pristine
src=$work/cctools-port-$commit
if [ ! -d "$pristine" ]; then
  for attempt in 1 2 3 4 5; do
    rm -f "$work/cctools-port.tar.gz"
    curl -sSfL -o "$work/cctools-port.tar.gz" "https://codeload.github.com/tpoechtrager/cctools-port/tar.gz/$commit" && break
    [ "$attempt" = 5 ] && { echo "error: could not download cctools-port $commit" >&2; exit 1; }
    sleep 10
  done
  rm -rf "$pristine.partial"
  mkdir "$pristine.partial"
  tar xzf "$work/cctools-port.tar.gz" -C "$pristine.partial" --strip-components=1
  mv "$pristine.partial" "$pristine"
  rm "$work/cctools-port.tar.gz"
fi
# The source is the pristine tree with the patches, made again when they change. The copy keeps
# file times, so the build recompiles only what the patches touch.
stamp=$(cat "$patches"/*.patch | sha256sum | cut -d' ' -f1)
if [ "$(cat "$src/.nomac-patches" 2>/dev/null)" != "$stamp" ]; then
  rm -rf "$src.partial"
  cp -a "$pristine" "$src.partial"
  for patch in "$patches"/*.patch; do
    patch -d "$src.partial" -p1 --forward < "$patch"
  done
  echo "$stamp" > "$src.partial/.nomac-patches"
  rm -rf "$src"
  mv "$src.partial" "$src"
fi
build=$work/build-$commit
if [ ! -f "$build/config.status" ]; then
  rm -rf "$build"
  mkdir -p "$build"
  # The installed binary finds libdispatch and BlocksRuntime in the toolchain it is copied into.
  (cd "$build" && CC=clang CXX=clang++ \
    CPPFLAGS="-isystem $swift -isystem $swift/Block" \
    LDFLAGS="-L$swift/linux -Wl,-rpath,\\\$\$ORIGIN/../lib/swift/linux" \
    "$src/cctools/configure" >/dev/null)
fi
make -C "$build/libstuff" -j "$jobs" >/dev/null
make -C "$build/libmacho" -j "$jobs" >/dev/null
make -C "$build/ld64" -j "$jobs" >/dev/null
# strip prunes the exports trie with prune_trie() (0004-strip-prunes-the-exports-trie.patch), C++
# on ld64's trie code, linked into strip alone.
flags=$(printf 'print-flags:\n\t@echo $(DEFS) $(CXXFLAGS)\n' | make -s -C "$build/misc" -f Makefile -f - print-flags)
eval clang++ "$flags" -D__DARWIN_UNIX03 -I"$src/cctools/include" -I"$src/cctools/include/foreign" -I"$src/cctools/ld64/src" \
  -I"$src/cctools/ld64/src/3rd" -I"$src/cctools/ld64/src/abstraction" -c "$src/cctools/misc/prune_trie.cpp" -o "$build/misc/prune_trie.o"
make -C "$build/misc" -j "$jobs" bitcode_strip libtool lipo >/dev/null
make -C "$build/misc" -j "$jobs" strip LIBS="$build/misc/prune_trie.o -lstdc++" >/dev/null
cp "$build/ld64/src/ld/ld" "$out/ld64"
cp "$build/misc/bitcode_strip" "$out/bitcode_strip"
cp "$build/misc/libtool" "$out/libtool"
cp "$build/misc/strip" "$out/strip"
cp "$build/misc/lipo" "$out/lipo"
# The patches the tools were built with, which `nomac toolchain install` checks against its own.
echo "$stamp" > "$out/cctools.patches.sha256"
mkdir -p "$out/ld64-licenses"
cp "$src/cctools/ld64/APPLE_LICENSE" "$src/cctools/COPYING" "$src/cctools/AUTHORS" "$out/ld64-licenses/"
LD_LIBRARY_PATH="$swift/linux" "$out/ld64" -v 2>&1 | head -1

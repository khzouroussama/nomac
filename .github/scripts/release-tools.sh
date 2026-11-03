#!/bin/bash
# One step of the release-tools workflow (docs/RELEASES.md): runs the step's build script in
# swift:6.4.1-noble with the packages the release downloads were first built with, as the Mac's
# Docker builds did, so the hosted runner's own compilers and libraries play no part.
#
# Usage: release-tools.sh cctools|llvm|swift-frontend|package|nomac|release <dir>
#   <dir>  the folder shared by the steps: tools/ (what the build scripts write), llvm-work/,
#          swift-work/, swift/ (the swift.org toolchain the frontend is built with), dist/ (the tools'
#          archive), nomac-build/ (nomac built with the Swift standard library linked in), release/
# RELEASE_VERSION names the release's archive (release step).
# Runs on the host; it starts the container itself. SOURCE_DATE_EPOCH (default: HEAD's commit
# time) dates the package's entries.
set -euo pipefail
step=$1
dir=$(mkdir -p "$2" && cd "$2" && pwd)
repo=$(cd "$(dirname "$0")/../.." && pwd)
image=swift:6.4.1-noble
tag=swift-6.4.0-RELEASE
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo" log -1 --format=%ct)}

if [ "${RELEASE_TOOLS_IN_CONTAINER:-}" != 1 ]; then
  exec docker run --rm -e RELEASE_TOOLS_IN_CONTAINER=1 -e SOURCE_DATE_EPOCH="$epoch" -e JOBS="$(nproc)" -e RELEASE_VERSION="${RELEASE_VERSION:-}" \
    -v "$repo:/src:ro" -v "$dir:/work" "$image" /src/.github/scripts/release-tools.sh "$step" /work
fi

for attempt in 1 2 3 4 5; do
  apt-get update -q >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
    cmake ninja-build make patch libsqlite3-dev python3 curl ca-certificates rsync xz-utils file uuid-dev patchelf zstd >/dev/null && break
  [ "$attempt" = 5 ] && { echo "error: apt-get failed" >&2; exit 1; }
  sleep 15
done
scripts=/src/.github/scripts
case $step in
  cctools)
    WORK=/work/cctools-work "$scripts/build-cctools.sh" /work/tools ;;
  llvm)
    CLANG=1 WORK=/work/llvm-work "$scripts/build-llvm-tools.sh" /work/tools ;;
  swift-frontend)
    suffix=$([ "$(uname -m)" = aarch64 ] && echo -aarch64 || true)
    if [ ! -x /work/swift/usr/bin/swift-frontend ]; then
      version=${tag#swift-} version=${version%-RELEASE}
      curl -sSfL --retry 5 -o /work/swift.tar.gz \
        "https://download.swift.org/swift-$version-release/ubuntu2404$suffix/$tag/$tag-ubuntu24.04$suffix.tar.gz"
      mkdir -p /work/swift && tar xzf /work/swift.tar.gz -C /work/swift --strip-components=1 && rm /work/swift.tar.gz
    fi
    WORK=/work/swift-work "$scripts/build-swift-frontend.sh" /work/swift/usr "/work/llvm-work/llvm-project-$tag" /work/tools ;;
  package)
    chmod +x /work/tools/{lld,dsymutil,clang,libclang.so,ld64,bitcode_strip,libtool,strip,lipo,swift-frontend,lib_InternalSwiftScan.so}
    "$scripts/package-toolchain.sh" /work/tools "/work/llvm-work/llvm-project-$tag" /work/swift-work/src/swift.orig /work/dist ;;
  nomac)
    rm -rf /work/nomac-src && cp -R /src /work/nomac-src
    swift build -c release --static-swift-stdlib --package-path /work/nomac-src --scratch-path /work/nomac-build
    /work/nomac-build/release/nomac --version ;;
  release)
    "$scripts/package-release.sh" "$RELEASE_VERSION" /work/nomac-build/release /work/dist/nomac-tools-*-linux-*.tar.xz /work/release ;;
  *)
    echo "error: unknown step $step" >&2; exit 64 ;;
esac

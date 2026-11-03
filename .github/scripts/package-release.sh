#!/bin/bash
# Assembles nomac's release download for one Linux architecture (docs/INSTALL.md):
#   nomac-<version>-linux-<arch>/bin/nomac and the resource bundles (*.bundle) SwiftPM writes beside it,
#   tools/ (the contents of package-toolchain.sh's archive), install.sh, NOTICE, LICENSE.
# The archive is reproducible as package-toolchain.sh's is.
#
# Usage: package-release.sh <version> <nomac-build-dir> <tools-archive> <output-dir>
#   <nomac-build-dir>  `swift build -c release --static-swift-stdlib`'s .build/release
#   <tools-archive>    nomac-tools-…-linux-<arch>.tar.xz from package-toolchain.sh
# Writes <output-dir>/nomac-<version>-linux-<arch>.tar.xz and its .sha256.
set -euo pipefail
version=$1
build=$(cd "$2" && pwd)
tools=$3
out=$(mkdir -p "$4" && cd "$4" && pwd)
repo=$(cd "$(dirname "$0")/../.." && pwd)
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)}
case $(od -An -tx1 -j18 -N2 "$build/nomac" | tr -d ' \n') in
  b700) arch=aarch64 ;;
  3e00) arch=x86_64 ;;
  *) echo "error: $build/nomac is not an aarch64 or x86_64 ELF executable" >&2; exit 1 ;;
esac
case $tools in
  *-linux-$arch.tar.xz) ;;
  *) echo "error: $tools is not the tools download for $arch" >&2; exit 1 ;;
esac
name=nomac-$version-linux-$arch
stage=$out/$name
rm -rf "$stage" "$out/$name.tar.xz" "$out/$name.tar.xz.sha256"
mkdir -p "$stage/bin" "$stage/tools"
cp "$build/nomac" "$stage/bin/nomac"
for resources in "$build"/*.bundle; do
  case $resources in *Tests.bundle) continue ;; esac
  cp -R "$resources" "$stage/bin/"
done
ls "$stage"/bin/*.bundle > /dev/null || { echo "error: no resource bundles beside $build/nomac" >&2; exit 1; }
tar xJf "$tools" -C "$stage/tools" --strip-components=1
cp "$repo/install.sh" "$repo/NOTICE" "$repo/LICENSE" "$stage/"
find "$stage" -exec touch -h -d "@$epoch" {} +
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  -C "$out" -cf - "$name" | xz -T0 --block-size=67108864 -6 > "$out/$name.tar.xz"
(cd "$out" && sha256sum "$name.tar.xz" > "$name.tar.xz.sha256")
rm -rf "$stage"
cat "$out/$name.tar.xz.sha256"

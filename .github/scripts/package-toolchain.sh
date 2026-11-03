#!/bin/bash
# Packages the Linux tools `nomac toolchain install --llvm-tools` takes into one release download
# (docs/RELEASES.md): lld and dsymutil, the patched clang and libclang (build-llvm-tools.sh with
# CLANG=1), cctools' ld64, bitcode_strip, libtool, strip and lipo (build-cctools.sh), and the
# patched swift-frontend with its dependency scanner (build-swift-frontend.sh), with their patch
# stamps, the patches themselves and the upstream license texts. It refuses tools whose stamps are
# not this repository's patches. The archive is reproducible: sorted entries, owner 0, every
# mtime $SOURCE_DATE_EPOCH or else the commit time of HEAD, xz with a fixed block size.
#
# Usage: package-toolchain.sh <llvm-tools-dir> <llvm-project-src> <swift-src> <output-dir> [swift-frontend-dir]
#   <llvm-tools-dir>      what build-llvm-tools.sh (CLANG=1) and build-cctools.sh wrote, as /ref/llvm-tools
#   <llvm-project-src>    the llvm-project source the tools were built from (its LICENSE.TXT and
#                         llvm/, clang/ and lld/ LICENSE.TXT are copied)
#   <swift-src>           the swiftlang/swift source swift-frontend was built from (its LICENSE.txt)
#   [swift-frontend-dir]  build-swift-frontend.sh's output, when not already in <llvm-tools-dir>
# Needs GNU tar, xz, sha256sum and od. Writes <output-dir>/<name>.tar.xz and <name>.tar.xz.sha256,
# where <name> is nomac-tools-<swift tag>-<first 8 hex of the stamps' SHA-256>-linux-<arch>.
set -euo pipefail
tools=$(cd "$1" && pwd)
llvm=$(cd "$2" && pwd)
swift=$(cd "$3" && pwd)
out=$(mkdir -p "$4" && cd "$4" && pwd)
frontend=$(cd "${5:-$1}" && pwd)
github=$(cd "$(dirname "$0")/.." && pwd)
tag=$(sed -n 's/^tag=[$]{LLVM_TAG:-\(.*\)}$/\1/p' "$github/scripts/build-llvm-tools.sh")
swift_tag=$(sed -n 's/^tag=[$]{SWIFT_TAG:-\(.*\)}$/\1/p' "$github/scripts/build-swift-frontend.sh")
cctools_commit=$(sed -n 's/^commit=[$]{CCTOOLS_COMMIT:-\(.*\)}$/\1/p' "$github/scripts/build-cctools.sh")
[ "$tag" = "$swift_tag" ] || { echo "error: build-llvm-tools.sh builds $tag but build-swift-frontend.sh $swift_tag" >&2; exit 1; }
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$github" log -1 --format=%ct 2>/dev/null || echo 0)}

files=(lld dsymutil clang libclang.so ld64 bitcode_strip libtool strip lipo)
frontend_files=(swift-frontend lib_InternalSwiftScan.so)
for file in "${files[@]}"; do
  [ -f "$tools/$file" ] || { echo "error: no $file in $tools" >&2; exit 1; }
done
for file in "${frontend_files[@]}" swift-frontend.patches.sha256; do
  [ -f "$frontend/$file" ] || { echo "error: no $file in $frontend" >&2; exit 1; }
done
[ -d "$tools/ld64-licenses" ] || { echo "error: no ld64-licenses in $tools" >&2; exit 1; }

check() {
  local stamp=$1 dir=$2 patches=$3
  local expected built
  expected=$(cat "$github/$patches"/*.patch | sha256sum | cut -d' ' -f1)
  built=$(cat "$dir/$stamp" 2>/dev/null || echo missing)
  [ "$built" = "$expected" ] || { echo "error: $dir/$stamp is $built, but .github/$patches gives $expected: build the tools again" >&2; exit 1; }
  echo "$expected"
}
lld_stamp=$(check lld.patches.sha256 "$tools" lld)
clang_stamp=$(check clang.patches.sha256 "$tools" clang)
cctools_stamp=$(check cctools.patches.sha256 "$tools" cctools)
swift_stamp=$(check swift-frontend.patches.sha256 "$frontend" swift)

case $(od -An -tx1 -j18 -N2 "$tools/lld" | tr -d ' \n') in
  b700) arch=aarch64 ;;
  3e00) arch=x86_64 ;;
  *) echo "error: $tools/lld is not an aarch64 or x86_64 ELF executable" >&2; exit 1 ;;
esac
for file in "${files[@]}"; do
  [ "$(od -An -tx1 -j18 -N2 "$tools/$file" | tr -d ' \n')" = "$(od -An -tx1 -j18 -N2 "$tools/lld" | tr -d ' \n')" ] \
    || { echo "error: $file is not built for $arch as lld is" >&2; exit 1; }
done

combined=$(printf '%s\n' "$lld_stamp" "$clang_stamp" "$cctools_stamp" "$swift_stamp" | sha256sum | cut -c1-8)
name=nomac-tools-$tag-$combined-linux-$arch
stage=$out/$name
rm -rf "$stage" "$out/$name.tar.xz" "$out/$name.tar.xz.sha256"
mkdir -p "$stage/licenses" "$stage/patches"
for file in "${files[@]}" lld.patches.sha256 clang.patches.sha256 cctools.patches.sha256; do
  cp "$tools/$file" "$stage/$file"
done
for file in "${frontend_files[@]}" swift-frontend.patches.sha256; do
  cp "$frontend/$file" "$stage/$file"
done
cp -R "$tools/ld64-licenses" "$stage/ld64-licenses"
cp "$llvm/LICENSE.TXT" "$stage/licenses/llvm-project-LICENSE.TXT"
for project in llvm clang lld; do
  cp "$llvm/$project/LICENSE.TXT" "$stage/licenses/$project-LICENSE.TXT"
done
cp "$swift/LICENSE.txt" "$stage/licenses/swift-LICENSE.txt"
cp "$github/../NOTICE" "$stage/NOTICE"
for patches in lld clang swift cctools; do
  mkdir "$stage/patches/$patches"
  cp "$github/$patches"/*.patch "$stage/patches/$patches/"
done

{
  echo "nomac's Linux tools, for 'nomac toolchain install <swift.org $tag usr> --llvm-tools <this folder>'."
  echo "Architecture: linux-$arch. Built from open-source code with the patches in patches/:"
  echo
  echo "- lld, dsymutil, clang, libclang.so: https://github.com/swiftlang/llvm-project at $tag,"
  echo "  .github/lld and .github/clang (licenses/llvm-project-LICENSE.TXT: Apache-2.0 WITH LLVM-exception)"
  echo "- swift-frontend, lib_InternalSwiftScan.so: https://github.com/swiftlang/swift at $tag, .github/swift,"
  echo "  against the patched llvm-project (licenses/swift-LICENSE.txt: Apache-2.0 WITH Swift-exception)"
  echo "- ld64, bitcode_strip, libtool, strip, lipo: https://github.com/tpoechtrager/cctools-port at"
  echo "  $cctools_commit, .github/cctools (ld64-licenses/: APSL-2.0)"
  echo
  echo "Patch stamps (SHA-256 of each patch directory's patches, in order), which nomac checks:"
  echo "  lld $lld_stamp"
  echo "  clang $clang_stamp"
  echo "  cctools $cctools_stamp"
  echo "  swift-frontend $swift_stamp"
  echo
  echo "Rebuild them with nomac's .github/scripts/build-llvm-tools.sh (CLANG=1), build-cctools.sh and"
  echo "build-swift-frontend.sh. SHA-256 of each file:"
  (cd "$stage" && find . -type f ! -name README.txt | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum | sed 's/^/  /')
} > "$stage/README.txt"

find "$stage" -exec touch -h -d "@$epoch" {} +
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  -C "$out" -cf - "$name" | xz -T0 --block-size=67108864 -6 > "$out/$name.tar.xz"
(cd "$out" && sha256sum "$name.tar.xz" > "$name.tar.xz.sha256")
rm -rf "$stage"
cat "$out/$name.tar.xz.sha256"

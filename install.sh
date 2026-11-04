#!/bin/bash
# Installs nomac's release download on Ubuntu 24.04, arm64 or x86_64 (docs/INSTALL.md): the system
# packages nomac and Swift need, nomac with its patched tools, the swift.org toolchain nomac builds
# apps with, checked against swift.org's signature, and unxip, which expands Xcode.xip.
#
# Usage: install.sh [--prefix <dir>] [<archive>]
#   <archive>  a downloaded nomac-<version>-linux-<arch>.tar.xz; without one, run from an extracted
#              archive it installs that, and otherwise it downloads the release's archive and checks
#              it against its .sha256
#   --prefix   where nomac goes (default ~/.local/share/nomac); nomac is linked into ~/.local/bin
set -euo pipefail

# In a function, so that a download cut short runs nothing, and piped into bash, nothing reads the
# rest of the script as its input.
main() {
version=27.0.3
swift_version=6.4.0
swift="swift-$swift_version-RELEASE"
unxip_version=3.3
unxip_commit=6c3990517fcc4c1db6952fccf4c562fb14097601
repository=https://github.com/khzouroussama/nomac
prefix=$HOME/.local/share/nomac
archive=
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) prefix=$2; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) archive=$1; shift ;;
  esac
done
case $(uname -m) in
  aarch64|arm64) arch=aarch64 suffix=-aarch64 ;;
  x86_64) arch=x86_64 suffix= ;;
  *) echo "error: nomac's downloads are for aarch64 and x86_64 Linux, not $(uname -m)" >&2; exit 1 ;;
esac
[ "$(uname -s)" = Linux ] || { echo "error: this installer is for Linux; on a Mac, build nomac from source (docs/INSTALL.md)" >&2; exit 1; }
sudo=$([ "$(id -u)" = 0 ] && echo || echo sudo)

here=$(cd "$(dirname "$0")" && pwd)
name=nomac-$version-linux-$arch.tar.xz
if [ -z "$archive" ] && ! { [ -x "$here/bin/nomac" ] && [ -d "$here/tools" ]; }; then
  status=$(curl -sIL --retry 3 --retry-all-errors -o /dev/null -w '%{http_code}' "$repository/releases/download/v$version/$name" || true)
  case $status in
    200) ;;
    404)
      echo "error: the release v$version has no download for linux-$arch yet; it comes later." >&2
      echo "Build nomac from source meanwhile: $repository/blob/main/docs/INSTALL.md#building-from-source" >&2
      exit 1 ;;
    *) echo "error: could not reach GitHub for the release v$version (HTTP $status); check the network and run this again." >&2; exit 1 ;;
  esac
fi

echo "==> System packages"
$sudo env DEBIAN_FRONTEND=noninteractive apt-get update -q < /dev/null
$sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libpython3-dev libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata unzip zlib1g-dev \
  curl ca-certificates libsqlite3-0 7zip xz-utils libheif-examples libc++abi1 liblzma-dev < /dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -z "$archive" ] && [ -x "$here/bin/nomac" ] && [ -d "$here/tools" ]; then
  bundle=$here
else
  if [ -z "$archive" ]; then
    echo "==> nomac $version for linux-$arch"
    curl -fL -C - --retry 5 --retry-all-errors -o "$work/$name" "$repository/releases/download/v$version/$name"
    curl -fsSL --retry 5 -o "$work/$name.sha256" "$repository/releases/download/v$version/$name.sha256"
    (cd "$work" && sha256sum -c "$name.sha256")
    archive=$work/$name
  fi
  mkdir "$work/bundle"
  tar xJf "$archive" -C "$work/bundle" --strip-components=1
  bundle=$work/bundle
fi

echo "==> Swift ($swift), which nomac builds apps with"
url=https://download.swift.org/swift-$swift_version-release/ubuntu2404$suffix/$swift/$swift-ubuntu24.04$suffix.tar.gz
curl -fL -C - --retry 5 --retry-all-errors -o "$work/swift.tar.gz" "$url"
curl -fsSL --retry 5 -o "$work/swift.tar.gz.sig" "$url.sig"
export GNUPGHOME=$work/gnupg
mkdir -m 700 "$GNUPGHOME"
# swift.org serves its keys gzip-compressed without saying so (no Content-Encoding).
curl -fsSL --retry 5 -o "$work/keys" https://www.swift.org/keys/all-keys.asc
if [ "$(od -An -tx1 -N2 "$work/keys" | tr -d ' \n')" = 1f8b ]; then
  gzip -dc "$work/keys" > "$work/keys.asc"
else
  mv "$work/keys" "$work/keys.asc"
fi
gpg --quiet --import "$work/keys.asc"
gpg --quiet --verify "$work/swift.tar.gz.sig" "$work/swift.tar.gz"

echo "==> Installing into $prefix"
mkdir -p "$prefix" "$HOME/.local/bin"
rm -rf "${prefix:?}/bin" "${prefix:?}/tools" "${prefix:?}/swift"
cp -R "$bundle/bin" "$bundle/tools" "$prefix/"
cp "$bundle/NOTICE" "$bundle/LICENSE" "$prefix/"
mkdir "$prefix/swift"
tar xzf "$work/swift.tar.gz" -C "$prefix/swift" --strip-components=1
ln -sf "$prefix/bin/nomac" "$HOME/.local/bin/nomac"

echo "==> unxip $unxip_version, which expands Xcode.xip"
mkdir "$work/unxip"
if curl -fsSL --retry 5 --retry-all-errors -o "$work/unxip.tar.gz" "https://github.com/saagarjha/unxip/archive/$unxip_commit.tar.gz" 2>"$work/unxip.log" \
   && tar xzf "$work/unxip.tar.gz" -C "$work/unxip" --strip-components=1 \
   && (cd "$work/unxip" && "$prefix/swift/usr/bin/swift" build -c release --product unxip) >>"$work/unxip.log" 2>&1; then
  cp "$work/unxip/.build/release/unxip" "$prefix/bin/unxip"
  ln -sf "$prefix/bin/unxip" "$HOME/.local/bin/unxip"
else
  tail -5 "$work/unxip.log" >&2
  echo "warning: unxip did not build, so 'nomac sdk install' takes an Xcode.app but not a .xip; 'nomac doctor' prints how to install it." >&2
fi

"$prefix/bin/nomac" --version

cat <<EOF

nomac is installed ($HOME/.local/bin/nomac; add $HOME/.local/bin to PATH if it is not there). Next:
  nomac sdk install <your Xcode_27.xip or Xcode.app>
  nomac toolchain install
  nomac doctor
EOF
}

main "$@"

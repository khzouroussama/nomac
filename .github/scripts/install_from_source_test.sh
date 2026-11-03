#!/bin/bash
# Runs docs/INSTALL.md's "Building from source" block as written, on a fresh Ubuntu 24.04 (the
# quickstart workflow's container), then the online step of README's Quick start (the sample's clone). Two changes only: the
# repository is this checkout rather than a clone, and on x86_64 the Swift downloads lose their
# -aarch64 suffix, as the README's comment says. Runs as root in a fresh container.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
block=$(awk '/^## Building from source$/ {install=1} install && /^```sh$/ {code=1; next} code && /^```$/ {exit} code' "$repo/docs/INSTALL.md")
[ -n "$block" ] || { echo "error: no sh block under docs/INSTALL.md's Building from source" >&2; exit 1; }
grep -q '^git clone https://github.com/khzouroussama/nomac && cd nomac$' <<< "$block" \
  || { echo "error: the block no longer clones the repository as this test expects" >&2; exit 1; }
block=${block//"git clone https://github.com/khzouroussama/nomac && cd nomac"/"cd \"$repo\""}
[ "$(uname -m)" = aarch64 ] || block=${block//-aarch64/}
# What an installed Ubuntu already has: sudo, and a configured time zone (tzdata asks otherwise).
apt-get update -q >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -q sudo tzdata >/dev/null
cd ~
bash -euxo pipefail -c "$block"
cd ~ && git clone -q https://github.com/nicklockwood/RetroRampage && git -C RetroRampage log -1 --format='RetroRampage %h'

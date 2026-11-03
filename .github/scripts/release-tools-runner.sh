#!/bin/bash
# Makes room on a GitHub-hosted Linux runner for the LLVM and Swift builds of release-tools.sh:
# about 14 GB are free on a fresh runner, less than the sources and builds take, and linking clang in four
# jobs at once can exceed its 16 GB of memory. Removes the preinstalled SDKs nomac's builds never
# use and adds 8 GB of swap.
set -euo pipefail
df -h / | tail -1
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache /usr/share/swift \
  /usr/local/share/powershell /usr/local/share/chromium /usr/local/lib/node_modules
sudo docker image prune -a -f >/dev/null
sudo fallocate -l 8G /swapfile-release && sudo chmod 600 /swapfile-release && sudo mkswap /swapfile-release >/dev/null && sudo swapon /swapfile-release
df -h / | tail -1
free -g | head -2

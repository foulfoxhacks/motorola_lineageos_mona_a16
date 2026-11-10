#!/usr/bin/env bash
#
# Ubuntu 24.04 build dependencies for LineageOS 24.0 / AOSP 17.
# Fixes the handoff doc's list (JDK 17 -> 21, adds libncurses-dev, libssl-dev, dtc, ...).
#
# Run inside WSL2:
#   bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/wsl-deps.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

echo "==> apt update"
apt update

echo "==> installing build dependencies"
apt install -y \
  git gnupg flex bison build-essential \
  zip unzip curl wget rsync ccache bc \
  zlib1g-dev libc6-dev-i386 lib32z1-dev \
  libncurses-dev libssl-dev libelf-dev \
  libgl1-mesa-dev libxml2-utils xsltproc fontconfig \
  lz4 liblz4-tool bzip2 \
  device-tree-compiler imagemagick \
  tmux \
  openjdk-21-jdk-headless \
  python3 python3-pip python3-venv python3-protobuf \
  protobuf-compiler \
  android-sdk-libsparse-utils

# `repo` from Ubuntu is often stale; use Google's launcher if missing
if ! command -v repo >/dev/null 2>&1; then
  echo "==> installing repo launcher"
  mkdir -p /usr/local/bin
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
    -o /usr/local/bin/repo
  chmod a+x /usr/local/bin/repo
fi

# repo/git want an identity; set it for the real user, not root
TARGET_USER="${SUDO_USER:-$USER}"
if ! sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "==> setting a git identity for $TARGET_USER"
  sudo -u "$TARGET_USER" git config --global user.name  "lineage builder"
  sudo -u "$TARGET_USER" git config --global user.email "builder@localhost"
fi

echo
echo "==> versions"
java -version 2>&1 | head -1
python3 --version
repo --version 2>/dev/null | head -1 || true

echo
echo "==> done."
echo "Next: check disk space, then run scripts/lineage-sync.sh"
echo "   df -h ~"

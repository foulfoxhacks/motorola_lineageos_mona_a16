#!/usr/bin/env bash
#
# repo init + sync for mona (lineage-24.0), with the local manifest applied.
#
#   bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/lineage-sync.sh
#
# NOTE: must live on ext4 (e.g. ~/lineage), never under /mnt/c.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/lineage}"
BRANCH="${BRANCH:-lineage-24.0}"
# `-j` is how many projects are fetched at once, NOT CPU jobs. Each fetch is
# mostly network wait, so going above nproc is usually faster. Override with
# JOBS=32 bash lineage-sync.sh (memory cost is roughly 100 MB per slot).
JOBS="${JOBS:-16}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$SRC_DIR" in
  /mnt/*) echo "ERROR: $SRC_DIR is on DrvFs. Use a path under \$HOME." >&2; exit 1 ;;
esac

mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

echo "==> repo init ($BRANCH)"
repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs

echo "==> local manifest"
mkdir -p .repo/local_manifests
cp "$HERE/../local_manifests/mona.xml" .repo/local_manifests/mona.xml

echo "==> repo sync"
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags

echo
echo "==> synced into $SRC_DIR"
echo "Next: extract blobs (docs/BUILD.md section 4), then:"
echo "   source build/envsetup.sh && breakfast mona && mka bacon -j\$(nproc)"

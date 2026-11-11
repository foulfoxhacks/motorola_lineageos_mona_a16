#!/usr/bin/env bash
#
# Extract vendor blobs from the stock firmware into
#   vendor/motorola/mona  and  vendor/motorola/sm6475-common
#
#   bash scripts/extract-blobs.sh
#
# extract-files.py (extract-utils) does the whole job: it finds the 25
# super.img_sparsechunk.* files, sorts them numerically, unsparses them into
# super.img, splits the logical partitions, unpacks ext4 with debugfs and erofs
# with fsck.erofs, then copies the files listed in proprietary-files.txt.
#
# IMPORTANT: it works inside its source directory and DELETES what it consumes
# (the sparse chunks, then the partition images). Pointing it at the firmware
# folder on /mnt/c would destroy the restore source, so the folder is mirrored
# to ext4 first and only the copy is touched.
#
# The mirror is rebuilt on every run (rsync --delete). That is deliberate:
# a previous run consumed super.img_sparsechunk.*, vendor.img, system_ext.img
# and recovery.img, so "resuming" a half-finished dump would silently extract
# nothing. Re-copying 8.9 GB takes ~1 minute on this disk.
set -euo pipefail

FW="${FW:-/mnt/c/mona_firmware/W1VAS36/MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml}"
WORK="${WORK:-$HOME/work/fw}"
SRC="${SRC:-$HOME/lineage}"
DEVICE="$SRC/device/motorola/mona"
LOG="${LOG:-$HOME/work/extract.log}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Never let a mistyped WORK turn `rsync --delete` loose on $HOME or /.
case "$WORK" in
    "$HOME"/*) : ;;
    *) die "refusing WORK='$WORK' (must live under \$HOME)" ;;
esac

[ -d "$FW" ]                      || die "firmware folder not found: $FW"
[ -x "$DEVICE/extract-files.py" ] || die "missing $DEVICE/extract-files.py"
command -v fsck.erofs >/dev/null  || die "fsck.erofs missing (sudo apt install erofs-utils)"
command -v debugfs    >/dev/null  || die "debugfs missing (sudo apt install e2fsprogs)"
command -v rsync      >/dev/null  || die "rsync missing (sudo apt install rsync)"

# cpio unpacks the recovery ramdisk. Without it the extractor warns
# "Failed to find executable path for: cpio" and skips the partition.
if ! command -v cpio >/dev/null 2>&1; then
    echo "==> installing cpio (needed to unpack recovery)"
    sudo -n apt-get install -y cpio || die "cpio missing and sudo failed; run: sudo apt install -y cpio"
fi

# extract-files.py shells out to prebuilts/clang/.../llvm-binutils-stable/llvm-objdump
# for the GraphicBuffer size fixup. A missing prebuilt kills the whole run.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -x "$SRC/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-objdump" ]; then
    bash "$HERE/fix-extract-tools.sh"
fi

mkdir -p "$WORK" "$(dirname "$LOG")"

echo "==> mirroring firmware into $WORK (clean copy, ~8.9 GB)"
echo "    the extractor rewrites this copy; the /mnt/c original is never touched"
rsync -a --delete --info=progress2 "$FW/" "$WORK/"

echo
echo "==> extracting blobs (missing-file warnings are expected)"
echo "    full log: $LOG"
cd "$DEVICE"
set +e
./extract-files.py "$WORK" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

echo
if [ "$rc" -ne 0 ]; then
    echo "==> extract-files.py FAILED (exit $rc). Last 40 lines:" >&2
    tail -40 "$LOG" >&2
    exit "$rc"
fi

echo "==> vendor trees"
du -sh "$SRC/vendor/motorola/mona" "$SRC/vendor/motorola/sm6475-common" 2>/dev/null || true

echo
echo "==> staging stock device trees (DTB + DTBO)"
FW="$FW" SRC="$SRC" bash <(tr -d '\r' < "$HERE/extract-dt.sh")

missing=$(grep -c 'warning.*[Nn]ot found\|Failed to extract' "$LOG" || true)
echo
echo "==> warnings: ${missing:-0} (see $LOG)"

echo
echo "Next:"
echo "  cd $SRC && source build/envsetup.sh && lunch lineage_mona-userdebug"

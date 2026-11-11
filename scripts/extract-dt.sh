#!/usr/bin/env bash
# extract-dt.sh - stage the STOCK device trees (DTB + DTBO) from your firmware.
#
#   bash scripts/extract-dt.sh
#
# Why: no public source exists for mona's board device trees. LineageOS's
# sm6475-devicetrees is Qualcomm reference code (parrot QRD/IDP, no moto,mona
# overlay), and Motorola's kernel drop leaves out arch/arm64/boot/dts/vendor. So the
# build packages the stock DTB (from vendor_boot.img) and the stock dtbo.img
# (mona BoardConfig.mk: BOARD_PREBUILT_DTBIMAGE_DIR / BOARD_PREBUILT_DTBOIMAGE).
#
# Output goes to $SRC/vendor/motorola/mona-dt/, a separate folder because
# extract-files.py empties vendor/motorola/mona on every run. Nothing is
# redistributed; it comes from your own firmware, like the blobs.
set -euo pipefail

FW="${FW:-/mnt/c/mona_firmware/W1VAS36/MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml}"
SRC="${SRC:-$HOME/lineage}"
DST="$SRC/vendor/motorola/mona-dt"
UNPACK="$SRC/system/tools/mkbootimg/unpack_bootimg.py"

die() { echo "ERROR: $*" >&2; exit 1; }
[ -f "$FW/vendor_boot.img" ] || die "no vendor_boot.img in $FW (set FW=...)"
[ -f "$FW/dtbo.img" ]        || die "no dtbo.img in $FW (set FW=...)"
[ -f "$UNPACK" ]             || die "missing $UNPACK (is SRC=$SRC a synced tree?)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -I "$UNPACK" --boot_img "$FW/vendor_boot.img" --out "$tmp" >/dev/null
[ -s "$tmp/dtb" ] || die "vendor_boot.img has no DTB section"

magic() { od -An -tx1 -N4 "$1" | tr -d ' \n'; }
[ "$(magic "$tmp/dtb")" = "d00dfeed" ]     || die "extracted DTB has a bad magic ($(magic "$tmp/dtb"))"
[ "$(magic "$FW/dtbo.img")" = "d7b7ab1e" ] || die "dtbo.img has a bad magic ($(magic "$FW/dtbo.img"))"

mkdir -p "$DST/dtb"
cp -f "$tmp/dtb" "$DST/dtb/stock.dtb"
cp -f "$FW/dtbo.img" "$DST/dtbo.img"
echo "staged stock device trees in $DST:"
ls -la "$DST/dtb/stock.dtb" "$DST/dtbo.img" | awk '{print "  " $5 "  " $NF}'

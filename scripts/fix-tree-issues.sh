#!/usr/bin/env bash
#
# Fix known device tree issues for mona (XT2517-1) before building.
#
#   bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/fix-tree-issues.sh
#
set -euo pipefail

MONA="${SRC:-$HOME/lineage}/device/motorola/mona"

[ -f "$MONA/device.mk" ] || { echo "ERROR: $MONA/device.mk not found"; exit 1; }

echo "==> Fixing PRODUCT_SHIPPING_API_LEVEL: 34 -> 35"
sed -i 's/PRODUCT_SHIPPING_API_LEVEL := 34/PRODUCT_SHIPPING_API_LEVEL := 35/' "$MONA/device.mk"

echo "==> Renaming SKU prop: XT2405V -> XT2517-1"
if [ -f "$MONA/props/hardware.sku.XT2405V.prop" ]; then
    mv "$MONA/props/hardware.sku.XT2405V.prop" "$MONA/props/hardware.sku.XT2517-1.prop"
    echo "    renamed props/hardware.sku.XT2405V.prop -> hardware.sku.XT2517-1.prop"
elif [ -f "$MONA/props/hardware.sku.XT2517-1.prop" ]; then
    echo "    already renamed"
else
    echo "    WARNING: neither XT2405V nor XT2517-1 prop file found"
fi

echo "==> Updating IMEI SV: 17 -> 34"
sed -i 's/ro.vendor.radio.imei.sv=17/ro.vendor.radio.imei.sv=34/' "$MONA/props/hardware.sku.XT2517-1.prop"

echo "==> Updating Android.bp: XT2405V -> XT2517-1"
sed -i 's/hardware\.sku\.XT2405V\.prop/hardware.sku.XT2517-1.prop/g' "$MONA/props/Android.bp"

echo "==> Updating device.mk package reference: XT2405V -> XT2517-1"
sed -i 's/hardware\.sku\.XT2405V\.prop/hardware.sku.XT2517-1.prop/g' "$MONA/device.mk"

echo
echo "==> Verification"
echo
echo "[device.mk]"
grep -n 'SHIPPING_API_LEVEL\|hardware\.sku\|XT25' "$MONA/device.mk" || true
echo
echo "[props/Android.bp]"
cat "$MONA/props/Android.bp"
echo
echo "[props/hardware.sku.XT2517-1.prop]"
cat "$MONA/props/hardware.sku.XT2517-1.prop"
echo
echo "[stale XT2405 check]"
if grep -rn 'XT2405' "$MONA/" 2>/dev/null; then
    echo "WARNING: stale XT2405 references remain!"
else
    echo "clean -- no XT2405 references"
fi

# patches — local changes on top of upstream LineageOS `lineage-24.0`

The published `mona` trees target a different firmware build (`W1UANS36H.29-25-2-6`). These
patches adapt them to the stock firmware this port extracts blobs from:
**`W1VAS36.62-22-16-1-18`** (T-Mobile subsidy `mona_g`). Its vendor partition is an Android 15 / 202404 freeze.

They are plain `git diff` patches, applied with `git apply`. Every one was checked to apply cleanly to the
upstream base commit below and to match the working tree it was exported from.

| Project | Upstream base commit | Patch |
|---|---|---|
| `device/motorola/mona` | `b41432100a054e1e47cb05e874e5154faa1c47ac` "mona: Inherit from sm6475-common" | `0001-mona-adapt-to-W1VAS36-firmware.patch` |
| `device/motorola/sm6475-common` | `a0fe3968b045102f9892c27e5ecc611972eab49f` "sm7435-common: Rebrand to sm6475-common" | `0001-sm6475-common-adapt-to-W1VAS36-firmware.patch` |
| `kernel/motorola/sm6475-modules` | `47a594be4cde8ec4685416e8b3d58c36939c3945` | `0001-modules-fix-soong-namespace-import.patch` |

## Apply

```bash
bash scripts/apply-patches.sh            # SRC defaults to ~/lineage
SRC=/path/to/lineage bash scripts/apply-patches.sh
```

The script is idempotent: it skips a patch that is already applied and stops on the first one
that does not apply. It never resets or discards anything in your tree.

## What they change

**`device/motorola/mona`**
- `device.mk`: `PRODUCT_SHIPPING_API_LEVEL` 34 → 35 (the device shipped on Android 15). The SKU prop
  file changes from `XT2405V` (2024 model) to `XT2517-1`.
- `props/hardware.sku.XT2517-1.prop` (new) with `ro.vendor.radio.imei.sv=34`; `props/Android.bp` is updated to match.
- `extract-files.py`:
  - soong namespace `sm8450` → `sm8450-6.6`.
  - New blob fixups: graphics allocator V1→V2 (`libcamximageformatutils`, `camera.postproc@1.0-service-impl`)
    and biometrics fingerprint V3→V4 (Goodix fingerprint service).
- `proprietary-files.txt` / `proprietary-files-carriersettings.txt`: entries removed for blobs that do not exist in
  W1VAS36 (alternate camera sensors, SNPE, ArcSoft, some touch firmware, unused carrier settings).

**`device/motorola/sm6475-common`**
- `extract-files.py`: namespace `sm8450-6.6`. New fixups for `libwfdmmsrc_proprietary` (audio.common.types V2→V3)
  and keymint `rkp-V1` → `rkp-V3`.
- `proprietary-files.txt`: about 200 entries removed (absent from this firmware) and about 110 added. The additions
  are AIDL `-V1-ndk` service libs, libheif, DxHdcp, nicm, camera.postprocess, wifidisplaysession, bluetooth_sar,
  Moto sensors, 24 qcrilNr/radio AIDL libs, ATFWD, and the qcril SQL files under their stock names.

**`kernel/motorola/sm6475-modules`**
- `Android.bp`: the soong namespace import pointed at `kernel/qcom/sm8450`, which does not exist. It now
  imports `kernel/motorola/sm6475`.

## Plan

These are a stop-gap so the work is public and reproducible. Once the tree builds, the plan is to fork
`android_device_motorola_mona` and `android_device_motorola_sm6475-common` under `foulfoxhacks`,
commit these as proper changes, and point `local_manifests/mona.xml` at the forks.

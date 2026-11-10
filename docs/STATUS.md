# STATUS — verified state

Last verified: **2026-11-10**. Everything below was checked against the build tree, the firmware
package, or GitHub. None of it is copied from older notes.

**Active work: Lane 2, a from-source `lineage-24.0` build for `mona`.** Lane 1 (the GSI) is closed.

---

## 1. Where the build is

| Stage | State |
|---|---|
| `repo sync` lineage-24.0 (manifest `e4b71068`, 2026-11-03, 1245 projects) | ✅ complete. Exception: `device/generic/car` checkout is broken (see E1). |
| Local manifest (`local_manifests/mona.xml`, 6 projects) | ✅ in place |
| Tree adaptations for W1VAS36 firmware | ✅ done; exported to `patches/` |
| Blob extraction (`vendor/motorola/{mona,sm6475-common}`) | ✅ complete: 3550 + 819 files, 0 listed entries missing |
| `breakfast mona` (lunch `lineage_mona-cp2a-userdebug`, PLATFORM_VERSION 17, `CP2A.260605.016`) | ✅ product config resolves |
| Soong analysis | ❌ **fails: 4 AIDL version conflicts (B1–B4)** |
| Kati / ninja / compile | not reached yet |
| Boot on hardware | not reached yet |

### Why AIDL conflicts are the main blocker

The stock **vendor** partition is an **Android 15 freeze** (`VVAS35V-W1-ST15.1.1`, `ro.board.api_level=202404`),
even though the phone reports Android 16. Its blobs link old AIDL versions; the Android 17 system
links newer ones. Soong refuses any module that ends up depending on two versions of one AIDL interface.
Each conflict is fixed with an `extract-files.py` blob fixup (`replace_needed` / `remove_needed`), or by
building the AOSP module instead of the blob.

## 2. Current blockers

All four come from the last build (2026-11-09 13:34), and all are soong `depends on multiple versions
of the same aidl_interface` errors. There are no undefined-module errors left.

| # | Module | Conflict | Proposed fix |
|---|---|---|---|
| B1 | `com.qti.chi.override` (mona) | `graphics.allocator` V1 + V2 (blob NEEDs both) | blob fixup on `vendor/lib64/hw/com.qti.chi.override.so`: `.remove_needed('android.hardware.graphics.allocator-V1-ndk.so')`. Apply the same to `vendor/lib64/camera/components/com.qti.node.dewarp.so`, which will fail next. |
| B2 | `libcamera2ndk_vendor` (mona) | `cameraservice.device/service` V2 (blob) vs V3 (AOSP) | Drop the blob from `proprietary-files.txt` so the AOSP module is built, **or** `replace_needed` V2 → V3 |
| B3 | `libqcodec2_core` (sm6475-common) | `graphics.common` V5 (blob) vs V7 (via `libgralloctypes`) | `blob_fixup().replace_needed('android.hardware.graphics.common-V5-ndk.so', 'android.hardware.graphics.common-V7-ndk.so')` |
| B4 | `libwfdservice` (sm6475-common) | `audio.common.types-cpp` V4 vs V5 | A fixup already exists but is **skipped**: the WFD block (26 entries) is pinned to upstream SHA1s that do not match W1VAS36, so extract-utils treats the files as mismatched and skips fixups. Remove the `\|sha1\|sha1` pins (or extract with `--kang`), then re-extract. |

After these, re-extract and rebuild. Expect more of the same kind, then the Kati, `check_elf_files`,
VINTF and sepolicy stages, none of which have run yet.

## 3. Environment issues

| # | Issue | Fix |
|---|---|---|
| E1 | `device/generic/car` never finished checking out (no index, 253/331 files missing) → VehicleEmulator undefined. It was worked around by hand-gutting `system/software_defined_vehicle/samples/vhal_proxy/sdv_emulated_vhal/Android.bp`. | `repo sync -l device/generic/car` (or `git -C device/generic/car checkout -f`), then revert the hack: `git -C system/software_defined_vehicle/samples checkout .` That hack is **not** in `patches/` on purpose. |
| E2 | Memory: WSL has 9.7 GB; `soong_build` peaked at 9.5 GB, with memory-stall warnings | Raise `.wslconfig` to `memory=16GB` (or more) and `swap=32GB`; keep `-j4` until then |
| E3 | `~/lineage/run_build.sh` is a stray, truncated copy at the tree root | delete it; use `scripts/run_build.sh` |

## 4. Next steps

1. Fix E1 and E2.
2. Fix B1–B4 in `extract-files.py` / `proprietary-files.txt`. Re-extract with `scripts/extract-blobs.sh`.
3. `mka bacon` until soong, Kati and ninja pass. Export each fix as a patch.
4. Fork `android_device_motorola_mona` and `sm6475-common` under `foulfoxhacks`, move `patches/` into
   real commits, and point `local_manifests/mona.xml` at the forks.
5. First boot. Have `RESTORE-STOCK.md` open.
6. After a stable boot: start `HARDENING.md` Phase 1.

---

## 5. Device facts (verified on hardware and firmware)

| Property | Value |
|---|---|
| Product / device | `mona_g` (T-Mobile subsidy SKU) / `mona` |
| Model | XT2517-1 |
| SoC | SM6475 / Snapdragon 6 Gen 3. Qualcomm **`parrot`** platform (`ro.board.platform=parrot`), msm-id 0x297 |
| Shipped Android | 15 (`V2VAS35.29-59-4`, kernel 6.6.50) |
| Current firmware | `W1VAS36.62-22-16-1-18`: Android 16 system on an **Android 15 / 202404 vendor** |
| Kernel | GKI `6.6.118-android15-8`, 4 KiB pages |
| Bootloader | unlocked: `securestate=flashing_unlocked`, `verifiedbootstate=orange` |
| Slots | A/B, Virtual A/B (compressed), dynamic partitions |
| Partition sizes | boot 96 MiB, init_boot 8 MiB, vendor_boot 96 MiB, dtbo 24 MiB, recovery 128 MiB, super 9,840 MiB |
| Filesystems | all logical partitions erofs; no `odm` partition; userdata f2fs + FBE (wrapped keys) |
| Device tree identity | `ro.vendor.product.display=moto g stylus - 2025` |

Full firmware breakdown: `FIRMWARE.md`.

---

## 6. GrapheneOS: what is and isn't possible

GrapheneOS itself cannot run here. It is built for specific Pixel hardware and requires a relockable
bootloader with a custom verified-boot key, which Motorola does not provide. Its device support,
`adevtool` pipeline, verified-boot model and hardened kernel all assume that hardware.

What *is* achievable is **LineageOS with GrapheneOS-derived hardening**: kernel hardening flags,
`hardened_malloc`, and selected framework features such as the network permission toggle, auto-reboot
and PIN scrambling. That is the long-term goal of this repo, staged in `HARDENING.md`.

---

## 7. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-11-08 | GrapheneOS-derived hardening, not a GrapheneOS port | GrapheneOS's security model needs hardware/bootloader support `mona` lacks; individual features are portable |
| 2026-11-08 | Root via Magisk on `init_boot` | Confirmed method for XT2517-1; reversible |
| 2026-11-08 | A16 path = GSI; source path = lineage-24.0 | No A16 (`lineage-23.2`) device tree exists |
| 2026-11-08 | eSIM blocked on the GSI: no eUICC/LPA service | `dumpsys euicc` → service not found |
| 2026-11-08 | GMS GSI abandoned: does not fit `system_a` | 3.13 GiB image vs 2.55 GiB `system_a` |
| 2026-11-08 | Stock restore verified: 5G + data on eSIM | Hardware, eUICC and modem are fine; the GSI telephony stack was at fault |
| 2026-11-08 | **Lane 1 (GSI) closed; Lane 2 (source) is the project** | GSI cannot provide working eSIM |
| 2026-11-09 | Adapt tree to W1VAS36 instead of hunting W1UANS36H firmware | The tree pins `W1UANS36H.29-25-2-6`; the W1VAS36 firmware is what's available. Missing blobs trimmed, new ones added |
| 2026-11-10 | Publish tree changes as `patches/` now, forks later | They existed only as uncommitted edits in WSL; one `repo sync --force-sync` could lose them |

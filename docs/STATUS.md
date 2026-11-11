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
| Soong analysis | ✅ **passes with no errors** (2026-11-10, 2 h 53 m on a 10 GB WSL). It wrote `make_vars`/`late`/`installs-lineage_mona.mk`, then was killed by SIGHUP from a closed terminal while writing the ninja file. Re-running detached in tmux (`scripts/start-build.sh`). |
| Kati | ✅ passes (2026-11-10 13:45), including packaging rules and the license/SBOM check. It had failed at 08:38 on 4 non-existent `PRODUCT_PACKAGES` (legacy HIDL audio HAL + `MotoNrEnabler`), fixed by switching to the AIDL audio HAL (`patches/*/0003`). |
| ninja / compile | ⏳ restarted after the kernel-stage fixes below |

### Kernel stage (2026-11-10)

1. `run_build.sh` set `NINJA_ARGS="-j4"`. lineage-24.0 executes with **siso**, which rejects it (`flag provided but not defined: -j4`). ✅ Removed.
2. The kernel config named the 5.10-era fragment `vendor/parrot_GKI.config` and two Motorola `ext_config` fragments. None of them exist in the LineageOS 6.6 kernel. ✅ `patches/device/motorola/sm6475-common/0004`: `gki_defconfig` + `vendor/parrot_perf.config` (msm-kernel 6.6 naming, the fragment Motorola's own parrot build uses). Motorola's fragments only set symbols this kernel doesn't define. Also dropped `cvp-kernel`/`eva-kernel`, which are not in `sm6475-modules` and not on stock.
3. ✅ **35 Motorola driver dirs were missing** (`motorola/drivers/...`: touch, fingerprint, stylus, charger, sensors, NFC, …). LineageOS's `sm6475-modules` has no `motorola/` directory; its parent `sm7435-modules` does. Added Motorola's own release for exactly this firmware, `MotorolaMobilityLLC/motorola-kernel-modules` at tag `MMI-W1VAS36.62-22-16-16` (commit `78c22b4`). It goes into `local_manifests/mona.xml` at `kernel/motorola/sm6475-modules/motorola`. All 51 external module dirs now resolve.
4. ✅ Touch over SPI: `goodix_berlin_mmi` compiles its SPI bus code only with `CONFIG_TOUCHSCREEN_GOODIX_BRL_SPI`. Motorola sets that from their device makefiles, which LineageOS doesn't use. `patches/device/motorola/mona/0004` passes it through `TARGET_KERNEL_ADDITIONAL_FLAGS`.
   **To verify at first boot:** the touch driver's other feature flags (`DRM_PANEL_EVENT_NOTIFICATIONS`, `GTP_ENABLE_PM_QOS`, `GOODIX_ESD_ENABLE`, FOD) are off. Compare with the stock `goodix_brl_mmi.ko` (`modinfo`/`strings`) if touch suspend/resume or gestures misbehave.
5. ✅ `mona/BoardConfig.mk` added one more missing fragment (`vendor/ext_config/moto-parrot-mona.config`), and it failed at 18:45. Removed.
6. ✅ **Device trees.** No public source exists for mona's board DTS. LineageOS `sm6475-devicetrees` is Qualcomm reference code (parrot QRD/IDP, no `moto,mona` overlay), and Motorola's kernel drop omits `dts/vendor`. Separately, the kernel's `dts/vendor` symlink points at a non-existent `sm8750-devicetrees`. That is harmless: the dts Makefile then builds only the upstream DTs.
   → `patches/device/motorola/mona/0005` packages the **stock** DTB (2 DTBs, parrot + parrot-lite, from `vendor_boot.img`) and the stock `dtbo.img`. `scripts/extract-dt.sh` stages them from your own firmware into `vendor/motorola/mona-dt`, and `extract-blobs.sh` runs it automatically.
7. ✅ **Motorola driver build paths.** 225 of Motorola's Kbuild/Makefiles assume their own source layout (`$(ANDROID_BUILD_TOP)/motorola/kernel/modules`, `$(TOP)/…`, `…/kernel/drivers/base`). `patches/kernel/motorola/sm6475-modules/motorola/0001` rewrites them to `$(KERNEL_SRC)/../sm6475-modules/motorola` and `$(KERNEL_SRC)/drivers/base`. This is the same approach LineageOS's `sm7435-modules` fork uses. Cross-module `Module.symvers` paths were already relative.

Rebuild started 2026-11-10 20:05. The `BoardConfig` change triggers another ~3.5 h soong analysis, then Kati, then the first kernel + module compile.
| Boot on hardware | not reached yet |

### Why AIDL conflicts are the main blocker

The stock **vendor** partition is an **Android 15 freeze** (`VVAS35V-W1-ST15.1.1`, `ro.board.api_level=202404`),
even though the phone reports Android 16. Its blobs link old AIDL versions; the Android 17 system
links newer ones. Soong refuses any module that ends up depending on two versions of one AIDL interface.
Each conflict is fixed with an `extract-files.py` blob fixup (`replace_needed` / `remove_needed`), or by
building the AOSP module instead of the blob.

## 2. AIDL version conflicts: fixed (2026-11-10)

The 2026-11-09 build stopped on four soong `depends on multiple versions of the same aidl_interface`
errors. All four are fixed in `patches/device/motorola/*/0002-*.patch`. The blobs were re-extracted and each fix
was verified in the resulting ELF `NEEDED` entries:

| # | Module | Conflict | Fix (verified) |
|---|---|---|---|
| B1 | `com.qti.chi.override` + `com.qti.node.dewarp` (mona) | `graphics.allocator` V1 + V2 in one blob | `remove_needed` V1 → both now NEED only V2 |
| B2 | `libcamera2ndk_vendor` (mona) | `cameraservice.device/service` V2 (blob) vs V3 (AOSP) | blob dropped; AOSP module built via `PRODUCT_PACKAGES` (no other blob links it) |
| B3 | `libqcodec2_core` (sm6475-common) | `graphics.common` V5 vs V7 (via `libgralloctypes`) | `replace_needed` V5 → V7 |
| B4 | `libwfdservice` (sm6475-common) | `audio.common.types-cpp` V4 vs V5 | WFD block unpinned. The pins mismatched W1VAS36, which made extract-utils **skip** the existing V4→V5 fixup. Now NEEDs V5; the `WfdCommon.jar` apktool patch also applies. |

A scan of all 4,400 extracted ELF blobs found no other blob linking two versions of one AIDL interface.
Further conflicts can still come from AOSP modules mixing with blobs, and the Kati, `check_elf_files`,
VINTF and sepolicy stages have not run yet.

### Open risk: no `init_boot` image

The tree's `AB_OTA_PARTITIONS` (sm6475-common) has `boot`, `dtbo`, `recovery`, `vendor_boot`, `vbmeta*` and the
super partitions, but **no `init_boot`**, and there is no `BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE`. The device ships
its generic ramdisk in `init_boot`, so LineageOS will boot with whatever `init_boot` is already on the phone. Until
that is resolved, the install uses **stock** `init_boot` on both slots (`RUNBOOK.md` step 3.2), never a
Magisk-patched one. If first boot fails in first-stage init, building `init_boot` is the first thing to try.

## 3. Environment issues

| # | Issue | State |
|---|---|---|
| E1 | `device/generic/car` was never fully checked out: a stale `index.lock` from the interrupted sync, and every file staged as deleted. That caused `VehicleEmulator` undefined, which was worked around by gutting an SDV `Android.bp`. | ✅ fixed: lock removed, `git reset --hard HEAD` (331 files, clean), SDV hack reverted. |
| E2 | Memory. The host has 15.8 GB, WSL gets 10 GB + 40 GB swap. Once past the AIDL errors, `soong_build` uses **all 9.7 GB of RAM plus 14+ GB of swap**, with constant memory stalls. Analysis still progresses, but slowly. | ⚠️ open. Options: raise `.wslconfig` `memory=` to ~12–13 GB (leave Windows ~3 GB), close other apps during analysis, or build on a machine with ≥ 32 GB. |
| E3 | Stray, truncated `~/lineage/run_build.sh` at the tree root | ✅ removed; use `scripts/run_build.sh` |
| E4 | Builds launched from a terminal die with SIGHUP when it closes (lost a completed 3 h analysis on 2026-11-10) | ✅ `scripts/start-build.sh` now runs `run_build.sh` detached in tmux and refuses to kill a running session without `--force` |
| E6 | After an interrupted analysis, a 0-byte `out/soong/build.lineage_mona.ninja` makes `soong_ui` panic in dumpvars. lunch then fails, and breakfast falls back to roomservice and a repo sync. | ✅ `run_build.sh` removes a 0-byte `build.*.ninja` before starting. The patched trees survived the roomservice sync (`apply-patches.sh` confirms) |
| E5 | WSL 2.7.11 terminates the distro, tmux included, once no `wsl.exe` client is connected | ✅ `scripts/wsl-keepalive.ps1` holds one hidden client (`sleep infinity`), started via WMI so it survives the terminal; `-Stop` when done |

## 4. Next steps

1. ~~Fix E1~~ ✅. ~~Fix B1–B4 and re-extract~~ ✅.
2. Get soong analysis through on this host (E2), then Kati and ninja.
3. `mka bacon` until it produces a zip. Export each fix as a numbered patch.
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
| 2026-11-10 | `libcamera2ndk_vendor`: build AOSP's instead of patching the blob | `replace_needed` V2→V3 on a prebuilt risks parcelable ABI drift; the NDK camera C API is stable, so the AOSP build is the safer swap |
| 2026-11-10 | Audio: AIDL QTI HAL from source (`sm8450-6.6`), not the legacy HIDL HAL | Kernel 6.6 selects the `sm8450-6.6` variant, which only has the AIDL HAL. The stock vendor runs the same AIDL stack. Pointing audio back at the `sm8450` HIDL tree would mix two QCOM variants. |
| 2026-11-10 | Unpin the WFD blobs rather than kang | The pins describe another firmware; with the pins removed, the existing fixups run on the stock W1VAS36 files |

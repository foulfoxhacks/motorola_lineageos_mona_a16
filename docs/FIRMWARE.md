# Stock firmware reference — `W1VAS36.62-22-16-1-18`

These facts were read from the official T-Mobile-subsidy fastboot package
(`MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml`).
The reading used header and metadata parsing only: no image was modified and none is redistributed here.
All 40 images match the MD5s in `flashfile.xml`.

The package is **generic**. It contains no persist, efs, modemst, fsc or other device-unique data,
and no IMEI or serial numbers. `fsg.mbn` is a generic carrier MCFG bundle.

---

## Build identity

| Item | Value |
|---|---|
| Product fingerprint | `motorola/mona_g/mona:16/W1VAS36.62-22-16-1-18/285398a-18976c:user/release-keys` |
| Vendor / boot chain fingerprint | `motorola/mona/mona:15/VVAS35V-W1-ST15.1.1/285398a` (**Android 15 vendor**) |
| system / system_ext / product | Android 16 (`W1VAS36M-W1-ST15.1.1`) |
| Security patch | 2026-09-01 (all partitions) |
| Vendor base | `AU_LINUX_ANDROID_LA.VENDOR.15.4.1.R1.11.00.00.1214.090` |
| Modem | `M6475_DE314_05.436.01.134R` |
| API levels | `ro.product.first_api_level=35`, `ro.board.api_level=202404` (frozen), sepolicy vers 202404 |
| Platform | `ro.board.platform=parrot`. In the kernel, mona builds as the **parrot** target. "monaco" is a different Qualcomm target. |
| AVB | rollback index 20, SHA256_RSA2048; `vbmeta_system` chained at location 2 |
| CID | 0x32 (50, retail) |

> The vendor side is an **Android 15 (202404) vendor freeze** under an Android 16 system.
> A `lineage-24.0` (Android 17) system runs on top of this vendor. Vendor-interface
> compatibility is governed by `ro.board.api_level=202404`, not by the marketing Android version.

## Boot chain

| Image | Notes |
|---|---|
| `boot` | header v4, **kernel only**: Google GKI `6.6.118-android15-8`, 4 KiB pages, IKCONFIG embedded |
| `init_boot` | generic ramdisk (this is what Magisk patches) |
| `vendor_boot` | vendor header v4. Ramdisk holds `fstab.qcom` and 253 first-stage modules. 2 DTBs (Parrot / Parrot Lite, msm-id 0x297). Vendor cmdline ends in `bootconfig`. |
| `dtbo` | overlay `moto,mona`, board-id `<0x41 0x9000>` |
| `recovery` | dedicated A/B partition, ramdisk only, **no kernel** → `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE` |
| `pvmfw` | protected-VM firmware (pKVM supported) |

## Partitions

- A/B with **Virtual A/B (compressed)** and dynamic partitions. The package's `info.txt` says
  "AB Update Enabled: False"; that is wrong.
- `super` is 10,317,987,840 B, with groups `mot_dp_group_a/b`. Its logical partitions are
  `system`, `system_ext`, `product`, `vendor`, `system_dlkm`, `vendor_dlkm`, all **erofs**.
  There is **no `odm` partition** (`/vendor/odm` is a directory).
- `userdata` is f2fs with FBE `aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0`
  and wrapped-key metadata encryption. Storage is UFS (`1d84000.ufshc`).

## Flash sequence (51 steps)

1. `getvar max-sparse-size`, then `oem fb_mode_set`.
2. Flash `gpt` and `bootloader`.
3. Flash `vbmeta`, `vbmeta_system`, `modem`, `fsg`.
4. Erase `modemst1/2`.
5. Flash `bluetooth`, `dsp`, `logo`, `boot`, `init_boot`, `vendor_boot`, `dtbo`, `recovery`, `pvmfw`.
6. Flash 25 `super` sparse chunks, in numeric order.
7. Erase `apdp`, `apdpb`, `carrier`, `userdata`, `metadata`, `ddr`.
8. `oem fb_mode_clear`.

`servicefile.xml` is the same minus the userdata/metadata erases. `scripts/restore-stock.ps1` runs this
sequence from `flashfile.xml` directly.

## Hardware (from dtbo / vendor / vendor_dlkm)

| Block | Part / driver |
|---|---|
| Display | 6.67" 120 Hz DSC: CSOT VTDR6126 or Tianma NT37706 (two panel sources) |
| Touch + stylus | Goodix GT9916 (Berlin, SPI). Passive stylus through touch; dock detection via `hall_pen` |
| Fingerprint | Goodix and Egis (`rbs`), loaded conditionally |
| Wi-Fi / BT | WCN6750 (`qca_cld3_qca6750`) |
| NFC | ST54L (`stm_nfc_i2c`, `nfc-service-st`) |
| Audio | 2× Awinic aw882xx smart amps, fsa4480 |
| Other | sx937x SAR sensor, hv-haptics, rtc6226 FM, wireless charging, 3 camera sensors |

## Kernel source release

Motorola publishes `kernel-msm` tag `android-16-release-w1vas36.62-22-16-16` (Linux 6.6.118, GPL-2.0).
It is **not** mirrored here: reference it by tag.

- Builds as `parrot`. The mona-specific config fragment is `ext_config/moto-parrot-mona.config`
  (`MONA_DTB`, `SCHED_MOTO_UNFAIR`, UFS HID features).
- The release is **incomplete**. It lacks `moto_fragment.config`, `moto_product.bzl`, the vendor DTS
  directory, Qualcomm techpacks and all Moto MMI drivers (touch, fingerprint, `hall_pen`, charger).
  The LineageOS `android_kernel_motorola_sm6475{,-modules,-devicetrees}` repos fill those gaps,
  and the build uses them.
- The source tag (`…-16-16`) is close to the firmware build (`…-1-18`) but does not match it exactly.

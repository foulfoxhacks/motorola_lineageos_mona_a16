# motorola_lineageos_mona_a16

Unofficial **LineageOS 24.0** bring-up for the **Motorola Moto G Stylus 5G (2025)**:
`mona` / `mona_g`, **XT2517-1**, Snapdragon 6 Gen 3 (SM6475, Qualcomm `parrot` platform), arm64, A/B, GKI 6.6.

The long-term goal is a LineageOS build carrying **GrapheneOS-derived hardening**, added one small piece
at a time. See [`docs/HARDENING.md`](docs/HARDENING.md).

> **Honesty note.** LineageOS does **not** officially support `mona`. There is no wiki page and no
> official build. This is a community port, not affiliated with LineageOS, GrapheneOS or Motorola.
> **No build has booted yet.** Unlocking voids your warranty, and a bad flash can brick the device.
> Read [`docs/RESTORE-STOCK.md`](docs/RESTORE-STOCK.md) **before** you flash anything.

---

## Status (2026-11-10)

| Stage | |
|---|---|
| Source sync (`lineage-24.0`, Android 17) | ✅ |
| Tree adapted to stock firmware `W1VAS36.62-22-16-1-18` | ✅ [`patches/`](patches/) |
| Vendor blobs extracted from stock firmware | ✅ 4,369 files, 0 missing |
| Soong analysis | ✅ AIDL conflicts fixed ([`patches/*/0002`](patches/)); memory-bound on a 10 GB WSL, see [`docs/STATUS.md`](docs/STATUS.md) |
| Kati (product makefiles) | ✅ after switching audio to the AIDL HAL ([`patches/*/0003`](patches/)) |
| Compile → first boot → smoke test | ⏳ compile running |
| Hardening Phase 1 (kernel cmdline) | ⏳ after a stable boot |

Detail, blockers and the decision log: [`docs/STATUS.md`](docs/STATUS.md).

---

## Device baseline (verified)

| Property | Value |
|---|---|
| Codename / product | `mona` / `mona_g` (T-Mobile subsidy SKU) |
| Model | XT2517-1 |
| SoC | SM6475 / Snapdragon 6 Gen 3, `ro.board.platform=parrot` |
| Shipped Android | 15 (`V2VAS35.29-59-4`) |
| Current firmware | `W1VAS36.62-22-16-1-18`: **Android 16 system, Android 15 / 202404 vendor** |
| Kernel | GKI `6.6.118-android15-8`, 4 KiB pages |
| Bootloader | unlockable (`verifiedbootstate=orange` once unlocked) |
| Partitions | A/B + Virtual A/B, dynamic `super` (all erofs), no `odm`; boot 96 MiB, init_boot 8 MiB, vendor_boot 96 MiB, dtbo 24 MiB |

Full firmware breakdown: [`docs/FIRMWARE.md`](docs/FIRMWARE.md).

---

## Which Android version?

| Piece | Version |
|---|---|
| This port's system (`lineage-24.0`) | **Android 17** (the only branch with a `mona` device tree) |
| Stock vendor blobs it runs on | **Android 15 / board API 202404** (frozen in the A16 firmware) |
| Repo name `..._a16` | historical: the firmware it targets is the Android 16 release |

`lineage-23.2` (Android 16) has no `mona` tree. The earlier GSI route (LineageOS 23.2 GSI) booted but could
not bring up the eSIM, so it is closed. Its runbook is kept in [`docs/GSI-A16.md`](docs/GSI-A16.md).

---

## Upstream repos

| Repo | Branch | Purpose |
|---|---|---|
| `LineageOS/android_device_motorola_mona` | `lineage-24.0` | device tree (+ `patches/device/motorola/mona`) |
| `LineageOS/android_device_motorola_sm6475-common` | `lineage-24.0` | platform tree (+ `patches/device/motorola/sm6475-common`) |
| `LineageOS/android_kernel_motorola_sm6475` | `lineage-24.0` | kernel (used by the build; Motorola's source drop is incomplete) |
| `LineageOS/android_kernel_motorola_sm6475-modules` | `lineage-24.0` | DLKM modules (+ 1 patch) |
| `LineageOS/android_kernel_motorola_sm6475-devicetrees` | `lineage-24.0` | DTB/DTBO sources |
| `LineageOS/android_hardware_motorola` | `lineage-24.0` | Motorola HALs |

Motorola's GPL kernel drop for this firmware is `MotorolaMobilityLLC/kernel-msm` tag
`android-16-release-w1vas36.62-22-16-16`. It is used only for reference.

---

## Build quick start (WSL2 Ubuntu 24.04, ~400 GB, ≥16 GB RAM for WSL)

```bash
bash scripts/wsl-deps.sh          # JDK 21, repo, build deps
bash scripts/lineage-sync.sh      # repo init lineage-24.0 + local_manifests/mona.xml + sync
bash scripts/apply-patches.sh     # adapt the trees to W1VAS36 firmware (idempotent)
bash scripts/extract-blobs.sh     # extract vendor blobs from YOUR stock firmware
bash scripts/run_build.sh         # breakfast mona && mka bacon
```

Full walkthrough: [`docs/BUILD.md`](docs/BUILD.md). Vendor blobs are **never** redistributed here: you
extract them from your own copy of the stock firmware.

---

## Repo layout

```
.
├── README.md
├── docs/
│   ├── RUNBOOK.md         step-by-step commands + timings: build → install → first boot
│   ├── STATUS.md          current state, blockers, decision log
│   ├── BUILD.md           from-source lineage-24.0 build, flashing, smoke test
│   ├── FIRMWARE.md        stock W1VAS36 firmware: partitions, boot chain, hardware
│   ├── HARDENING.md       GrapheneOS-derived hardening roadmap (phased)
│   ├── RESTORE-STOCK.md   return to stock from the official firmware package
│   ├── ROOT-MAGISK.md     root stock with Magisk (init_boot method)
│   └── GSI-A16.md         closed: LineageOS 23.2 GSI runbook (historical)
├── local_manifests/
│   └── mona.xml           repo local manifest for the 6 mona projects
├── patches/               local changes to upstream trees (see patches/README.md)
└── scripts/
    │  ── device (Windows / PowerShell) ──
    ├── _common.ps1            shared helpers (firmware detection, MD5, mona product guard)
    ├── get-platform-tools.ps1 install adb/fastboot
    ├── preflight.ps1          check firmware/tools/disk before touching the phone
    ├── restore-stock.ps1      run the official flashfile.xml sequence
    ├── root-magisk.ps1        flash a Magisk-patched init_boot to both slots
    ├── fastbootd-repair.ps1   recovery path via fastbootd (FRP, init_boot)
    ├── radio-check.ps1        read-only SIM/modem/registration dump (identifiers masked)
    ├── download-gsi.ps1, flash-gsi.ps1, gsi-triage.ps1    GSI lane (closed)
    │  ── build host (WSL) ──
    ├── setup-build-wsl.ps1    create the lineage-build distro on a big drive + .wslconfig
    ├── wsl-deps.sh            build dependencies
    ├── lineage-sync.sh, sync-start.sh, sync-watch.sh, sync-status.ps1   sync + progress/ETA
    ├── apply-patches.sh       apply patches/ to the tree (idempotent)
    ├── extract-blobs.sh, fix-extract-tools.sh   blob extraction from stock firmware
    ├── extract-dt.sh          stage the stock DTB + DTBO from your firmware (run by extract-blobs.sh)
    ├── run_build.sh, start-build.sh             build launchers (start-build = detached tmux)
    ├── wsl-keepalive.ps1      keep the WSL distro alive during long builds (tmux alone dies with it)
    ├── keep-awake.ps1         stop Windows idle-sleep until the build result is written
    ├── post-build.sh          on build end: collect zip/images to C:\mona_work\out, write BUILD_RESULT.txt
    ├── fix-tree-issues.sh, trim-missing-blobs.sh, fix-vendor-deps.sh,
    │   fix_goodix.py, fix_remaining_aidls.py, fix_qcril_sql.py,
    │   add_missing_entries.py, append_blobs.py, append_final_blobs.py
    │                          the scripts that produced patches/ (kept for provenance; already applied)
    ├── fix-all-prebuilts.sh   find dirty prebuilts repos after an interrupted sync (dry run unless --apply)
    └── dev/                   one-off diagnostics from bring-up (see dev/README.md)
```

All flashing scripts refuse to run unless fastboot reports a `mona` device.

---

## Licence / credits

Build scripts and docs here: do what you like with them.
Device trees, kernel and HALs are the work of the LineageOS project and Motorola, and their licences apply.
The patches in `patches/` modify Apache-2.0 LineageOS trees and are offered under the same licence.
GrapheneOS-derived work (later) keeps its original Apache-2.0 / MIT / GPL-2.0 headers.
Vendor blobs and stock images are **not** redistributed in this repo.

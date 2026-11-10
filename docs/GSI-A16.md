# Lane 1 — LineageOS 23.2 GSI on Android 16 (closed / historical)

> **Status: closed (2026-11-08).** The GSI booted, but the phh telephony stack could not
> bring up the eSIM (no LPA/eUICC service), and the only GSI that ships an LPA (Google's GMS
> GSI) does not fit `system_a`. The project moved to the from-source `lineage-24.0` port —
> see `BUILD.md`. This runbook is kept because the GSI is still a quick way to sanity-check
> the vendor partition, and because the fastboot/fastbootd notes below are hard-won.
> Some flashing details here conflict with later findings; `RESTORE-STOCK.md` and
> `BUILD.md` take precedence.

Target: **LineageOS 23.2 / Android 16 QPR2** on the stock Android 16 vendor.
Root: Magisk on `init_boot` (works with GSI; root lives outside `system`).

Read `RESTORE-STOCK.md` before Phase D. Have it open on a second screen.

---

## Summary of what gets changed

| Partition | Action | Reversible? |
|---|---|---|
| `vbmeta` / `vbmeta_system` | reflashed with `--disable-verity --disable-verification` | ✅ stock images on disk |
| `system` (logical, in `super`) | replaced with the GSI | ✅ via stock `super` chunks |
| `product` (logical) | **deleted only if** the GSI doesn't fit | ✅ via stock `super` chunks |
| `userdata` | wiped (`fastboot -w`) | ⚠️ data gone — back up first |
| `init_boot` | Magisk-patched | ✅ stock `init_boot.img` |
| `vendor`, kernel, modem, firmware | **untouched** | — |

---

## Phase A — Pre-flight

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\preflight.ps1
```

Checkpoints:

- [ ] All 40 referenced firmware images present, `super` = 25 chunks, 7.60 GiB
- [ ] `flashfile.xml` present (restore path)
- [ ] `adb` and `fastboot` on PATH
- [ ] GSI image found (preflight reports the path)
- [ ] Battery > 60 %
- [ ] **Back up photos/2FA/authenticator seeds** — `fastboot -w` wipes everything

On the phone:

- [ ] Developer options on, USB debugging on
- [ ] `adb devices` shows `device` (authorise the prompt)

---

## Phase B — Root first (verify it works before changing `system`)

Doing this on stock first means you have a known-good fallback.

```powershell
# copy stock init_boot to the phone
$FW = 'C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml'
adb push "$FW\init_boot.img" /sdcard/Download/
```

1. Install Magisk from <https://github.com/topjohnwu/Magisk/releases>.
2. Magisk → **Install** → **Select and Patch a File** → `/sdcard/Download/init_boot.img`.
3. Pull the result back:

```powershell
adb pull /sdcard/Download/magisk_patched-*.img .\magisk_patched.img
```

4. Flash it (bootloader first; fall back to fastbootd on validation errors):

```powershell
adb reboot bootloader
fastboot flash init_boot   magisk_patched.img
fastboot flash init_boot_b magisk_patched.img
fastboot reboot
```

5. Verify: `adb shell su -c id` → `uid=0(root)`.

Checkpoint: **if root does not work, stop and fix that before Phase D.** A GSI with no root is
fine, but you want to know the init_boot path works while stock recovery is still trivial.

---

## Phase C — Get the GSI

You already have the extracted image:

```
C:\mona_firmware\W1VAS36\LineageOS-23.2-20260524-VANILLA-EXT4-GSI\LineageOS-23.2-20260524-VANILLA-EXT4-GSI.img
```

`download-gsi.ps1` detects it and uses it in place — no copy, no download. Safe to run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\download-gsi.ps1
```

Only if no image is found does it download the archive:

- Release: `v2026.05.24-lineage23.2` (Android 16 QPR2, A/B only, no built-in root)
- Asset: **`LineageOS-23.2-20260524-VANILLA-EXT4-GSI.7z`** (922,022,276 bytes → ~2.5 GB)
- Mirrors used: `master.dl`, `downloads`, `netix.dl`, `phoenixnap.dl` on SourceForge
  (the main `/download` redirect and some mirrors reset the connection)

Why EXT4: this device's `system` is `BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4`. The EROFS
variant needs matching fstab entries — don't mix on the first attempt.

Checkpoint: the GSI image is found (preflight prints its path). `flash-gsi.ps1` uses it
directly; it is only downloaded if no image exists on disk.

---

## Phase D — Flash the GSI

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\flash-gsi.ps1
```

Manual equivalent (if you prefer to drive it yourself):

```powershell
$FW = "C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml"
$GSI = "C:\mona_work\motorola_lineageos_mona_a16\gsi\system.img"

# 1. enter fastbootd from booted Android
#    (this bootloader ignores `fastboot reboot fastboot`)
adb reboot fastboot
fastboot getvar is-userspace          # must say: yes

# 2. tell AVB to ignore the unsigned system
fastboot --disable-verity --disable-verification flash vbmeta        "$FW\vbmeta.img"
fastboot --disable-verity --disable-verification flash vbmeta_system "$FW\vbmeta_system.img"

# 3. flash
fastboot flash system "$GSI"
# if this fails with "not enough space":
#   fastboot delete-logical-partition product
#   fastboot flash system "$GSI"

# 4. wipe and boot
fastboot -w
fastboot reboot
```

First boot: **5–15 minutes**, screen may sit on the boot animation a long time. Do not
interrupt it.

---

## Phase E — First boot checks

```powershell
adb devices
adb shell getprop ro.build.version.release      # 16
adb shell getprop ro.lineage.version            # 23.2-...
adb shell getprop ro.product.device             # mona
adb shell su -c id                              # root survived
```

Check by hand: Wi-Fi, mobile data, calls, SMS, camera, fingerprint, NFC, Bluetooth, speakers,
stylus (hardware only — no Moto Note).

---

## Phase F — Known GSI limitations on this device

| Area | Verified on `mona` (2026-11-08) |
|---|---|
| Moto stylus integration / Moto Note | Gone — no Moto framework |
| Moto camera, Moto gestures | Gone |
| VoLTE / VoWiFi | **Broken out of the box** — the GSI ships with all phh IMS switches off. See Phase F2. |
| 5G / NR | Not connected (`isNrAvailable=false`); `preferred_network_mode` defaults to `0` |
| Widevine L1 | Usually drops to L3 (Netflix SD) |
| Fingerprint (goodix) | Vendor HAL runs (`biometrics.fingerprint-service-rbs`) |
| Screen lock | **Blocked by FRP** until the persistent-data block is erased. See Phase F2. |
| SIM toggle | Disabling a SIM can leave it stuck off (telephony DB) |
| OTA | None — manual reflash |
| Play Integrity | Fails (unlocked + GSI) |

If a hardware feature is broken, capture `adb logcat -b all -d > logcat.txt` and check
`adb shell dmesg` before changing anything.

---

## Phase F2 — Post-install repairs (verified failure modes)

Run the triage script first; it prints every value below.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gsi-triage.ps1        # read-only
powershell -ExecutionPolicy Bypass -File .\scripts\gsi-triage.ps1 -Fix   # apply
```

Screen lock and root are the two things that need writes to a physical
partition, so they live in their own script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1 -SkipFrp    # root only
powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1 -SkipRoot   # FRP only
```

It enters fastbootd, erases `frp`, flashes `magisk_patched.img` to both
`init_boot` slots, reboots and checks `su -c id`.

### Calls: enable CAF IMS

The GSI is phh-treble based and ships with:

```
persist.sys.phh.ims.caf   = false
persist.sys.phh.ims.floss = false
persist.sys.phh.ims.sec   = false
```

All three off means the framework never binds an IMS service, so on an LTE-only
carrier (T-Mobile/Metro) there is no way to place or receive a call — there is no
2G/3G to fall back to. The radio side is healthy: `mVopsSupport = 2`.

Fix: **Treble Settings → IMS → enable CAF IMS → reboot.** The Qualcomm CAF stack
is already present (the `me.phh.treble.overlay.cafims_telephony` overlay ships with
the GSI). After reboot a **VoLTE** toggle appears under
Settings → Network & internet → SIMs.

A crash in `com.qualcomm.qti.cne` (`.qtidataservices`,
`NetworkCallback was not registered`) is that vendor stack waking up and is
expected before IMS is enabled.

### Screen lock: FRP is still armed

Setting a PIN fails with:

```
java.lang.SecurityException: Cannot change credential while factory reset protection is active
```

`fastboot -w` wipes userdata but **not** the FRP persistent-data block, and a
vanilla GSI cannot complete FRP verification.

**The bootloader refuses to erase it** (verified 2026-11-08):

```
fastboot erase frp
(bootloader) frp is NOT erased. Permission denied.
FAILED (remote: '')
```

That is FRP protection, not a lock state. **fastbootd** writes the block device
directly, so the erase has to happen there:

```powershell
adb reboot fastboot
fastboot getvar is-userspace        # must print: yes
fastboot erase frp
fastboot reboot
```

`fastboot reboot fastboot` from the bootloader is ignored on this device — go
back to Android and use `adb reboot fastboot`.

Check `adb shell getprop ro.frp.pst` first. It reports
`/dev/block/bootdevice/by-name/frp` on `mona`. If it points at `persist`
instead, **stop** — erasing `persist` destroys calibration data.

### SIM stuck disabled

The "Use SIM" toggle maps to `setUiccApplicationsEnabled`. If the toggle fails,
the row stays disabled in the telephony DB.

The provider only serves `siminfo` to the phone/system UID, so this is **not**
fixable from plain `adb shell`:

```
SecurityException: Access SIMINFO table from not phone/system UID
```

With root:

```powershell
adb shell "su -c 'content update --uri content://telephony/siminfo --bind uicc_applications_enabled:i:1'"
adb reboot
```

Without root, clear the whole provider (it re-populates from the SIM on boot):

```powershell
adb shell "pm clear com.android.providers.telephony"
adb reboot
```

That also drops APNs and the SMS/MMS database; the carrier config re-provisions
APNs on the next boot.

`adb shell cmd phone help` is worth checking after a GSI update — `cmd phone`
runs inside the phone process, so any UICC subcommand it grows would work
without root.

### The line is an eSIM — there is no tray to re-seat

Verified 2026-11-08: this XT2517-1 runs its T-Mobile/Metro line as an **embedded
profile**, not a physical SIM. That changes the diagnosis:

```
gsm.sim.state          = ABSENT,NOT_READY     slot 0 = empty physical slot
                                              slot 1 = eUICC
gsm.sim.operator.numeric = ,310260            T-Mobile on slot 1, as expected
ril.iccid.sim1          = (empty)             that prop is the *physical* slot
```

So `ABSENT` on slot 0 and an empty `ril.iccid.sim1` are **normal** and not a
fault. The real fault is the eUICC profile being disabled:

```
simSlotIndex=-1   areUiccApplicationsEnabled=0   carrierName=No service
```

An eSIM profile cannot be power-cycled by re-seating anything, and neither a
reboot nor a `content update` re-enables it. It has to go back through the LPA
(`EuiccManager`):

- Settings → Network & internet → SIMs → T-Mobile → **Use SIM**
- Settings → SIMs → **Add SIM** / eSIM manager (profile list)
- carrier app

Check where it stands:

```powershell
adb shell "dumpsys euicc | Select-String -Pattern 'profile|state|active|slot'"
adb shell "pm list packages | Select-String -Pattern 'euicc|lpa|esim'"
adb shell "cmd phone get-sim-card-mapping"
```

If `dumpsys euicc` reports the profile as inactive, the eUICC itself has it
disabled and **no GSI flash will change that** — the fix is LPA-side.

### 5G

**NR lives in `modem`/`vendor`, not in the GSI.** Flashing a system image cannot
add or remove 5G support — the QCRIL NR stack, band list and NV items all come
from the stock vendor side, which the GSI flow never touches. So "5G doesn't
work on the GSI" is almost always one of four *system-side* restrictions, or it
is simply that the SIM never registered.

Evidence that the modem already does NR on this unit (2026-11-08, no SIM
service, emergency-only attach to AT&T):

```
accessNetworkTechnology=NR   mBands = [5]   mMcc = 310   mMnc = 410
```

That is a real NR attach on band n5 with an empty physical slot. The radio
works. What was missing was a registered subscription.

Check it:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\radio-check.ps1
```

The four levers, in order:

| Lever | Want | Why |
|---|---|---|
| `gsm.sim.state` | `LOADED` | no subscription → no registration → no NR, regardless of settings |
| `preferred_network_mode` / `…mode1` | `33` | `0` is WCDMA-preferred and excludes NR entirely |
| `ro.telephony.default_network` | `33` (or unset) | the boot-time default; a low value silently downgrades |
| `me.phh.treble.overlay.telephony.lte` | disabled | the name is literal: an LTE-only carrier/network overlay |

Set the mode from the UI where possible — **Settings → Network & internet →
SIMs → T-Mobile → Preferred network type → 5G/LTE/3G/2G** — because that path
also updates the modem's `allowedNetworkTypesForReasons`:

```powershell
adb shell "settings put global preferred_network_mode 33"
adb shell "settings put global preferred_network_mode1 33"
```

If the overlay is forcing LTE, drop it and reboot:

```powershell
adb shell "cmd overlay list | grep -i telephony"
adb shell "su -c 'cmd overlay disable --user 0 me.phh.treble.overlay.telephony.lte'"
adb reboot
```

Two more things that silently break NR:

- **A deleted `product` partition.** `flash-gsi.ps1` deletes `product` when the
  image does not fit in `super`. Motorola ships its carrier-config overlays in
  `/product`, and those decide whether NR is offered for a given PLMN. Check
  `adb shell "ls /product/overlay | grep -i carrier"` after any flash that
  triggered that fallback.
- **Carrier config mismatch.** `mIsEmergencyOnly=true` plus an operator you did
  not expect means the modem attached somewhere else; fix the subscription
  first, never the network mode.

5G **data** is realistic on a GSI once the SIM registers. 5G **calls** (VoNR)
are not: they need IMS, which is the same blocker as VoLTE.

### Root not available on the GSI

`adb shell su -c id` returning `su: inaccessible or not found` means the Magisk
daemon is not running, not that the app is missing.

Two red herrings, both normal on a working Magisk install:

```
ls: /system/bin/su: No such file or directory
ls: /debug_ramdisk: Permission denied
```

Magisk's `su` is not a real file in `/system/bin`, and `/debug_ramdisk` is
`0700 root:root`. The real test is `adb shell su -c id`, or the Magisk app
reporting an installed version.

`ro.build.type=userdebug` but `ro.debuggable=0`, so `adb root` needs
Developer options → **Rooted debugging**.

If Magisk reports *Installed: N/A*, re-flash `magisk_patched.img` to both
`init_boot` slots from fastbootd:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1 -SkipFrp
```

Also check `ro.boot.flash.locked` — a locked bootloader rejects the flash with
`Preflash validation failed` / `not allowed in locked state`, and root cannot be
restored until the device is unlocked again.

**Do not trust `ro.boot.flash.locked` / `ro.boot.verifiedbootstate` on a phh
GSI.** They are spoofed for Play Integrity (`flash.locked=1`,
`verifiedbootstate=green`, `vbmeta.device_state=locked`) even though the device
is unlocked, and `/proc/cmdline` is not readable as shell on Android 16
(`cat: /proc/cmdline: Permission denied`). Ask the bootloader instead:

```powershell
fastboot getvar all 2>&1 | Select-String -Pattern 'lock|secure|verity'
```

Verified on `mona` (2026-11-08):

```
(bootloader) secure: yes
(bootloader) securestate: flashing_unlocked
(bootloader) verity-state: disabled (0)
```

`flashing_unlocked` means flashing is allowed. `fastboot oem device-info` and
`fastboot flashing get_unlock_ability` are **not** available on this bootloader
(both just point at motorola.com/unlockbootloader).

---

## Phase F3 — why the eSIM never came up on the GSI

> **Correction (2026-11-08, after the stock restore).** The original diagnosis
> here used the wrong service name. `dumpsys euicc` is invalid on *any* build —
> the binder services are named `econtroller` and `euicc_card_controller`:
>
> ```
> 157  econtroller:          [com.android.internal.telephony.euicc.IEuiccController]
> 160  euicc_card_controller: [com.android.internal.telephony.euicc.IEuiccCardController]
> ```
>
> Those lines are from **stock**, where `dumpsys euicc` also fails. So
> "Can't find service: euicc" was never evidence of anything. The real evidence
> is that on the GSI `service list | grep -i euicc` returned nothing at all,
> which means at minimum `euicc_card_controller` was absent. `econtroller` would
> not have matched that pattern either way, so its state on the GSI is unknown.

Use this probe instead:

```powershell
adb shell "service list | grep -iE 'econtroller|euicc'"
```

### Verified working baseline (stock, 2026-11-08)

After `restore-stock.ps1`, with the Metro eSIM and no physical SIM:

```
gsm.sim.state            ABSENT,LOADED     slot 0 empty, slot 1 eUICC loaded
gsm.network.type         Unknown,NR_SA     5G SA on the eSIM
preferred_network_mode   26,26             NR_LTE_GSM_WCDMA
```

So the eUICC, the profile, the T-Mobile provisioning and 5G **SA** are all
healthy on Motorola's stack. Note `26`, not `33`: Motorola's default already
includes NR, so the GSI's `0` was the only reason NR was excluded there.

The GSI could not reproduce any of this. No GSI can: VoLTE needs `ims-patches/`
and `qcril-database/` from `device/motorola/sm6475-common`.

### Command syntax trap

`Select-String` is a PowerShell cmdlet. Inside `adb shell "..."` the string runs
in Android's `sh`, so it must be `grep`:

```powershell
# wrong - runs on the phone
adb shell "dumpsys euicc | Select-String -Pattern 'profile'"

# right - filter on the PC side
adb shell "service list" | Select-String -Pattern 'econtroller|euicc'

# also right - filter on the phone
adb shell "service list | grep -iE 'econtroller|euicc'"
```

### What "absent" would mean

- `econtroller` + `euicc_card_controller` present → the stack exists; the fault
  is elsewhere (LPA, profile state, HAL).
- `euicc_card_controller` missing → nothing can talk to the eUICC HAL, which is
  consistent with the GSI's behaviour.
- Both missing → the framework never published them; the image is at fault.

### Consequence for any future image

An eSIM needs an **LPA** (`android.service.euicc.EuiccService`) as well as the
controller. Google's GMS GSI is the only readily obtained image that ships one
(`com.google.android.euicc`). The AOSP variant and vanilla LineageOS builds
generally do not.

That is moot for `mona`: the GMS image is 3.13 GiB and does not fit the 2.55 GiB
`system_a`, and `resize` fails even after deleting `product_a`. The GSI branch is
closed — the from-source tree is the only route.

---

## Phase G — Rollback

The stock `system` is **not** a single `system.img` — it lives inside the 25 `super` sparse
chunks. So rollback means reflashing `super`, not one partition:

```powershell
# simplest and exact: run Motorola's own sequence
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1

# if you only want the system side back (keeps boot/bootloader untouched)
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -SkipBootloader
```

Manual minimum (fastbootd required for logical partitions):

```powershell
adb reboot bootloader
fastboot reboot fastboot
fastboot getvar is-userspace          # must say: yes

0..24 | ForEach-Object { fastboot flash super "$FW\super.img_sparsechunk.$_" }

fastboot flash vbmeta        "$FW\vbmeta.img"          # WITHOUT the disable flags
fastboot flash vbmeta_system "$FW\vbmeta_system.img"
fastboot -w
fastboot reboot
```

`restore-stock.ps1` is preferred: it also restores `boot`, `init_boot`, `dtbo`, `modem` and
clears the partitions the GSI flow touched.

---

## Decision log

- Chose GSI over source build because no `mona` Android 16 device tree exists; the only
  published tree is `lineage-24.0` (Android 17).
- Chose EXT4 GSI because the stock `system` partition is ext4.
- Chose VANILLA (no GApps) to match the de-Googled goal; switch to GAPPS later if needed.
- Root via `init_boot` because the ramdisk is not in `boot` on this device.

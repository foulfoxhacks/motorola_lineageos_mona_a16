# Restoring stock Android 16

Your safety net. Read this before flashing anything.

**Source of truth (verified on disk):**

```
C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml\
```

This is a complete extraction of the official package — it contains `flashfile.xml`,
`servicefile.xml`, all boot images, and **25** `super` chunks (`.0`–`.24`), plus MD5 hashes
for every file in `flashfile.xml`.

> The RSA download folder (`C:\ProgramData\RSA\Download\RomFiles`) is now **empty**. Don't
> rely on it. The copy above is the one to protect. Back it up to external storage if you can.

---

## 0. Do NOT use RSA's "Rescue" button

RSA Rescue reflashes **and relocks** the bootloader. Manual flashing keeps it unlocked.

---

## 1. Automated restore (recommended)

The script parses `flashfile.xml` and runs Motorola's exact sequence — no hand-typed
partition names, no guessing.

```powershell
# optional but recommended: verify every MD5 first (slow, several minutes)
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -VerifyHashes

# normal restore
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1
```

It performs, in order:

1. `fastboot getvar max-sparse-size`
2. `fastboot oem fb_mode_set`
3. flash `partition` ← `gpt.bin`
4. flash `bootloader` ← `bootloader.img`
5. flash `vbmeta`, `vbmeta_system`
6. flash `modem` ← `NON-HLOS.bin`, `fsg` ← `fsg.mbn`
7. erase `modemst1`, `modemst2`
8. flash `bluetooth`, `dsp`, `logo`
9. flash `boot`, `init_boot`, `vendor_boot`, `dtbo`, `recovery`, `pvmfw`
10. flash `super` ← 25 sparse chunks
11. erase `apdp`, `apdpb`, `carrier`, `userdata`, `metadata`, `ddr`
12. `fastboot oem fb_mode_clear`, reboot

### If you only need to recover boot/system (no GPT or bootloader work)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -SkipBootloader
```

This skips `gpt.bin` and `bootloader.img` — the two highest-risk steps.

---

## 2. Manual restore (fallback)

Enter the bootloader: power off, hold **Volume Down + Power**.

```powershell
$FW = 'C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml'

fastboot oem fb_mode_set

fastboot flash vbmeta        "$FW\vbmeta.img"
fastboot flash vbmeta_system "$FW\vbmeta_system.img"
fastboot flash modem         "$FW\NON-HLOS.bin"
fastboot flash fsg           "$FW\fsg.mbn"
fastboot flash bluetooth     "$FW\BTFM.bin"
fastboot flash dsp           "$FW\dspso.bin"
fastboot flash logo          "$FW\logo.bin"

fastboot flash boot          "$FW\boot.img"
fastboot flash init_boot     "$FW\init_boot.img"
fastboot flash vendor_boot   "$FW\vendor_boot.img"
fastboot flash dtbo          "$FW\dtbo.img"
fastboot flash recovery      "$FW\recovery.img"
fastboot flash pvmfw         "$FW\pvmfw.img"

0..24 | ForEach-Object { fastboot flash super "$FW\super.img_sparsechunk.$_" }

fastboot erase userdata
fastboot erase metadata
fastboot oem fb_mode_clear
fastboot reboot
```

---

## 3. Warnings

| Item | Why |
|---|---|
| `gpt.bin` | Rewrites the partition table. Only needed for a corrupted GPT; a bad flash is a hard brick. Same-version is safe — **downgrading is not**. |
| `bootloader.img` | **Anti-rollback fuses.** Only flash the exact `W1VAS36.62-22-16-1-18` bootloader. An older one can permanently brick the device. |
| `erase modemst1/2` | Part of Motorola's official flow. IMEI is restored from `fsg`/`persist`; still, don't interrupt it. |
| Mixing builds | Never mix files from a different build ID. Everything must be `W1VAS36.62-22-16-1-18`. |
| `erase userdata` | Wipes everything. Intended when leaving a custom ROM. |

---

## 4. Bootloop triage

1. **Still looping after restore?** Re-flash `vbmeta` + `vbmeta_system`, then `erase userdata`.
2. **Slot confusion:** `fastboot --set-active=a`, reboot.
3. **Fastboot alive but nothing boots?** Run the full `restore-stock.ps1`.
4. **Fastboot dead?** That's the brick case — RSA Rescue (relocks) or a service centre.

---

## 5. Verify you are back

```powershell
adb shell getprop ro.build.fingerprint
# motorola/mona_g/mona:16/W1VAS36.62-22-16-1-18/285398a-18976c:user/release-keys

adb shell getprop ro.boot.verifiedbootstate
# orange  (unlocked - expected)
```

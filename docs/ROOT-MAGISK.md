# Rooting XT2517-1 with Magisk (init_boot method)

Root is **independent** of which ROM you end up on, and it is the lowest-risk thing you can
do today. On this device the ramdisk lives in **`init_boot`**, so Magisk patches
`init_boot.img` — **not** `boot.img`. Flashing a patched `boot.img` will not root you and can
break the kernel.

You already have the exact stock image:
`C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml\init_boot.img`

(The RSA download folder is empty; the firmware now lives under `C:\mona_firmware`.)

---

## 0. Before you start

- Bootloader is already unlocked (`ro.boot.flash.locked=0`).
- Have `adb` + `fastboot` (Google platform-tools) on PATH.
  In a fresh PowerShell window the scripts add it themselves, but for manual
  `adb` commands run this once per window:

  ```powershell
  $env:Path = "C:\mona_work\platform-tools;$env:Path"
  ```

- **Back up `init_boot.img`** — that file is your unroot button. Keep a copy outside the RSA folder.
- Battery > 50 %.

---

## 1. Patch the image on the phone

> Automated: `powershell -ExecutionPolicy Bypass -File .\scripts\root-magisk.ps1`
> does steps 1, 2, 4, 5 and the flashing below; you only do the Magisk patching itself.
> Re-running it offers to reuse a `magisk_patched-*.img` already on the phone
> (`-ForcePatch` to patch again).

1. Copy stock `init_boot.img` to the phone (USB file transfer).
2. Install the Magisk APK from <https://github.com/topjohnwu/Magisk/releases> (latest stable).
3. Open Magisk → **Install** → **Select and Patch a File** → pick `init_boot.img`.
4. Magisk writes `magisk_patched-<version>_xxxxx.img` to `Download/`.
5. Copy that file back to the PC.

---

## 2. Flash it

```bash
adb devices                      # confirm the phone is visible
adb reboot bootloader
fastboot devices                 # confirm bootloader mode
fastboot getvar current-slot     # note _a or _b
```

Try the bootloader first:

```bash
fastboot flash init_boot magisk_patched.img
fastboot flash init_boot_b magisk_patched.img
```

If you get `pre-flash validation failed` (common on Moto), switch to **fastbootd**:

> On this device the bootloader **will** reject a Magisk-patched `init_boot` with
> `Preflash validation failed`. That is expected, not a sign of a bad image.
> Fastbootd is the reliable path — prefer `adb reboot fastboot` from booted Android,
> which is what `root-magisk.ps1` now does first.

```bash
fastboot reboot fastboot
fastboot devices
fastboot flash init_boot magisk_patched.img
fastboot reboot bootloader
fastboot --set-active=b
fastboot reboot fastboot
fastboot flash init_boot magisk_patched.img
fastboot --set-active=a
fastboot reboot
```

Then open the Magisk app — it may ask for one reboot to finish setup.

---

## 3. Verify

```bash
adb shell su -c id        # should print uid=0(root)
```

---

## 4. Unroot / recover

```bash
fastboot flash init_boot init_boot.img
fastboot flash init_boot_b init_boot.img
fastboot reboot
```

Root is fully reversible as long as you kept the stock `init_boot.img`.

---

## 5. Consequences you should expect

| Effect | Reality |
|---|---|
| Play Integrity / banking apps | **Fail.** Unlocked bootloader + root. Mitigate with PlayIntegrityFix / DenyList, but it's a moving target. |
| OTA updates | **Fail while rooted.** Re-flash stock `init_boot`, take the OTA, then re-patch and re-flash. |
| Google Wallet | Will not work for tap-to-pay. |
| Security | Root + unlocked bootloader = physical-access attacks are viable. Don't treat this as a hardened device. |
| Warranty | Void (bootloader already unlocked anyway). |

---

## 6. If you land on "device is corrupt / may need to perform factory reset"

That screen is the **bootloader**, not Android. It means AVB or the boot-retry
counter failed for the slot it tried. Do **not** pick *Factory reset* — it wipes
data and does not fix AVB.

Repair ladder (stop as soon as it boots):

1. **Just continue.** Wait 10–20 s, then press `Power` once. If a menu appears,
   choose *Continue* / *Try again* — never *Factory reset*.
2. **Return to the good slot.** Bootloader (`Vol Down` + `Power`), then:
   ```powershell
   fastboot --set-active=a
   fastboot reboot
   ```
3. **Undo a Magisk write to `boot`.** Root belongs in `init_boot`; on a GSI the
   app can patch `boot` instead. Restore the stock image — it is signed, so it
   passes preflash validation even in the bootloader:
   ```powershell
   $FW = "C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml"
   fastboot flash boot   "$FW\boot.img"
   fastboot flash boot_b "$FW\boot.img"
   fastboot reboot
   ```
4. **Suspect the patched ramdisk.** Flash stock `init_boot` to both slots (loses
   root, proves the point), boot, then re-root from fastbootd.
5. **Modified images need fastbootd.** If Android will not boot, reach fastbootd
   through recovery: bootloader → *Recovery mode* → at the Android screen hold
   `Power` and tap `Volume Up` once → *Enter fastboot*. Then re-flash
   `vbmeta` + `vbmeta_system` for both slots with
   `--disable-verity --disable-verification`.

> Never run `fastboot -w` or *Factory reset* to "fix" this screen. Wiping
> userdata does not change AVB and only costs you the setup you already did.

---

## Notes specific to this device

- `init_boot` is a **physical** partition (8 MiB) — it is not part of `super`.
- Slot suffix matters: flash **both** `init_boot` and `init_boot_b`, or a slot switch after an
  update will silently drop root.
- Do **not** patch/flash `boot.img`, `vendor_boot.img`, or `vbmeta.img` to gain root.
- The `mona_g` product means the same image works on the `_g` variant; there is no separate
  root image per SKU.

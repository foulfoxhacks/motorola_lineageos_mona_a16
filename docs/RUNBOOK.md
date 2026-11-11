# Runbook: from "build running" to LineageOS on the phone

Commands only, in order. Each step says **where** to run it and roughly **how long** it takes.

- **PS** = Windows PowerShell, in `C:\mona_work\motorola_lineageos_mona_a16`
- **WSL** = inside the build distro (open it from PS with `wsl -d lineage-build -u builder`)

Every PS session that uses adb/fastboot needs this once:

```powershell
cd C:\mona_work\motorola_lineageos_mona_a16
$env:Path = "C:\mona_work\platform-tools;$env:Path"
```

---

## One-window automated pipeline (recommended)

```powershell
# PS: opens a dedicated "mona build pipeline" window that runs every step below
Start-Process powershell -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File','C:\mona_work\motorola_lineageos_mona_a16\scripts\build-pipeline.ps1'
```

| Step | What it does |
|---|---|
| 1 | checks the WSL distro and `~/lineage` |
| 2 | starts the WSL keepalive and keep-awake |
| 3 | applies `patches/` (skipped while a build runs) |
| 4 | stages the stock DTB/DTBO if missing (skipped while a build runs) |
| 5 | starts the build in tmux, or **attaches** to the one already running |
| 6 | prints the stage every minute: soong → Kati → compile `[ x% n/total ]` |
| 7 | shows `C:\mona_work\out\BUILD_RESULT.txt` |

Closing the window does **not** stop the build; run the same command again to re-attach.
`-Restart` kills the running build and starts a fresh one.
WSL can answer slowly while soong uses all memory. The window then prints "WSL busy" and retries.

---

## Unattended builds (runs without Claude or any open window)

Three detached pieces, none of them a child of your terminal or of Claude:

| Piece | What it does | Ends |
|---|---|---|
| `scripts/wsl-keepalive.ps1` (PS) | a hidden `wsl.exe … sleep infinity`, so WSL doesn't shut the distro (and tmux) down | stopped by `post-build.sh`, or `-Stop` |
| `scripts/start-build.sh` (WSL) | runs the build in tmux session `build`, and `post-build.sh` in tmux session `post` | when the build ends |
| `scripts/keep-awake.ps1` (PS) | holds a "system required" power request so Windows doesn't idle-sleep or hibernate (no settings changed) | when `BUILD_RESULT.txt` is written, or after 30 h |

When the build ends, `post-build.sh`:
- writes **`C:\mona_work\out\BUILD_RESULT.txt`** (SUCCESS or FAILED, with the errors);
- on success, copies the images, zip and `SHA256SUMS.txt` to `C:\mona_work\out`;
- stops the keepalive.

Check that file instead of watching the log.

Limits:
- Lid close and a flat battery still sleep the laptop, so keep it **plugged in with the lid open**.
- Closing the Claude app, logging out or hitting a usage limit doesn't stop anything above.
- A reboot, a Windows update restart or `wsl --shutdown` does.

```powershell
# PS: start/verify both Windows-side helpers (idempotent)
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 -Status
```

---

## Phase 1: finish the build (≈ 12–20 h, mostly unattended)

| # | Where | Command | Time |
|---|---|---|---|
| 1.1 | PS | `powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1 -Status`. If it says *no keepalive*, run it without `-Status`. | 5 s |
| 1.2 | WSL | `tmux ls`. If there is **no** `build` session: `bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/start-build.sh` | 5 s |
| 1.3 | WSL | Watch it: `tmux attach -t build` (leave with **Ctrl-b** then **d**). Or `tail -f ~/build.log` (leave with Ctrl-c). | — |
| 1.4 | — | Stage 1, soong analysis: RAM full + heavy swap is normal here. | **≈ 3 h** |
| 1.5 | — | Stage 2, Kati (`Running Kati`) | 30–60 min |
| 1.6 | — | Stage 3, compile (`[ 12% 3456/28000 ]` …), `-j4` | **8–16 h** |
| 1.7 | PS | Done when `C:\mona_work\out\BUILD_RESULT.txt` exists: `Get-Content C:\mona_work\out\BUILD_RESULT.txt`. On SUCCESS, Phase 2 has already been done for you. | — |

**If it fails** (`BUILD-EXIT=1`):

```bash
# WSL: show the errors of the LATEST run only (~/build.log keeps every run), then send them to Claude
tac ~/build.log | sed '/Build started at/q' | tac | grep -E '^error:|FAILED:'
cat ~/lineage/out/error.log | head -60
```

From PowerShell, the same check is:

```powershell
wsl -d lineage-build -u builder -- bash -c "tac ~/build.log | sed '/Build started at/q' | tac | grep -E '^error:|FAILED:'"
```

No output means no errors in the current run. A plain `grep ~/build.log` also shows errors from old,
already-fixed runs.

After a fix, restart from step 1.2 with `start-build.sh --force`. Don't run `wsl --shutdown` while a build
is running.

---

## Phase 2: collect the output (2 min)

```bash
# WSL
OUT=~/lineage/out/target/product/mona
ls -la $OUT/*.img $OUT/lineage-*.zip
mkdir -p /mnt/c/mona_work/out
cp $OUT/boot.img $OUT/dtbo.img $OUT/vendor_boot.img $OUT/recovery.img $OUT/vbmeta.img $OUT/lineage-*.zip /mnt/c/mona_work/out/
ls $OUT/init_boot.img 2>/dev/null || echo "no init_boot.img built (expected: see 3.2)"
```

```powershell
# PS: record checksums
Get-FileHash C:\mona_work\out\* -Algorithm SHA256 | Format-Table Hash, Path -AutoSize
```

---

## Phase 3: install (≈ 30 min hands-on). **This wipes the phone.**

| # | Where | Command / action | Time |
|---|---|---|---|
| 3.0 | phone | Back up anything you want to keep. Charge > 50 %. Settings → Developer options → USB debugging **on**. | 10 min |
| 3.1 | PS | `adb devices`. The phone must be listed as `device`. | 10 s |
| 3.2 | PS | Unroot first: the build does **not** make an `init_boot`, so the one on the phone is what boots with LineageOS. Put stock back on both slots: `adb reboot bootloader`, then the five commands below this table. | 2 min |
| 3.3 | PS | Get to **fastbootd**: `adb reboot fastboot`, then `fastboot getvar is-userspace` must print `yes`. (No booted Android? Use bootloader → *Recovery mode* → *Enter fastboot*.) | 1 min |
| 3.4 | PS | Flash the LineageOS boot chain + recovery (block below) | 2 min |
| 3.5 | PS | `fastboot reboot recovery`. The LineageOS Recovery menu appears. | 1 min |
| 3.6 | phone | *Factory reset* → *Format data / factory reset* → confirm | 2 min |
| 3.7 | phone | *Apply update* → *Apply from ADB* | — |
| 3.8 | PS | `adb sideload (Get-Item C:\mona_work\out\lineage-*.zip).FullName`. It stops at ~47 % with "Total xfer: 1.00x": that is success. | 5–10 min |
| 3.9 | phone | Back arrow → *Reboot system now* | — |
| 3.10 | — | First boot | 5–10 min |

Step 3.2, stock `init_boot` on both slots (bootloader mode):

```powershell
$FW = "C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml"
fastboot getvar product                      # must say mona
fastboot flash init_boot_a "$FW\init_boot.img"
fastboot flash init_boot_b "$FW\init_boot.img"
fastboot reboot
```

If the bootloader rejects it ("Preflash validation failed"), do 3.3 first and run the same two `flash` lines in fastbootd.

Step 3.4, in fastbootd:

```powershell
fastboot getvar product                      # must say mona
fastboot flash dtbo        C:\mona_work\out\dtbo.img
fastboot flash vendor_boot C:\mona_work\out\vendor_boot.img
fastboot flash recovery    C:\mona_work\out\recovery.img
fastboot flash vbmeta      C:\mona_work\out\vbmeta.img
```

---

## Phase 4: first boot (≈ 30 min)

**It boots:**

```powershell
adb shell getprop ro.lineage.version          # 24.0-...
adb shell getprop ro.build.version.release    # 17
adb shell getenforce                          # Enforcing (Permissive = note it)
```

Then go through the smoke-test table in `BUILD.md` §6: calls, SMS, data, eSIM, Wi-Fi, BT, NFC, camera,
fingerprint, stylus, audio, charging. Write down what fails.

**It bootloops or hangs on the logo** for more than 10 minutes:

```text
phone: hold Power + Volume Down until the bootloader, choose Recovery mode
phone: LineageOS Recovery → Advanced → Enable ADB
```

```powershell
mkdir C:\mona_work\out\logs -Force
adb shell cat /sys/fs/pstore/console-ramoops-0  > C:\mona_work\out\logs\ramoops.txt
adb shell cat /sys/fs/pstore/pmsg-ramoops-0     > C:\mona_work\out\logs\pmsg.txt
adb shell dmesg                                 > C:\mona_work\out\logs\recovery-dmesg.txt
```

If it boots but crashes or a feature is broken:

```powershell
adb logcat -b all -d > C:\mona_work\out\logs\logcat.txt
adb shell dmesg      > C:\mona_work\out\logs\dmesg.txt
```

Send those files to Claude. Logs can contain your phone number / IMEI / SIM IDs, so don't post them publicly unedited.

**Back to stock** (≈ 15 min, keeps the bootloader unlocked), in **bootloader** mode, not fastbootd:

```powershell
adb reboot bootloader         # or Power + Volume Down
powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -SkipBootloader
```

---

## Phase 5: after it boots

| # | Where | What | Time |
|---|---|---|---|
| 5.1 | PS | Stop the keepalive: `powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1 -Stop` | 5 s |
| 5.2 | PS | Fork the device trees (makes `patches/` into real commits): `gh repo fork LineageOS/android_device_motorola_mona --clone=false` and `gh repo fork LineageOS/android_device_motorola_sm6475-common --clone=false`. Ask Claude to push the branches and repoint `local_manifests/mona.xml`. | 5 min |
| 5.3 | WSL | Hardening Phase 1 (kernel cmdline, see `HARDENING.md`). Edit the `BOARD_KERNEL_CMDLINE +=` block at line 73 of `~/lineage/device/motorola/sm6475-common/BoardConfigCommon.mk`, add one flag, then run `start-build.sh`. | edit 5 min, build ≈ 4 h |
| 5.4 | PS | Only `vendor_boot` changes for cmdline flags: `adb reboot fastboot`, `fastboot flash vendor_boot C:\mona_work\out\vendor_boot.img`, `fastboot reboot` | 3 min |
| 5.5 | PS | Check: `adb root`, then `adb shell cat /proc/cmdline`. Re-run the smoke test. | 15 min |

---

## Time summary

| Phase | Your time | Wall clock |
|---|---|---|
| 1. Build | 5 min to start, check occasionally | 12–20 h |
| 2. Collect | 2 min | 2 min |
| 3. Install | 30 min | 30 min |
| 4. First boot / triage | 30 min + | open-ended |
| 5. Keepalive off, forks, hardening step 1 | 30 min | ≈ 5 h (one rebuild) |

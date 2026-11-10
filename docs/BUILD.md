# Lane 2 — From-source build (`lineage-24.0`)

This is the real port. Read `docs/STATUS.md` first for the current blockers.

**Reality check:** the only published `mona` tree is on `lineage-24.0`, which is **Android 17**.
The stock vendor blobs come from W1VAS36, whose **vendor partition is an Android 15 / 202404 freeze**
(the phone reports Android 16, but only its system side is 16). Running a newer system on an older,
frozen vendor is how Treble is meant to work. Here, though, it shows up as AIDL version conflicts
(`STATUS.md` §2), and it is the single biggest risk in this project. If it refuses to boot, the fallback
is either an A17 firmware release from Motorola, or backporting the device tree to `lineage-23.2`
(a significant job — see §7).

---

## 1. Host requirements

- WSL2 Ubuntu 24.04, **ext4** filesystem (never `/mnt/c`).
- ~400 GB free: source ~150 GB, `out/` ~150 GB, ccache ~50 GB.
- **WSL memory: as much as the host can spare, plus ≥ 32 GB swap.** Measured on lineage-24.0: once
  the blob errors are gone, `soong_build` analysis uses **~24 GB** (all 9.7 GB of RAM plus 14+ GB of swap on a
  10 GB WSL). It keeps progressing, but thrashes. 32 GB of host RAM is the comfortable minimum. Compile jobs need roughly
  1 GB each on top of that.
- `nproc` ≥ 8.

> **Windows hosts with a small system drive:** `scripts/setup-build-wsl.ps1` exports the existing
> `Ubuntu-24.04` and imports it as `lineage-build` on another drive (default `E:\WSL\lineage-build`).
> It creates a `builder` user with passwordless sudo and writes `%USERPROFILE%\.wslconfig`.
> The original distro is left alone. The script's default is 10 GB RAM / 24 GB swap; raise it to
> `memory=16GB` / `swap=32GB` (see above). Do not start `repo sync` until `df -h ~` inside the
> distro shows ≥ 400 GB.
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\scripts\setup-build-wsl.ps1
> ```

Check the WSL disk actually has room before syncing:

```bash
df -h ~
```

---

## 2. Dependencies

```bash
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/wsl-deps.sh
```

Note: Android 16/17 needs **JDK 21**, not 17. The handoff doc's `openjdk-17-jdk` was wrong.

---

## 3. Sync

```bash
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/lineage-sync.sh
```

That does:

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs
cp local_manifests/mona.xml .repo/local_manifests/
repo sync -c -j8 --force-sync --no-clone-bundle --no-tags
```

`--git-lfs` is needed for prebuilt blobs in some Lineage repos.

### 3.1 Watch it — progress bar + ETA

`repo sync` gives no overall ETA, so `scripts/sync-watch.sh` derives one from
disk usage (monotonic) and prints milestone lines at 10/25/50/75/90/100 %.

```powershell
# start the sync detached, then follow it with the bar
powershell -ExecutionPolicy Bypass -File .\scripts\sync-status.ps1 -Start -Watch

# from a second terminal: one snapshot
powershell -ExecutionPolicy Bypass -File .\scripts\sync-status.ps1

# raw repo output
wsl -d lineage-build -u builder -- tmux attach -t sync
```

Output looks like:

```
[##########----------------------]  33%  49.8 GiB / 150 GiB  6.2 MiB/s  ETA 4h 31m  Fetching projects
  >> milestone  25%   37.4 GiB on disk   ETA 5h 02m
  >> 14:22:10   41%  6.4 MiB/s  ETA 3h 58m
```

Ctrl+C stops the bar, **not** the sync — it runs in tmux.

When the watcher is not attached to a real terminal (which is what happens
through `wsl.exe` from PowerShell), it cannot redraw in place, so it prints one
timestamped bar per sample instead:

```
14:22:10 [#####---------------------------]   8%  12.1 GiB / 150 GiB  6.2 MiB/s  ETA 6h 18m  syncing
14:22:30 [######--------------------------]  10%  15.0 GiB / 150 GiB  6.1 MiB/s  ETA 6h 09m  syncing
  >> milestone  10%   15.0 GiB on disk   ETA 6h 09m
```

That is the intended behaviour, not a failure. For a true single-line redraw,
run the watcher inside a WSL terminal:

```bash
wsl -d lineage-build -u builder
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/sync-watch.sh
```

Tuning (all optional):

| env | default | meaning |
|---|---|---|
| `TARGET_GB` | 150 | expected final source size; sets the 100 % mark |
| `INTERVAL` | 20 | seconds between `du` samples |
| `HEARTBEAT` | 300 | seconds between persistent status lines |
| `DU_PATH` | `$SRC_DIR/.repo` | what gets measured |

`TARGET_GB` is a guess until the first sync completes. If the bar sits at 100 %
before repo finishes, the tree is bigger than 150 GiB — the ETA stays correct,
only the percentage is off.

If bash complains about `$'\r'` or `: command not found` on the first line, the
script picked up Windows line endings. Fix once:

```bash
sed -i 's/\r$//' /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/*.sh
```

### 3.2 Check the checkout, then apply this repo's patches

`repo sync` can report success while leaving a project half checked out. This happened to
`device/generic/car` (no index, most files missing), and it surfaces much later as
`VehicleEmulator` undefined. Check for it, and repair it rather than patching around it:

```bash
cd ~/lineage
git -C device/generic/car status --short | head     # must not list hundreds of deleted files
repo sync -l device/generic/car                      # repair from the local objects if it does
```

Then apply the tree adaptations for the W1VAS36 firmware (`patches/README.md` explains each one):

```bash
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/apply-patches.sh
```

The script is idempotent. Re-run it after every `repo sync`. A `--force-sync` that resets
`device/motorola/*` will silently drop the patches otherwise.

---

## 4. Extract vendor blobs from your stock firmware

The device tree expects `vendor/motorola/mona/` and `vendor/motorola/sm6475-common/`.
Generate them from your own firmware — blobs are **not** redistributed here.

Run the wrapper:

```bash
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/extract-blobs.sh
```

It **mirrors** the firmware folder into `~/work/fw` on every run
(`rsync -a --delete`, ~1 minute for 8.9 GB), then runs:

```bash
cd ~/lineage/device/motorola/mona
./extract-files.py ~/work/fw
```

A clean mirror each time is deliberate. The extractor *deletes* what it
consumes (`super.img_sparsechunk.*`, `vendor.img`, `system_ext.img`,
`recovery.img`), so "resuming" a half-finished dump would find nothing left to
extract and silently produce empty vendor trees.

The full output is saved to `~/work/extract.log`.

`extract-files.py` (extract-utils) handles everything: it finds the 25
`super.img_sparsechunk.*` files, sorts them numerically, unsparses them into
`super.img`, splits the logical partitions with its built-in LP reader, unpacks
ext4 with `debugfs` and erofs with `fsck.erofs`, then copies the files listed in
`proprietary-files.txt`.

> **The extractor works inside its source directory and deletes what it consumes.**
> Pointing it at `/mnt/c/mona_firmware/...` would delete the 25 sparse chunks that
> `restore-stock.ps1` needs. The wrapper copies the folder to ext4 first for that reason.

Requirements:

```bash
sudo apt install erofs-utils e2fsprogs cpio rsync
```

`cpio` is not optional: `recovery.img` is in the firmware folder, and without
cpio the extractor prints

```
Warning: Failed to extract partition recovery: Failed to find executable path for: cpio
```

and skips it. The wrapper installs cpio automatically if it is missing.

The extractor also calls the prebuilt
`prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-objdump` directly
(for the GraphicBuffer size fixup). If that file is missing, the run dies with
`ValueError: Failed to find executable path for: .../llvm-objdump`. The wrapper
runs `scripts/fix-extract-tools.sh`, which links a working `llvm-objdump` into
that path (preferring the prebuilt clang in the tree, falling back to
`sudo apt install llvm`).

Do **not** build `lpunpack` for this. The extractor has its own LP reader, and
`lunch lineage_mona-userdebug` cannot work before
`vendor/motorola/mona/BoardConfigVendor.mk` exists — `BoardConfig.mk` hard-includes it
and `device.mk` hard-inherits `mona-vendor.mk`. Extracting blobs first breaks the
chicken-and-egg.

If you ever unpack `super` by hand, `cat chunk.*.img` is wrong: the shell sorts
`chunk.10.img` before `chunk.2.img`. Zero-pad the names (`chunk.%02d.img`) or sort
numerically.

Expect missing-file warnings. The list of files it could not find is your first to-do.

**Pinned blobs.** The upstream tree was made from firmware `W1UANS36H.29-25-2-6`. Entries pinned with
`|sha1|sha1` (for example the WFD block in `sm6475-common/proprietary-files.txt`) will **mismatch** on
W1VAS36. extract-utils then copies the stock file but **skips its fixups**, which shows up later
as an AIDL version conflict. Check `~/work/extract.log` for `expected hash` lines, and remove those
pins (or run the extractor with `--kang`).

---

## 5. Tree issues

The issues below are fixed by `patches/` (§3.2):

| Issue | Where | Fix in patches |
|---|---|---|
| `hardware.sku.XT2405V.prop` (2024 SKU) | `device.mk`, `props/` | replaced by `hardware.sku.XT2517-1.prop` |
| `PRODUCT_SHIPPING_API_LEVEL := 34` | `device.mk` | → 35 (shipped on Android 15) |
| soong namespace `sm8450` (does not exist) | both `extract-files.py`, `sm6475-modules/Android.bp` | → `sm8450-6.6` / `kernel/motorola/sm6475` |
| ~290 listed blobs absent from W1VAS36, ~110 present but unlisted | `proprietary-files*.txt` | trimmed / added |
| AIDL version fixups (allocator, biometrics, rkp, audio types) | `extract-files.py` | added |

These must stay as they are:

| Setting | Why |
|---|---|
| `BOARD_AVB_ROLLBACK_INDEX := 20` and `BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := 20` | Stock firmware uses rollback index 20. A lower value will not boot. |

The **current blockers** (four AIDL conflicts) and their proposed fixes are in `STATUS.md` §2.

---

## 6. Build

```bash
source build/envsetup.sh
breakfast mona          # resolves to lunch target lineage_mona-cp2a-userdebug

export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

mka bacon -j4           # raise -j only once WSL has >= 16 GB (see §1)
```

`scripts/run_build.sh` wraps exactly this and tees to `~/build.log`. **Launch it with `scripts/start-build.sh`**,
which runs it detached in a `tmux` session. A build started from a terminal or `wsl -e bash -c …` dies with
SIGHUP when that window closes. On a 10 GB WSL, soong analysis alone takes about 3 hours, and one closed window
has already thrown away a finished analysis.

tmux alone is **not enough on WSL**: WSL terminates the whole distro shortly after the last `wsl.exe`
client disconnects, which kills tmux too (verified on WSL 2.7.11). Start a hidden keepalive client on
the Windows side first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1          # once; idempotent
```

```bash
bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/start-build.sh
tmux attach -t build        # Ctrl-b d to detach again
```

When the build is done: `.\scripts\wsl-keepalive.ps1 -Stop` (the distro then shuts down normally).

Soong errors land in `out/soong/siso_output` and `out/error.log`; `scripts/dev/` has the probes used to
chase them. A signal or cancellation is recorded in `out/soong.log` (`grep -i signal out/soong.log`).

Outputs in `out/target/product/mona/`:

```
boot.img  init_boot.img  vendor_boot.img  dtbo.img  vbmeta.img  vbmeta_system.img
lineage-24.0-*-mona.zip
```

### Flash (first boot)

> **Untested: no build has completed yet.** The sequence below is the expected one.
> On this device the **bootloader** has rejected a modified `init_boot` with
> `Preflash validation failed` (see `ROOT-MAGISK.md`). If any image is rejected there, flash it from
> **fastbootd** instead (`adb reboot fastboot` from a booted system, or recovery → *Enter fastboot*).
> Check `fastboot getvar is-userspace` to see which mode you are in.

```bash
adb reboot bootloader
fastboot flash boot        boot.img
fastboot flash init_boot   init_boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash dtbo        dtbo.img
fastboot flash vbmeta      vbmeta.img
fastboot flash vbmeta_system vbmeta_system.img

fastboot reboot fastboot
fastboot flash system      system.img
fastboot flash system_ext  system_ext.img
fastboot flash product     product.img
fastboot flash vendor      vendor.img
fastboot flash vendor_dlkm vendor_dlkm.img

fastboot -w
fastboot reboot
```

Always keep `RESTORE-STOCK.md` open in another window the first time.

### Smoke test (gate for every later change)

A build counts as "boots" only when all of these pass. Record results in `STATUS.md`.

| Area | Check |
|---|---|
| Identity | `getprop ro.lineage.version` and `ro.build.version.release` = 17; `ro.product.device` = `mona` |
| SELinux | `getenforce` = Enforcing (permissive is OK for bring-up only; note it) |
| Display / touch | both panel vendors (CSOT, Tianma) if available; touch, 120 Hz |
| Stylus | pen input, and the `hall_pen` dock/undock event |
| Fingerprint | enrol and unlock (Goodix or Egis, whichever the unit has) |
| Telephony | SIM / eSIM detected, calls, SMS, mobile data, VoLTE |
| Wi-Fi / BT / NFC | connect, pair, tap |
| Camera | all three sensors, photo + video |
| Audio | speaker (both amps), earpiece, mic, headset |
| Charging | wired + wireless; battery stats sane |
| Sensors | rotation, proximity during calls |

---

## 7. If you really need Android 16 from source

You would have to backport:

1. `device/motorola/mona` → `lineage-23.2`
2. `device/motorola/sm6475-common` → `lineage-23.2`
3. `kernel/motorola/sm6475*` → `lineage-23.2` (or the `lineage-23.2` kernel branch if it exists)

Device trees are mostly version-agnostic; the pain is in `sm6475-common` (HAL interfaces,
sepolicy, `BoardConfigCommon.mk` API assumptions) and the kernel's `ext_config` fragments.
Budget days, not hours, and expect to bisect boot failures via `adb logcat` / `pstore`.

# Hardening roadmap — GrapheneOS-derived features on LineageOS `mona`

**Goal:** after LineageOS 24.0 runs on `mona`, bring in GrapheneOS-style hardening one small,
testable piece at a time. Start with the least invasive pieces and work toward the larger ones.

> This is **not** GrapheneOS and must never be called that. GrapheneOS only supports devices
> that meet its hardware and verified-boot requirements; a Motorola with an unlocked bootloader
> does not (see `STATUS.md` §4). The aim here is narrower and achievable: port individual
> hardening features that do not depend on Pixel hardware.

---

## Ground rules

1. **Phase 0 comes first.** Nothing here starts until a plain `lineage_mona-userdebug` build
   boots and passes the smoke test in `BUILD.md` §6 (telephony, Wi-Fi, BT, camera, fingerprint, stylus).
2. **One feature per change.** Each feature gets its own patch set under `patches/hardening/<feature>/`
   (created when the first feature lands), a short README, and a before/after test. If it breaks boot, it is reverted without touching others.
3. **Track upstream, don't fork blindly.** Reference the GrapheneOS commit each patch came from
   (repo + hash) in the patch header so rebases stay possible.
4. **Licences:** GrapheneOS code is Apache-2.0 / MIT (e.g. `hardened_malloc`) or GPL-2.0 (kernel).
   Keep their copyright headers intact.

---

## Phase 1 — kernel command line hardening (lowest risk)

No code changes, only `BOARD_KERNEL_CMDLINE` in `device/motorola/sm6475-common` (with boot header v4
it goes into the `vendor_boot` cmdline; `androidboot.*` keys go into bootconfig instead). Each flag
can be toggled independently.

- **Check:** on a userdebug build, `adb root && adb shell cat /proc/cmdline`. Plain `adb shell` cannot
  read it. Then compare boot time and benchmarks.
- **Before adding a flag**, check the stock GKI config (`/proc/config.gz`, or IKCONFIG in `boot.img`).
  Some of these may already be on by default in `android15-6.6`.

| Flag | Effect | Risk |
|---|---|---|
| `init_on_alloc=1` | zero heap/page allocations | small perf cost |
| `init_on_free=1` | zero memory on free | measurable perf cost — benchmark |
| `page_alloc.shuffle=1` | randomise page allocator free lists | negligible |
| `slab_nomerge` | stop merging slab caches (limits heap-spray reach) | small memory cost |
| `randomize_kstack_offset=on` | per-syscall kernel stack offset randomisation | negligible |

Watch for vendor modules (camera, display, modem) that misbehave with zeroing.
That is the main way this phase can fail.

## Phase 2 — `hardened_malloc`

- Source: `GrapheneOS/hardened_malloc` (MIT), plus GrapheneOS `platform_bionic` integration patches.
- Use the **light** config first (`CONFIG_LIGHT`), then the default config once stable.
- Needs per-app opt-outs for known-incompatible vendor processes. Expect some Qualcomm/Moto
  blobs (camera HAL, audio HAL) to crash on use-after-free/overflow that stock malloc tolerated.
  Collect those as tombstones; fix or exempt them, one at a time.
- Prior art: DivestOS (discontinued Dec 2024) shipped hardened_malloc on Lineage bases. Its patch
  sets are a useful reference for the vendor-exemption list.

## Phase 3 — small framework / SystemUI features

Self-contained patches with no hardware dependency:

| Feature | Area | Size |
|---|---|---|
| Auto-reboot timer (reboot after N hours locked) | `frameworks/base` | small |
| PIN scrambling on the lock screen | SystemUI | small |
| Per-connection Wi-Fi MAC randomisation | `packages/modules/Wifi` | small–medium |
| `INTERNET` as a user-toggleable permission (Network toggle) | `frameworks/base`, `packages/modules/Connectivity` | medium |
| Sensors permission toggle | `frameworks/base`, `frameworks/native` | medium |

## Phase 4 — larger features (only after 1–3 are stable)

- Storage Scopes / Contact Scopes
- Exploit-protection compatibility toggles per app
- USB-C new-peripheral blocking when locked. Needs a kernel `deny_new_usb` knob plus a Moto/QCOM USB HAL
  hook, and is hardware-dependent.
- Sandboxed Google Play compatibility layer. This is very large and should be its own sub-project.

## Out of reach on this hardware

| GrapheneOS feature | Why not on `mona` |
|---|---|
| Relocked bootloader with own AVB key (green/yellow boot) | Moto bootloader will not accept a custom root of trust; device stays `orange` |
| Hardware-backed attestation of the OS | depends on the above |
| Pixel-specific firmware/radio hardening, Titan M2 features | no equivalent hardware |
| GrapheneOS update server / seamless verified OTAs | needs the verified-boot chain |

<#
.SYNOPSIS
    Triage and repair the post-GSI problems on the Moto G Stylus 5G (2025) / mona.

.DESCRIPTION
    READ-ONLY by default. Reports:

      - FRP state (this is what blocks setting a screen lock)
      - SIM / subscription state (the "can't re-enable the SIM" bug)
      - IMS / VoLTE (the phh CAF IMS switch - why calls fail)
      - Telecom / in-call UI
      - Magisk root state
      - phh overlays and preferred network mode (5G)

    With -Fix it applies the safe, reversible repairs:

      - preferred_network_mode -> 33 (NR/LTE/GSM/WCDMA) for 5G
      - re-enable the disabled UICC application in the telephony DB (root only;
        without root use -ResetTelephony to clear the provider instead)
      - erase the FRP persistent-data block (reboots to fastbootd, because the
        bootloader refuses `erase frp` on Motorola)

    IMS and Magisk still need a UI action / fastbootd reflash; the script
    prints the exact steps at the end. For those two use
    scripts/fastbootd-repair.ps1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\gsi-triage.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\gsi-triage.ps1 -Fix

.EXAMPLE
    # last resort for a SIM that stays disabled after -Fix + reboot
    powershell -ExecutionPolicy Bypass -File .\scripts\gsi-triage.ps1 -Fix -ResetTelephony
#>

param(
    [switch]$Fix,
    [switch]$ResetTelephony,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Continue'   # native tools write to stderr; PS 5.1 turns that into terminating errors
. (Join-Path $PSScriptRoot '_common.ps1')

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Info($m) { Write-Host "  $m" }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Sh([string]$Cmd) {
    $o = (& adb shell $Cmd 2>&1 | Out-String)
    return $o.Trim()
}
function Prop([string]$Name) { return (Sh "getprop $Name").Trim() }
function AdbState {
    $s = (& adb get-state 2>$null) | Select-Object -First 1
    if ($s) { $s.ToString().Trim() } else { $null }
}

function Wait-Adb([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((AdbState) -eq 'device') { return $true }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

function Wait-Fastboot([int]$TimeoutSeconds = 90) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $fb = (Get-Command fastboot -ErrorAction SilentlyContinue).Source
    if (-not $fb) { return $false }
    while ((Get-Date) -lt $deadline) {
        $job = Start-Job -ScriptBlock { param($exe) & $exe getvar product 2>&1 } -ArgumentList $fb
        if (Wait-Job $job -Timeout 6) {
            $o = (Receive-Job $job | Out-String)
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            if ($o -match 'product:') { return $true }
        } else {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

# ================================================================== report
Step 'Device'
Ensure-PlatformTools
if ((AdbState) -ne 'device') {
    Die @'
no adb device.

Enable USB debugging, accept the prompt, then re-run:
  adb devices        # must print: <serial>  device
'@
}
Ok 'adb device'
Info "lineage     : $(Prop ro.lineage.version)"
Info "android     : $(Prop ro.build.version.release)"
Info "device      : $(Prop ro.product.device)"
Info "slot        : $(Prop ro.boot.slot_suffix)"
Info "boot state  : $(Prop ro.boot.verifiedbootstate)"
Info "flash locked: $(Prop ro.boot.flash.locked)"
Info "vndk        : $(Prop ro.vndk.version)"

Step 'Factory Reset Protection  (blocks screen lock)'
$frp = Prop 'ro.frp.pst'
Info "ro.frp.pst  : $frp"
Info "partitions  : $(Sh "ls /dev/block/by-name 2>/dev/null | grep -iE '^frp$|^persist$|^metadata$' | tr '\n' ' '")"

Step 'SIM / subscription'
Info (Sh "dumpsys telephony.registry | grep -E 'mServiceState=' | head -2")
Info '--- siminfo ---'
# The telephony provider only serves this table to the phone/system UID, so as
# shell this is expected to throw SecurityException. It still tells us whether
# the provider is up; the value itself needs root (or `pm clear`, see -Fix).
Info (Sh "content query --uri content://telephony/siminfo --projection _id,sub_id,sim_slot_index,uicc_applications_enabled,display_name 2>&1")
Info '--- cmd phone (runs inside the phone process; may expose a uicc switch) ---'
Info (Sh "cmd phone help 2>&1 | grep -iE 'uicc|applications|sim-' | head -10")

Step 'IMS / VoLTE  (why calls fail)'
Info (Sh "getprop | grep -iE 'phh.ims|volte|wfc|vt_'")

Step 'Telecom / in-call UI'
Info "dialer role : $(Sh "cmd role get-role-holders android.app.role.DIALER")"
Info (Sh "dumpsys telecom | grep -iE 'InCallService|isDefault' | head -10")

Step 'Root'
Info (Sh "ls -l /debug_ramdisk /system/bin/su 2>&1 | head -12")
Info (Sh "pm list packages 2>/dev/null | grep -i magisk")

Step 'phh overlays / network mode'
Info (Sh "cmd overlay list 2>/dev/null | grep -iE 'phh|ims|telephony'")
Info "preferred_network_mode : $(Sh "settings get global preferred_network_mode")"

# ================================================================== fixes
if (-not $Fix) {
    Write-Host @"

Read-only run complete.

Re-run with -Fix to apply:
  * preferred network mode 33 (5G/LTE)
  * re-enable the disabled SIM in the telephony DB (root) / clear the provider (-ResetTelephony)
  * erase the FRP block from fastbootd so a screen lock can be set

For root + FRP in one go:
  powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1

"@ -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------- network mode
Step 'Fix: preferred network mode -> 33 (NR/LTE/GSM/WCDMA)'
$r = (& adb shell "settings put global preferred_network_mode 33" 2>&1 | Out-String).Trim()
if ($r) { Info $r }
$r = (& adb shell "settings put global preferred_network_mode1 33" 2>&1 | Out-String).Trim()
if ($r) { Info $r }
Ok "now: $(Sh "settings get global preferred_network_mode")"

# ---------------------------------------------------------- SIM re-enable
Step 'Fix: re-enable the disabled SIM'
# The telephony provider only accepts phone/system UID, so the DB edit needs
# root. As shell we can only reset the whole provider with pm clear.
$isRoot = ((Sh 'id') -match 'uid=0')

if ($isRoot) {
    $upd = (& adb shell "content update --uri content://telephony/siminfo --bind uicc_applications_enabled:i:1" 2>&1 | Out-String).Trim()
    if ($upd) { Info $upd }
    Ok "siminfo: $(Sh "content query --uri content://telephony/siminfo --projection _id,sim_slot_index,uicc_applications_enabled 2>&1")"
} else {
    Warn 'not root: the telephony provider rejects shell (phone/system UID only)'
    if ($ResetTelephony) {
        Warn 'clearing the telephony provider (APNs + SMS/MMS will reset)'
        $r = (& adb shell "pm clear com.android.providers.telephony" 2>&1 | Out-String).Trim()
        Info $r
    } else {
        Info 're-run with -ResetTelephony to clear the provider, or get root first'
    }
}

# ---------------------------------------------------------- IMS (needs root)
Step 'Fix: enable CAF IMS (Qualcomm VoLTE)'
$rootOk = $false
$before = Prop 'persist.sys.phh.ims.caf'
& adb root 2>&1 | Out-Null
Start-Sleep -Seconds 3
$null = Wait-Adb -TimeoutSeconds 20
if ((Sh 'id') -match 'uid=0') {
    $rootOk = $true
    $r = (& adb shell "setprop persist.sys.phh.ims.caf true" 2>&1 | Out-String).Trim()
    if ($r) { Info $r }
    Info "persist.sys.phh.ims.caf = $(Prop 'persist.sys.phh.ims.caf')"
}

if (-not $rootOk) {
    Warn 'adb root is unavailable, so the property cannot be set from here.'
    Write-Host @'
  Do this on the phone instead:
    Open the "Treble Settings" app (me.phh.treble.app)
    -> IMS
    -> enable "CAF IMS"
    -> reboot

  Or enable Developer options -> "Rooted debugging", then re-run this script.
'@ -ForegroundColor Yellow
} elseif ((Prop 'persist.sys.phh.ims.caf') -ne 'true') {
    Warn 'setprop did not take - use the Treble Settings app instead (IMS -> CAF IMS).'
}

# ---------------------------------------------------------- FRP (last)
if ($NoReboot) {
    Step 'FRP block (skipped: -NoReboot)'
    Warn 'run manually: adb reboot fastboot; fastboot erase frp; fastboot reboot'
} else {
    Step 'Fix: erase the FRP persistent-data block'
    if ($frp -match 'by-name/(frp|persist)') {
        $part = $Matches[1]
        if ($part -ne 'frp') {
            Warn "persistent data block lives on '$part'; refusing to erase it (calibration data)."
            Warn 'Tell the operator before touching that partition.'
        } else {
            # The bootloader refuses `erase frp` on Motorola ("frp is NOT erased.
            # Permission denied"). fastbootd writes the block directly, so try there.
            Info 'rebooting to fastbootd (the bootloader blocks erase frp)...'
            & adb reboot fastboot
            if (Wait-Fastboot -TimeoutSeconds 120) {
                $us = (& fastboot getvar is-userspace 2>&1 | Out-String)
                if ($us -notmatch 'is-userspace:\s*yes') {
                    Warn 'this is the bootloader, not fastbootd - erase frp will be denied'
                }
                $o = (& fastboot erase frp 2>&1 | Out-String).Trim()
                Info $o
                if ($o -match 'FAILED|denied|Permission') {
                    Warn 'fastbootd refused as well - FRP needs root (see scripts/fastbootd-repair.ps1)'
                } else {
                    Ok 'frp block erased'
                }
                & fastboot reboot
                Info 'rebooting; waiting for Android...'
                if (Wait-Adb -TimeoutSeconds 240) { Ok 'back in Android' } else { Warn 'Android did not come back in 4 min' }
            } else {
                Warn 'did not reach fastbootd - run manually: adb reboot fastboot; fastboot erase frp'
            }
        }
    } else {
        Warn "could not determine the FRP partition (ro.frp.pst = '$frp')"
        Warn 'run manually: adb reboot fastboot; fastboot erase frp; fastboot reboot'
    }
}

# ================================================================== next
Write-Host @'

==================================================================
Next, on the phone (these are UI/fastboot steps, not scriptable):

1. Treble Settings -> IMS -> CAF IMS -> reboot.
   Then check Settings -> Network & internet -> SIMs -> VoLTE.
   Re-test: outgoing call, incoming call, SMS.

2. SIM still disabled after the reboot?
   - This unit has an eSIM: slot 0 ABSENT + slot 1 NOT_READY is normal.
     Re-enable the profile through the eSIM UI, not a tray:
       Settings -> Network & internet -> SIMs -> T-Mobile -> Use SIM
       Settings -> SIMs -> Add SIM / eSIM manager
   - Still off: re-run with  -Fix -ResetTelephony
   - Last resort: factory reset from Settings.

3. Screen lock:
   - Settings -> Security -> Screen lock -> PIN.
   - If it still says "FRP is active", the erase did not take. The bootloader
     always refuses it; only fastbootd works:
       adb reboot fastboot
       fastboot getvar is-userspace          # yes
       fastboot erase frp
       fastboot reboot

4. Root (su missing):
   - Open the Magisk app. If it says "Installed: N/A", the daemon is
     not running. Re-flash the patched image from fastbootd:
       adb reboot fastboot
       fastboot getvar is-userspace          # yes
       fastboot flash init_boot   .\magisk_patched.img
       fastboot flash init_boot_b .\magisk_patched.img
       fastboot reboot

   Or just run:  .\scripts\fastbootd-repair.ps1   (does 3 and 4 together)
==================================================================
'@ -ForegroundColor Green

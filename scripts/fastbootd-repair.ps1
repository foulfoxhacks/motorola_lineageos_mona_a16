<#
.SYNOPSIS
    Repair the two things the GSI cannot fix from inside Android:
    the FRP persistent-data block (screen lock) and Magisk root.

.DESCRIPTION
    Both repairs are writes to a physical partition, and Motorola's *bootloader*
    refuses them:

        (bootloader) frp is NOT erased. Permission denied.
        FAILED (remote: '')

    fastbootd (userspace fastboot) writes the block device directly and does
    allow them. This script gets you there, does the work, and verifies it.

    Steps:
      1. find the patched init_boot image (default: .\magisk_patched.img)
      2. get into fastbootd (adb reboot fastboot, or bootloader -> reboot)
      3. fastboot erase frp                (screen lock / FRP)
      4. fastboot flash init_boot   <img>  (Magisk, slot a)
      5. fastboot flash init_boot_b <img>  (Magisk, slot b)
      6. reboot and verify `su -c id`

    Nothing is written until you type REPAIR, and stock init_boot.img stays in
    the firmware folder, so unrooting is always possible.

    Read docs/GSI-A16.md (Phase F2) and docs/ROOT-MAGISK.md first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1

.EXAMPLE
    # only the FRP fix, leave root alone
    powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1 -SkipRoot

.EXAMPLE
    # only root, leave FRP alone
    powershell -ExecutionPolicy Bypass -File .\scripts\fastbootd-repair.ps1 -SkipFrp
#>

param(
    [string]$Patched,
    [switch]$SkipFrp,
    [switch]$SkipRoot,
    [switch]$NoReboot,
    [switch]$SkipConfirm,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; PS 5.1 turns that into terminating errors
. (Join-Path $PSScriptRoot '_common.ps1')

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Info($m) { Write-Host "  $m" }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

Ensure-PlatformTools
if (-not (Get-Command adb -ErrorAction SilentlyContinue))      { Die 'adb not found (run get-platform-tools.ps1)' }
if (-not (Get-Command fastboot -ErrorAction SilentlyContinue)) { Die 'fastboot not found (run get-platform-tools.ps1)' }

function Get-AdbState {
    $s = (& adb get-state 2>$null) | Select-Object -First 1
    if ($s) { $s.ToString().Trim() } else { $null }
}

# PS 5.1 turns a native tool's stderr into an ErrorRecord, which then renders
# with "At <script>:<line>" noise. Flatten it to plain text.
function FbOut([string[]]$FbArgs) {
    $o = (& fastboot @FbArgs 2>&1) | ForEach-Object { "$_" } | Out-String
    return $o.Trim()
}

# `fastboot devices` is unreliable in fastbootd on this device, so probe the
# bootloader variable in a short-lived job instead of trusting the device list.
function Test-Fastboot([int]$TimeoutMs = 6000) {
    $fb = (Get-Command fastboot -ErrorAction SilentlyContinue).Source
    if (-not $fb) { return $false }
    $job = Start-Job -ScriptBlock { param($exe) & $exe getvar is-userspace 2>&1 } -ArgumentList $fb
    if (Wait-Job $job -Timeout ($TimeoutMs / 1000)) {
        $o = (Receive-Job $job | Out-String)
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return ($o -match 'is-userspace:')
    }
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return $false
}

function Test-Fastbootd {
    $o = (& fastboot getvar is-userspace 2>&1 | Out-String)
    return ($o -match 'is-userspace:\s*yes')
}

function Wait-Adb([int]$Seconds = 120) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-AdbState) -eq 'device') { return $true }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

function Wait-Fastbootd([int]$Seconds = 120) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Fastboot) -and (Test-Fastbootd)) { return $true }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

function Enter-Fastbootd {
    <# Land in userspace fastboot. Returns $true on success. #>
    if ((Test-Fastboot) -and (Test-Fastbootd)) { return $true }

    if ((Get-AdbState) -eq 'device') {
        Info 'adb reboot fastboot'
        & adb reboot fastboot
        return (Wait-Fastbootd $TimeoutSeconds)
    }

    if (Test-Fastboot) {
        # Bootloader. This device ignores `fastboot reboot fastboot`, so go the
        # long way round: back to Android, then adb reboot fastboot.
        Info 'in the bootloader; trying fastboot reboot fastboot first'
        & fastboot reboot fastboot | Out-Null
        Start-Sleep -Seconds 5
        if ((Test-Fastboot) -and (Test-Fastbootd)) { return $true }

        Info 'not supported here - rebooting to Android and re-entering fastbootd'
        & fastboot reboot | Out-Null
        if (-not (Wait-Adb 180)) { return $false }
        & adb reboot fastboot
        return (Wait-Fastbootd $TimeoutSeconds)
    }

    return $false
}

# ------------------------------------------------------------------ preflight
Step 'Device'

$adbState = Get-AdbState
$inFastboot = Test-Fastboot

if ($adbState -eq 'device') {
    Ok 'adb device'
    Info "lineage     : $(((& adb shell getprop ro.lineage.version) | Out-String).Trim())"
    Info "flash locked: $(((& adb shell getprop ro.boot.flash.locked) | Out-String).Trim())"
    Info "boot state  : $(((& adb shell getprop ro.boot.verifiedbootstate) | Out-String).Trim())"
} elseif ($inFastboot) {
    Ok 'fastboot device'
    Info (FbOut @('getvar', 'is-userspace'))
    Info (FbOut @('getvar', 'securestate'))
    Info (FbOut @('getvar', 'verity-state'))
} else {
    Die @'
no device found.

  - Android booted + USB debugging: adb devices should show it
  - bootloader / fastbootd:          fastboot devices should show it

Unplug/replug the cable and try another USB port if neither works.
'@
}

$localPatched = if ($Patched) { $Patched } else { Join-Path (Get-Location) 'magisk_patched.img' }
if (-not $SkipRoot) {
    if (-not (Test-Path $localPatched)) { Die "missing $localPatched (or pass -Patched <file>)" }
    $len = (Get-Item $localPatched).Length
    $fs = [System.IO.File]::OpenRead($localPatched)
    try { $buf = New-Object byte[] 8; [void]$fs.Read($buf, 0, 8) } finally { $fs.Close() }
    $magic = [System.Text.Encoding]::ASCII.GetString($buf)
    if ($magic -ne 'ANDROID!') { Die "$localPatched is not an Android boot image (magic '$magic')" }
    Ok ("root image  : {0:N2} MiB  {1}" -f ($len / 1MB), $localPatched)
}

# ------------------------------------------------------------------ confirm
Step 'Plan'
$plan = @()
if (-not $SkipFrp)  { $plan += 'fastboot erase frp                 (clears FRP so a screen lock can be set)' }
if (-not $SkipRoot) { $plan += "fastboot flash init_boot   $localPatched" }
if (-not $SkipRoot) { $plan += "fastboot flash init_boot_b $localPatched" }
$plan += 'fastboot reboot'

$plan | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
Write-Host "`n  All of this happens in fastbootd. The bootloader refuses both writes." -ForegroundColor DarkGray

if (-not $SkipConfirm) {
    if ((Read-Host 'Type REPAIR to continue') -ne 'REPAIR') { Die 'aborted' }
}

# ------------------------------------------------------------------ fastbootd
Step 'Entering fastbootd'
if (-not (Enter-Fastbootd)) {
    Die @'
could not reach fastbootd.

Manual route:
  1. boot the phone to Android
  2. adb reboot fastboot
  3. fastboot getvar is-userspace        # must print: yes
  4. fastboot erase frp
  5. fastboot flash init_boot   .\magisk_patched.img
  6. fastboot flash init_boot_b .\magisk_patched.img
  7. fastboot reboot
'@
}
Ok 'in fastbootd'

$slot = (& fastboot getvar current-slot 2>&1 | Select-String 'current-slot:' | Select-Object -First 1)
if ($slot) { Info $slot.ToString().Trim() }

# ------------------------------------------------------------------ frp
$frpOk = $null
if ($SkipFrp) {
    Warn 'FRP erase skipped (-SkipFrp)'
} else {
    Step 'Erasing the FRP persistent-data block'
    $o = FbOut @('erase', 'frp')
    Info $o
    if ($o -match 'FAILED|denied|Permission|not allowed|doesn''t exist') {
        $frpOk = $false
        Warn 'fastbootd cannot touch frp - will zero the block through root after the reboot'
    } else {
        $frpOk = $true
        Ok 'frp erased - set the screen lock after the reboot'
    }
}

# ------------------------------------------------------------------ root
$rootOk = $null
if ($SkipRoot) {
    Warn 'init_boot flash skipped (-SkipRoot)'
} else {
    Step 'Flashing init_boot (slot a)'
    $o = FbOut @('flash', 'init_boot', $localPatched)
    Info $o
    if ($LASTEXITCODE -eq 0) {
        $rootOk = $true
        Ok 'init_boot flashed'
    } else {
        $rootOk = $false
        Warn 'init_boot rejected'
    }

    if ($rootOk) {
        Step 'Flashing init_boot_b (slot b)'
        $o = FbOut @('flash', 'init_boot_b', $localPatched)
        Info $o
        if ($LASTEXITCODE -ne 0) {
            Warn 'init_boot_b failed (root still works on the current slot)'
        } else {
            Ok 'init_boot_b flashed'
        }
    }
}

# ------------------------------------------------------------------ reboot
if ($NoReboot) {
    Step 'Reboot skipped (-NoReboot)'
    Info 'run: fastboot reboot'
} else {
    Step 'Rebooting'
    & fastboot reboot
    if (Wait-Adb 240) { Ok 'back in Android' } else { Warn 'Android did not come back in 4 min' }
}

# ------------------------------------------------------------------ verify
if (-not $SkipRoot -and $rootOk -and -not $NoReboot -and (Get-AdbState) -eq 'device') {
    Step 'Verifying root'
    Start-Sleep -Seconds 20     # magiskd needs a moment on first boot
    $id = ((& adb shell 'su -c id' 2>&1 | Out-String).Trim())
    Info $id
    if ($id -match 'uid=0') {
        Ok 'root is live'

        # fastbootd on mona has no `frp` partition at all ("Partition doesn't
        # exist"), so the erase above can never work. With root the persistent
        # data block can be zeroed directly.
        if ($frpOk -ne $true -and -not $SkipFrp) {
            Step 'Erasing FRP through root (fastbootd has no frp partition)'
            $dev = ((& adb shell "su -c 'ls -l /dev/block/by-name/frp'" 2>&1) | ForEach-Object { "$_" } | Out-String).Trim()
            Info $dev
            if ($dev -match 'No such file') {
                Warn 'no /dev/block/by-name/frp - check: su -c "ls -l /dev/block/by-name | grep -i frp"'
                Warn "ro.frp.pst says: $(((& adb shell 'getprop ro.frp.pst') | Out-String).Trim())"
            } else {
                $dd = ((& adb shell "su -c 'dd if=/dev/zero of=/dev/block/by-name/frp bs=4096 count=8'" 2>&1) | ForEach-Object { "$_" } | Out-String).Trim()
                Info $dd
                if ($dd -match 'denied|No such file|Read-only') {
                    Warn 'could not zero the frp block'
                } else {
                    Ok 'frp block zeroed - reboot, then set the PIN'
                }
            }
        }

        Info 'next: adb shell "su -c ''setprop persist.sys.phh.ims.caf true''"'
        Info '      adb shell "su -c ''content update --uri content://telephony/siminfo --bind uicc_applications_enabled:i:1''"'
        Info '      adb reboot'
    } else {
        Warn 'su is not answering yet - open the Magisk app; if it says "Installed: N/A" the daemon is not running'
        Warn 'check: adb shell "getprop ro.boot.verifiedbootstate" (orange = unlocked)'
    }
}

Write-Host @'

==================================================================
After the reboot:

  screen lock : Settings -> Security -> Screen lock -> PIN
                (works once FRP is cleared)

  calls       : Treble Settings -> IMS -> CAF IMS -> reboot
                or, with root:
                  adb shell "su -c 'setprop persist.sys.phh.ims.caf true'"

  SIM off     : with root:
                  adb shell "su -c 'content update --uri content://telephony/siminfo --bind uicc_applications_enabled:i:1'"
                without root:
                  adb shell "pm clear com.android.providers.telephony"
                  adb reboot
                (clears APNs + SMS/MMS, the carrier config re-provisions APNs)
==================================================================
'@ -ForegroundColor Green

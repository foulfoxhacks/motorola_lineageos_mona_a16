<#
.SYNOPSIS
    Root the Moto G Stylus 5G (2025) / XT2517-1 with Magisk via init_boot.

.DESCRIPTION
    Automates everything except the one step that must happen on the phone:
    Magisk's "Select and Patch a File".

    Flow:
      1. locate stock init_boot.img in the firmware folder
      2. if a patched image is already on the phone, offer to reuse it
      3. otherwise push the stock image and wait while you patch it in Magisk
      4. pull the patched image back and sanity-check it
      5. reboot to bootloader (polling until fastboot appears) and flash
         init_boot + init_boot_b, falling back to fastbootd on Motorola's
         "Preflash validation failed"
      6. reboot and verify with `su -c id`

    If the phone is already in the bootloader and .\magisk_patched.img exists
    locally, the script skips straight to flashing.

    Read docs/ROOT-MAGISK.md first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\root-magisk.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\root-magisk.ps1 -ForcePatch
#>

param(
    [string]$FwDir,
    [string]$Patched,
    [string]$RemotePatched,
    [int]$WaitMinutes = 15,
    [switch]$ForcePatch,
    [switch]$SkipConfirm
)

$ErrorActionPreference = 'Continue'   # native tools write progress/errors to stderr; PS 5.1 would turn those into terminating errors
. (Join-Path $PSScriptRoot '_common.ps1')

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

Ensure-PlatformTools
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { Die 'adb not found (run get-platform-tools.ps1)' }
if (-not (Get-Command fastboot -ErrorAction SilentlyContinue)) { Die 'fastboot not found (run get-platform-tools.ps1)' }

if (-not $FwDir) { $FwDir = Get-FirmwareDir }
if (-not $FwDir) { Die 'firmware folder not found' }

$stock = Join-Path $FwDir 'init_boot.img'
if (-not (Test-Path $stock)) { Die "missing $stock" }

$localPatched = if ($Patched) { $Patched } else { Join-Path (Get-Location) 'magisk_patched.img' }

function Get-AdbState {
    $s = (& adb get-state 2>$null) | Select-Object -First 1
    if ($s) { $s.ToString().Trim() } else { $null }
}

function Get-FastbootDevices {
    (& fastboot devices 2>$null) | Where-Object { $_ -match '\S' }
}

function Wait-Fastboot {
    param([int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $d = @(Get-FastbootDevices)
        if ($d.Count -gt 0) { return $d }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return @()
}

function Test-Fastbootd {
    $u = (& fastboot getvar is-userspace 2>&1 | Out-String)
    return ($u -match 'yes')
}

function Wait-Fastbootd {
    param([int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-FastbootDevices).Count -gt 0 -and (Test-Fastbootd)) { return $true }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

function Enter-Fastbootd {
    <# Tries to land in userspace fastboot (fastbootd). Returns $true on success. #>
    param([int]$TimeoutSeconds = 90)

    if (@(Get-FastbootDevices).Count -gt 0 -and (Test-Fastbootd)) { return $true }

    if (@(Get-FastbootDevices).Count -gt 0) {
        & fastboot reboot fastboot
    } elseif ((Get-AdbState) -eq 'device') {
        & adb reboot fastboot
    } else {
        return $false
    }

    return (Wait-Fastbootd -TimeoutSeconds $TimeoutSeconds)
}

function Get-RemotePatched {
    <# Newest magisk_patched-*.img in /sdcard/Download, or $null. #>
    $raw = & adb shell 'ls -t /sdcard/Download/magisk_patched-*.img 2>/dev/null'
    @($raw) |
        ForEach-Object { ($_ -replace "`r", '').Trim() } |
        Where-Object { $_ -match '/magisk_patched-.*\.img$' } |
        Select-Object -First 1
}

function Test-BootImageMagic {
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 8
        [void]$fs.Read($buf, 0, 8)
    } finally { $fs.Close() }
    [System.Text.Encoding]::ASCII.GetString($buf)
}

# ------------------------------------------------------------------ mode
Step 'Checking device'

$adbState    = Get-AdbState
$fbDevices   = @(Get-FastbootDevices)
$haveLocal   = Test-Path $localPatched
$skipToFlash = $false

if ($adbState -eq 'device') {
    $devName = ((& adb shell getprop ro.product.device) | Out-String).Trim()
    $devFp   = ((& adb shell getprop ro.build.fingerprint) | Out-String).Trim()
    Write-Host "    adb:     $devName"
    Write-Host "    build:   $devFp"
} elseif ($fbDevices.Count -gt 0) {
    Write-Host "    fastboot: $($fbDevices[0])"
    if (-not $haveLocal) {
        Die "phone is in fastboot, but $localPatched does not exist. Reboot to Android and re-run."
    }
    Write-Host "    using existing $localPatched" -ForegroundColor Green
    $skipToFlash = $true
} else {
    Die @"
no device found.
  - Android booted + USB debugging: adb devices should show it
  - bootloader screen: fastboot devices should show it
If neither works, unplug/replug the cable and try another USB port.
"@
}

# ------------------------------------------------------------------ patch
$remote = $null

if (-not $skipToFlash) {
    if ($RemotePatched) {
        $remote = $RemotePatched
    } elseif (-not $ForcePatch) {
        Step 'Looking for an existing patched image on the phone'
        $remote = Get-RemotePatched
        if ($remote) {
            Write-Host "    found: $remote" -ForegroundColor Green
            if (-not $SkipConfirm) {
                $ans = Read-Host 'Use this one instead of patching again? [Y/n]'
                if ($ans -match '^[Nn]') { $remote = $null }
            }
        } else {
            Write-Host '    none found' -ForegroundColor DarkGray
        }
    }

    if (-not $remote) {
        # ---------------------------------------------------------- push stock
        Step 'Pushing stock init_boot.img'
        & adb push $stock /sdcard/Download/init_boot.img
        if ($LASTEXITCODE -ne 0) { Die 'adb push failed' }

        # ---------------------------------------------------------- patch
        Step 'Patch it in Magisk on the phone'
        Write-Host @"
    On the phone:
      1. open Magisk
      2. tap Install
      3. choose "Select and Patch a File"
      4. pick Download/init_boot.img
      5. wait for the "All done!" toast

    Magisk writes Download/magisk_patched-<version>_xxxxx.img
    This script is watching that folder - no need to press anything here.
"@ -ForegroundColor Yellow

        Step 'Waiting for the patched image'
        $deadline = (Get-Date).AddMinutes($WaitMinutes)
        while ((Get-Date) -lt $deadline) {
            $remote = Get-RemotePatched
            if ($remote) { break }
            Start-Sleep -Seconds 3
            Write-Host '.' -NoNewline
        }
        Write-Host ''

        if (-not $remote) {
            Write-Host "    Timed out after $WaitMinutes minutes." -ForegroundColor Yellow
            Write-Host "`n    /sdcard/Download contains:" -ForegroundColor Yellow
            & adb shell 'ls -l /sdcard/Download'

            $pkgs = (& adb shell 'pm list packages' | Out-String)
            if ($pkgs -notmatch 'magisk') {
                Write-Host "`n    Magisk is NOT installed on the phone." -ForegroundColor Red
                Write-Host '    Install: https://github.com/topjohnwu/Magisk/releases/latest  (Magisk-v*.apk)' -ForegroundColor Yellow
            } else {
                Write-Host "`n    Magisk is installed, but no patched file appeared." -ForegroundColor Yellow
                Write-Host '    Search the whole phone with:' -ForegroundColor Yellow
                Write-Host '      adb shell "find /sdcard -iname ''magisk_patched*'' 2>/dev/null"' -ForegroundColor DarkGray
            }

            Write-Host @"

    Checklist:
      1. open Magisk
      2. tap Install
      3. choose "Select and Patch a File"
      4. pick Download/init_boot.img
      5. wait for the "All done!" toast

    If the image ended up somewhere else:
      -RemotePatched /sdcard/Download/whatever.img
"@ -ForegroundColor Yellow
            Die 'no patched image found'
        }
        Write-Host "    $remote" -ForegroundColor Green
    }

    # -------------------------------------------------------------- pull
    Step 'Pulling the patched image'
    & adb pull $remote $localPatched
    if ($LASTEXITCODE -ne 0) { Die 'adb pull failed' }
}

# ------------------------------------------------------------------ validate local
$patchLen = (Get-Item $localPatched).Length
Write-Host ("    {0:N2} MiB -> {1}" -f ($patchLen / 1MB), $localPatched)

$magic = Test-BootImageMagic $localPatched
if ($magic -ne 'ANDROID!') {
    Die "file is not an Android boot image (magic was '$magic'). Delete it and retry."
}

$stockLen = (Get-Item $stock).Length
if ($patchLen -lt ($stockLen * 0.5) -or $patchLen -gt ($stockLen * 1.5)) {
    Write-Host "    WARN: patched size $patchLen differs a lot from stock $stockLen" -ForegroundColor Yellow
}

# ------------------------------------------------------------------ confirm
Step 'Confirm'
Write-Host @"
This will flash the patched image to BOTH slots:
  init_boot    (current slot)
  init_boot_b  (other slot)

Stock init_boot.img stays on disk, so this is reversible.
"@ -ForegroundColor Yellow

if (-not $SkipConfirm) {
    if ((Read-Host 'Type ROOT to continue') -ne 'ROOT') { Die 'aborted' }
}

# ------------------------------------------------------------------ get to fastbootd
Step 'Entering fastbootd'
$userspace = $false

if ((Get-AdbState) -eq 'device') {
    Write-Host '    adb reboot fastboot' -NoNewline
    & adb reboot fastboot
    $userspace = Wait-Fastbootd -TimeoutSeconds 90
} elseif (@(Get-FastbootDevices).Count -gt 0) {
    $userspace = Enter-Fastbootd -TimeoutSeconds 90
}

if ($userspace) {
    Write-Host '    in fastbootd' -ForegroundColor Green
} else {
    Write-Host '    fastbootd not reachable; will try the bootloader' -ForegroundColor Yellow
    if (@(Wait-Fastboot -TimeoutSeconds 60).Count -eq 0) {
        Die @"
no fastboot device.

Manual route:
  1. boot the phone to Android
  2. adb reboot fastboot
  3. fastboot getvar is-userspace     # must print: yes
  4. fastboot flash init_boot   "$localPatched"
  5. fastboot flash init_boot_b "$localPatched"
  6. fastboot reboot
"@
    }
}

$slotLine = (& fastboot getvar current-slot 2>&1 | Select-String 'current-slot:' | Select-Object -First 1)
if ($slotLine) { Write-Host "    $($slotLine.ToString().Trim())" }
Assert-MonaDevice

# ------------------------------------------------------------------ flash init_boot
Step 'Flashing init_boot'
$ok = $false
& fastboot flash init_boot $localPatched
if ($LASTEXITCODE -eq 0) { $ok = $true }

if (-not $ok) {
    Write-Host "`n    rejected (Motorola preflash validation) - switching to fastbootd" -ForegroundColor Yellow
    if (Enter-Fastbootd -TimeoutSeconds 90) {
        & fastboot flash init_boot $localPatched
        if ($LASTEXITCODE -eq 0) { $ok = $true }
    }
}
if (-not $ok) {
    Die @"
could not flash init_boot.

Manual route:
  1. boot the phone to Android
  2. adb reboot fastboot
  3. fastboot getvar is-userspace     # must print: yes
  4. fastboot flash init_boot   "$localPatched"
  5. fastboot flash init_boot_b "$localPatched"
  6. fastboot reboot
"@
}
Write-Host '    init_boot flashed' -ForegroundColor Green

# ------------------------------------------------------------------ flash init_boot_b
Step 'Flashing init_boot_b'
& fastboot flash init_boot_b $localPatched
if ($LASTEXITCODE -ne 0) {
    Write-Host '    WARN: init_boot_b failed (root still works on the current slot)' -ForegroundColor Yellow
} else {
    Write-Host '    init_boot_b flashed' -ForegroundColor Green
}

# ------------------------------------------------------------------ boot
Step 'Rebooting'
& fastboot reboot

Write-Host @"

Wait for the phone to boot, open Magisk (it may ask for one reboot to finish setup).

Verify:
  adb shell su -c id

Unroot:
  fastboot flash init_boot   "$stock"
  fastboot flash init_boot_b "$stock"
  fastboot reboot
"@ -ForegroundColor Green

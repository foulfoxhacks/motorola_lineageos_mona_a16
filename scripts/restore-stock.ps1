<#
.SYNOPSIS
    Restore stock Android 16 by executing the official flashfile.xml.

.DESCRIPTION
    Parses flashfile.xml from your firmware folder and runs the exact Motorola
    service sequence: getvar / oem / flash / erase, in order.

    DESTRUCTIVE: erases userdata, metadata, carrier, apdp, modemst1/2.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -VerifyHashes
    powershell -ExecutionPolicy Bypass -File .\scripts\restore-stock.ps1 -SkipBootloader
#>

param(
    [string]$FwDir,
    [switch]$VerifyHashes,
    [switch]$SkipBootloader,
    [switch]$SkipConfirm
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

if (-not $FwDir) { $FwDir = Get-FirmwareDir }
if (-not $FwDir) { Die 'firmware folder not found' }

$plan = Get-FlashPlan $FwDir
if (-not $plan) { Die "flashfile.xml missing in $FwDir" }

Write-Host "    firmware: $FwDir"
Write-Host "    steps:    $($plan.Count)"

if ($VerifyHashes) {
    Step 'Verifying MD5 (slow)'
    $bad = Test-FirmwareHashes -FwDir $FwDir -Plan $plan
    if ($bad -gt 0) { Die "$bad file(s) failed MD5 - do not flash" }
}

if (-not $SkipConfirm) {
    Write-Host @"

This will flash the FULL stock image and ERASE userdata.
Bootloader will stay unlocked (this is not RSA's Rescue).

Press Ctrl+C to abort.
"@ -ForegroundColor Yellow
    if ((Read-Host 'Type RESTORE to continue') -ne 'RESTORE') { Die 'aborted' }
}

Ensure-PlatformTools
if (-not (Get-Command fastboot -ErrorAction SilentlyContinue)) { Die 'fastboot not on PATH (run get-platform-tools.ps1)' }

$devs = (& fastboot devices) 2>$null
if (-not $devs) {
    Write-Host '    no fastboot device; trying adb reboot bootloader...' -ForegroundColor Yellow
    & adb reboot bootloader
    Start-Sleep -Seconds 8
    $devs = (& fastboot devices) 2>$null
    if (-not $devs) { Die 'no device in fastboot mode' }
}
Write-Host "    $devs"
Assert-MonaDevice

# The stock sequence writes gpt/bootloader and the whole `super` physical
# partition, so it must run in the bootloader. fastbootd would reject those.
$mode = (& fastboot getvar is-userspace 2>&1 | Out-String)
if ($mode -match 'yes') {
    Die @"
the device is in fastbootd, but the stock sequence needs the BOOTLOADER
(it writes gpt, bootloader and the raw super partition).

  fastboot reboot bootloader
  fastboot getvar is-userspace     # must print: no
Then re-run this script.
"@
}

$i = 0
foreach ($s in $plan) {
    $i++
    $tag = "[$i/$($plan.Count)]"

    switch ($s.Operation) {
        'getvar' {
            & fastboot getvar $s.Var 2>&1 | Out-Null
        }
        'oem' {
            Write-Host "$tag oem $($s.Var)"
            & fastboot oem $s.Var | Out-Null
        }
        'flash' {
            if ($SkipBootloader -and ($s.File -in @('gpt.bin','bootloader.img'))) {
                Write-Host "$tag SKIP $($s.File) (-SkipBootloader)" -ForegroundColor DarkGray
                continue
            }
            $path = Join-Path $FwDir $s.File
            Write-Host "$tag flash $($s.Partition) <- $($s.File)"
            & fastboot flash $s.Partition $path | Out-Null
            if ($LASTEXITCODE -ne 0) { Die "flash $($s.Partition) failed ($LASTEXITCODE)" }
        }
        'erase' {
            Write-Host "$tag erase $($s.Partition)"
            & fastboot erase $s.Partition | Out-Null
        }
        default {
            Write-Host "$tag unknown operation '$($s.Operation)' - skipped" -ForegroundColor Yellow
        }
    }
}

Step 'Rebooting'
& fastboot reboot | Out-Null

Write-Host @"

Restore complete. First boot takes a few minutes.

Verify:
  adb shell getprop ro.build.fingerprint
  # motorola/mona_g/mona:16/W1VAS36.62-22-16-1-18/285398a-18976c:user/release-keys
  adb shell getprop ro.boot.verifiedbootstate
  # orange (unlocked - expected)
"@ -ForegroundColor Green

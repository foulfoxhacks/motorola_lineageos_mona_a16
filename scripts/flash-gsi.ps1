<#
.SYNOPSIS
    Flash the LineageOS 23.2 GSI to a Moto G Stylus 5G (2025) / XT2517-1.

.DESCRIPTION
    DESTRUCTIVE: replaces the system partition and wipes userdata.
    Requires the stock firmware folder (for vbmeta) and the GSI image.

    This device's bootloader rejects modified physical partitions with
    "Preflash validation failed" and ignores `fastboot reboot fastboot`, so
    everything happens in fastbootd, entered from booted Android with
    `adb reboot fastboot`.

    Note: `fastboot devices` is unreliable in fastbootd on this setup, so
    detection uses `fastboot getvar is-userspace` (run in a job with a timeout,
    because fastboot blocks forever when no device is present).

    Read docs/GSI-A16.md and docs/RESTORE-STOCK.md first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\flash-gsi.ps1
#>

param(
    [string]$FwDir,
    [string]$Gsi,
    [switch]$SkipConfirm
)

$ErrorActionPreference = 'Continue'   # native tools write progress/errors to stderr; PS 5.1 would turn those into terminating errors
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $FwDir) { $FwDir = Get-FirmwareDir }
if (-not $Gsi)  { $Gsi   = Resolve-GsiImage }

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Die "$Exe $($Arguments -join ' ') failed ($LASTEXITCODE)" }
}

function Get-AdbState {
    $s = (& adb get-state 2>$null) | Select-Object -First 1
    if ($s) { $s.ToString().Trim() } else { $null }
}

function Invoke-FastbootGetvar {
    <# fastboot blocks forever without a device, so run it in a job with a timeout. #>
    param([string]$Var, [int]$TimeoutSeconds = 90)
    $fb = (Get-Command fastboot -ErrorAction SilentlyContinue).Source
    if (-not $fb) { return '' }

    $job = Start-Job -ScriptBlock {
        param($exe, $v)
        & $exe getvar $v 2>&1
    } -ArgumentList $fb, $Var

    if (Wait-Job $job -Timeout $TimeoutSeconds) {
        $out = (Receive-Job $job) | Out-String
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $out
    }
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return ''
}

function Wait-Fastbootd {
    param([int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $o = Invoke-FastbootGetvar -Var 'is-userspace' -TimeoutSeconds 15
        if ($o -match 'yes') { return $true }
        Start-Sleep -Seconds 3
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    return $false
}

# ------------------------------------------------------------------ validate
Step 'Validating inputs'

Ensure-PlatformTools

foreach ($t in 'adb','fastboot') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t not on PATH" }
}
if (-not $Gsi) { Die 'GSI image not found (looked in .\gsi and C:\mona_firmware)' }
if (-not (Test-Path $Gsi)) { Die "GSI not found: $Gsi" }
if (-not $FwDir) { Die 'firmware folder not found (looked in C:\mona_firmware and C:\ProgramData\RSA)' }
if (-not (Test-Path $FwDir)) { Die "firmware folder not found: $FwDir" }

$vbmeta       = Join-Path $FwDir 'vbmeta.img'
$vbmetaSystem = Join-Path $FwDir 'vbmeta_system.img'
foreach ($f in $vbmeta, $vbmetaSystem) {
    if (-not (Test-Path $f)) { Die "missing $f" }
}

Write-Host ("    GSI: {0:N2} GiB" -f ((Get-Item $Gsi).Length / 1GB))
Write-Host "    vbmeta: $vbmeta"

# ------------------------------------------------------------------ confirm
Step 'Confirm'
Write-Host @"
This will:
  1. reflash vbmeta / vbmeta_system with verity+verification DISABLED
  2. replace the system partition with the GSI
  3. WIPE USERDATA (fastboot -w)

Root (init_boot) is not touched and will survive.
Your bootloader stays unlocked. Rollback: docs/RESTORE-STOCK.md
"@ -ForegroundColor Yellow

if (-not $SkipConfirm) {
    $answer = Read-Host 'Type FLASH to continue'
    if ($answer -ne 'FLASH') { Die 'aborted by user' }
}

# ------------------------------------------------------------------ fastbootd
Step 'Entering fastbootd'

# The phone can be in three states. fastbootd answers `fastboot` but not `adb`,
# so probe it first and never demand adb state before that.
$manualRoute = @"

Manual route:
  fastboot getvar is-userspace     # must print: yes
  fastboot --disable-verity --disable-verification flash vbmeta        "$vbmeta"
  fastboot --disable-verity --disable-verification flash vbmeta_system "$vbmetaSystem"
  fastboot flash system "$Gsi"
  fastboot -w
  fastboot reboot
"@

if ((Get-AdbState) -eq 'device') {
    Write-Host '    adb reboot fastboot' -NoNewline
    & adb reboot fastboot
    Write-Host ''
    Write-Host '    waiting for fastbootd (up to 2 minutes, do not Ctrl+C)' -NoNewline
    if (-not (Wait-Fastbootd -TimeoutSeconds 120)) { Die "fastbootd did not come up.$manualRoute" }
} elseif ((Invoke-FastbootGetvar -Var 'is-userspace' -TimeoutSeconds 10) -match 'yes') {
    Write-Host '    already in fastbootd - skipping the reboot' -ForegroundColor Green
} elseif ((Invoke-FastbootGetvar -Var 'product' -TimeoutSeconds 10) -match 'mona') {
    Write-Host '    in the bootloader - fastboot reboot fastboot' -NoNewline
    & fastboot reboot fastboot
    Write-Host ''
    Write-Host '    waiting for fastbootd (up to 2 minutes, do not Ctrl+C)' -NoNewline
    if (-not (Wait-Fastbootd -TimeoutSeconds 120)) { Die "fastbootd did not come up.$manualRoute" }
} else {
    Die @"
the phone is neither booted to Android, nor in the bootloader, nor in fastbootd.

  adb devices        # expect: <serial>  device
  fastboot devices   # expect: <serial>  fastboot

Boot it, or leave it in fastbootd, then re-run.
"@
}
Write-Host '    in fastbootd' -ForegroundColor Green
Assert-MonaDevice

# ------------------------------------------------------------------ vbmeta
Step 'Disabling AVB for the unsigned system'
Invoke-Checked 'fastboot' @('--disable-verity','--disable-verification','flash','vbmeta',$vbmeta)
Invoke-Checked 'fastboot' @('--disable-verity','--disable-verification','flash','vbmeta_system',$vbmetaSystem)

# ------------------------------------------------------------------ flash system
Step 'Flashing system'
& fastboot flash system $Gsi
if ($LASTEXITCODE -ne 0) {
    Write-Host '    flash failed - likely not enough space in super' -ForegroundColor Yellow
    Write-Host '    deleting logical partition "product" and retrying...' -ForegroundColor Yellow
    & fastboot delete-logical-partition product
    Invoke-Checked 'fastboot' @('flash','system',$Gsi)
}

# ------------------------------------------------------------------ wipe
Step 'Wiping userdata'
& fastboot -w
if ($LASTEXITCODE -ne 0) {
    # fastbootd frequently cannot see `metadata`, which makes `fastboot -w`
    # exit non-zero even though userdata was erased. Finish it by hand.
    Write-Host '    fastboot -w reported an error; erasing userdata directly' -ForegroundColor Yellow
    & fastboot erase userdata
    if ($LASTEXITCODE -ne 0) {
        Write-Host '    could not erase userdata - first boot may fail' -ForegroundColor Yellow
    }
    & fastboot erase metadata 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '    metadata not present in fastbootd (normal on this device)' -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------ boot
Step 'Rebooting'
Invoke-Checked 'fastboot' @('reboot')

Write-Host @"

First boot takes 5-15 minutes. Do not interrupt it.

After boot:
  adb shell getprop ro.build.version.release   # expect 16
  adb shell getprop ro.lineage.version         # expect 23.2-...
  adb shell su -c id                           # root (init_boot was patched)

If it bootloops, restore with docs/RESTORE-STOCK.md.
"@ -ForegroundColor Green

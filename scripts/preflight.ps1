<#
.SYNOPSIS
    Pre-flight check for the mona port: firmware integrity, disk, tools, device.

.DESCRIPTION
    Read-only. Changes nothing on the phone.
    Auto-detects the firmware folder (C:\mona_firmware or RSA's default).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\preflight.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\preflight.ps1 -VerifyHashes
#>

param(
    [string]$FwDir,
    [switch]$VerifyHashes
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

$MinFreeGB = 400
$problems = 0

function Section($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }
function Ok($m)      { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m)    { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m)    { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:problems++ }

# ---------------------------------------------------------------- firmware
Section 'Firmware'

if (-not $FwDir) { $FwDir = Get-FirmwareDir }

if (-not $FwDir) {
    Fail 'firmware folder not found (looked in C:\mona_firmware and C:\ProgramData\RSA)'
} else {
    Ok "folder: $FwDir"

    $plan = Get-FlashPlan $FwDir
    if ($plan) {
        Ok "flashfile.xml: $($plan.Count) steps"
    } else {
        Warn 'flashfile.xml missing - cannot derive the exact flash plan'
    }

    if (Test-Path (Join-Path $FwDir 'servicefile.xml')) { Ok 'servicefile.xml present' }
    else { Warn 'servicefile.xml missing' }

    # every file the official plan references must exist and be non-empty
    $files = if ($plan) { $plan.File | Where-Object { $_ } | Select-Object -Unique } else { @() }
    $missing = 0
    foreach ($f in $files) {
        $p = Join-Path $FwDir $f
        if (-not (Test-Path $p))      { Fail "missing: $f"; $missing++ }
        elseif ((Get-Item $p).Length -eq 0) { Fail "zero bytes: $f"; $missing++ }
    }
    if ($files.Count -gt 0 -and $missing -eq 0) { Ok "all $($files.Count) referenced images present and non-empty" }

    $chunks = Get-SuperChunks $FwDir
    if ($chunks.Count -gt 0) {
        $total = ($chunks | Measure-Object Length -Sum).Sum
        Ok ("super: {0} chunks, {1:N2} GiB" -f $chunks.Count, ($total / 1GB))
        $expectedCount = @($plan | Where-Object { $_.Partition -eq 'super' }).Count
        if ($expectedCount -gt 0 -and $chunks.Count -ne $expectedCount) {
            Warn "flashfile.xml expects $expectedCount super chunks, found $($chunks.Count)"
        }
    } else {
        Fail 'no super.img_sparsechunk.* files found'
    }

    if ($VerifyHashes) {
        Write-Host '  verifying MD5 (slow, several minutes)...' -ForegroundColor Cyan
        $bad = Test-FirmwareHashes -FwDir $FwDir -Plan $plan
        if ($bad -eq 0) { Ok 'all MD5 hashes match flashfile.xml' }
    } else {
        Write-Host '  (run with -VerifyHashes to check MD5 against flashfile.xml)' -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------- GSI
Section 'GSI image'

$gsi = Resolve-GsiImage
if ($gsi) {
    Ok "image: $gsi"
    Ok ("size:  {0:N2} GiB" -f ((Get-Item $gsi).Length / 1GB))
} else {
    Warn 'no GSI image found (run download-gsi.ps1, or extract the .7z yourself)'
}

# ---------------------------------------------------------------- disk
Section 'Disk space'

$c = Get-PSDrive C
$freeGB = [math]::Round($c.Free / 1GB, 1)
if ($freeGB -lt 5) { Fail "C: free ${freeGB} GB - not even enough for the GSI" }
elseif ($freeGB -lt $MinFreeGB) {
    Ok "C: free ${freeGB} GB"
    Write-Host '         (enough for the GSI route; a from-source build wants ~400 GB)' -ForegroundColor DarkGray
} else { Ok "C: free ${freeGB} GB" }

$vhdx = Get-ChildItem "$env:LOCALAPPDATA\wsl" -Recurse -Filter 'ext4.vhdx' -ErrorAction SilentlyContinue |
        Select-Object -First 1
if ($vhdx) { Ok ("WSL disk: {0:N1} GiB" -f ($vhdx.Length / 1GB)) }
else { Warn 'WSL ext4.vhdx not found (not needed for the GSI route)' }

# ---------------------------------------------------------------- tools
Section 'Host tools'

Ensure-PlatformTools

$haveAdb = Get-Command adb -ErrorAction SilentlyContinue
$haveFastboot = Get-Command fastboot -ErrorAction SilentlyContinue

if ($haveAdb)     { Ok "adb -> $($haveAdb.Source)" }     else { Fail 'adb not on PATH' }
if ($haveFastboot){ Ok "fastboot -> $($haveFastboot.Source)" } else { Fail 'fastboot not on PATH' }

if (-not ($haveAdb -and $haveFastboot)) {
    Write-Host '         fix: powershell -ExecutionPolicy Bypass -File .\scripts\get-platform-tools.ps1' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- device
Section 'Device (optional)'

if ($haveFastboot) {
    $devs = (& fastboot devices) 2>$null
    if ($devs) {
        Ok "fastboot sees: $devs"
        $slot = (& fastboot getvar current-slot) 2>&1 | Select-String 'current-slot'
        if ($slot) { Ok $slot.ToString().Trim() }
    } else {
        Warn 'no device in fastboot mode (fine if the phone is booted normally)'
    }
} elseif ($haveAdb) {
    $devs = (& adb devices) 2>$null | Select-String 'device$'
    if ($devs) { Ok "adb sees: $devs" } else { Warn 'no adb device' }
}

# ---------------------------------------------------------------- summary
Section 'Summary'
if ($problems -eq 0) {
    Write-Host '  All critical checks passed.' -ForegroundColor Green
} else {
    Write-Host "  $problems problem(s) found - fix before flashing." -ForegroundColor Red
    exit 1
}

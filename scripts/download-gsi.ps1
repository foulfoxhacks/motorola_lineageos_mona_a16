<#
.SYNOPSIS
    Get the LineageOS 23.2 (Android 16) GSI ready at .\gsi\system.img

.DESCRIPTION
    If an extracted GSI already exists on disk (e.g. under C:\mona_firmware), it is
    staged instead of downloaded. Otherwise it fetches
    LineageOS-23.2-20260524-VANILLA-EXT4-GSI.7z from a SourceForge mirror and extracts it.

    SourceForge's main /download redirect is unreliable on some networks; this script
    tries direct mirror hosts and three transfer methods.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\download-gsi.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\download-gsi.ps1 -Force
#>

param(
    [string]$Name = 'LineageOS-23.2-20260524-VANILLA-EXT4-GSI.7z',
    [string]$ExpectedBytes = 922022276,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$OutDir  = Join-Path (Get-Location) 'gsi'
$Target  = Join-Path $OutDir 'system.img'
$Archive = Join-Path $OutDir $Name

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ------------------------------------------------------------------ already have it?
if (-not $Force) {
    $existing = Resolve-GsiImage
    if ($existing) {
        Write-Host "==> found existing GSI: $existing" -ForegroundColor Green
        Write-Host ("    {0:N2} GiB - no download needed" -f ((Get-Item $existing).Length / 1GB)) -ForegroundColor Green
        Write-Host 'Next: powershell -ExecutionPolicy Bypass -File .\scripts\flash-gsi.ps1'
        exit 0
    }
}

# ------------------------------------------------------------------ download
$rel = 'misterztr-gsi/LineageOS/Android%2016/' + $Name
$mirrors = @(
    "https://master.dl.sourceforge.net/project/$rel",
    "https://downloads.sourceforge.net/project/$rel",
    "https://netix.dl.sourceforge.net/project/$rel",
    "https://phoenixnap.dl.sourceforge.net/project/$rel"
)

function Try-Download {
    param([string]$From, [string]$To)
    if ((Test-Path $To) -and ((Get-Item $To).Length -eq $ExpectedBytes)) { return $true }

    if (Test-Path $To) { Remove-Item $To -Force }

    Write-Host '  curl --ssl-no-revoke' -ForegroundColor DarkGray
    curl.exe -L --fail --ssl-no-revoke --retry 2 -o $To $From
    if ((Test-Path $To) -and (Get-Item $To).Length -eq $ExpectedBytes) { return $true }

    Write-Host '  BITS' -ForegroundColor DarkGray
    try {
        if (Test-Path $To) { Remove-Item $To -Force }
        Start-BitsTransfer -Source $From -Destination $To -ErrorAction Stop
        if ((Get-Item $To).Length -eq $ExpectedBytes) { return $true }
    } catch { Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray }

    Write-Host '  Invoke-WebRequest' -ForegroundColor DarkGray
    try {
        if (Test-Path $To) { Remove-Item $To -Force }
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -Uri $From -OutFile $To -UseBasicParsing } finally { $ProgressPreference = $old }
        if ((Get-Item $To).Length -eq $ExpectedBytes) { return $true }
    } catch { Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray }

    return $false
}

$ok = $false
foreach ($m in $mirrors) {
    Write-Host "==> mirror: $m" -ForegroundColor Cyan
    if (Try-Download -From $m -To $Archive) { $ok = $true; break }
    Write-Host '    mirror failed' -ForegroundColor Yellow
}

if (-not $ok) {
    throw "all mirrors failed. Download manually in a browser:`n  https://github.com/MisterZtr/LineageOS_gsi/releases/tag/v2026.05.24-lineage23.2`nthen extract with 7-Zip into .\gsi\system.img"
}

$len = (Get-Item $Archive).Length
if ($len -ne $ExpectedBytes) {
    throw "size mismatch: got $len, expected $ExpectedBytes"
}
Write-Host ("    size:   {0:N0} bytes" -f $len) -ForegroundColor Green
Write-Host ("    sha256: {0}" -f (Get-FileHash $Archive -Algorithm SHA256).Hash)

# ------------------------------------------------------------------ extract
$sevenZip = @(
    'C:\Program Files\7-Zip\7z.exe',
    'C:\Program Files (x86)\7-Zip\7z.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $sevenZip) {
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { $sevenZip = $cmd.Source }
}
if (-not $sevenZip) { throw '7-Zip not found. Install from https://www.7-zip.org/ then re-run.' }

Write-Host "==> extracting with $sevenZip" -ForegroundColor Cyan
& $sevenZip x $Archive "-o$OutDir" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7z extraction failed ($LASTEXITCODE)" }

$img = Get-ChildItem $OutDir -Filter '*.img' -Recurse |
       Where-Object { $_.Length -gt 1GB } |
       Sort-Object Length -Descending |
       Select-Object -First 1
if (-not $img) { throw "no .img larger than 1 GB found in $OutDir" }
if ($img.FullName -ne $Target) { Move-Item -Force $img.FullName $Target }

Write-Host ("==> ready: {0} ({1:N2} GiB)" -f $Target, ((Get-Item $Target).Length / 1GB)) -ForegroundColor Green
Write-Host 'Next: powershell -ExecutionPolicy Bypass -File .\scripts\flash-gsi.ps1'

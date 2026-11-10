<#
.SYNOPSIS
    Install Android platform-tools (adb/fastboot) and put them on PATH.

.DESCRIPTION
    Downloads Google's platform-tools to C:\mona_work\platform-tools if adb/fastboot
    are not already available, then adds the folder to your user PATH.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\get-platform-tools.ps1
#>

$ErrorActionPreference = 'Stop'

$Dest = 'C:\mona_work\platform-tools'
$Url  = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'

if ((Get-Command adb -ErrorAction SilentlyContinue) -and (Get-Command fastboot -ErrorAction SilentlyContinue)) {
    Write-Host "==> adb and fastboot already on PATH" -ForegroundColor Green
    adb version | Select-Object -First 1
    fastboot --version | Select-Object -First 1
    exit 0
}

if (-not (Test-Path (Join-Path $Dest 'adb.exe'))) {
    $tmp = Join-Path $env:TEMP 'platform-tools.zip'
    Write-Host "==> downloading platform-tools" -ForegroundColor Cyan
    curl.exe -L --fail -o $tmp $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed" }

    Write-Host "==> extracting" -ForegroundColor Cyan
    $stage = Join-Path $env:TEMP 'platform-tools-stage'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Expand-Archive -Path $tmp -DestinationPath $stage -Force

    # zip contains a platform-tools/ folder
    $inner = Join-Path $stage 'platform-tools'
    if (Test-Path $inner) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
        if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
        Move-Item $inner $Dest
    } else {
        throw "unexpected archive layout"
    }
}

$env:Path = "$Dest;$env:Path"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$Dest*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$Dest", 'User')
    Write-Host "==> added $Dest to your user PATH (new terminals only)" -ForegroundColor Cyan
}

Write-Host "==> verifying" -ForegroundColor Cyan
& "$Dest\adb.exe" version | Select-Object -First 1
& "$Dest\fastboot.exe" --version | Select-Object -First 1
Write-Host "OK - re-run preflight.ps1 in this same window" -ForegroundColor Green

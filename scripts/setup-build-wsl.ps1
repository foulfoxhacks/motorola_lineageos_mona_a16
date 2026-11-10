<#
.SYNOPSIS
    Create (or finish setting up) a WSL2 build distro for the LineageOS port on E:.

.DESCRIPTION
    WSL distros are single dynamically-growing ext4.vhdx files. The existing
    Ubuntu-24.04 lives on C: and can never exceed C:'s free space (~118 GB),
    which is not enough for a LineageOS sync + build (~400 GB).

    First run:
      1. checks the target drive (free space, filesystem)
      2. exports the existing Ubuntu-24.04 to a tar
      3. imports it as a NEW distro (default: lineage-build) on the target drive
      4. creates a `builder` user with passwordless sudo
      5. writes %USERPROFILE%\.wslconfig (memory/swap/processors)

    Re-run: if the distro already exists, steps 2-3 are skipped and only the
    user/config steps are applied. The original Ubuntu-24.04 is never touched.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-build-wsl.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-build-wsl.ps1 -Root 'E:\WSL' -MinFreeGB 450
#>

param(
    [string]$SourceDistro = 'Ubuntu-24.04',
    [string]$BuildDistro  = 'lineage-build',
    [string]$Root         = 'E:\WSL',
    [int]$MinFreeGB       = 400,
    [int]$MemoryGB        = 10,
    [int]$SwapGB          = 24,
    [int]$Processors      = 10,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ checks
Step 'Checking environment'

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { Die 'wsl not found' }

$drive = ((Split-Path -Qualifier $Root) -replace '[:\\]', '').Trim().ToUpper()
$vol = Get-Volume -DriveLetter $drive -ErrorAction SilentlyContinue
if (-not $vol) { Die "drive ${drive}: not found" }

$freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
Write-Host "    target:     $Root"
Write-Host "    filesystem: $($vol.FileSystem)"
Write-Host "    free:       $freeGB GB"

if ($vol.FileSystem -ne 'NTFS') {
    Die "drive ${drive}: is $($vol.FileSystem). WSL vhdx needs NTFS."
}
if ($freeGB -lt $MinFreeGB) {
    Die "only $freeGB GB free on ${drive}: - need at least $MinFreeGB GB (source + out + ccache)."
}
Ok "$freeGB GB available"

$distros = (& wsl -l -q) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$exists  = $distros -contains $BuildDistro

# ------------------------------------------------------------------ export/import
if ($exists -and -not $Force) {
    Step "Distro '$BuildDistro' already exists - skipping export/import"
    Ok 'using the existing distro'
} else {
    if ($distros -notcontains $SourceDistro) {
        Die "source distro '$SourceDistro' not found. Available: $($distros -join ', ')"
    }
    Ok "source distro: $SourceDistro"

    if ($exists) {
        Warn "unregistering existing $BuildDistro (data will be lost)"
        & wsl --terminate $BuildDistro | Out-Null
        & wsl --unregister $BuildDistro | Out-Null
    }

    Step 'Stopping WSL'
    & wsl --shutdown
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $tar = Join-Path $Root "$SourceDistro.tar"

    Step "Exporting $SourceDistro -> $tar"
    if (Test-Path $tar) { Remove-Item $tar -Force }
    & wsl --export $SourceDistro $tar
    if ($LASTEXITCODE -ne 0) { Die "wsl --export failed ($LASTEXITCODE)" }
    Ok ("{0:N2} GB" -f ((Get-Item $tar).Length / 1GB))

    $dest = Join-Path $Root $BuildDistro
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    Step "Importing as $BuildDistro -> $dest"
    & wsl --import $BuildDistro $dest $tar --version 2
    if ($LASTEXITCODE -ne 0) { Die "wsl --import failed ($LASTEXITCODE)" }
    Ok 'imported'

    Remove-Item $tar -Force
    Write-Host '    (removed the temporary tar)'
}

# ------------------------------------------------------------------ builder user
Step 'Creating builder user (passwordless sudo)'

# Single-line bash -c: avoids the BOM/CRLF problems of piping a script into bash.
$cmd = "id builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder; " +
       "echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder; " +
       "chmod 440 /etc/sudoers.d/builder; " +
       "printf '[user]\ndefault=builder\n' > /etc/wsl.conf"

& wsl -d $BuildDistro -u root -- bash -c $cmd
if ($LASTEXITCODE -ne 0) { Die 'failed to create builder user' }
Ok 'builder created; default user set'

& wsl --terminate $BuildDistro | Out-Null

# ------------------------------------------------------------------ .wslconfig
Step 'Writing .wslconfig'
$cfgPath = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $cfgPath) {
    $backup = "$cfgPath.bak"
    Copy-Item -Force $cfgPath $backup
    Warn "existing .wslconfig backed up to $backup"
}
@"
[wsl2]
memory=${MemoryGB}GB
swap=${SwapGB}GB
processors=${Processors}
"@ | Set-Content -Path $cfgPath -Encoding ASCII
Ok "$cfgPath (memory ${MemoryGB}GB, swap ${SwapGB}GB, processors ${Processors})"

# ------------------------------------------------------------------ done
Step 'Done'
Write-Host @"

Build distro:  $BuildDistro
Location:      $Root\$BuildDistro
Default user:  builder

Verify:
  wsl -d $BuildDistro -- whoami          # expect: builder
  wsl -d $BuildDistro -- df -h /         # expect ~${freeGB}G available

First steps inside WSL:
  wsl -d $BuildDistro
  bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/wsl-deps.sh
  bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/lineage-sync.sh

Note: keep the repo in the Linux filesystem (e.g. ~/android/lineage), never on /mnt/c.
"@ -ForegroundColor Green

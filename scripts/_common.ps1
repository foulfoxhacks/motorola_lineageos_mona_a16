# Shared helpers. Dot-source, do not run directly.

function Ensure-PlatformTools {
    <#
      Makes adb/fastboot resolvable for this process: uses PATH if already there,
      otherwise looks in the known install locations and prepends them.
    #>
    if ((Get-Command adb -ErrorAction SilentlyContinue) -and (Get-Command fastboot -ErrorAction SilentlyContinue)) { return }

    $candidates = @(
        'C:\mona_work\platform-tools',
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages')
    )

    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'adb.exe'))) {
            $env:Path = "$c;$env:Path"
            Write-Host "  (using platform-tools at $c)" -ForegroundColor DarkGray
            return
        }
    }

    $wingetRoot = $candidates[1]
    if (Test-Path $wingetRoot) {
        $hit = Get-ChildItem $wingetRoot -Recurse -Filter 'adb.exe' -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) {
            $env:Path = "$($hit.DirectoryName);$env:Path"
            Write-Host "  (using platform-tools at $($hit.DirectoryName))" -ForegroundColor DarkGray
        }
    }
}

function Resolve-GsiImage {
    <#
      Finds the extracted GSI image:
        1. explicit path
        2. .\gsi\system.img
        3. any >512 MiB .img under C:\mona_firmware (prefers paths containing 'GSI')
    #>
    param([string]$Explicit)

    if ($Explicit -and (Test-Path $Explicit)) { return (Resolve-Path $Explicit).Path }

    $staged = Join-Path (Get-Location) 'gsi\system.img'
    if (Test-Path $staged) { return (Resolve-Path $staged).Path }

    if (-not (Test-Path 'C:\mona_firmware')) { return $null }

    $imgs = Get-ChildItem 'C:\mona_firmware' -Recurse -Filter '*.img' -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 512MB }

    $gsi = $imgs | Where-Object { $_.FullName -match 'GSI' } | Sort-Object Length -Descending | Select-Object -First 1
    if ($gsi) { return $gsi.FullName }

    $any = $imgs | Sort-Object Length -Descending | Select-Object -First 1
    if ($any) { return $any.FullName }

    return $null
}

function Get-FirmwareDir {
    <#
      Finds the extracted mona firmware folder. Accepts an explicit path,
      otherwise probes known locations, otherwise searches for flashfile.xml.
    #>
    param([string[]]$Candidates)

    if (-not $Candidates) {
        $Candidates = @(
            'C:\mona_firmware\W1VAS36\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml',
            'C:\ProgramData\RSA\Download\RomFiles\MONA_G_W1VAS36.62_22_16_1_18_subsidy_TMO_USKU_RSU_regulatory_DEFAULT_cid50_CFC.xml'
        )
    }

    foreach ($c in $Candidates) {
        if ($c -and (Test-Path (Join-Path $c 'boot.img'))) {
            return (Resolve-Path $c).Path
        }
    }

    foreach ($root in 'C:\mona_firmware', 'C:\ProgramData\RSA') {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Filter 'flashfile.xml' -ErrorAction SilentlyContinue |
               Where-Object { Test-Path (Join-Path $_.DirectoryName 'boot.img') } |
               Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }

    return $null
}

function Assert-MonaDevice {
    <#
      Refuses to continue unless the device in fastboot/fastbootd reports product `mona*`.
      Every flashing script calls this before its first write: these images will brick
      any other phone. Override only with -AllowOtherProduct (you should never need it).
    #>
    param([switch]$AllowOtherProduct)
    $raw = (& fastboot getvar product 2>&1 | Out-String)
    $m = [regex]::Match($raw, 'product:\s*(\S+)')
    $product = if ($m.Success) { $m.Groups[1].Value } else { '' }
    if ($product -match '^mona') {
        Write-Host "    product: $product (ok)" -ForegroundColor DarkGray
        return
    }
    if ($AllowOtherProduct) {
        Write-Host "    WARNING: product '$product' is not mona - continuing because -AllowOtherProduct" -ForegroundColor Yellow
        return
    }
    Write-Host "ERROR: fastboot reports product '$product', expected 'mona' (Moto G Stylus 5G 2025, XT2517-1). Refusing to flash." -ForegroundColor Red
    exit 1
}

function Get-SuperChunks {
    param([string]$FwDir)
    Get-ChildItem $FwDir -Filter 'super.img_sparsechunk.*' |
        Sort-Object { [int]($_.Name -replace '^.*\.', '') }
}

function Get-FlashPlan {
    <# Parses flashfile.xml into a flat list of steps. #>
    param([string]$FwDir)
    $xmlPath = Join-Path $FwDir 'flashfile.xml'
    if (-not (Test-Path $xmlPath)) { return $null }
    [xml]$xml = Get-Content $xmlPath -Raw
    $steps = foreach ($s in $xml.flashing.steps.step) {
        [pscustomobject]@{
            Operation = $s.operation
            Partition = $s.partition
            Var       = $s.var
            File      = $s.filename
            Md5       = $s.MD5
        }
    }
    return $steps
}

function Test-FirmwareHashes {
    <# Verifies MD5 of every file referenced by flashfile.xml. Slow on 8+ GiB. #>
    param([string]$FwDir, [object[]]$Plan)
    $bad = 0
    foreach ($s in $Plan | Where-Object { $_.File -and $_.Md5 }) {
        $p = Join-Path $FwDir $s.File
        if (-not (Test-Path $p)) { Write-Host "  [FAIL] missing $($s.File)" -ForegroundColor Red; $bad++; continue }
        $h = (Get-FileHash $p -Algorithm MD5).Hash
        if ($h -ne $s.Md5.ToUpper()) {
            Write-Host "  [FAIL] $($s.File) md5 $h != $($s.Md5)" -ForegroundColor Red; $bad++
        } else {
            Write-Host "  [OK]   $($s.File)" -ForegroundColor Green
        }
    }
    return $bad
}

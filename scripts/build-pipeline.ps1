<#
.SYNOPSIS
    Run the whole mona build as numbered, automated steps in one PowerShell window.

.DESCRIPTION
    Step 1  check WSL distro + source tree
    Step 2  start the WSL keepalive and keep-awake helpers
    Step 3  apply patches/ to the tree                (skipped if a build is running)
    Step 4  stage the stock DTB/DTBO if missing       (skipped if a build is running)
    Step 5  start the build in tmux                   (attaches if one is already running)
    Step 6  monitor: shows the current stage every minute until the build ends
    Step 7  show C:\mona_work\out\BUILD_RESULT.txt

    The build itself runs inside WSL/tmux: closing this window does NOT stop it.
    Re-run this script any time to re-attach.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build-pipeline.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\build-pipeline.ps1 -Restart   # kill + restart the build
    # open it in its own window:
    Start-Process powershell -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File','C:\mona_work\motorola_lineageos_mona_a16\scripts\build-pipeline.ps1'
#>
param(
    [switch]$Restart,
    [int]$PollSeconds = 60
)

$ErrorActionPreference = 'Continue'
$Repo    = Split-Path $PSScriptRoot -Parent
$WslRepo = '/mnt/c/' + ($Repo.Substring(3) -replace '\\', '/')
$Distro  = 'lineage-build'
$Result  = 'C:\mona_work\out\BUILD_RESULT.txt'
$Host.UI.RawUI.WindowTitle = 'mona build pipeline'

function Step($n, $msg) { Write-Host ("`n[{0}] Step {1}: {2}" -f (Get-Date -Format 'HH:mm'), $n, $msg) -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    !!  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    XX  $m" -ForegroundColor Red; exit 1 }

# WSL can time out (Wsl/Service/0x8007274c) when Windows is low on memory during
# soong analysis. Run each call with a timeout and retry instead of hanging.
function Invoke-Wsl([string]$Cmd, [int]$TimeoutSec = 120, [int]$Tries = 5) {
    for ($i = 1; $i -le $Tries; $i++) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo 'wsl.exe'
        $psi.Arguments = "-d $Distro -u builder -e bash -lc `"$($Cmd -replace '"','\"')`""
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEndAsync()
        if ($p.WaitForExit($TimeoutSec * 1000)) {
            $text = ($out.Result -replace "`0", '').Trim()
            if ($text -notmatch 'Wsl/Service/0x') { return $text }
        } else { try { $p.Kill() } catch {} }
        Start-Sleep -Seconds 30
    }
    return $null
}

# ---------------------------------------------------------------- 1
Step 1 'check WSL distro and source tree'
$distros = (wsl.exe -l -q) -replace "`0", '' | Where-Object { $_.Trim() }
if ($distros -notcontains $Distro) { Fail "WSL distro '$Distro' not found (see docs/BUILD.md)" }
$probe = Invoke-Wsl "test -d ~/lineage/.repo && echo tree-ok"
if ($probe -ne 'tree-ok') { Fail "no synced tree at ~/lineage inside $Distro" }
Ok "$Distro with ~/lineage"

# ---------------------------------------------------------------- 2
Step 2 'start helpers (WSL keepalive, keep-awake)'
& "$PSScriptRoot\wsl-keepalive.ps1" | ForEach-Object { Ok $_ }
& "$PSScriptRoot\keep-awake.ps1"    | ForEach-Object { Ok $_ }
Warn 'keep the laptop plugged in with the lid open'

$status = Invoke-Wsl "bash <(tr -d '\r' < $WslRepo/scripts/build-status.sh)"
$running = $status -like 'running*'

# ---------------------------------------------------------------- 3 / 4
if ($running -and -not $Restart) {
    Step 3 'apply patches - skipped, a build is already running'
    Step 4 'stage stock DTB/DTBO - skipped, a build is already running'
} else {
    Step 3 'apply patches/'
    $o = Invoke-Wsl "bash $WslRepo/scripts/apply-patches.sh 2>&1 | tail -3" 300
    $o -split "`n" | ForEach-Object { Ok $_ }
    if ($o -match 'ERROR') { Fail 'patches did not apply - see above' }

    Step 4 'stage stock DTB/DTBO (if missing)'
    $o = Invoke-Wsl "test -s ~/lineage/vendor/motorola/mona-dt/dtbo.img && echo present || bash <(tr -d '\r' < $WslRepo/scripts/extract-dt.sh) 2>&1 | tail -3" 300
    $o -split "`n" | ForEach-Object { Ok $_ }
}

# ---------------------------------------------------------------- 5
Step 5 'start the build'
if ($running -and -not $Restart) {
    Ok "attached to the running build: $($status -replace '^[^|]*\|','')"
} else {
    if (Test-Path $Result) { Move-Item -Force $Result ($Result -replace '\.txt$', '.prev.txt') }
    $force = if ($Restart) { '--force' } else { '' }
    $o = Invoke-Wsl "bash $WslRepo/scripts/start-build.sh $force 2>&1 | tail -4" 300
    $o -split "`n" | ForEach-Object { Ok $_ }
    if ($o -match 'ERROR') { Fail 'build did not start - see above' }
    & "$PSScriptRoot\keep-awake.ps1" | Out-Null   # restart if the old one ended
}

# ---------------------------------------------------------------- 6
Step 6 "monitor (every $PollSeconds s; closing this window does not stop the build)"
$last = ''
while ($true) {
    $s = Invoke-Wsl "bash <(tr -d '\r' < $WslRepo/scripts/build-status.sh)" 120 2
    if (-not $s) { Warn "$(Get-Date -Format HH:mm) WSL busy (low memory), retrying"; Start-Sleep $PollSeconds; continue }
    $state, $detail = $s -split '\|', 2
    $line = "$(Get-Date -Format HH:mm)  $state  $detail"
    if ($state -ne ($last -split '\|')[0]) { Write-Host "    >> $line" -ForegroundColor White } else { Write-Host "       $line" -ForegroundColor DarkGray }
    $last = $s
    if ($state -like 'done*' -or $state -eq 'idle') { break }
    Start-Sleep $PollSeconds
}

# ---------------------------------------------------------------- 7
Step 7 'result'
for ($i = 0; $i -lt 10 -and -not (Test-Path $Result); $i++) { Start-Sleep 15 }   # post-build writes it
if (Test-Path $Result) {
    Get-Content $Result | ForEach-Object {
        $c = if ($_ -match 'SUCCESS') { 'Green' } elseif ($_ -match 'FAILED|error') { 'Red' } else { 'Gray' }
        Write-Host "    $_" -ForegroundColor $c
    }
} else {
    Warn "no $Result yet - check: wsl -d $Distro -u builder -- tail -50 ~/build.log"
}

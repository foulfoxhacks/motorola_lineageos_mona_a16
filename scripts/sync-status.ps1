<#
.SYNOPSIS
    Start and/or watch the lineage-24.0 `repo sync` with a progress bar and ETA.

.DESCRIPTION
    Wraps scripts/sync-watch.sh inside the WSL build distro.

    -Start   launches `lineage-sync.sh` in a detached tmux session, logging to
             ~/sync.log.
    -Watch   runs the bar in this window. Ctrl+C stops the bar, NOT the sync.

    Without -Watch it prints a single snapshot, which is handy from a second
    terminal.

.EXAMPLE
    # start the sync and watch it
    powershell -ExecutionPolicy Bypass -File .\scripts\sync-status.ps1 -Start -Watch

.EXAMPLE
    # just look at where it is
    powershell -ExecutionPolicy Bypass -File .\scripts\sync-status.ps1

.EXAMPLE
    # attach to the raw repo output
    wsl -d lineage-build -u builder -- tmux attach -t sync
#>

param(
    [string]$Distro = 'lineage-build',
    [string]$User   = 'builder',
    [int]$TargetGB  = 115,
    [int]$Interval  = 20,
    [int]$Jobs      = 16,
    [switch]$Start,
    [switch]$Watch
)

$ErrorActionPreference = 'Continue'
$script:lastRc = 0

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host 'wsl.exe not found - WSL2 is not installed.' -ForegroundColor Red
    exit 1
}

if (-not $PSScriptRoot) {
    Write-Host 'run this with -File so the script folder is known.' -ForegroundColor Red
    exit 1
}

$drive  = $PSScriptRoot.Substring(0, 1).ToLower()
$rest   = $PSScriptRoot.Substring(2) -replace '\\', '/'
$wslDir = "/mnt/$drive$rest"

$watchSh = "$wslDir/sync-watch.sh"
$startSh = "$wslDir/sync-start.sh"

# Every WSL call below passes arguments as a list (no shell string), so
# PowerShell's native-argument quoting never has to survive a round trip.
Write-Host "distro : $Distro ($User)" -ForegroundColor DarkGray

# ---------------------------------------------------------------- sanity
# A cold or loaded WSL VM can time out on the first connection
# (Wsl/Service/0x8007274c). That is NOT the same as a missing file, so retry
# and report the two cases differently.
$probe = ''
$reachable = $false
for ($i = 1; $i -le 3; $i++) {
    $probe = (& wsl -d $Distro -u $User -- test -f $watchSh 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) { $reachable = $true; break }
    Start-Sleep -Seconds 3
}

if (-not $reachable) {
    if ($probe -match 'Wsl/Service|0x8007|connection attempt failed|timed out|WSL_E_') {
        Write-Host "WSL distro '$Distro' is not responding." -ForegroundColor Red
        if ($probe) { Write-Host ("  " + ($probe -split "`n")[0]) -ForegroundColor DarkGray }
        Write-Host ''
        Write-Host 'Try, in order:' -ForegroundColor Yellow
        Write-Host "  wsl -d $Distro -u $User -- echo ok     # is it alive at all?" -ForegroundColor DarkGray
        Write-Host '  wsl --shutdown                          # reset the VM' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'The repo sync is resumable and continues from what is on disk.' -ForegroundColor DarkGray
        exit 1
    }
    Write-Host "cannot see $watchSh inside '$Distro'." -ForegroundColor Red
    Write-Host 'Check the distro name:' -ForegroundColor Yellow
    Write-Host '  wsl -l -v' -ForegroundColor DarkGray
    Write-Host 'Check the mount:' -ForegroundColor Yellow
    Write-Host "  wsl -d $Distro -u $User -- ls /mnt/c/mona_work" -ForegroundColor DarkGray
    exit 1
}

# ---------------------------------------------------------------- start
if ($Start) {
    Write-Host "`n==> repo sync" -ForegroundColor Cyan
    $out = (& wsl -d $Distro -u $User -- env "JOBS=$Jobs" bash $startSh 2>&1 | Out-String).Trim()

    if ($out -match 'started') {
        Write-Host '  started in tmux session "sync"  ->  ~/sync.log' -ForegroundColor Green
    } elseif ($out -match 'already running') {
        Write-Host '  already running - attaching the watcher' -ForegroundColor Yellow
    } else {
        Write-Host "  could not start: $out" -ForegroundColor Red
        Write-Host '  is tmux installed?  sudo apt install tmux' -ForegroundColor Yellow
        exit 1
    }
}

# ---------------------------------------------------------------- watch
$envArgs = @("TARGET_GB=$TargetGB", "INTERVAL=$Interval")

if ($Watch) {
    Write-Host "`n==> live  (Ctrl+C stops the bar, not the sync)" -ForegroundColor Cyan
    & wsl -d $Distro -u $User -- env @envArgs bash $watchSh | Out-Host
} else {
    Write-Host "`n==> snapshot" -ForegroundColor Cyan
    & wsl -d $Distro -u $User -- env @envArgs bash $watchSh --once | Out-Host
}
$rc = $LASTEXITCODE

if (-not $Watch) {
    Write-Host @"

Follow it live:
  powershell -ExecutionPolicy Bypass -File .\scripts\sync-status.ps1 -Watch

Raw repo output:
  wsl -d $Distro -u $User -- tmux attach -t sync

Stop the sync:
  wsl -d $Distro -u $User -- tmux kill-session -t sync
"@ -ForegroundColor DarkGray
}

exit $rc

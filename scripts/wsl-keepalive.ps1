<#
.SYNOPSIS
    Keep the lineage-build WSL distro running while a long build runs in tmux.

.DESCRIPTION
    WSL terminates a distro shortly after the last wsl.exe client disconnects, and
    every process in it dies, tmux sessions included. A ~3 h soong analysis is lost
    the moment you close the last terminal.

    This starts one hidden `wsl.exe -- sleep infinity` through WMI, so it is not a
    child of your terminal and survives closing it. It is idempotent: if a keepalive
    is already running it does nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1          # start
    powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1 -Stop    # stop
    powershell -ExecutionPolicy Bypass -File .\scripts\wsl-keepalive.ps1 -Status
#>
param(
    [string]$Distro = 'lineage-build',
    [switch]$Stop,
    [switch]$Status
)

$marker = "-d $Distro -u root -- sleep infinity"

function Get-Keepalive {
    Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($marker) }
}

$running = @(Get-Keepalive)

if ($Status) {
    if ($running.Count) { $running | ForEach-Object { "keepalive running: pid $($_.ProcessId)" } }
    else { 'no keepalive running' }
    return
}

if ($Stop) {
    if (-not $running.Count) { 'no keepalive running'; return }
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "stopped keepalive pid $($_.ProcessId)" }
    'The distro will now shut down once no other wsl.exe client is connected (any build in it stops).'
    return
}

if ($running.Count) { "keepalive already running: pid $($running[0].ProcessId)"; return }

$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine                = "wsl.exe $marker"
    ProcessStartupInformation  = $startup
}
if ($r.ReturnValue -ne 0) { Write-Host "ERROR: Win32_Process.Create returned $($r.ReturnValue)" -ForegroundColor Red; exit 1 }
"keepalive started: pid $($r.ProcessId) (hidden). Stop it with: .\scripts\wsl-keepalive.ps1 -Stop"

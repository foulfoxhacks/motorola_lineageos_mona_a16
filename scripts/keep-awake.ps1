<#
.SYNOPSIS
    Keep Windows from idle-sleeping/hibernating until the build result file appears.

.DESCRIPTION
    Holds a "system required" power request (SetThreadExecutionState, the same thing
    video players use). It does NOT change any power settings, and it releases the
    request when it exits. It runs hidden and detached, so closing the terminal
    (or Claude) does not stop it. It exits on its own when
    C:\mona_work\out\BUILD_RESULT.txt is (re)written after it started, or after
    -MaxHours.

    It cannot stop sleep on lid close or a dying battery: keep the laptop
    plugged in with the lid open.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1           # start (idempotent)
    powershell -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 -Status
    powershell -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 -Stop
#>
param(
    [string]$UntilFile = 'C:\mona_work\out\BUILD_RESULT.txt',
    [int]$MaxHours = 30,
    [switch]$Run,
    [switch]$Stop,
    [switch]$Status
)

$self = $MyInvocation.MyCommand.Path

function Get-Runners {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains('keep-awake.ps1') -and $_.CommandLine.Contains('-Run') }
}

if ($Run) {
    Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
    $ES_CONTINUOUS = [uint32]'0x80000000'; $ES_SYSTEM_REQUIRED = [uint32]'0x00000001'
    $started = Get-Date
    $deadline = $started.AddHours($MaxHours)
    while ((Get-Date) -lt $deadline) {
        [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
        if ((Test-Path $UntilFile) -and ((Get-Item $UntilFile).LastWriteTime -gt $started)) { break }
        Start-Sleep -Seconds 60
    }
    [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS)
    return
}

$running = @(Get-Runners)
if ($Status) {
    if ($running.Count) { $running | ForEach-Object { "keep-awake running: pid $($_.ProcessId)" } } else { 'keep-awake not running' }
    return
}
if ($Stop) {
    if (-not $running.Count) { 'keep-awake not running'; return }
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "stopped keep-awake pid $($_.ProcessId)" }
    return
}
if ($running.Count) { "keep-awake already running: pid $($running[0].ProcessId)"; return }

$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
$cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Run -UntilFile `"$UntilFile`" -MaxHours $MaxHours"
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Host "ERROR: Win32_Process.Create returned $($r.ReturnValue)" -ForegroundColor Red; exit 1 }
"keep-awake started: pid $($r.ProcessId) (hidden; ends when $UntilFile is written, or after $MaxHours h)"

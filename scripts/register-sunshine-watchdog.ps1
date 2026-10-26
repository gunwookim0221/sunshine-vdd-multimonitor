# Register/remove Sunshine watchdog scheduled tasks.
# Creates:
# 1) Event task: runs on unexpected Windows service termination events (7031/7034).
# 2) Hourly task: light safety check for hangs that do not emit a crash event.
#
# Run from an elevated PowerShell.

param(
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$WatchdogScript = "C:\SunshineScripts\sunshine-watchdog.ps1"
$CrashTask = "Sunshine Watchdog - Crash Event"
$HourlyTask = "Sunshine Watchdog - Hourly"

function Remove-TaskIfExists {
    param([string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed existing task: $TaskName"
    }
}

if ($Remove) {
    Remove-TaskIfExists -TaskName $CrashTask
    Remove-TaskIfExists -TaskName $HourlyTask
    Write-Host "Removed watchdog tasks."
    exit 0
}

if (-not (Test-Path $WatchdogScript)) {
    throw "Watchdog script not found: $WatchdogScript"
}

$taskRun = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $WatchdogScript

# Any unexpected service termination wakes the watchdog. The watchdog itself then
# verifies Sunshine health and exits immediately when Sunshine is healthy.
# This avoids hard-coding the Sunshine service name into the event subscription.
$eventQuery = "*[System[Provider[@Name='Service Control Manager'] and (EventID=7031 or EventID=7034)]]"

Remove-TaskIfExists -TaskName $CrashTask
Remove-TaskIfExists -TaskName $HourlyTask

& schtasks.exe /Create /TN $CrashTask /TR $taskRun /SC ONEVENT /EC System /MO $eventQuery /RU SYSTEM /RL HIGHEST /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create event-triggered watchdog task."
}

& schtasks.exe /Create /TN $HourlyTask /TR $taskRun /SC HOURLY /MO 1 /RU SYSTEM /RL HIGHEST /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create hourly watchdog task."
}

Write-Host "Registered: $CrashTask"
Write-Host "Registered: $HourlyTask"
Write-Host "The crash task reacts to SCM 7031/7034 events; the hourly task is a low-frequency fallback."
Write-Host "Watchdog logs: C:\SunshineLogs\watchdog\sunshine-watchdog.log"

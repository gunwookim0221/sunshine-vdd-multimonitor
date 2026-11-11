# Register/remove the interactive Sunshine local-takeover watcher.
# Run from an elevated PowerShell.
#
# The task intentionally runs as the logged-on user with Highest privileges.
# SYSTEM/session-0 tasks cannot reliably receive the user's Raw Input stream.

param(
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$TaskName = "Sunshine Local Takeover"
$ScriptPath = "C:\SunshineScripts\sunshine-local-takeover.ps1"

function Remove-TaskIfExists {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: $TaskName"
    }
}

if ($Remove) {
    Remove-TaskIfExists
    exit 0
}

if (-not (Test-Path $ScriptPath)) {
    throw "Local takeover script not found: $ScriptPath"
}

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Remove-TaskIfExists

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Detect learned local keyboard/mouse Raw Input during VDD-only Moonlight mode, disconnect Sunshine, and restore the safe physical-monitor layout." `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host "Registered and started: $TaskName"
Write-Host "Watcher: $ScriptPath"
Write-Host "Log: C:\SunshineLogs\local-takeover\local-takeover.log"
Write-Host "Known local HID devices are learned automatically during normal local use."

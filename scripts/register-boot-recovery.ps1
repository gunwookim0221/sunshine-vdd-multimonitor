# Register or remove the logon-time display recovery safety net.
# Run from an elevated PowerShell.

param([switch]$Remove)

$ErrorActionPreference = "Stop"
$TaskName = "Sunshine VDD Boot Recovery"
$ScriptPath = "C:\SunshineScripts\sunshine-boot-recovery.ps1"

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task: $TaskName"
    exit 0
}

if (-not (Test-Path $ScriptPath)) { throw "Recovery script not found: $ScriptPath" }

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File \"$ScriptPath\""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Restore the known-good physical monitor layout at user logon, then disable VDD only after two displays are verified." -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host "The task runs at logon; the recovery script waits 10 seconds before restoring displays."

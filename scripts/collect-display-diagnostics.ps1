# Collect a one-shot diagnostic bundle without changing monitor topology.
# Useful immediately after a display problem, before recovery/reboot when possible.

$ErrorActionPreference = "Continue"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LogRoot = "C:\SunshineLogs"
$RunId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-diagnostics"
$RunDir = Join-Path $LogRoot $RunId

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

if (Test-Path $MultiMonitorTool) {
    & $MultiMonitorTool /scomma (Join-Path $RunDir "monitors.csv") | Out-Null
}

Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
    Out-File (Join-Path $RunDir "display-pnp.txt") -Encoding utf8

try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Screen]::AllScreens |
        Format-List DeviceName,Primary,Bounds,WorkingArea,BitsPerPixel |
        Out-File (Join-Path $RunDir "active-screens.txt") -Encoding utf8
} catch {}

try {
    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddHours(-8) } |
        Where-Object { $_.ProviderName -match "Display|Kernel-PnP|nvlddmkm|Kernel-Power" } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List |
        Out-File (Join-Path $RunDir "system-display-events.txt") -Encoding utf8
} catch {}

Write-Host "Diagnostics saved to: $RunDir"

# Sunshine/Moonlight remote-session end script
# Safety-critical order:
# 1) Restore local.cfg FIRST
# 2) Verify at least two displays are attached again
# 3) Only then disable VDD
#
# Run elevated from Sunshine Prep Commands.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LocalConfig      = "C:\SunshineTools\multimonitortool\local.cfg"
$DxgiInfo         = "C:\Program Files\Sunshine\tools\dxgi-info.exe"
$TimeoutSeconds   = 20

function Get-MttVdd {
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InstanceId -like "ROOT\DISPLAY*" -and
            (
                $_.FriendlyName -eq "Virtual Display Driver" -or
                $_.FriendlyName -eq "VDD by MTT" -or
                $_.FriendlyName -like "*Virtual Display*"
            )
        } |
        Select-Object -First 1
}

if (-not (Test-Path $MultiMonitorTool)) {
    Write-Error "MultiMonitorTool not found: $MultiMonitorTool"
    exit 1
}
if (-not (Test-Path $LocalConfig)) {
    Write-Error "local.cfg not found: $LocalConfig"
    exit 1
}

Write-Host "Restoring local physical-monitor configuration..."
& $MultiMonitorTool /LoadConfig $LocalConfig

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$physicalRestored = $false

do {
    Start-Sleep -Milliseconds 750

    if (Test-Path $DxgiInfo) {
        $dxgi = (& $DxgiInfo 2>&1 | Out-String)
        $attached = ([regex]::Matches($dxgi, 'AttachedToDesktop\s*:\s*yes')).Count

        if ($attached -ge 2) {
            $physicalRestored = $true
            break
        }
    }
    else {
        Start-Sleep -Seconds 4
        $physicalRestored = $true
        break
    }
} while ((Get-Date) -lt $deadline)

if (-not $physicalRestored) {
    Write-Error "Physical monitors were not restored. VDD will NOT be disabled for safety."
    exit 1
}

Write-Host "Physical monitor configuration restored."

$device = Get-MttVdd
if (-not $device) {
    Write-Host "VDD already unavailable."
    exit 0
}

if ($device.Status -in @("OK", "Started", "Degraded")) {
    Write-Host "Disabling VDD: $($device.FriendlyName) [$($device.InstanceId)]"
    $device | Disable-PnpDevice -Confirm:$false
    Start-Sleep -Seconds 1
}
else {
    Write-Host "VDD already disabled."
}

Write-Host "Local mode restored successfully."
exit 0

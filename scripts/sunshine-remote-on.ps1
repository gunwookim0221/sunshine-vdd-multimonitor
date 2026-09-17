# Sunshine/Moonlight remote-session start script
# Tested design:
# 1) Enable MTT VDD if needed
# 2) Discover the VDD display dynamically
# 3) Enable it
# 4) Make it primary
# 5) Disable every other attached display
#
# Run elevated from Sunshine Prep Commands.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$TempCsv          = Join-Path $env:TEMP "sunshine-multimonitors.csv"

function Get-MttVddDevice {
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

function Get-MonitorRows {
    param([string]$ToolPath, [string]$CsvPath)

    Remove-Item $CsvPath -Force -ErrorAction SilentlyContinue
    & $ToolPath /scomma $CsvPath | Out-Null
    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $CsvPath)) {
        throw "MultiMonitorTool did not create CSV output."
    }

    return Import-Csv $CsvPath
}

function Find-VddDisplayName {
    param($Rows)

    foreach ($row in $Rows) {
        $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })

        $isVdd = $false
        foreach ($v in $values) {
            if ($v -match 'VDD by MTT|Virtual Display Driver|MttVDD|\bMTT\b') {
                $isVdd = $true
                break
            }
        }

        if (-not $isVdd) {
            continue
        }

        foreach ($v in $values) {
            if ($v -like '\\.\DISPLAY*') {
                return $v
            }
        }
    }

    return $null
}

function Get-AllDisplayNames {
    param($Rows)

    $names = New-Object System.Collections.Generic.List[string]

    foreach ($row in $Rows) {
        foreach ($prop in $row.PSObject.Properties) {
            $v = [string]$prop.Value
            if ($v -like '\\.\DISPLAY*') {
                if (-not $names.Contains($v)) {
                    $names.Add($v)
                }
            }
        }
    }

    return $names
}

if (-not (Test-Path $MultiMonitorTool)) {
    Write-Error "MultiMonitorTool not found: $MultiMonitorTool"
    exit 1
}

$device = Get-MttVddDevice
if (-not $device) {
    Write-Error "Virtual Display Driver device was not found."
    exit 1
}

if ($device.Status -notin @("OK", "Started", "Degraded")) {
    Write-Host "Enabling VDD device: $($device.FriendlyName) [$($device.InstanceId)]"
    $device | Enable-PnpDevice -Confirm:$false
    Start-Sleep -Seconds 3
}
else {
    Write-Host "VDD device already enabled."
    Start-Sleep -Seconds 1
}

$rows = Get-MonitorRows -ToolPath $MultiMonitorTool -CsvPath $TempCsv
$vddDisplay = Find-VddDisplayName -Rows $rows

if (-not $vddDisplay) {
    Write-Error "Could not locate the MTT virtual monitor in MultiMonitorTool."
    exit 1
}

Write-Host "Virtual monitor found: $vddDisplay"

Write-Host "Enabling virtual monitor..."
& $MultiMonitorTool /enable $vddDisplay
Start-Sleep -Seconds 1

Write-Host "Setting virtual monitor as primary..."
& $MultiMonitorTool /SetPrimary $vddDisplay
Start-Sleep -Seconds 1

$rows = Get-MonitorRows -ToolPath $MultiMonitorTool -CsvPath $TempCsv
$allDisplays = Get-AllDisplayNames -Rows $rows
$otherDisplays = @($allDisplays | Where-Object { $_ -ne $vddDisplay })

if ($otherDisplays.Count -gt 0) {
    Write-Host "Disabling other displays: $($otherDisplays -join ', ')"

    foreach ($display in $otherDisplays) {
        & $MultiMonitorTool /disable $display
        Start-Sleep -Milliseconds 500
    }
}

Start-Sleep -Seconds 2
Write-Host "Remote mode applied. Active target: $vddDisplay"
exit 0

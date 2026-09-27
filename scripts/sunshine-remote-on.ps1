# Sunshine/Moonlight remote-session start script
# v4: diagnostics + dynamic VDD detection
# Run elevated from Sunshine Prep Commands.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LogRoot = "C:\SunshineLogs"
$RunId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-on"
$RunDir = Join-Path $LogRoot $RunId
$LogFile = Join-Path $RunDir "operations.log"

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

function Get-MttVddDevice {
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InstanceId -like "ROOT\DISPLAY*" -and
            ($_.FriendlyName -eq "Virtual Display Driver" -or $_.FriendlyName -eq "VDD by MTT" -or $_.FriendlyName -like "*Virtual Display*")
        } | Select-Object -First 1
}

function Save-MonitorSnapshot {
    param([string]$Name)
    $csv = Join-Path $RunDir ($Name + ".csv")
    & $MultiMonitorTool /scomma $csv | Out-Null
    $pnp = Join-Path $RunDir ($Name + "-pnp.txt")
    Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
        Out-File -FilePath $pnp -Encoding utf8
}

function Get-MonitorRows {
    $csv = Join-Path $RunDir "current.csv"
    Remove-Item $csv -Force -ErrorAction SilentlyContinue
    & $MultiMonitorTool /scomma $csv | Out-Null
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path $csv)) { throw "MultiMonitorTool did not create CSV output." }
    Import-Csv $csv
}

function Find-VddDisplayName {
    param($Rows)
    foreach ($row in $Rows) {
        $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
        if (-not ($values -match 'VDD by MTT|Virtual Display Driver|MttVDD|\bMTT\b')) { continue }
        foreach ($v in $values) {
            if ($v -like '\\.\DISPLAY*') { return $v }
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
            if ($v -like '\\.\DISPLAY*' -and -not $names.Contains($v)) { $names.Add($v) }
        }
    }
    return $names
}

try {
    Write-Log "SESSION_START pid=$PID user=$env:USERNAME"
    if (-not (Test-Path $MultiMonitorTool)) { throw "MultiMonitorTool not found: $MultiMonitorTool" }
    Save-MonitorSnapshot "01-before-on"

    $device = Get-MttVddDevice
    if (-not $device) { throw "Virtual Display Driver device was not found." }
    Write-Log "VDD_PNP friendly='$($device.FriendlyName)' instance='$($device.InstanceId)' status='$($device.Status)'"

    if ($device.Status -notin @("OK", "Started", "Degraded")) {
        Write-Log "Enabling VDD PnP device."
        $device | Enable-PnpDevice -Confirm:$false
        Start-Sleep -Seconds 3
    } else {
        Write-Log "VDD PnP device already enabled."
        Start-Sleep -Seconds 1
    }

    Save-MonitorSnapshot "02-after-vdd-pnp"
    $rows = Get-MonitorRows
    $vddDisplay = Find-VddDisplayName -Rows $rows
    if (-not $vddDisplay) { throw "Could not locate the MTT virtual monitor in MultiMonitorTool." }

    Write-Log "VDD_DISPLAY=$vddDisplay"
    Write-Log "Enabling virtual monitor $vddDisplay"
    & $MultiMonitorTool /enable $vddDisplay
    Start-Sleep -Seconds 1

    Write-Log "Setting $vddDisplay as primary."
    & $MultiMonitorTool /SetPrimary $vddDisplay
    Start-Sleep -Seconds 1

    $rows = Get-MonitorRows
    $allDisplays = Get-AllDisplayNames -Rows $rows
    $otherDisplays = @($allDisplays | Where-Object { $_ -ne $vddDisplay })

    if ($otherDisplays.Count -gt 0) {
        Write-Log "Disabling other displays: $($otherDisplays -join ', ')"
        foreach ($display in $otherDisplays) {
            & $MultiMonitorTool /disable $display
            Start-Sleep -Milliseconds 500
        }
    } else {
        Write-Log "No other displays found to disable."
    }

    Start-Sleep -Seconds 2
    Save-MonitorSnapshot "03-after-on"
    Write-Log "SESSION_START_SUCCESS target=$vddDisplay"
    exit 0
} catch {
    Write-Log "SESSION_START_FAILED error='$($_.Exception.Message)'"
    try { Save-MonitorSnapshot "99-failure" } catch {}
    exit 1
}

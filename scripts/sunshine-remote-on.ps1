# Sunshine/Moonlight remote-session start script
# v4.1: diagnostics + stable monitor identifiers + post-switch verification
#
# Key rule:
# Never disable physical monitors by \\.\DISPLAYx one-by-one. Windows can renumber
# DISPLAY names immediately after a topology change. Instead, resolve stable monitor
# identifiers first, then disable all physical monitors in ONE MultiMonitorTool call.
#
# Run elevated from Sunshine Prep Commands.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LocalConfig      = "C:\SunshineTools\multimonitortool\local.cfg"
$LogRoot          = "C:\SunshineLogs"
$RunId            = (Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-on"
$RunDir           = Join-Path $LogRoot $RunId
$LogFile          = Join-Path $RunDir "operations.log"

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
            (
                $_.FriendlyName -eq "Virtual Display Driver" -or
                $_.FriendlyName -eq "VDD by MTT" -or
                $_.FriendlyName -like "*Virtual Display*"
            )
        } |
        Select-Object -First 1
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

    if (-not (Test-Path $csv)) {
        throw "MultiMonitorTool did not create CSV output."
    }

    return Import-Csv $csv
}

function Test-IsVddRow {
    param($Row)

    return (
        [string]$Row.Adapter -match 'Virtual Display Driver' -or
        [string]$Row.'Monitor Name' -match 'VDD by MTT' -or
        [string]$Row.'Short Monitor ID' -match '^MTT' -or
        [string]$Row.'Device ID' -match 'MttVDD'
    )
}

function Get-StableMonitorIdentifier {
    param($Row)

    # Prefer identifiers that do not depend on Windows DISPLAY numbering.
    # Serial is strongest when present; full Monitor ID is next; Short Monitor ID is
    # the practical fallback. Name (\\.\DISPLAYx) is used only as a last resort.
    $serial = [string]$Row.'Monitor Serial Number'
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        return $serial.Trim()
    }

    $monitorId = [string]$Row.'Monitor ID'
    if (-not [string]::IsNullOrWhiteSpace($monitorId)) {
        return $monitorId.Trim()
    }

    $shortId = [string]$Row.'Short Monitor ID'
    if (-not [string]::IsNullOrWhiteSpace($shortId)) {
        return $shortId.Trim()
    }

    $name = [string]$Row.Name
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        return $name.Trim()
    }

    return $null
}

function Get-ActiveScreenCount {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return [System.Windows.Forms.Screen]::AllScreens.Count
    }
    catch {
        Write-Log "Screen enumeration failed: $($_.Exception.Message)"
        return 0
    }
}

function Restore-LocalFailSafe {
    Write-Log "ROLLBACK_START: attempting local.cfg restore."

    if (-not (Test-Path $LocalConfig)) {
        Write-Log "ROLLBACK_SKIPPED: local.cfg not found; VDD will remain enabled for safety."
        return
    }

    & $MultiMonitorTool /LoadConfig $LocalConfig
    Start-Sleep -Seconds 3

    $screenCount = Get-ActiveScreenCount
    Write-Log "ROLLBACK active Windows screens=$screenCount"

    if ($screenCount -ge 2) {
        $device = Get-MttVddDevice
        if ($device -and $device.Status -in @("OK", "Started", "Degraded")) {
            Write-Log "ROLLBACK verified physical displays; disabling VDD PnP device."
            $device | Disable-PnpDevice -Confirm:$false
            Start-Sleep -Seconds 1
        }
        Write-Log "ROLLBACK_SUCCESS"
    }
    else {
        Write-Log "ROLLBACK_FAIL_SAFE: fewer than two active screens; VDD left unchanged."
    }
}

try {
    Write-Log "SESSION_START_V41 pid=$PID user=$env:USERNAME"

    if (-not (Test-Path $MultiMonitorTool)) {
        throw "MultiMonitorTool not found: $MultiMonitorTool"
    }

    Save-MonitorSnapshot "01-before-on"

    $device = Get-MttVddDevice
    if (-not $device) {
        throw "Virtual Display Driver device was not found."
    }

    Write-Log "VDD_PNP friendly='$($device.FriendlyName)' instance='$($device.InstanceId)' status='$($device.Status)'"

    if ($device.Status -notin @("OK", "Started", "Degraded")) {
        Write-Log "Enabling VDD PnP device."
        $device | Enable-PnpDevice -Confirm:$false
        Start-Sleep -Seconds 3
    }
    else {
        Write-Log "VDD PnP device already enabled."
        Start-Sleep -Seconds 1
    }

    Save-MonitorSnapshot "02-after-vdd-pnp"

    $rows = Get-MonitorRows
    $vddRow = @($rows | Where-Object { Test-IsVddRow $_ } | Select-Object -First 1)
    if (-not $vddRow -or $vddRow.Count -eq 0) {
        throw "Could not locate the MTT virtual monitor in MultiMonitorTool."
    }
    $vddRow = $vddRow[0]

    $vddId = Get-StableMonitorIdentifier -Row $vddRow
    if (-not $vddId) {
        throw "VDD was found but no usable monitor identifier was available."
    }

    Write-Log "VDD name='$($vddRow.Name)' stableId='$vddId' shortId='$($vddRow.'Short Monitor ID')'"

    Write-Log "Enabling VDD by stable identifier: $vddId"
    & $MultiMonitorTool /enable $vddId
    Start-Sleep -Seconds 1

    Write-Log "Setting VDD primary by stable identifier: $vddId"
    & $MultiMonitorTool /SetPrimary $vddId
    Start-Sleep -Seconds 1

    # Refresh once, BEFORE any physical display is disabled. Resolve every target to a
    # stable identifier now so a later DISPLAY renumber cannot redirect the next command.
    $rows = Get-MonitorRows
    $physicalRows = @($rows | Where-Object {
        $_.Active -eq 'Yes' -and -not (Test-IsVddRow $_)
    })

    $physicalIds = @(
        $physicalRows |
            ForEach-Object { Get-StableMonitorIdentifier -Row $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($physicalIds.Count -gt 0) {
        Write-Log "Disabling physical displays in one call using stable identifiers: $($physicalIds -join ' | ')"
        $disableArgs = @('/disable') + $physicalIds
        & $MultiMonitorTool @disableArgs
        Start-Sleep -Seconds 2
    }
    else {
        Write-Log "No active physical displays found to disable."
    }

    Save-MonitorSnapshot "03-after-on"

    # Strong post-condition: exactly one active monitor, and it must be the VDD.
    $verifyRows = Get-MonitorRows
    $activeRows = @($verifyRows | Where-Object { $_.Active -eq 'Yes' })
    $activeVddRows = @($activeRows | Where-Object { Test-IsVddRow $_ })

    Write-Log "VERIFY activeCount=$($activeRows.Count) activeVddCount=$($activeVddRows.Count)"

    if ($activeRows.Count -ne 1 -or $activeVddRows.Count -ne 1) {
        $activeSummary = @($activeRows | ForEach-Object {
            "name=$($_.Name),short=$($_.'Short Monitor ID'),monitorId=$($_.'Monitor ID'),primary=$($_.Primary)"
        }) -join ' ; '
        Write-Log "VERIFY_FAILED active='$activeSummary'"
        Save-MonitorSnapshot "04-verification-failed"
        Restore-LocalFailSafe
        throw "Exclusive VDD mode verification failed; local rollback was attempted."
    }

    if ($activeVddRows[0].Primary -ne 'Yes') {
        Write-Log "VERIFY_FAILED: VDD is the only active display but is not primary."
        Save-MonitorSnapshot "04-verification-failed"
        Restore-LocalFailSafe
        throw "VDD primary verification failed; local rollback was attempted."
    }

    Write-Log "SESSION_START_SUCCESS targetName='$($activeVddRows[0].Name)' stableId='$vddId'"
    exit 0
}
catch {
    Write-Log "SESSION_START_FAILED error='$($_.Exception.Message)'"
    try { Save-MonitorSnapshot "99-failure" } catch {}
    exit 1
}

# Sunshine/Moonlight remote-session end script
# v4.2 safety order:
# 1) Snapshot current state
# 2) Restore local.cfg FIRST
# 3) Verify at least two active PHYSICAL monitors from fresh MultiMonitorTool CSV
# 4) Only then disable VDD
# 5) Persist diagnostics
# Run elevated from Sunshine Prep Commands.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LocalConfig = "C:\SunshineTools\multimonitortool\local.cfg"
$LogRoot = "C:\SunshineLogs"
$TimeoutSeconds = 20
$RunId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-off"
$RunDir = Join-Path $LogRoot $RunId
$LogFile = Join-Path $RunDir "operations.log"

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

function Get-MttVdd {
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
    param([string]$FileName = "current.csv")

    $csv = Join-Path $RunDir $FileName
    Remove-Item $csv -Force -ErrorAction SilentlyContinue
    & $MultiMonitorTool /scomma $csv | Out-Null
    Start-Sleep -Milliseconds 250

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

try {
    Write-Log "SESSION_END_START pid=$PID user=$env:USERNAME"
    if (-not (Test-Path $MultiMonitorTool)) { throw "MultiMonitorTool not found: $MultiMonitorTool" }
    if (-not (Test-Path $LocalConfig)) { throw "local.cfg not found: $LocalConfig" }

    Save-MonitorSnapshot "01-before-off"

    Write-Log "Loading local.cfg before touching VDD."
    & $MultiMonitorTool /LoadConfig $LocalConfig

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $physicalActiveRows = @()
    do {
        Start-Sleep -Milliseconds 750
        $rows = Get-MonitorRows -FileName "verify-current.csv"
        $physicalActiveRows = @($rows | Where-Object {
            $_.Active -eq 'Yes' -and -not (Test-IsVddRow $_)
        })

        $physicalSummary = @($physicalActiveRows | ForEach-Object {
            "name=$($_.Name),short=$($_.'Short Monitor ID'),monitor=$($_.'Monitor Name'),primary=$($_.Primary)"
        }) -join ' ; '

        Write-Log "VERIFY physicalActiveCount=$($physicalActiveRows.Count) physical='$physicalSummary'"
        if ($physicalActiveRows.Count -ge 2) { break }
    } while ((Get-Date) -lt $deadline)

    Save-MonitorSnapshot "02-after-local-restore"

    if ($physicalActiveRows.Count -lt 2) {
        Write-Log "FAIL_SAFE: fewer than two active physical monitors after local.cfg restore. VDD will remain enabled."
        throw "Physical monitors were not restored. VDD was NOT disabled for safety."
    }

    Write-Log "Physical monitor configuration verified with $($physicalActiveRows.Count) active physical monitors."

    $device = Get-MttVdd
    if (-not $device) {
        Write-Log "VDD device not found; local layout is already restored."
        Save-MonitorSnapshot "03-final"
        Write-Log "SESSION_END_SUCCESS"
        exit 0
    }

    Write-Log "VDD_PNP friendly='$($device.FriendlyName)' instance='$($device.InstanceId)' status='$($device.Status)'"

    if ($device.Status -in @("OK", "Started", "Degraded")) {
        Write-Log "Disabling VDD only after physical-monitor verification."
        $device | Disable-PnpDevice -Confirm:$false
        Start-Sleep -Seconds 1
    } else {
        Write-Log "VDD already disabled."
    }

    Save-MonitorSnapshot "03-final"
    Write-Log "SESSION_END_SUCCESS"
    exit 0
} catch {
    Write-Log "SESSION_END_FAILED error='$($_.Exception.Message)'"
    try { Save-MonitorSnapshot "99-failure" } catch {}
    exit 1
}

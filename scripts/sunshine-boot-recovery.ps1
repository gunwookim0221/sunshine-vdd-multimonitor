# Restore the normal physical-monitor layout at Windows logon.
# v4.3: verify physical-display recovery from fresh MultiMonitorTool topology.
# Safety net for crashes, power loss, forced reset, or a missed Sunshine Undo.
# Run elevated from Task Scheduler.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LocalConfig = "C:\SunshineTools\multimonitortool\local.cfg"
$LogRoot = "C:\SunshineLogs"
$TimeoutSeconds = 30
$StartupDelay = 10
$RequiredStableChecks = 2
$RunId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff") + "-boot-recovery"
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

function Save-RecentDisplayEvents {
    $out = Join-Path $RunDir "recent-system-display-events.txt"
    try {
        Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddHours(-8) } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match "Display|Kernel-PnP|nvlddmkm|Kernel-Power" } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
            Format-List |
            Out-File -FilePath $out -Encoding utf8
    } catch {
        Write-Log "Could not export recent System display events: $($_.Exception.Message)"
    }
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
    Write-Log "BOOT_RECOVERY_START pid=$PID user=$env:USERNAME"
    Write-Log "Waiting $StartupDelay seconds for the interactive desktop and display stack."
    Start-Sleep -Seconds $StartupDelay

    if (-not (Test-Path $MultiMonitorTool)) { throw "MultiMonitorTool not found: $MultiMonitorTool" }
    if (-not (Test-Path $LocalConfig)) { throw "local.cfg not found: $LocalConfig" }

    Save-MonitorSnapshot "01-before-recovery"
    Save-RecentDisplayEvents

    Write-Log "Loading known-good local.cfg."
    & $MultiMonitorTool /LoadConfig $LocalConfig

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $physicalActiveRows = @()
    $stableChecks = 0
    $attempt = 0

    do {
        Start-Sleep -Seconds 1
        $attempt++

        $rows = Get-MonitorRows -FileName "verify-current.csv"
        $physicalActiveRows = @($rows | Where-Object {
            $_.Active -eq 'Yes' -and -not (Test-IsVddRow $_)
        })

        if ($physicalActiveRows.Count -ge 2) {
            $stableChecks++
        }
        else {
            $stableChecks = 0
        }

        $physicalSummary = @($physicalActiveRows | ForEach-Object {
            "name=$($_.Name),short=$($_.'Short Monitor ID'),monitor=$($_.'Monitor Name'),primary=$($_.Primary)"
        }) -join ' ; '

        Write-Log "BOOT_VERIFY attempt=$attempt stable=$stableChecks/$RequiredStableChecks physicalActiveCount=$($physicalActiveRows.Count) physical='$physicalSummary'"

        if ($stableChecks -ge $RequiredStableChecks) { break }
    } while ((Get-Date) -lt $deadline)

    Save-MonitorSnapshot "02-after-local-restore"

    if ($stableChecks -lt $RequiredStableChecks) {
        Write-Log "FAIL_SAFE: physical monitor topology did not converge. Leaving VDD state unchanged."
        throw "Boot recovery could not verify two stable active physical displays."
    }

    $device = Get-MttVdd
    if ($device -and $device.Status -in @("OK", "Started", "Degraded")) {
        Write-Log "Stable physical topology verified; disabling VDD."
        $device | Disable-PnpDevice -Confirm:$false
        Start-Sleep -Seconds 1
    } else {
        Write-Log "VDD is already disabled or unavailable."
    }

    Save-MonitorSnapshot "03-final"
    Write-Log "BOOT_RECOVERY_SUCCESS physicalActiveCount=$($physicalActiveRows.Count) stableChecks=$stableChecks"
    exit 0
} catch {
    Write-Log "BOOT_RECOVERY_FAILED error='$($_.Exception.Message)'"
    try { Save-MonitorSnapshot "99-failure" } catch {}
    exit 1
}

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
$RunStartedAt = [DateTimeOffset]::Now
$RunStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
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

function Get-PnpInventory {
    param(
        [string]$Class,
        [switch]$PresentOnly
    )

    $queryStartedAt = [DateTimeOffset]::Now
    try {
        if ($PresentOnly) {
            $devices = @(Get-PnpDevice -Class $Class -PresentOnly -ErrorAction Stop)
        } else {
            $devices = @(Get-PnpDevice -Class $Class -ErrorAction Stop)
        }

        return [pscustomobject]@{
            Class = $Class
            PresentOnly = [bool]$PresentOnly
            QuerySucceeded = $true
            Error = $null
            QueryStartedAt = $queryStartedAt
            QueryEndedAt = [DateTimeOffset]::Now
            Devices = $devices
        }
    } catch {
        return [pscustomobject]@{
            Class = $Class
            PresentOnly = [bool]$PresentOnly
            QuerySucceeded = $false
            Error = $_.Exception.Message
            QueryStartedAt = $queryStartedAt
            QueryEndedAt = [DateTimeOffset]::Now
            Devices = @()
        }
    }
}

function Format-PnpDeviceSummary {
    param([object[]]$Devices)

    return @($Devices | ForEach-Object {
        $name = ([string]$_.FriendlyName) -replace "[\r\n;']", " "
        $instanceId = ([string]$_.InstanceId) -replace "[\r\n;']", " "
        "name=$name,status=$($_.Status),id=$instanceId"
    }) -join " ; "
}

function Save-MonitorSnapshot {
    param([string]$Name)

    $captureStartedAt = [DateTimeOffset]::Now
    $csv = Join-Path $RunDir ($Name + ".csv")
    & $MultiMonitorTool /scomma $csv | Out-Null
    $mttExitCode = $LASTEXITCODE
    $csvRows = @()
    $csvLastWriteUtc = $null
    $csvReadError = $null
    try {
        if (Test-Path $csv) {
            $csvRows = @(Import-Csv $csv)
            $csvLastWriteUtc = (Get-Item $csv).LastWriteTimeUtc
        } else {
            $csvReadError = "MultiMonitorTool did not create CSV output."
        }
    } catch {
        $csvReadError = $_.Exception.Message
    }

    $pnp = Join-Path $RunDir ($Name + "-pnp.txt")
    Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
        Out-File -FilePath $pnp -Encoding utf8

    try {
        $monitorAll = Get-PnpInventory -Class Monitor
        $monitorPresent = Get-PnpInventory -Class Monitor -PresentOnly
        $displayPresent = Get-PnpInventory -Class Display -PresentOnly

        $monitorAll.Devices |
            Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
            Out-File -FilePath (Join-Path $RunDir ($Name + "-monitor-pnp.txt")) -Encoding utf8
        $monitorPresent.Devices |
            Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
            Out-File -FilePath (Join-Path $RunDir ($Name + "-monitor-pnp-present.txt")) -Encoding utf8
        $displayPresent.Devices |
            Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode |
            Out-File -FilePath (Join-Path $RunDir ($Name + "-present-pnp.txt")) -Encoding utf8

        $targetPattern = 'SAM7053|LC49G95T|SAMSUNG'
        $monitorTargetAll = @($monitorAll.Devices | Where-Object {
            ([string]$_.FriendlyName -match $targetPattern) -or ([string]$_.InstanceId -match $targetPattern)
        })
        $monitorTargetPresent = @($monitorPresent.Devices | Where-Object {
            ([string]$_.FriendlyName -match $targetPattern) -or ([string]$_.InstanceId -match $targetPattern)
        })
        $adaptersSummary = Format-PnpDeviceSummary -Devices $displayPresent.Devices
        $topologySummary = @($csvRows | ForEach-Object {
            $name = ([string]$_.Name) -replace "[\r\n;']", " "
            $deviceId = ([string]$_.'Device ID') -replace "[\r\n;']", " "
            "name=$name,active=$($_.Active),primary=$($_.Primary),vdd=$(Test-IsVddRow $_),deviceId=$deviceId"
        }) -join " ; "
        $captureEndedAt = [DateTimeOffset]::Now
        $csvAgeMs = if ($csvLastWriteUtc) {
            [Math]::Round(($captureEndedAt.UtcDateTime - $csvLastWriteUtc).TotalMilliseconds, 1)
        } else { $null }
        $evidence = [pscustomobject]@{
            schemaVersion = 1
            runId = $RunId
            stage = $Name
            runStartedLocal = $RunStartedAt.ToString("o")
            runStartedUtc = $RunStartedAt.UtcDateTime.ToString("o")
            captureStartedLocal = $captureStartedAt.ToString("o")
            captureEndedLocal = $captureEndedAt.ToString("o")
            captureStartedUtc = $captureStartedAt.UtcDateTime.ToString("o")
            captureEndedUtc = $captureEndedAt.UtcDateTime.ToString("o")
            recoveryElapsedMs = $RunStopwatch.ElapsedMilliseconds
            mtt = [pscustomobject]@{
                path = $csv
                exitCode = $mttExitCode
                csvLastWriteUtc = if ($csvLastWriteUtc) { $csvLastWriteUtc.ToString("o") } else { $null }
                csvAgeAtCaptureEndMs = $csvAgeMs
                csvCreatedDuringCapture = if ($csvLastWriteUtc) {
                    $csvLastWriteUtc -ge $captureStartedAt.UtcDateTime.AddMilliseconds(-100)
                } else { $false }
                rowCount = $csvRows.Count
                readError = $csvReadError
                rows = @($csvRows | ForEach-Object {
                    [pscustomobject]@{
                        name = $_.Name
                        active = $_.Active
                        primary = $_.Primary
                        adapter = $_.Adapter
                        monitorName = $_.'Monitor Name'
                        shortMonitorId = $_.'Short Monitor ID'
                        deviceId = $_.'Device ID'
                        isVdd = Test-IsVddRow $_
                    }
                })
            }
            monitorPnp = [pscustomobject]@{
                allQuerySucceeded = $monitorAll.QuerySucceeded
                allQueryError = $monitorAll.Error
                allQueryStartedUtc = $monitorAll.QueryStartedAt.UtcDateTime.ToString("o")
                allQueryEndedUtc = $monitorAll.QueryEndedAt.UtcDateTime.ToString("o")
                allCount = $monitorAll.Devices.Count
                presentOnlyQuerySucceeded = $monitorPresent.QuerySucceeded
                presentOnlyQueryError = $monitorPresent.Error
                presentOnlyQueryStartedUtc = $monitorPresent.QueryStartedAt.UtcDateTime.ToString("o")
                presentOnlyQueryEndedUtc = $monitorPresent.QueryEndedAt.UtcDateTime.ToString("o")
                presentOnlyCount = $monitorPresent.Devices.Count
                samsungKnownCount = $monitorTargetAll.Count
                samsungPresentOnlyCount = $monitorTargetPresent.Count
                samsungAll = @($monitorTargetAll | ForEach-Object {
                    [pscustomobject]@{ status = $_.Status; friendlyName = $_.FriendlyName; instanceId = $_.InstanceId; problem = $_.Problem; configManagerErrorCode = $_.ConfigManagerErrorCode }
                })
                samsungPresentOnly = @($monitorTargetPresent | ForEach-Object {
                    [pscustomobject]@{ status = $_.Status; friendlyName = $_.FriendlyName; instanceId = $_.InstanceId; problem = $_.Problem; configManagerErrorCode = $_.ConfigManagerErrorCode }
                })
            }
            displayAdapters = [pscustomobject]@{
                allClassSnapshotPath = $pnp
                presentOnlyQuerySucceeded = $displayPresent.QuerySucceeded
                presentOnlyQueryError = $displayPresent.Error
                presentOnlyQueryStartedUtc = $displayPresent.QueryStartedAt.UtcDateTime.ToString("o")
                presentOnlyQueryEndedUtc = $displayPresent.QueryEndedAt.UtcDateTime.ToString("o")
                presentOnlyCount = $displayPresent.Devices.Count
                presentOnlySummary = $adaptersSummary
                presentOnly = @($displayPresent.Devices | ForEach-Object {
                    [pscustomobject]@{ status = $_.Status; friendlyName = $_.FriendlyName; instanceId = $_.InstanceId; problem = $_.Problem; configManagerErrorCode = $_.ConfigManagerErrorCode }
                })
            }
        }

        $evidencePath = Join-Path $RunDir ($Name + "-evidence.json")
        $evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $evidencePath -Encoding utf8
        Write-Log "DIAGNOSTIC_SNAPSHOT stage=$Name startLocal='$($captureStartedAt.ToString("o"))' endLocal='$($captureEndedAt.ToString("o"))' elapsedMs=$($RunStopwatch.ElapsedMilliseconds) mttExitCode='$mttExitCode' csvLastWriteUtc='$($evidence.mtt.csvLastWriteUtc)' csvAgeMs='$csvAgeMs' csvCurrent='$($evidence.mtt.csvCreatedDuringCapture)' rows=$($csvRows.Count) monitorPnpAll=$($monitorAll.Devices.Count) monitorPnpPresent=$($monitorPresent.Devices.Count) samsungKnown=$($monitorTargetAll.Count) samsungPresent=$($monitorTargetPresent.Count) displayAdaptersPresent=$($displayPresent.Devices.Count) adapters='$adaptersSummary' topology='$topologySummary'" | Out-Null
    } catch {
        Write-Log "DIAGNOSTIC_CAPTURE_ERROR stage=$Name error='$($_.Exception.Message)'" | Out-Null
    }
}

function Get-MonitorRows {
    param([string]$FileName = "current.csv")

    $csv = Join-Path $RunDir $FileName
    Remove-Item $csv -Force -ErrorAction SilentlyContinue
    $captureStartedAt = [DateTimeOffset]::Now
    $captureTimer = [System.Diagnostics.Stopwatch]::StartNew()
    & $MultiMonitorTool /scomma $csv | Out-Null
    $mttExitCode = $LASTEXITCODE
    Start-Sleep -Milliseconds 250

    if (-not (Test-Path $csv)) {
        $captureTimer.Stop()
        $captureEndedAt = [DateTimeOffset]::Now
        $script:LastMttCapture = [pscustomobject]@{
            StartedAt = $captureStartedAt
            EndedAt = $captureEndedAt
            DurationMs = $captureTimer.ElapsedMilliseconds
            ExitCode = $mttExitCode
            CsvLastWriteUtc = $null
            CsvAgeMs = $null
            CsvCreatedDuringCapture = $false
            RowCount = 0
        }
        Write-Log "TOPOLOGY_SAMPLE_ERROR file='$FileName' startLocal='$($captureStartedAt.ToString("o"))' endLocal='$($captureEndedAt.ToString("o"))' recoveryElapsedMs=$($RunStopwatch.ElapsedMilliseconds) mttDurationMs=$($captureTimer.ElapsedMilliseconds) mttExitCode='$mttExitCode' csvCurrent=false error='MultiMonitorTool did not create CSV output.'" | Out-Null
        throw "MultiMonitorTool did not create CSV output."
    }

    $rows = @(Import-Csv $csv)
    $csvLastWriteUtc = (Get-Item $csv).LastWriteTimeUtc
    $captureTimer.Stop()
    $captureEndedAt = [DateTimeOffset]::Now
    $script:LastMttCapture = [pscustomobject]@{
        StartedAt = $captureStartedAt
        EndedAt = $captureEndedAt
        DurationMs = $captureTimer.ElapsedMilliseconds
        ExitCode = $mttExitCode
        CsvLastWriteUtc = $csvLastWriteUtc
        CsvAgeMs = [Math]::Round(($captureEndedAt.UtcDateTime - $csvLastWriteUtc).TotalMilliseconds, 1)
        CsvCreatedDuringCapture = ($csvLastWriteUtc -ge $captureStartedAt.UtcDateTime.AddMilliseconds(-100))
        RowCount = $rows.Count
    }

    return $rows
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
    $attempt = 0
    do {
        $attempt++
        Start-Sleep -Milliseconds 750
        $rows = Get-MonitorRows -FileName "verify-current.csv"
        $physicalActiveRows = @($rows | Where-Object {
            $_.Active -eq 'Yes' -and -not (Test-IsVddRow $_)
        })

        $physicalSummary = @($physicalActiveRows | ForEach-Object {
            "name=$($_.Name),short=$($_.'Short Monitor ID'),monitor=$($_.'Monitor Name'),primary=$($_.Primary)"
        }) -join ' ; '

        $sample = $script:LastMttCapture
        $allTopologySummary = @($rows | ForEach-Object {
            $name = ([string]$_.Name) -replace "[\r\n;']", " "
            $deviceId = ([string]$_.'Device ID') -replace "[\r\n;']", " "
            "name=$name,active=$($_.Active),primary=$($_.Primary),vdd=$(Test-IsVddRow $_),deviceId=$deviceId"
        }) -join " ; "
        Write-Log "TOPOLOGY_SAMPLE attempt=$attempt startLocal='$($sample.StartedAt.ToString("o"))' endLocal='$($sample.EndedAt.ToString("o"))' startUtc='$($sample.StartedAt.UtcDateTime.ToString("o"))' endUtc='$($sample.EndedAt.UtcDateTime.ToString("o"))' recoveryElapsedMs=$($RunStopwatch.ElapsedMilliseconds) mttDurationMs=$($sample.DurationMs) mttExitCode='$($sample.ExitCode)' csvLastWriteUtc='$($sample.CsvLastWriteUtc)' csvAgeMs='$($sample.CsvAgeMs)' csvCurrent='$($sample.CsvCreatedDuringCapture)' rowCount=$($sample.RowCount) rows='$allTopologySummary'"
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

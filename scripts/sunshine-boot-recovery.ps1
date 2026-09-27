# Restore the normal physical-monitor layout at Windows logon.
# Safety net for crashes, power loss, forced reset, or a missed Sunshine Undo.
# Run elevated from Task Scheduler.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$LocalConfig = "C:\SunshineTools\multimonitortool\local.cfg"
$LogRoot = "C:\SunshineLogs"
$TimeoutSeconds = 30
$StartupDelay = 10
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

function Get-ActiveScreenCount {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return [System.Windows.Forms.Screen]::AllScreens.Count
    } catch {
        Write-Log "Screen enumeration failed: $($_.Exception.Message)"
        return 0
    }
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
    $screenCount = 0
    do {
        Start-Sleep -Seconds 1
        $screenCount = Get-ActiveScreenCount
        Write-Log "Active Windows screens=$screenCount"
        if ($screenCount -ge 2) { break }
    } while ((Get-Date) -lt $deadline)

    Save-MonitorSnapshot "02-after-local-restore"

    if ($screenCount -lt 2) {
        Write-Log "FAIL_SAFE: physical monitors did not restore. Leaving VDD state unchanged."
        throw "Boot recovery could not verify two active physical displays."
    }

    $device = Get-MttVdd
    if ($device -and $device.Status -in @("OK", "Started", "Degraded")) {
        Write-Log "Two active displays verified; disabling VDD."
        $device | Disable-PnpDevice -Confirm:$false
        Start-Sleep -Seconds 1
    } else {
        Write-Log "VDD is already disabled or unavailable."
    }

    Save-MonitorSnapshot "03-final"
    Write-Log "BOOT_RECOVERY_SUCCESS activeScreens=$screenCount"
    exit 0
} catch {
    Write-Log "BOOT_RECOVERY_FAILED error='$($_.Exception.Message)'"
    try { Save-MonitorSnapshot "99-failure" } catch {}
    exit 1
}

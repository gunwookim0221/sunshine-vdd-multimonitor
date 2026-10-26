# Sunshine watchdog
# Purpose:
# - Keep Sunshine available without polling every few minutes.
# - Run on Service Control Manager crash events and as a light hourly safety check.
# - Restart Sunshine only when its Windows service/process/control ports are unhealthy.
# - Do NOT change monitor topology or VDD state.
#
# Run elevated (the registration script installs scheduled tasks as SYSTEM).

param(
    [int]$BasePort = 47989,
    [int]$CooldownMinutes = 5
)

$ErrorActionPreference = "Stop"

$LogRoot = "C:\SunshineLogs\watchdog"
$LogFile = Join-Path $LogRoot "sunshine-watchdog.log"
$LastRestartFile = Join-Path $LogRoot "last-restart.txt"
$WebPort = $BasePort + 1

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-SunshineService {
    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'sunshine' -or
            $_.DisplayName -match 'Sunshine' -or
            $_.PathName -match 'sunshinesvc|sunshine'
        }

    return $services | Select-Object -First 1
}

function Test-TcpPort {
    param([int]$Port)

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(1500, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($client) { $client.Close() }
    }
}

function Test-RestartCooldown {
    if (-not (Test-Path $LastRestartFile)) { return $false }

    try {
        $last = [datetime]::Parse((Get-Content $LastRestartFile -Raw).Trim())
        return ((Get-Date) - $last).TotalMinutes -lt $CooldownMinutes
    }
    catch {
        return $false
    }
}

function Wait-ForSunshineHealthy {
    param([string]$ServiceName, [int]$TimeoutSeconds = 25)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 1

        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $proc = Get-Process sunshine -ErrorAction SilentlyContinue | Select-Object -First 1
        $httpOk = Test-TcpPort -Port $BasePort
        $webOk = Test-TcpPort -Port $WebPort

        if ($svc.Status -eq 'Running' -and $proc -and $httpOk -and $webOk) {
            return $true
        }
    } while ((Get-Date) -lt $deadline)

    return $false
}

try {
    $svcInfo = Get-SunshineService
    if (-not $svcInfo) {
        Write-Log "CHECK_FAILED Sunshine Windows service was not found. No action taken."
        exit 2
    }

    $serviceName = [string]$svcInfo.Name
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $proc = Get-Process sunshine -ErrorAction SilentlyContinue | Select-Object -First 1
    $httpOk = Test-TcpPort -Port $BasePort
    $webOk = Test-TcpPort -Port $WebPort

    Write-Log "CHECK service='$serviceName' status='$($svc.Status)' process=$([bool]$proc) tcp$BasePort=$httpOk tcp$WebPort=$webOk"

    if ($svc.Status -eq 'Running' -and $proc -and $httpOk -and $webOk) {
        Write-Log "HEALTHY no action required."
        exit 0
    }

    if (Test-RestartCooldown) {
        Write-Log "UNHEALTHY but restart cooldown (${CooldownMinutes}m) is active; skipping to avoid a restart loop."
        exit 3
    }

    Write-Log "UNHEALTHY restarting Sunshine service."
    (Get-Date).ToString('o') | Set-Content -Path $LastRestartFile -Encoding ASCII

    try {
        Restart-Service -Name $serviceName -Force -ErrorAction Stop
    }
    catch {
        Write-Log "Restart-Service failed: $($_.Exception.Message). Trying Stop/Start."
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service -Name $serviceName -ErrorAction Stop
    }

    if (Wait-ForSunshineHealthy -ServiceName $serviceName) {
        Write-Log "RECOVERY_SUCCESS service/process/control ports are healthy."
        exit 0
    }

    $finalSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $finalProc = Get-Process sunshine -ErrorAction SilentlyContinue | Select-Object -First 1
    $finalHttp = Test-TcpPort -Port $BasePort
    $finalWeb = Test-TcpPort -Port $WebPort
    Write-Log "RECOVERY_FAILED status='$($finalSvc.Status)' process=$([bool]$finalProc) tcp$BasePort=$finalHttp tcp$WebPort=$finalWeb"
    exit 1
}
catch {
    Write-Log "WATCHDOG_ERROR $($_.Exception.Message)"
    exit 1
}

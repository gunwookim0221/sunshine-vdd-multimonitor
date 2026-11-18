# Sunshine Watchdog

[한국어](sunshine-watchdog.ko.md)

This watchdog is intended for cases where Moonlight shows the host as grey/offline even though the Windows PC itself is still powered on.

## Design

The watchdog does not change monitor topology or VDD state. It only checks Sunshine health.

Recovery-authority checks:

- Sunshine Windows service exists and is `Running`
- `sunshine.exe` process exists
- default Sunshine HTTP port `47989/TCP` is reachable on localhost
- default Web UI port `47990/TCP` is reachable on localhost

Additional diagnostic-only evidence:

- actual LISTEN addresses and owning PID for Sunshine-related ports
- Windows network profiles/categories and IPv4 connectivity
- non-loopback, non-APIPA IPv4 addresses
- Tailscale adapter presence and status

Sunshine's default Web UI is `https://localhost:47990`, with default HTTP/Web ports 47989/47990.

## Trigger strategy

`register-sunshine-watchdog.ps1` installs two scheduled tasks:

1. `Sunshine Watchdog - Crash Event`
   - runs on Windows Service Control Manager events 7031/7034
   - does not hard-code the Sunshine service name in the event filter
   - if another service crashes, the watchdog runs but exits immediately when Sunshine is healthy

2. `Sunshine Watchdog - Hourly`
   - runs once per hour as a low-frequency fallback
   - catches hangs where the service still appears Running but the process or local ports are unhealthy

## Recovery

When Sunshine is unhealthy, the watchdog restarts its Windows service and waits up to 25 seconds for all of these conditions:

```text
service Running
sunshine.exe present
47989/TCP listening
47990/TCP listening
```

If they recover, `RECOVERY_SUCCESS` is logged.

Network evidence is written as `NET_DIAG_*` lines and **does not change restart authority**. For example, a down Tailscale adapter or a Public Ethernet profile alone will not restart Sunshine when service/process/localhost ports remain healthy.

A five-minute restart cooldown prevents a crash loop from causing repeated restarts.

## Install

Copy:

```text
C:\SunshineScripts\sunshine-watchdog.ps1
C:\SunshineScripts\register-sunshine-watchdog.ps1
```

From elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1"
```

Verify:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "Sunshine Watchdog*"
```

Manual health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-watchdog.ps1"
```

A healthy host logs `HEALTHY no action required.`

## Logs

```text
C:\SunshineLogs\watchdog\sunshine-watchdog.log
C:\SunshineLogs\watchdog\last-restart.txt
```

When Moonlight appears grey/offline, inspect `CHECK`, `NET_DIAG_LISTENERS`, `NET_DIAG_PROFILES`, `NET_DIAG_IPV4`, and `NET_DIAG_TAILSCALE` around the same time. This helps distinguish a healthy local Sunshine instance from a broken external network path.

Also check `RECOVERY_SUCCESS`, `RECOVERY_FAILED`, and `WATCHDOG_ERROR` for Sunshine-side failures.

## Remove

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1" -Remove
```

## Limitations

- Restart authority remains limited to Sunshine service/process/localhost-port health.
- A broken Tailscale/Wi-Fi/routing/firewall path can be recorded as diagnostic evidence, but it does not trigger a Sunshine restart.
- Listener/profile/IPv4/Tailscale evidence is diagnostic-only and does not change behavior or authority.
- If Sunshine uses a non-default base port, configure the scheduled task to call `sunshine-watchdog.ps1 -BasePort <port>`.
- VDD/physical-monitor recovery remains the responsibility of `sunshine-boot-recovery.ps1` and the remote on/off scripts.

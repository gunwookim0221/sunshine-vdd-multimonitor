# Sunshine + VDD Multi-Monitor Automation

[한국어](README.ko.md)

Automate Sunshine/Moonlight on Windows when the host has two or more physical monitors but the remote client should see only a dedicated virtual display.

## What this solves

Typical multi-monitor Sunshine setups can become awkward on a phone: the streamed desktop is too wide, apps open on the wrong physical monitor, and disabling a virtual display at the wrong time can leave Windows with no visible output.

The repository also includes a separate Sunshine watchdog for cases where the PC is still running but Sunshine becomes unhealthy and Moonlight shows the host as grey/offline.

This repository documents a working setup built around:

- Sunshine
- Moonlight
- Virtual Display Driver (VDD by MTT)
- NirSoft MultiMonitorTool
- PowerShell session/recovery/watchdog scripts

## Official downloads

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

The final design is:

```text
Normal local use
  Physical monitor 1 + 2 ON
  VDD OFF

Moonlight session start
  Enable VDD
  Discover VDD dynamically
  Enable/make primary using a stable monitor identifier
  Resolve physical-monitor identifiers before changing topology
  Disable all physical monitors in one call
  Verify VDD is the only active display and is Primary

Moonlight session end
  Restore local.cfg
  Verify physical displays are back
  Disable VDD

Sunshine availability protection
  React to service crash events
  Run one lightweight hourly fallback check
  Restart only Sunshine when unhealthy
```

## Important design choices

- Never hard-code `DISPLAY5`, `DISPLAY7`, etc.; Windows can renumber DISPLAY names during topology changes.
- v4.1 chooses stable monitor command identifiers in this order: Serial Number -> full Monitor ID -> Short Monitor ID.
- Resolve all physical-monitor identifiers before changing topology, then disable them in one MultiMonitorTool `/disable` invocation.
- Verify exactly one active display remains, the VDD, and it is Primary. Roll back to `local.cfg` on verification failure.
- Leave Sunshine `output_name` / Display Device ID blank and disable Sunshine Display Device Configuration.
- Do not rely on Sunshine `ensure_only_display` for this workflow.
- Always restore `local.cfg` before disabling VDD.
- The Sunshine watchdog never changes monitor topology or VDD state; it only checks Sunshine service/process/local-port health.
- The watchdog uses a restart cooldown and combines crash-event triggers with a lightweight hourly fallback check.

## Files

- `scripts/sunshine-remote-on.ps1` — session start (v4.1)
- `scripts/sunshine-remote-off.ps1` — session end / restore
- `scripts/sunshine-boot-recovery.ps1` — logon-time monitor recovery safety net
- `scripts/register-boot-recovery.ps1` — register/remove monitor recovery task
- `scripts/collect-display-diagnostics.ps1` — capture display diagnostics
- `scripts/sunshine-watchdog.ps1` — Sunshine health check / auto restart
- `scripts/register-sunshine-watchdog.ps1` — register crash-event + hourly watchdog tasks
- `docs/sunshine-watchdog.md` — watchdog setup and limitations
- `docs/safety-and-diagnostics.md` — recovery and diagnostic logging
- `docs/setup.md` — full setup guide
- `docs/troubleshooting.md` — failure modes and fixes
- `docs/recovery.md` — black-screen recovery procedure
- `docs/lessons-learned.md` — what failed and why
- `docs/rca-2026-10-04-display-renumbering.md` — real incident RCA

## Requirements

- Windows 11
- Sunshine
- Moonlight
- VDD by MTT / Virtual Display Driver
- NirSoft MultiMonitorTool

Recommended paths:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

## Quick setup

1. Install the components.
2. Put the PowerShell scripts in `C:\SunshineScripts\`.
3. Save a clean `local.cfg` with VDD off and the physical monitors in their normal layout.
4. Leave Sunshine Display Device ID / `output_name` blank and disable Display Device Configuration.
5. Configure one elevated Prep Command pair:

```text
Do:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

Undo:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

6. Register the logon monitor-recovery safety net.
7. Install the Sunshine watchdog for grey/offline Moonlight host cases.

## Sunshine watchdog installation and verification

Place these two scripts in `C:\SunshineScripts\` and run the registration script from an elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1"
```

A successful registration creates:

```text
Sunshine Watchdog - Crash Event
Sunshine Watchdog - Hourly
```

Verify the tasks:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "Sunshine Watchdog*"
```

Both tasks should report `Ready`.

Run one manual watchdog health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-watchdog.ps1"
```

Healthy example:

```text
CHECK service='SunshineService' status='Running' process=True tcp47989=True tcp47990=True
HEALTHY no action required.
```

Check the log:

```powershell
Get-Content "C:\SunshineLogs\watchdog\sunshine-watchdog.log" -Tail 20
```

The watchdog behavior is:

- reacts immediately to Service Control Manager 7031/7034 unexpected-termination events
- performs one lightweight hourly fallback check for hang/offline cases that produce no crash event
- restarts Sunshine only when its service/process/local ports are unhealthy
- never changes VDD or physical-monitor topology
- uses a restart cooldown to avoid restart loops

See [Setup Guide](docs/setup.md) and [Sunshine Watchdog](docs/sunshine-watchdog.md).

## When something fails

If Moonlight shows the host as grey/offline, preferably inspect the watchdog log before rebooting:

```powershell
Get-Content "C:\SunshineLogs\watchdog\sunshine-watchdog.log" -Tail 50
```

If the physical monitors are missing or display switching looks wrong, collect diagnostics:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

For emergency physical-monitor recovery, restore `local.cfg` first and verify visible physical output before disabling VDD.

## Safety note

This setup intentionally disables physical displays during a remote session. Keep the recovery procedure available before experimenting. See [docs/recovery.md](docs/recovery.md).

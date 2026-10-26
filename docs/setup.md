# Setup Guide

[한국어](setup.ko.md)

## 1. Install the components

Download from the official project pages:

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

Recommended paths:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

Copy the repository scripts to:

```text
C:\SunshineScripts\sunshine-remote-on.ps1
C:\SunshineScripts\sunshine-remote-off.ps1
C:\SunshineScripts\sunshine-boot-recovery.ps1
C:\SunshineScripts\register-boot-recovery.ps1
C:\SunshineScripts\collect-display-diagnostics.ps1
C:\SunshineScripts\sunshine-watchdog.ps1
C:\SunshineScripts\register-sunshine-watchdog.ps1
```

## 2. Create the local monitor baseline

Disable VDD, enable only the physical monitors, and verify normal position/primary/resolution/orientation/scaling.

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

Do not commit `local.cfg`; it is machine-specific.

## 3. Configure Sunshine

In Sunshine Audio/Video settings:

- Display Device ID / `output_name`: leave blank
- Display Device Configuration: disabled

Use one elevated Prep Command pair:

```text
Do:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

Undo:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

## 4. How the v4.1 start script works

v4.1 does not treat `\\.\DISPLAY1`-style names as persistent identities.

1. Enable VDD PnP device
2. Discover VDD from MultiMonitorTool CSV
3. Choose stable identifier: Serial Number -> full Monitor ID -> Short Monitor ID
4. Enable/make VDD Primary
5. Resolve all physical monitor identifiers before topology changes
6. Disable all physical monitors in one `/disable` call
7. Verify exactly one active display remains and it is VDD + Primary
8. Attempt `local.cfg` rollback if verification fails

## 5. Test manually before enabling automation

From elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

Expected log pattern:

```text
SESSION_START_V41
Disabling physical displays in one call using stable identifiers: ...
VERIFY activeCount=1 activeVddCount=1
SESSION_START_SUCCESS
```

Then restore:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

Verify both physical displays return and VDD is disabled.

## 6. Final session flow

```text
Moonlight connects
  -> VDD ON
  -> stable VDD identifier
  -> VDD Primary
  -> disable physical monitors in one call
  -> verify VDD-only topology
  -> Sunshine capture

Moonlight disconnects
  -> local.cfg restored
  -> physical displays verified
  -> VDD disabled
```

## 7. Logon recovery safety net

Register the logon recovery task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"
```

Verify:

```powershell
Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"
```

## 8. Logs and diagnostics

Session-start, session-end, and recovery logs are stored under `C:\SunshineLogs\`.

Before reboot/recovery when possible:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

## 9. Sunshine Watchdog

For cases where Moonlight shows the PC as grey/offline while Windows itself is still alive, register the dedicated Sunshine watchdog:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1"
```

It creates:

```text
Sunshine Watchdog - Crash Event
Sunshine Watchdog - Hourly
```

Behavior:

- reacts immediately to Service Control Manager 7031/7034 events
- performs one lightweight hourly fallback health check
- checks Sunshine service, `sunshine.exe`, and default TCP ports 47989/47990
- restarts only Sunshine when unhealthy
- never changes VDD or monitor topology
- uses a five-minute restart cooldown to avoid restart loops

Manual check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-watchdog.ps1"
```

Log:

```text
C:\SunshineLogs\watchdog\sunshine-watchdog.log
```

Remove:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1" -Remove
```

See [Sunshine Watchdog](sunshine-watchdog.md) for details.

## Notes

- Tested topology: two physical monitors plus one temporary VDD.
- DISPLAY numbering may change legitimately.
- The watchdog owns Sunshine availability only; monitor recovery remains the responsibility of boot recovery and remote on/off scripts.

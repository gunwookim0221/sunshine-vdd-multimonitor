# Setup Guide

[한국어](setup.ko.md)

## 1. Install the components

Download from the official project pages:

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

Prefer official project pages rather than third-party mirrors.

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
```

## 2. Create the local monitor baseline

Before saving the baseline:

1. Disable VDD.
2. Make sure only the physical monitors are active.
3. Arrange them exactly as you normally use them.
4. Set the correct primary monitor.
5. Verify resolution, orientation, scaling, and position.

Then save:

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

Do not commit `local.cfg`; it is machine-specific.

## 3. Configure Sunshine

In Sunshine Audio/Video settings:

- Display Device ID / `output_name`: leave blank
- Display Device Configuration: disabled

In Sunshine Prep Commands, add one elevated command pair:

```text
Do:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

Undo:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

Enable the elevated/admin option.

## 4. How the v4.1 start script works

v4.1 does not treat `\\.\DISPLAY1`-style names as persistent identities for topology-changing commands. Windows can renumber DISPLAY names immediately after the first monitor is disabled.

The start sequence is:

1. Enable the VDD PnP device.
2. Find VDD from the MultiMonitorTool CSV.
3. Choose command identifiers in this order: Serial Number -> full Monitor ID -> Short Monitor ID.
4. Enable and make VDD Primary using the stable identifier.
5. Resolve every active physical-monitor identifier before changing topology.
6. Disable all physical monitors in **one MultiMonitorTool `/disable` invocation**.
7. Re-read the topology and verify exactly one `Active=Yes` display remains, and it is the VDD and Primary.
8. If verification fails, immediately attempt `local.cfg` rollback.

MultiMonitorTool supports Monitor ID, Short Monitor ID, and monitor serial number as command-line monitor identifiers. See the official MultiMonitorTool documentation: https://www.nirsoft.net/utils/multi_monitor_tool.html

## 5. Test manually before enabling automation

Run from elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

Expected log pattern:

```text
SESSION_START_V41
VDD ... stableId=...
Disabling physical displays in one call using stable identifiers: ...
VERIFY activeCount=1 activeVddCount=1
SESSION_START_SUCCESS
```

The actual topology should also show only the VDD active.

Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

Expected result:

- `local.cfg` restores the physical monitor layout.
- At least two active physical displays are verified.
- VDD is disabled only after that verification.

Only after this round-trip succeeds should the scripts be connected to Sunshine Prep Commands.

## 6. Final session flow

```text
Moonlight connects
  -> VDD ON
  -> choose stable VDD identifier
  -> VDD Primary
  -> resolve physical stable identifiers
  -> disable physical monitors in one call
  -> verify VDD is the only active display
  -> Sunshine capture

Moonlight disconnects
  -> local.cfg restored
  -> physical displays verified
  -> VDD disabled
```

## 7. Logon recovery safety net

Register a scheduled task so the normal physical-monitor layout is restored at user logon even if Sunshine Undo was missed because of a crash or forced reboot.

From elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"
```

Verify:

```powershell
Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"
```

The recovery script waits 10 seconds after logon, loads `local.cfg`, verifies at least two active Windows screens, and only then disables VDD.

## 8. Logs and diagnostics

Session-start, session-end, and recovery logs are stored under `C:\SunshineLogs\`.

If a failure occurs, preferably before reboot/recovery:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

See:

- [Safety Net and Diagnostics](safety-and-diagnostics.md)
- [2026-10-04 DISPLAY renumbering RCA](rca-2026-10-04-display-renumbering.md)

## Notes

- The tested topology is two physical monitors plus one temporary VDD.
- `DISPLAY5`, `DISPLAY7`, `DISPLAY8`, etc. may legitimately change.
- Stable identifiers and post-switch topology verification matter more than DISPLAY numbering.
- If your topology is materially different, test manually before enabling Prep Commands.

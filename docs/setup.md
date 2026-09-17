# Setup Guide

[한국어](setup.ko.md)

## 1. Install the components

Download from the official project pages:

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

Prefer official project pages rather than third-party mirrors.

Install or extract the components as appropriate.

Recommended paths:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

Copy the repository scripts to:

```text
C:\SunshineScripts\sunshine-remote-on.ps1
C:\SunshineScripts\sunshine-remote-off.ps1
```

## 2. Create the local monitor baseline

Before saving the baseline:

1. Disable VDD.
2. Make sure only the physical monitors are active.
3. Arrange them exactly as you normally use them.
4. Set the correct primary monitor.
5. Verify resolution, orientation, scaling, and position.

Then save the configuration:

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

Do not commit `local.cfg`; it is machine-specific.

## 3. Configure Sunshine

In Sunshine Audio/Video settings:

- Display Device ID / `output_name`: leave blank
- Display Device Configuration: disabled

Why: the start script makes the VDD the Windows primary display, so Sunshine can simply capture the active primary display. A fixed GUID is fragile because Windows can recreate/renumber the VDD.

In Sunshine Prep Commands, add one elevated command pair:

```text
Do:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

Undo:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

Enable the elevated/admin option for the command pair.

## 4. Test manually before enabling automation

Run the start script from an elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

Expected result:

- VDD is enabled.
- The VDD display is found dynamically.
- The VDD becomes primary.
- Physical displays are disabled.

Then run the restore script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

Expected result:

- `local.cfg` restores the physical monitor layout.
- At least two displays are detected again.
- VDD is disabled only after the physical monitors have returned.

Only after this round-trip succeeds should the scripts be connected to Sunshine Prep Commands.

## 5. Final session flow

```text
Moonlight connects
  -> Sunshine Do command
  -> VDD enabled
  -> VDD detected dynamically
  -> VDD primary
  -> physical monitors disabled
  -> Sunshine captures the current primary display

Moonlight disconnects
  -> Sunshine Undo command
  -> local.cfg restored
  -> physical displays verified
  -> VDD disabled
```

## Notes

- The VDD may appear as `DISPLAY5`, `DISPLAY7`, `DISPLAY8`, etc. The script intentionally does not assume a fixed number.
- The setup was developed for a host with two physical monitors plus one temporary VDD. The start script disables every display other than the detected VDD.
- If your topology is materially different, test manually before enabling Prep Commands.

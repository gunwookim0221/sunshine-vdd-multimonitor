# Sunshine + VDD Multi-Monitor Automation

[한국어](README.ko.md)

Automate Sunshine/Moonlight on Windows when the host has two or more physical monitors but the remote client should see only a dedicated virtual display.

## What this solves

Typical multi-monitor Sunshine setups can become awkward on a phone: the streamed desktop is too wide, apps open on the wrong physical monitor, and disabling a virtual display at the wrong time can leave Windows with no visible output.

This repository documents a working setup built around:

- Sunshine
- Moonlight
- Virtual Display Driver (VDD by MTT)
- NirSoft MultiMonitorTool
- PowerShell prep/undo scripts

## Official downloads

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

Prefer the official project pages above rather than third-party mirrors.

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
  Restore the saved physical-monitor layout from local.cfg
  Verify physical displays are back
  Disable VDD
```

## Important design choices

- Do not hard-code `DISPLAY5`, `DISPLAY7`, etc. Windows can renumber DISPLAY names during topology changes, not only across reboots.
- v4.1 chooses a stable command target in this order: Serial Number -> full Monitor ID -> Short Monitor ID.
- Resolve all physical-monitor identifiers before changing topology, then disable them in **one MultiMonitorTool `/disable` invocation**.
- Verify the post-condition: exactly one active display, the VDD, and it is Primary. If verification fails, attempt `local.cfg` rollback immediately.
- Leave Sunshine `output_name` / Display Device ID blank so Sunshine captures the current primary display.
- Set Sunshine Display Device Configuration to disabled. The PowerShell scripts own the monitor topology.
- Do not rely on Sunshine `ensure_only_display` for this workflow.
- Always restore `local.cfg` before disabling VDD. Reversing that order can leave you with zero visible displays.

## Files

- `scripts/sunshine-remote-on.ps1` — session start (v4.1)
- `scripts/sunshine-remote-off.ps1` — session end / restore
- `scripts/sunshine-boot-recovery.ps1` — logon-time physical-monitor recovery safety net
- `scripts/register-boot-recovery.ps1` — register/remove the recovery scheduled task
- `scripts/collect-display-diagnostics.ps1` — capture state during a failure
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

Recommended paths used by the scripts:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

## Quick setup

1. Download and install the components from the official links above.
2. Put the PowerShell scripts in `C:\SunshineScripts\`.
3. With only the physical monitors in the exact normal arrangement, save:

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

4. In Sunshine:
   - Display Device ID / `output_name`: **blank**
   - Display Device Configuration: **disabled**
   - Prep command (elevated):

```text
Do:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

Undo:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

5. Test the scripts manually before connecting them to Sunshine.
6. For crash/forced-reboot protection, register the logon recovery task described in [Safety Net and Diagnostics](docs/safety-and-diagnostics.md).

The v4.1 scripts automatically write transition logs under `C:\SunshineLogs\`.

See [docs/setup.md](docs/setup.md) for the full procedure.

## Safety note

This setup intentionally disables physical displays during a remote session. Keep the recovery procedure available before experimenting. See [docs/recovery.md](docs/recovery.md).

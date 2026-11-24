# Safety Net and Diagnostics

[한국어](safety-and-diagnostics.ko.md)

This covers failures where physical monitors are not restored after a crash, forced reboot, power loss, or a missed Sunshine Undo command.

## 1. v4 logging

The session start/end scripts create timestamped folders under `C:\SunshineLogs\` and save:

- `operations.log`: step-by-step execution and success/failure markers
- `*.csv`: MultiMonitorTool topology snapshots
- `*-pnp.txt`: Display-class PnP state
- OFF recovery boundary snapshots `*-monitor-pnp*.txt`: all Monitor-class devices and currently present (`-PresentOnly`) devices
- OFF recovery boundary snapshots `*-present-pnp.txt`: currently enumerated Display adapters, including the NVIDIA GPU and VDD
- OFF recovery boundary snapshots `*-evidence.json`: MTT rows, PnP summaries, per-query UTC times, and CSV currentness metadata

The OFF script writes a `TOPOLOGY_SAMPLE` row for every recovery verification. It records the MTT CSV read start/end, CSV write time and age, process exit code, and each display row's membership and `Active` value. Full/current PnP lists are saved at the `01-before-off`, `02-after-local-restore`, `03-final`, and `99-failure` boundaries.

Keep these signals distinct:

- A missing Samsung row in the MTT CSV means Samsung was absent from MTT's current list at that sample. It does not establish that its PnP device was absent.
- `*-monitor-pnp-present.txt` and `samsungPresentOnlyCount` in the evidence use `Get-PnpDevice -Class Monitor -PresentOnly`. A zero count means no matching Samsung Monitor PnP device was currently enumerated when that query ran.
- If Samsung appears only in the full Monitor list and not in `PresentOnly`, the capture distinguishes a retained non-current device record from current enumeration.
- The Display class shows GPU/display-adapter and VDD state. It cannot establish monitor PnP presence or active display topology by itself.
- Queries run sequentially. UTC timestamps and MTT CSV age show the sampling window and whether the CSV may be stale; they are not an atomic snapshot of all Windows state.

Useful interpretations:

- `SESSION_START_SUCCESS` without a corresponding `SESSION_END_START` suggests Sunshine Undo did not run or the session ended abnormally.
- `FAIL_SAFE` after `SESSION_END_START` means `local.cfg` restore was attempted but two active physical displays could not be verified.
- `SESSION_END_SUCCESS` means the end script completed; investigate later Windows/GPU/PnP topology changes.

## 2. Automatic logon recovery

`scripts/sunshine-boot-recovery.ps1` waits 10 seconds after user logon, then:

1. Saves the current state and recent Windows display-related events
2. Loads `local.cfg`
3. Verifies at least two active Windows screens
4. Disables VDD only after verification
5. Leaves VDD unchanged if verification fails

Copy:

    C:\SunshineScripts\sunshine-boot-recovery.ps1
    C:\SunshineScripts\register-boot-recovery.ps1

Register from elevated PowerShell:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"

Verify:

    Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"

Remove:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1" -Remove

> This runs at user logon. It does not repair a BIOS/boot-logo stage or a pre-logon display failure.

## 3. One-shot diagnostics

If possible, before rebooting or restoring the layout:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"

The bundle is written to `C:\SunshineLogs\<timestamp>-diagnostics\` and includes MultiMonitorTool topology, Display PnP state, active Windows screens, and the last 8 hours of Display/Kernel-PnP/nvlddmkm/Kernel-Power System events.

## 4. Emergency manual restore

Restore the known-good physical layout directly:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"

After the physical displays are visibly back:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"

Always preserve the order: **verify physical displays first, then disable VDD**.

# Local input takeover

This optional watcher lets a person at the host reclaim the PC while a Moonlight/VDD-only session is active.

It does not replace or modify the existing v4.3 topology contract. It runs as a separate interactive-user scheduled task.

## Detection model

- Learn Raw Input device paths only while VDD is inactive and at least one physical monitor is active.
- Persist learned paths in `C:\SunshineLogs\local-takeover\known-local-devices.json`.
- During VDD-only mode, only learned device paths can trigger takeover.
- Unknown devices and input without a Raw Input device handle are logged and ignored.
- Keyboard key-down and mouse buttons trigger immediately.
- Mouse movement triggers after cumulative raw delta reaches 160 within 1 second.

This avoids relying on generic last-input timestamps, because Sunshine keyboard/mouse delivery on Windows can use either injected input or a virtual HID path depending on the installed input backend.

## Takeover sequence

1. Log trigger reason and device path.
2. Stop the Sunshine Windows service to disconnect the remote stream.
3. Check whether Sunshine's configured Undo already restored physical monitors.
4. If needed, run the existing `sunshine-remote-off.ps1`.
5. Verify at least two active physical monitors using fresh MultiMonitorTool topology.
6. Start Sunshine again.

If physical recovery is not verified, the existing OFF fail-safe is preserved; the watcher does not forcibly remove VDD.

## Install

Place:

```text
C:\SunshineScripts\sunshine-local-takeover.ps1
C:\SunshineScripts\register-local-takeover.ps1
```

Then run from elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-local-takeover.ps1"
```

Verify:

```powershell
Get-ScheduledTask -TaskName "Sunshine Local Takeover"
Get-Content "C:\SunshineLogs\local-takeover\local-takeover.log" -Tail 80
```

After installation, use the physical keyboard and mouse once while the normal local monitor layout is active. The log should show `KNOWN_DEVICE_LEARNED` for those devices.

## Remove

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-local-takeover.ps1" -Remove
```

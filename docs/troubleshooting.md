# Troubleshooting

[한국어](troubleshooting.ko.md)

## A physical monitor remains active or the phone looks like it has multiple screens

This was reproduced with pre-v4.1 logic. Disabling monitors sequentially by names such as `\\.\DISPLAY1` and `\\.\DISPLAY2` is unsafe because Windows can renumber display names immediately after the first topology change. The second command may then target a different monitor than originally intended.

v4.1 fixes this by:

- using Serial Number / full Monitor ID / Short Monitor ID instead of DISPLAY numbering
- resolving all physical-monitor identifiers before changing topology
- disabling all physical monitors in one `/disable` invocation
- verifying that exactly one `Active=Yes` display remains, and that it is the VDD
- attempting `local.cfg` rollback if verification fails

Copy the latest `scripts/sunshine-remote-on.ps1` to `C:\SunshineScripts\sunshine-remote-on.ps1`.

Incident analysis: [2026-10-04 RCA](rca-2026-10-04-display-renumbering.md)

## Moonlight connects but all monitors remain active

Do not rely on Sunshine `ensure_only_display` for this workflow. The start script should make the VDD primary and disable all other displays itself.

Check that Sunshine Display Device Configuration is disabled and that only `sunshine-remote-on.ps1` is used as the Do command.

## Moonlight cannot connect after VDD is recreated

If Sunshine has a fixed Display Device ID / `output_name`, clear it. VDD recreation can change both display numbering and device identity. This setup expects Sunshine to capture the current primary display.

## VDD appears as DISPLAY5, then DISPLAY7 or DISPLAY8

This is expected. Do not hard-code the display number. The v4.1 start script discovers the VDD and then uses a stable monitor identifier for topology-changing commands.

## Apps keep opening on the invisible virtual monitor during normal PC use

The VDD is probably still enabled outside a remote session. The intended normal state is:

```text
Physical displays ON
VDD OFF
```

Run the restore script or disable the VDD device after restoring `local.cfg`.

## Physical monitors do not return after Moonlight disconnects

Run:

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /LoadConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

Then, only after the physical monitors are visible again, disable VDD:

```powershell
Get-PnpDevice -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -like "*Virtual Display*" } |
  Disable-PnpDevice -Confirm:$false
```

If `local.cfg` restores the wrong primary monitor or wrong geometry, recreate it while VDD is disabled and the physical monitors are arranged exactly as desired.

## Capture diagnostics before rebooting or recovering

If possible, run this before rebooting or restoring the layout:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

The bundle is saved under `C:\SunshineLogs\<timestamp>-diagnostics\` and includes current topology, PnP state, and recent Display/Kernel-PnP/NVIDIA/Kernel-Power events.

## `Get-PnpDevice -HardwareID` fails

Some Windows PowerShell versions do not provide a `-HardwareID` parameter for `Get-PnpDevice`. The repository scripts avoid that parameter and identify the device using `InstanceId` and `FriendlyName`.

## VDD Control opens a GUI for `--help`, `-h`, or `/?`

The tested VDD Control build behaves as a GUI application rather than a normal CLI. This setup therefore controls the PnP device with PowerShell and the monitor topology with MultiMonitorTool.

## Sunshine encoder log shows AV1 errors on an RTX 3080

That is unrelated to monitor switching. RTX 3080 can use H.264/HEVC NVENC but does not provide AV1 encoding. If Sunshine successfully reports H.264/HEVC encoders, the monitor automation can still work normally.

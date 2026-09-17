# Lessons Learned

[한국어](lessons-learned.ko.md)

This setup took several iterations. The failures were useful because they exposed which component should own each part of the display lifecycle.

## 1. A fixed Sunshine display GUID is fragile

Initially Sunshine was configured with a specific VDD device ID. After VDD disable/enable cycles, Windows recreated or renumbered the virtual display and Moonlight could no longer connect reliably.

Final approach: leave Sunshine `output_name` blank and make the VDD the Windows primary display before Sunshine starts capture.

## 2. DISPLAY numbers are not stable

The same virtual monitor appeared as DISPLAY5, later DISPLAY7, and later DISPLAY8.

Final approach: discover the VDD dynamically from MultiMonitorTool output. Never assume a fixed DISPLAY number.

## 3. Sunshine `ensure_only_display` was not sufficient in this topology

The option was expected to leave only the selected VDD active, but in the tested setup the physical displays could remain active when the VDD was created as part of the session-start flow.

Final approach: disable Sunshine display-topology management and let the PowerShell start script explicitly make the VDD primary and disable every other display.

## 4. Enabling the VDD device is not the same as attaching the VDD monitor

At one point the PnP device was enabled but the virtual display was still shown as disconnected in Windows.

Final approach: after enabling the VDD device, use MultiMonitorTool to enable the detected virtual monitor itself.

## 5. Disabling VDD before restoring physical displays is dangerous

When Windows remembered that the physical monitors were disconnected and VDD was then disabled, the machine reached a state where no normal Windows desktop was visible. BIOS/boot output still appeared, proving the hardware path was fine.

Final approach: restore `local.cfg` first, verify physical displays are back, and only then disable VDD.

## 6. `local.cfg` must be captured from a clean baseline

An early baseline was saved while the monitor arrangement/primary selection had already drifted, so restoring it brought the screens back with the wrong geometry and primary monitor.

Final approach: disable VDD, arrange the physical monitors exactly as desired, set primary/scaling/orientation correctly, then save `local.cfg` again.

## 7. VDD Control was not useful as a CLI in the tested build

`--help`, `-h`, and `/?` opened the GUI instead of returning normal CLI help.

Final approach: use PowerShell `Enable-PnpDevice` / `Disable-PnpDevice` for the driver and MultiMonitorTool for Windows monitor topology.

## 8. Separate responsibilities

The stable architecture is:

```text
Sunshine
  capture/stream only

PowerShell + VDD
  virtual display device lifecycle

MultiMonitorTool
  monitor enable/disable/primary/layout restore
```

Keeping those responsibilities separate reduced timing conflicts and made recovery predictable.

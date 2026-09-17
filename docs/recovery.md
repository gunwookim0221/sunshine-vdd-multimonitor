# Recovery Guide

[한국어](recovery.ko.md)

Use this if the physical monitors go black or Windows appears to have no visible output after monitor switching.

## First recovery attempt: restore `local.cfg`

Even if you cannot see the desktop, use `Win + R` and run:

```text
"C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /LoadConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

Wait several seconds.

## If the displays still do not return

Try Windows display extension:

```text
Win + R
DisplaySwitch.exe /extend
```

You can also reset the graphics driver with:

```text
Win + Ctrl + Shift + B
```

Then try `DisplaySwitch.exe /extend` again.

## If Windows login goes black but BIOS/boot graphics are visible

That usually means the hardware path is fine and the Windows display topology is broken.

Boot into Windows Recovery Environment and use Safe Mode:

1. Interrupt Windows startup several times to enter recovery.
2. Advanced options -> Troubleshoot -> Advanced options -> Startup Settings -> Restart.
3. Choose Safe Mode.
4. Open Device Manager.
5. Disable (do not necessarily uninstall) `Virtual Display Driver` / VDD by MTT.
6. Reboot normally.

After recovery, fix the Sunshine Prep Commands before reconnecting Moonlight.

## Critical rule

Never disable VDD first when the physical monitors are still disconnected in Windows.

Safe shutdown order:

```text
Load local.cfg
-> verify physical monitors are back
-> disable VDD
```

This ordering is the main protection against a zero-visible-display state.

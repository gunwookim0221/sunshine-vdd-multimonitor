# RCA: Physical monitor remained active during remote session (2026-10-04)

[한국어](rca-2026-10-04-display-renumbering.ko.md)

## Symptom

During a Moonlight session, the VDD should have been the only active display, but one physical monitor remained active. On the phone this looked like multiple screens were still present. The session did not complete a normal Undo path before reboot; the logon boot-recovery task later restored the normal local topology.

## Log evidence

The start log reported:

```text
VDD_DISPLAY=\\.\DISPLAY5
Disabling other displays: \\.\DISPLAY1, \\.\DISPLAY2
SESSION_START_SUCCESS
```

However, the post-switch MultiMonitorTool snapshot still showed the VDD and one physical monitor as `Active=Yes`.

Example stable identifiers seen before the switch:

```text
MSI MP242       Short Monitor ID: MSI30A1
Samsung monitor Short Monitor ID: SAM7053
VDD by MTT      Short Monitor ID: MTT1337
```

Names such as `DISPLAY1`, `DISPLAY2`, and `DISPLAY5` may be renumbered while Windows changes display topology. Monitor ID, Short Monitor ID, or serial number are more appropriate command targets.

## Root cause

The v4 start script disabled physical monitors **sequentially by `\\.\DISPLAYx` name**.

After the first `/disable`, Windows may immediately renumber the display topology. The second command can therefore target a different monitor than the `DISPLAYx` name referred to when the list was originally collected. That can leave one physical display active.

## v4.1 fix

1. Identify the VDD and physical monitors from the MultiMonitorTool CSV.
2. Choose a stable command identifier in this order: Serial Number -> full Monitor ID -> Short Monitor ID.
3. Resolve all physical-monitor identifiers **before changing topology**.
4. Pass all physical monitors in a **single `/disable` invocation**.
5. Verify the post-condition: exactly one `Active=Yes` display, and that display is the VDD and Primary.
6. If verification fails, immediately attempt `local.cfg` rollback and disable VDD only after at least two active physical screens are verified.

## Lessons

- Treat `DISPLAYx` as an ephemeral display name, not a persistent identity.
- For multi-monitor changes, resolve stable identifiers first and prefer a single topology-changing command.
- Do not declare success only because commands returned without an error; verify the final topology.
- The boot-recovery and diagnostic logs proved useful for real incident RCA.

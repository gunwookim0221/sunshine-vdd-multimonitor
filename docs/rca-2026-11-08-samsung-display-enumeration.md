# RCA 2026-11-08~09 — Samsung G9 missing display and recovery-verification issue

## Summary

On 2026-11-08 and 2026-11-09 the Samsung LC49G95T ultrawide repeatedly became unavailable while the MSI MP242 remained visible.

The observed facts are:

- In some failure captures, the Samsung row was **absent entirely** from the current MultiMonitorTool display list.
- At the same time, `Get-PnpDevice -Class Monitor` reported Samsung instances as `Unknown`.
- Applying `local.cfg` alone did not always restore the Samsung immediately.
- On 2026-11-09, power-cycling the monitor did not recover it, but after one Moonlight start/end cycle, the OFF path applied `local.cfg` and both MSI and Samsung were present as `Active=Yes`.
- Immediately afterward, the previous OFF script still received 1 from `[System.Windows.Forms.Screen]::AllScreens.Count` and **incorrectly treated a successful recovery as a failure**.

Two conclusions are therefore supported:

1. The Samsung did at times disappear from the current Windows/MultiMonitorTool display set.
2. The previous recovery verification based on WinForms `Screen.AllScreens.Count` had a stale-state false-negative bug.

**The original cause of the Samsung missing-display condition is not yet established.** Current evidence is insufficient to attribute it specifically to DP cable/port, monitor power/EDID/hot-plug behavior, NVIDIA/Windows display state, or prior Sunshine/VDD transitions.

## 2026-11-08 observations

Problem-time MultiMonitorTool CSV:

- MSI MP242: `Active=Yes`, `Primary=Yes`
- VDD by MTT: `Active=No`
- Samsung LC49G95T: **absent from the list**

Problem-time PnP:

- VDD by MTT: `OK`
- MSI MP242: `OK`
- Samsung LC49G95T: existing instances reported `Unknown`

At the time, this suggested a DP/EDID/hot-plug layer problem, but later recurrence does not justify treating that as a confirmed root cause.

## 2026-11-09 recurrence

The same symptom recurred.

Before recovery:

- Samsung PnP instances: `Unknown`
- applying `local.cfg` alone: no immediate Samsung recovery
- monitor power-cycle: no recovery

A Moonlight session was then started and ended once.

The OFF path's saved `02-after-local-restore.csv` showed:

- MSI MP242: `Active=Yes`
- Samsung LC49G95T: `Active=Yes`
- VDD: `Active=No`

So the **actual physical-monitor recovery succeeded**.

However, the previous OFF script logged:

```text
Active Windows screens=1
...
FAIL_SAFE
```

This did not match the actual MultiMonitorTool topology.

## Confirmed code bug

The old OFF and ON rollback verification used:

```powershell
[System.Windows.Forms.Screen]::AllScreens.Count
```

Immediately after topology changes this value can remain stale, producing a false negative even when two physical displays have already been restored.

### v4.2 fix

Both OFF and ON rollback now generate a fresh MultiMonitorTool CSV and directly require:

```text
Active=Yes
AND
non-VDD physical monitor
AND
count >= 2
```

Only after that condition is satisfied is physical recovery considered successful and VDD allowed to be disabled.

## Current assessment

**Confirmed:**

- the Samsung can temporarily disappear from the current display set
- WinForms screen-count recovery verification can produce a false negative

**Not yet confirmed:**

- the original cause of the Samsung missing-display condition
- whether DP cable/port or monitor hardware is responsible
- whether NVIDIA/Windows display state is responsible
- whether Sunshine/VDD transition is a prerequisite or contributing factor

The earlier statements that recovery occurred because of physical-link/power renegotiation, and that the incident was separate from Sunshine ON/OFF, are withdrawn.

## Data to capture on recurrence

Before recovery:

```powershell
Get-PnpDevice -Class Monitor |
    Format-Table Status, FriendlyName, InstanceId -AutoSize

& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /scomma "C:\SunshineLogs\current-monitors.csv"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

Then compare fresh MultiMonitorTool CSVs before and after `local.cfg` restoration or a Moonlight ON/OFF cycle.

## Safe recovery

Do not disable VDD first when physical monitors are missing.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"
```

Starting with v4.3, recovery success is judged from stable consecutive fresh MultiMonitorTool topology reads.


## 2026-11-10 recurrence — VDD topology convergence race identified

The 2026-11-10 logs showed that the Samsung did not simply start the day missing. It remained present initially and then failed to recover after repeated Moonlight/VDD transition failures.

A key observation was that ON verification reported activeCount=1, activeVddCount=0 while a snapshot taken moments later showed the VDD as Active=Yes and Primary=Yes. The topology was still changing between the verification read and the snapshot.

Several earlier failed attempts rolled back to two physical monitors successfully, but a later attempt reached ROLLBACK_VERIFY physicalActiveCount=1 / ROLLBACK_FAIL_SAFE, after which the Samsung remained absent from the current MultiMonitorTool set.

As of 2026-11-10, **starting rollback before the VDD transition has converged is considered a major contributing factor on the actual production path**. This is not claimed as the sole root cause of every Samsung non-enumeration event.

### v4.3 fix

- replace the single ON post-check with a convergence window of up to 15 seconds
- require VDD-only + Primary state for 3 consecutive fresh reads
- do not rollback until the convergence window actually fails
- remove WinForms screen count from boot recovery
- require 2+ active physical monitors for 2 consecutive fresh reads before disabling VDD
- log only bounded evidence markers: VERIFY_CONVERGENCE and BOOT_VERIFY

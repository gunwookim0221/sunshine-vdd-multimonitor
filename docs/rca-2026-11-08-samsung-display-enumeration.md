# RCA 2026-11-08 — Temporary Samsung G9 display enumeration failure

## Summary

On 2026-11-08 the Samsung LC49G95T ultrawide stopped appearing during local use while the MSI MP242 portrait monitor remained active.

The captured evidence did not show the Samsung simply remaining present with `Active=No`. Instead, the Samsung row was completely absent from the current MultiMonitorTool display list. At the same time, `Get-PnpDevice -Class Monitor` showed existing Samsung instances as `Unknown`.

Because of that, restoring `local.cfg` recovered the MSI monitor but could not immediately recover the Samsung. After the physical display link/power path was renegotiated, the current Samsung instance returned to `OK` and the normal topology was restored.

## Observed state

Problem-time MultiMonitorTool CSV:

- MSI MP242: `Active=Yes`, `Primary=Yes`
- VDD by MTT: `Active=No`
- Samsung LC49G95T: **absent from the list**

Problem-time PnP state:

- VDD by MTT: `OK`
- MSI MP242: `OK`
- Samsung LC49G95T: two existing instances reported `Unknown`

Recovered PnP state:

- MSI MP242: `OK`
- current Samsung LC49G95T instance: `OK`
- older Samsung instance: `Unknown`
- inactive VDD instance: `Unknown`

## Impact

- Ultrawide output unavailable
- Powering the Samsung caused Windows to rebuild display topology and the MSI could temporarily disappear as well
- Reapplying `local.cfg` repeatedly recovered the MSI
- Full recovery was not possible until Windows enumerated the Samsung again as a current connected display

## Assessment

This differs from a normal Sunshine/MultiMonitorTool `/disable` state.

If the monitor were merely disabled, the Samsung would normally still be expected to appear in the MultiMonitorTool list with `Active=No`. During this incident the Samsung row was absent entirely and PnP did not report a healthy current connection.

Based on the available evidence, classify this as a **temporary Windows/NVIDIA display-enumeration or DP/EDID/hot-plug renegotiation failure affecting the Samsung monitor**.

The collected data is not sufficient to attribute the direct cause specifically to the cable, monitor firmware, or GPU driver.

## Recovery procedure

Do not disable VDD first when physical monitors are missing.

1. Capture current state
2. Check `Get-PnpDevice -Class Monitor`
3. Check whether the target physical monitor exists in the MultiMonitorTool CSV
4. Restore `local.cfg`
5. If the monitor is absent from enumeration, renegotiate the physical link/power path
6. Run `pnputil /scan-devices`
7. Run `DisplaySwitch.exe /extend`
8. Reapply `local.cfg` if needed

Emergency restore command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"
```

## Data to collect on recurrence

```powershell
Get-PnpDevice -Class Monitor |
    Format-Table Status, FriendlyName, InstanceId -AutoSize

& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /scomma "C:\SunshineLogs\current-monitors.csv"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

The important distinction is whether the affected monitor remains listed as `Active=No` or disappears from the current MultiMonitorTool list entirely.

## Follow-up

Treat this as separate from the Sunshine ON/OFF, rollback, and watchdog logic.

If the same pattern recurs, accumulate the same diagnostics first. If recurrence is confirmed, expand the investigation to DP cable/port changes, monitor firmware, and NVIDIA driver history.


## 2026-11-09 recurrence and verification fix

The same Samsung G9 non-enumeration symptom recurred. During the failure, the Samsung PnP instances again reported `Unknown`, and applying `local.cfg` alone did not restore the ultrawide.

After starting and then ending a Moonlight session, the OFF path applied `local.cfg`. The saved `02-after-local-restore.csv` showed both MSI and Samsung physical monitors as `Active=Yes`. However, the previous OFF script continued to receive 1 from `[System.Windows.Forms.Screen]::AllScreens.Count` and incorrectly entered the fail-safe path.

This incident therefore has two distinct layers:

1. a real enumeration failure where the Samsung temporarily disappears from the current Windows/MultiMonitorTool display set
2. a separate recovery-verification bug where WinForms screen enumeration can remain stale immediately after topology restoration

Starting with v4.2, OFF and ON rollback verify recovery from a fresh MultiMonitorTool CSV by requiring at least two `Active=Yes` non-VDD physical monitors. VDD is disabled only after that condition is satisfied.

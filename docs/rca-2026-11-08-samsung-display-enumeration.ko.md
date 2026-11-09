# RCA 2026-11-08~09 — Samsung G9 미표시 및 복구 검증 문제

## 결론 요약

2026-11-08과 11-09에 Samsung LC49G95T 와이드 모니터가 보이지 않고 MSI MP242만 남는 현상이 반복됐다.

문제 상태에서 확인된 사실은 다음과 같다.

- Samsung은 MultiMonitorTool 현재 목록에서 **행 자체가 사라지는 경우가 있었다**.
- 같은 시점 `Get-PnpDevice -Class Monitor`에서는 Samsung 인스턴스가 `Unknown`이었다.
- 단순 `local.cfg` 적용만으로는 즉시 복구되지 않는 경우가 있었다.
- 2026-11-09에는 모니터 전원 재연결로도 복구되지 않았지만, Moonlight 세션을 한 번 시작/종료한 뒤 OFF 경로의 `local.cfg` 적용으로 MSI와 Samsung이 모두 `Active=Yes`로 복구됐다.
- 그 직후 기존 OFF 스크립트의 `[System.Windows.Forms.Screen]::AllScreens.Count`는 계속 1을 반환해 **정상 복구를 실패로 오판**했다.

따라서 현재 확정할 수 있는 것은 두 가지다.

1. Samsung이 일시적으로 Windows/MultiMonitorTool의 현재 디스플레이 집합에서 정상적으로 보이지 않는 현상이 실제로 발생했다.
2. 복구 직후 WinForms `Screen.AllScreens.Count`를 신뢰한 기존 검증 로직에는 stale-state false negative 버그가 있었다.

**Samsung 미표시 현상의 최초 원인은 아직 확정되지 않았다.** DP 케이블/포트, 모니터 전원/EDID/hot-plug, NVIDIA/Windows 디스플레이 상태, Sunshine/VDD 전환의 선행 영향 중 어느 하나로 단정할 근거는 현재 없다.

## 2026-11-08 관측

문제 시점 MultiMonitorTool CSV:

- MSI MP242: `Active=Yes`, `Primary=Yes`
- VDD by MTT: `Active=No`
- Samsung LC49G95T: **목록에 없음**

문제 시점 PnP:

- VDD by MTT: `OK`
- MSI MP242: `OK`
- Samsung LC49G95T: 기존 인스턴스가 `Unknown`

당시에는 이 상태를 근거로 DP/EDID/hot-plug 계층 문제 가능성을 높게 봤지만, 이후 재현 결과만으로는 해당 원인을 확정할 수 없다.

## 2026-11-09 재발

같은 증상이 재발했다.

복구 전:

- Samsung PnP 인스턴스: `Unknown`
- `local.cfg` 단독 적용: Samsung 즉시 복구 안 됨
- 모니터 전원 재연결: 복구 안 됨

이후 Moonlight 세션을 한 번 시작했다가 종료했다.

OFF 경로에서 저장된 `02-after-local-restore.csv`에는:

- MSI MP242: `Active=Yes`
- Samsung LC49G95T: `Active=Yes`
- VDD: `Active=No`

가 확인됐다.

즉 **실제 물리 모니터 복구는 성공**했다.

하지만 기존 OFF 스크립트는 같은 시점에:

```text
Active Windows screens=1
...
FAIL_SAFE
```

로 기록했다. 이 값은 실제 MultiMonitorTool 토폴로지와 불일치했다.

## 확인된 코드 버그

기존 OFF 및 ON rollback 검증은:

```powershell
[System.Windows.Forms.Screen]::AllScreens.Count
```

를 사용했다.

디스플레이 토폴로지를 막 변경한 직후 이 값이 stale할 수 있어, 실제로 물리 모니터 2대가 복구됐는데도 1대로 인식하는 false negative가 발생했다.

### v4.2 수정

OFF와 ON rollback 모두 fresh MultiMonitorTool CSV를 다시 생성해 다음 조건을 직접 확인한다.

```text
Active=Yes
AND
non-VDD physical monitor
AND
count >= 2
```

이 조건을 만족한 경우에만 물리 모니터 복구 성공으로 판정하고 VDD를 끈다.

## 현재 해석

이번 사건에서 **확정된 문제**:

- Samsung이 한동안 현재 디스플레이 집합에서 보이지 않는 현상
- WinForms screen count 기반 복구 검증의 false negative

이번 사건에서 **아직 확정되지 않은 문제**:

- Samsung 미표시 현상의 최초 원인
- DP 케이블/포트 또는 모니터 자체 문제 여부
- NVIDIA/Windows 디스플레이 스택 문제 여부
- Sunshine/VDD 전환이 선행 조건이었는지 여부

따라서 이전의 “물리 링크/전원 재협상으로 복구됐다”, “Sunshine ON/OFF와 별개의 문제다”라는 표현은 철회한다.

## 재발 시 우선 수집

복구하기 전에:

```powershell
Get-PnpDevice -Class Monitor |
    Format-Table Status, FriendlyName, InstanceId -AutoSize

& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /scomma "C:\SunshineLogs\current-monitors.csv"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

그다음 `local.cfg` 복원 또는 Moonlight ON/OFF 흐름 전후의 MultiMonitorTool CSV를 비교한다.

## 안전 복구

물리 모니터가 보이지 않을 때 VDD를 먼저 끄지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"
```

복구 성공 여부는 v4.2부터 fresh MultiMonitorTool topology로 판단한다.

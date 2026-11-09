# RCA 2026-11-08 — Samsung G9 일시적 디스플레이 열거 실패

## 요약

2026-11-08 로컬 사용 중 Samsung LC49G95T 와이드 모니터가 보이지 않고 MSI MP242 세로 모니터만 활성 상태로 남는 현상이 발생했다.

문제 시점의 증거에서는 Samsung 모니터가 단순히 `Active=No` 상태로 남아 있던 것이 아니라, MultiMonitorTool의 현재 디스플레이 목록에서 **행 자체가 사라져 있었다**. 같은 시점 `Get-PnpDevice -Class Monitor`에서는 Samsung의 기존 인스턴스가 `Unknown` 상태였다.

이 때문에 `local.cfg` 복원은 MSI 모니터는 되살렸지만 Samsung 모니터는 즉시 복구하지 못했다. 이후 물리 링크/전원 재협상 후 현재 Samsung 인스턴스가 `OK`로 돌아왔고 정상 토폴로지가 복구되었다.

## 관측된 상태

문제 시점 MultiMonitorTool CSV:

- MSI MP242: `Active=Yes`, `Primary=Yes`
- VDD by MTT: `Active=No`
- Samsung LC49G95T: **목록에 없음**

문제 시점 PnP 상태:

- VDD by MTT: `OK`
- MSI MP242: `OK`
- Samsung LC49G95T: 기존 인스턴스 2개가 `Unknown`

복구 후 PnP 상태:

- MSI MP242: `OK`
- Samsung LC49G95T 현재 연결 인스턴스: `OK`
- 이전 Samsung 인스턴스: `Unknown`
- 비활성 VDD 인스턴스: `Unknown`

## 영향

- 와이드 모니터 출력 불가
- Samsung 모니터 전원 이벤트 시 디스플레이 토폴로지가 재구성되면서 MSI까지 일시적으로 보이지 않는 현상 발생
- `local.cfg` 재적용 시 MSI는 반복해서 복구됨
- Samsung이 현재 연결 디스플레이로 다시 열거되기 전까지는 `local.cfg`만으로 완전 복구되지 않음

## 판단

이번 사례는 Sunshine이 Samsung 모니터를 단순히 `/disable`한 상태와 다르다.

단순 disable이라면 일반적으로 MultiMonitorTool 목록에 Samsung 행이 남고 `Active=No`로 관측될 가능성이 높다. 실제 문제 시점에는 Samsung 행 자체가 없었고 PnP에서도 현재 연결 상태가 정상으로 확인되지 않았다.

따라서 현재 근거로는 **Windows/NVIDIA 디스플레이 열거 또는 DP/EDID/hot-plug 재협상 계층에서 Samsung 모니터가 일시적으로 현재 연결 디스플레이로 인식되지 않은 현상**으로 분류한다.

다만 해당 로그만으로 케이블, 모니터 펌웨어, GPU 드라이버 중 어느 구성 요소가 직접 원인인지까지 확정하지는 않는다.

## 복구 절차

물리 모니터가 사라진 경우 VDD를 먼저 끄지 않는다.

1. 현재 상태 수집
2. `Get-PnpDevice -Class Monitor` 확인
3. MultiMonitorTool CSV에서 대상 물리 모니터가 존재하는지 확인
4. `local.cfg` 복원
5. 대상 모니터가 목록 자체에 없다면 물리 링크/전원 재협상
6. `pnputil /scan-devices`
7. `DisplaySwitch.exe /extend`
8. 필요 시 `local.cfg` 재적용

긴급 복구 명령:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"
```

## 재발 시 수집할 정보

```powershell
Get-PnpDevice -Class Monitor |
    Format-Table Status, FriendlyName, InstanceId -AutoSize

& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /scomma "C:\SunshineLogs\current-monitors.csv"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

특히 대상 물리 모니터가 MultiMonitorTool에 `Active=No`로 남아 있는지, 아니면 행 자체가 사라지는지를 구분한다.

## 후속

현재 Sunshine ON/OFF, rollback, watchdog과는 별개의 물리 디스플레이 열거 문제로 취급한다.

재발 시 동일한 패턴이 반복되는지 로그를 누적하고, 반복성이 확인되면 DP 포트/케이블 교체, 모니터 펌웨어, NVIDIA 드라이버 이력까지 범위를 넓혀 점검한다.


## 2026-11-09 재발 및 검증 로직 수정

같은 Samsung G9 미열거 증상이 재발했다. 문제 상태에서는 Samsung PnP 인스턴스가 다시 `Unknown`이었고 `local.cfg` 단독 적용으로는 와이드 모니터가 복구되지 않았다.

이후 Moonlight 세션을 시작했다가 종료하면서 OFF 경로의 `local.cfg` 복원이 실행되었고, 저장된 `02-after-local-restore.csv`에는 MSI와 Samsung 두 물리 모니터가 모두 `Active=Yes`로 확인되었다. 그러나 기존 OFF 스크립트는 `[System.Windows.Forms.Screen]::AllScreens.Count`가 계속 1을 반환해 fail-safe로 잘못 판정했다.

따라서 이 현상은 두 층으로 분리한다.

1. Samsung이 한동안 Windows/MultiMonitorTool 현재 목록에서 사라지는 실제 열거 문제
2. 복구 직후 WinForms screen enumeration이 stale하여 정상 복구를 실패로 판단하는 별도 검증 버그

v4.2부터 OFF 및 ON rollback은 fresh MultiMonitorTool CSV에서 `Active=Yes`인 비-VDD 물리 모니터가 2대 이상인지 직접 확인한다. 이 조건을 만족한 경우에만 VDD를 끈다.

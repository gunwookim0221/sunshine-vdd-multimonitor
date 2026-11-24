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

복구 성공 여부는 v4.3에서 fresh MultiMonitorTool topology의 연속 안정 상태로 판단한다.


## 2026-11-10 재발 — VDD 전환 수렴 race 확인

2026-11-10 로그에서는 Samsung이 처음부터 사라진 것이 아니라, 오후 Moonlight/VDD 전환 반복 중 특정 실패 이후부터 현재 목록에서 복구되지 않는 흐름이 확인됐다.

특히 ON 검증에서 activeCount=1, activeVddCount=0으로 실패 판정된 직후 snapshot에서는 VDD가 Active=Yes, Primary=Yes로 보이는 경우가 있었다. 즉 단일 검증 read와 직후 snapshot 사이에서도 토폴로지가 변하고 있었다.

앞선 여러 실패는 rollback에서 물리 모니터 2대가 복구됐지만, 이후 한 시도에서는 ROLLBACK_VERIFY physicalActiveCount=1 / ROLLBACK_FAIL_SAFE가 되었고 이후 Samsung 행이 현재 MultiMonitorTool 목록에서 사라진 상태가 지속됐다.

따라서 2026-11-10 기준으로는 **VDD 전환 직후 토폴로지가 수렴하기 전에 실패/rollback을 너무 빨리 시작하는 race가 실제 production 경로의 주요 기여 요인**으로 판단한다. 이것이 Samsung 미열거 현상의 유일한 근본 원인이라고 단정하지는 않는다.

### v4.3 수정

- ON 단일 post-check를 제거하고 최대 15초 수렴 대기
- VDD-only + Primary 상태가 연속 3회 확인되어야 성공
- 그 전까지는 rollback하지 않음
- boot recovery도 WinForms screen count를 제거하고 fresh MultiMonitorTool 기반으로 변경
- boot recovery는 물리 모니터 2대 이상이 연속 2회 안정된 후에만 VDD를 끔
- VERIFY_CONVERGENCE / BOOT_VERIFY로 시도 번호, 연속 성공 횟수, 실제 active topology만 기록


## 2026-11-10 v4.3 실동작 검증 및 DP 포트 변경 후 복구

v4.3 적용 후 실제 Moonlight ON/OFF 왕복에서 다음이 확인됐다.

- ON 경로의 `VERIFY_CONVERGENCE`가 연속 3회 정상 상태를 확인한 뒤 `SESSION_START_SUCCESS`로 종료됐다.
- OFF 경로에서 `local.cfg`를 적용한 직후 첫 확인에서는 물리 모니터가 1대였으나, 약 2초 뒤 Samsung LC49G95T가 다시 현재 MultiMonitorTool 목록에 나타나면서 물리 모니터 2대가 모두 `Active=Yes`가 됐다.
- 이후 OFF는 물리 모니터 2대 복구를 확인한 뒤 VDD를 비활성화하고 `SESSION_END_SUCCESS`로 종료됐다.
- 이 성공 시점에는 Samsung G9의 DP 연결을 RTX 3080의 다른 DP 포트로 변경한 상태였다.

이 결과는 v4.3의 토폴로지 수렴 대기 방향이 실제 환경에서 유효했음을 보여준다. 또한 새 DP 포트 사용과 복구 성공 사이에 유의미한 시간적 연관이 있으나, **DP 포트가 근본 원인이라고 확정할 수는 없다.**

현재 상태:

- v4.3 ON convergence: 실동작 PASS
- OFF 물리 모니터 복구: PASS
- Samsung 재열거: PASS
- 새 DP 포트 효과: 정황상 유의미, 원인 확정 아님


## 2026-11-24 재발 — OFF 시작부터 Samsung이 현재 MTT 목록에 없음

이번 복구 ZIP의 `01-before-off.csv`, `02-after-local-restore.csv`, `99-failure.csv`, `verify-current.csv`는 같은 상태를 보였다.

- 물리 모니터 행은 MSI MP242 하나뿐이고 `Active=Yes`였다.
- VDD는 `Active=No`였다.
- Samsung LC49G95T/SAM7053 행은 어느 CSV에도 없었다.
- `local.cfg` 로드 뒤 약 20초 동안 19회 확인했지만 매번 활성 물리 모니터는 MSI 한 대뿐이었다.
- takeover 로그에는 Sunshine 중지 시각이 22:36:14, 첫 복구 확인이 22:36:15로 기록됐다. OFF 재시도는 `exitCode=1`로 끝났고, fail-safe가 VDD를 그대로 두었다.

따라서 이번 로그가 뒷받침하는 판정은 **복구가 시작될 때 이미 Samsung이 Windows의 현재 MTT 디스플레이 목록에 없었다**는 것이다. CSV에 Samsung 행이 없으므로 “비활성 행으로 열거됐지만 활성화에 실패했다”거나 “Samsung 대상 활성화 명령이 실패했다”고 결론 내릴 근거는 없다.

기존 PnP 텍스트는 `Class=Display` 장치인 NVIDIA GPU와 VDD를 기록했지만 `Class=Monitor` 목록은 저장하지 않았다. 따라서 이 ZIP만으로 Samsung Monitor PnP 장치가 현재 존재했는지 또는 사라졌는지는 판별할 수 없다. 같은 날 앞선 takeover 기록에서 MSI와 Samsung이 함께 보였다는 점은 증상이 간헐적임을 보여 주지만, 원인을 특정하지는 않는다.

### 다음 재발을 위한 진단 보강

OFF 복구는 이제 각 MTT 검증 읽기에 `TOPOLOGY_SAMPLE`을 남기며, 시작/종료 UTC 시각, CSV 수정 시각과 나이, MTT 종료 코드, 각 행의 `Active`/VDD 구분을 기록한다. OFF 경계 스냅샷에는 전체 Monitor PnP 목록과 `-PresentOnly` 목록, 현재 Display 어댑터 목록, 요약 및 조회 시간을 담은 `*-evidence.json`이 추가된다. 복구 판정 조건, `local.cfg` 복원 순서, fail-safe 동작은 바꾸지 않았다.

이 보강은 **다음 수집부터** 적용된다. 2026-11-24 ZIP에는 Monitor 클래스 PnP 자료가 없으므로 새 로깅으로 그날의 장치 존재 여부나 근본 원인을 소급 판정할 수 없다. PnP/어댑터/MTT 조회는 순차적으로 이뤄지므로 시각 메타데이터는 상태 변화의 시간 범위를 좁히는 자료이며, 완전히 동시인 단일 스냅샷은 아니다. MTT 행 누락은 MTT 현재 목록의 부재만 증명하고 PnP 부재를 증명하지 않는다.


## 2026-11-24 추가 관측 — Monitor PnP Unknown 및 수동 복구 시퀀스

같은 장애 상태에서 복구 후 추가로 확인한 `Get-PnpDevice -Class Monitor` 결과는 다음과 같았다.

- VDD by MTT: `OK`
- MSI MP242: `OK`
- Samsung LC49G95T / SAM7053: 기존 인스턴스 3개가 모두 `Unknown`

즉 Samsung의 PnP 장치 기록은 Windows에 남아 있었지만, 당시 정상적으로 현재 Monitor 장치로 시작/열거된 Samsung 인스턴스는 확인되지 않았다. 이는 앞선 MTT CSV에서 Samsung 행이 없었던 사실과 일관되지만, EDID/hot-plug, GPU 드라이버, Windows topology 중 어느 계층이 근본 원인인지는 여전히 확정하지 않는다.

이후 사용자가 Samsung G9의 전원 케이블을 완전히 분리했다가 다시 연결했다. 그 직후에는 두 물리 모니터 모두 보이지 않는 중간 상태가 있었고, 폰에서 Moonlight 세션을 한 번 시작한 뒤 정상적으로 연결을 종료하자 MSI MP242와 Samsung G9가 모두 다시 보였다.

이 시퀀스는 **완전 전원 재인가 뒤 Moonlight ON→OFF topology 전환이 복구와 시간적으로 연관되었다**는 관측 증거다. 전원 재인가 또는 Moonlight 전환 중 어느 하나가 단독 원인/해결책이었다고 단정하지 않는다. 자동 복구 로직에는 반영하지 않고, 재발 시 비교할 수 있는 수동 복구 사례로만 기록한다.

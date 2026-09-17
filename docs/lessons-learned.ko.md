# 시행착오와 교훈

[English](lessons-learned.md)

이번 구성은 여러 번의 시행착오를 거쳤고, 그 과정에서 각 구성 요소가 어떤 역할을 맡아야 안정적인지 명확해졌습니다.

## 1. Sunshine에 VDD GUID를 고정하면 취약함

초기에는 특정 VDD device ID를 Sunshine에 고정했습니다. 하지만 VDD를 껐다 켜는 과정에서 Windows가 가상 디스플레이를 재생성/재번호화하면서 Moonlight 접속이 불안정해졌습니다.

최종 방식: Sunshine `output_name`은 빈칸으로 두고, 접속 시작 전에 VDD를 Windows 주 모니터로 만들어 Sunshine이 현재 주 모니터를 자동 캡처하게 합니다.

## 2. DISPLAY 번호는 고정되지 않음

같은 가상 모니터가 처음에는 DISPLAY5, 이후 DISPLAY7, DISPLAY8로 바뀌었습니다.

최종 방식: MultiMonitorTool 출력에서 VDD를 동적으로 찾아 사용합니다. DISPLAY 번호를 절대 하드코딩하지 않습니다.

## 3. 이 토폴로지에서는 Sunshine `ensure_only_display`만으로 충분하지 않았음

선택한 VDD만 남기고 나머지 디스플레이를 끌 것으로 기대했지만, 실제 테스트에서는 세션 시작 중 VDD가 생성되는 타이밍 때문에 물리 모니터가 그대로 살아 있는 경우가 있었습니다.

최종 방식: Sunshine의 디스플레이 토폴로지 제어는 끄고, 시작 PowerShell이 VDD를 주 모니터로 만든 뒤 나머지 디스플레이를 직접 비활성화합니다.

## 4. VDD 장치를 켜는 것과 가상 모니터를 Windows 데스크톱에 연결하는 것은 다름

PnP 장치는 활성 상태인데 Windows 디스플레이 설정에서는 가상 모니터가 연결 끊김 상태로 남아 있던 적이 있었습니다.

최종 방식: VDD 장치를 활성화한 뒤 MultiMonitorTool로 감지된 가상 모니터 자체도 `enable` 합니다.

## 5. 물리 모니터 복원 전에 VDD를 끄는 것은 위험함

Windows가 물리 모니터를 연결 끊김 상태로 기억한 상황에서 VDD를 먼저 끄자 정상 Windows 화면이 하나도 보이지 않는 상태가 발생했습니다. BIOS/부팅 화면은 보였기 때문에 하드웨어 문제가 아니라 Windows 디스플레이 토폴로지 문제였습니다.

최종 방식: 반드시 `local.cfg 복원 → 물리 모니터 복귀 확인 → VDD OFF` 순서를 사용합니다.

## 6. `local.cfg`는 완전히 정상인 기준 상태에서 저장해야 함

초기에는 모니터 위치와 주 모니터가 조금 틀어진 상태에서 baseline을 저장해 복원 시 배치가 계속 어긋났습니다.

최종 방식: VDD를 끄고, 물리 모니터 위치/주 모니터/해상도/배율/방향을 정확히 맞춘 후 `local.cfg`를 다시 저장합니다.

## 7. 테스트한 VDD Control은 CLI로 쓰기 어려웠음

`--help`, `-h`, `/?`를 사용해도 도움말 대신 GUI가 열렸습니다.

최종 방식: 드라이버 ON/OFF는 PowerShell의 `Enable-PnpDevice` / `Disable-PnpDevice`, 모니터 토폴로지는 MultiMonitorTool이 담당합니다.

## 8. 역할을 분리하는 것이 안정적이었음

최종적으로 가장 안정적인 구조는 다음과 같았습니다.

```text
Sunshine
  캡처/스트리밍만 담당

PowerShell + VDD
  가상 디스플레이 장치 생명주기 담당

MultiMonitorTool
  모니터 enable/disable/primary/배치 복원 담당
```

역할을 분리하니 타이밍 충돌이 줄고, 문제가 생겼을 때 복구 경로도 명확해졌습니다.

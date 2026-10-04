# RCA: 물리 모니터 일부가 남은 원격 세션 (2026-10-04)

[English](rca-2026-10-04-display-renumbering.md)

## 증상

Moonlight 원격 접속 중 VDD만 보여야 하는데 물리 모니터 하나가 함께 활성 상태로 남아, 스마트폰에서 여러 화면이 보이는 것처럼 느껴졌습니다. 이후 정상 Undo 없이 재부팅했고, 로그인 시 boot-recovery가 정상 로컬 토폴로지를 복원했습니다.

## 로그 증거

세션 시작 로그는 VDD를 찾고 다음 대상을 비활성화했다고 기록했습니다.

```text
VDD_DISPLAY=\\.\DISPLAY5
Disabling other displays: \\.\DISPLAY1, \\.\DISPLAY2
SESSION_START_SUCCESS
```

하지만 전환 후 MultiMonitorTool 스냅샷에는 VDD와 물리 모니터 하나가 동시에 Active=Yes로 남아 있었습니다.

문제 세션 직전의 안정 식별자 예시는 다음과 같았습니다.

```text
MSI MP242       Short Monitor ID: MSI30A1
Samsung monitor Short Monitor ID: SAM7053
VDD by MTT      Short Monitor ID: MTT1337
```

`DISPLAY1`, `DISPLAY2`, `DISPLAY5` 같은 Name은 Windows 디스플레이 토폴로지가 바뀌는 동안 재번호화될 수 있지만 Monitor ID / Short Monitor ID / Serial Number는 해당 동작의 대상으로 사용하기 더 적합합니다.

## 근본 원인

v4 시작 스크립트는 물리 모니터를 `\\.\DISPLAYx` 이름으로 **한 대씩 순차 비활성화**했습니다.

첫 번째 `/disable`로 토폴로지가 바뀐 직후 Windows가 DISPLAY 번호를 다시 매길 수 있습니다. 그러면 두 번째 명령이 처음 수집한 DISPLAY 이름과 다른 실제 모니터를 가리킬 수 있습니다. 결과적으로 물리 모니터 하나가 남을 수 있습니다.

## v4.1 수정

1. VDD와 물리 모니터를 MultiMonitorTool CSV에서 식별합니다.
2. 명령 대상으로 Serial Number → full Monitor ID → Short Monitor ID 순으로 안정 식별자를 선택합니다.
3. 물리 모니터들의 식별자를 **토폴로지 변경 전에 전부 수집**합니다.
4. 여러 물리 모니터를 `/disable` 한 번의 호출로 동시에 전달합니다.
5. 전환 후 `Active=Yes`가 정확히 1개이고 그 1개가 VDD이면서 Primary인지 검증합니다.
6. 검증에 실패하면 `local.cfg` 복원을 즉시 시도하고, 물리 화면 2개 이상이 확인된 경우에만 VDD를 끕니다.

## 교훈

- `DISPLAYx`는 표시 이름이지 영구 식별자로 취급하면 안 됩니다.
- 복수 모니터 변경은 가능하면 대상 식별자를 먼저 고정한 뒤 한 번의 MultiMonitorTool 호출로 처리합니다.
- 명령이 오류 없이 끝났다는 사실만으로 성공으로 판정하지 말고 최종 토폴로지 post-condition을 검증해야 합니다.
- boot-recovery와 세션 로그는 실제 장애 RCA에 유효했습니다.

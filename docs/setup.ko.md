# 설정 가이드

[English](setup.md)

## 1. 구성 요소 설치

아래 공식 프로젝트 페이지에서 내려받습니다.

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

가능하면 서드파티 미러가 아니라 위 공식 페이지를 사용하세요.

권장 경로:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

저장소의 스크립트는 다음 위치에 복사합니다.

```text
C:\SunshineScripts\sunshine-remote-on.ps1
C:\SunshineScripts\sunshine-remote-off.ps1
C:\SunshineScripts\sunshine-boot-recovery.ps1
C:\SunshineScripts\register-boot-recovery.ps1
C:\SunshineScripts\collect-display-diagnostics.ps1
```

## 2. 평소 물리 모니터 상태 저장

`local.cfg` 저장 전:

1. VDD를 끕니다.
2. 물리 모니터만 활성화합니다.
3. 평소 쓰는 위치로 정확히 배치합니다.
4. 주 모니터를 정확히 지정합니다.
5. 해상도, 방향, 배율, 위치를 확인합니다.

그다음 현재 상태를 저장합니다.

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

`local.cfg`는 PC별 상태이므로 Git에 올리지 않는 것을 권장합니다.

## 3. Sunshine 설정

Sunshine Audio/Video 설정:

- 디스플레이 장치 ID / `output_name`: **빈칸**
- 디스플레이 장치 구성: **사용 안 함**

시작 스크립트가 VDD를 Windows 주 모니터로 직접 지정하므로 Sunshine은 현재 주 모니터를 자동 캡처하면 됩니다.

Sunshine의 명령 준비(Prep Commands)에 관리자 권한으로 다음 한 세트를 추가합니다.

```text
명령 수행:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

명령 실행 취소:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

관리자 권한 실행 옵션을 체크합니다.

## 4. v4.1 시작 스크립트 동작 방식

v4.1은 `\\.\DISPLAY1` 같은 번호를 토폴로지 변경 명령의 영구 식별자로 사용하지 않습니다. Windows는 첫 번째 모니터를 끄는 순간 DISPLAY 번호를 다시 매길 수 있기 때문입니다.

시작 시 다음 순서로 동작합니다.

1. VDD PnP 장치를 활성화합니다.
2. MultiMonitorTool CSV에서 VDD를 찾습니다.
3. 각 모니터의 명령용 식별자를 `Serial Number → full Monitor ID → Short Monitor ID` 순으로 선택합니다.
4. VDD를 안정 식별자로 enable/Primary 처리합니다.
5. 물리 모니터들의 안정 식별자를 토폴로지 변경 전에 모두 수집합니다.
6. 여러 물리 모니터를 MultiMonitorTool `/disable` **한 번의 호출**로 처리합니다.
7. 최종 상태를 다시 읽어 `Active=Yes`가 정확히 VDD 1개뿐이고 Primary인지 검증합니다.
8. 검증 실패 시 `local.cfg` rollback을 즉시 시도합니다.

MultiMonitorTool은 Monitor ID, Short Monitor ID, serial number를 명령줄의 모니터 식별자로 지원합니다.

## 5. 자동화 연결 전 수동 왕복 테스트

관리자 PowerShell에서 시작 스크립트 실행:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

기대 로그에는 다음과 비슷한 내용이 나와야 합니다.

```text
SESSION_START_V41
VDD ... stableId=...
Disabling physical displays in one call using stable identifiers: ...
VERIFY activeCount=1 activeVddCount=1
SESSION_START_SUCCESS
```

실제 화면 상태도 **VDD 1개만 활성**이어야 합니다.

이후 복구 스크립트 실행:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

기대 결과:

- `local.cfg`로 물리 모니터 배치 복원
- 물리 모니터 2개 이상 활성 확인
- 마지막에 VDD OFF

이 수동 왕복이 성공한 뒤 Sunshine 명령 준비에 연결하세요.

## 6. 최종 동작 흐름

```text
Moonlight 접속
  -> VDD ON
  -> VDD 안정 식별자 선택
  -> VDD Primary
  -> 물리 모니터 안정 식별자 사전 수집
  -> 물리 모니터들을 한 번에 OFF
  -> VDD 1개만 Active인지 검증
  -> Sunshine 캡처

Moonlight 종료
  -> local.cfg 복원
  -> 물리 모니터 복귀 확인
  -> VDD OFF
```

## 7. 로그인 자동 복구 안전장치

비정상 종료나 강제 재부팅으로 Sunshine Undo가 실행되지 않아도, 사용자 로그인 시 정상 물리 모니터 구성을 다시 적용하도록 예약 작업을 등록합니다.

관리자 PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"
```

확인:

```powershell
Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"
```

복구 스크립트는 로그인 후 10초 기다린 뒤 `local.cfg`를 로드하고, Windows에서 활성 화면 2개 이상을 확인한 경우에만 VDD를 끕니다.

## 8. 로그와 장애 진단

세션 시작/종료/부팅 복구 로그는 `C:\SunshineLogs\`에 저장됩니다.

문제 발생 시 가능하면 재부팅 전에:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

자세한 내용:

- [안전장치 및 진단 로그](safety-and-diagnostics.ko.md)
- [2026-10-04 DISPLAY 재번호화 장애 RCA](rca-2026-10-04-display-renumbering.ko.md)

## 참고

- 실제 검증 환경은 물리 모니터 2대 + 필요할 때만 켜는 VDD 1대였습니다.
- `DISPLAY5`, `DISPLAY7`, `DISPLAY8`처럼 이름이 바뀌는 것 자체는 정상일 수 있습니다.
- 중요한 것은 DISPLAY 번호가 아니라 안정 식별자와 최종 토폴로지 검증입니다.
- 다른 토폴로지에서는 반드시 수동 테스트 후 사용하세요.

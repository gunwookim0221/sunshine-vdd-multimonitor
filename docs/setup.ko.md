# 설정 가이드

[English](setup.md)

## 1. 구성 요소 설치

아래 공식 프로젝트 페이지에서 내려받습니다.

- Sunshine: https://github.com/LizardByte/Sunshine/releases
- Moonlight: https://moonlight-stream.org/
- Virtual Display Driver (VDD by MTT): https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- NirSoft MultiMonitorTool: https://www.nirsoft.net/utils/multi_monitor_tool.html

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
C:\SunshineScripts\sunshine-watchdog.ps1
C:\SunshineScripts\register-sunshine-watchdog.ps1
```

## 2. 평소 물리 모니터 상태 저장

`local.cfg` 저장 전 VDD를 끄고, 물리 모니터만 활성화한 뒤 평소 위치/주 모니터/해상도/방향/배율을 정확히 맞춥니다.

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

`local.cfg`는 PC별 상태이므로 Git에 올리지 않는 것을 권장합니다.

## 3. Sunshine 설정

Sunshine Audio/Video 설정:

- 디스플레이 장치 ID / `output_name`: **빈칸**
- 디스플레이 장치 구성: **사용 안 함**

Prep Commands에는 관리자 권한으로 다음 한 세트만 둡니다.

```text
명령 수행:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

명령 실행 취소:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

## 4. v4.1 시작 스크립트 동작 방식

v4.1은 `\\.\DISPLAY1` 같은 번호를 영구 식별자로 사용하지 않습니다.

1. VDD PnP 장치 활성화
2. MultiMonitorTool CSV에서 VDD 탐색
3. `Serial Number → full Monitor ID → Short Monitor ID` 순으로 안정 식별자 선택
4. VDD enable/Primary 처리
5. 물리 모니터 식별자를 토폴로지 변경 전에 모두 수집
6. 여러 물리 모니터를 `/disable` 한 번의 호출로 처리
7. `Active=Yes`가 VDD 1개뿐이고 Primary인지 검증
8. 실패 시 `local.cfg` rollback 시도

## 5. 자동화 연결 전 수동 왕복 테스트

관리자 PowerShell에서:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

기대 로그:

```text
SESSION_START_V41
Disabling physical displays in one call using stable identifiers: ...
VERIFY activeCount=1 activeVddCount=1
SESSION_START_SUCCESS
```

이후:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

물리 모니터 복구와 VDD OFF까지 확인합니다.

## 6. 최종 동작 흐름

```text
Moonlight 접속
  -> VDD ON
  -> 안정 식별자로 VDD Primary
  -> 물리 모니터를 한 번에 OFF
  -> VDD 1개만 Active인지 검증
  -> Sunshine 캡처

Moonlight 종료
  -> local.cfg 복원
  -> 물리 모니터 복귀 확인
  -> VDD OFF
```

## 7. 로그인 자동 복구 안전장치

비정상 종료나 강제 재부팅으로 Sunshine Undo가 실행되지 않아도 사용자 로그인 시 물리 모니터 구성을 복구합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"
```

확인:

```powershell
Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"
```

## 8. 로그와 장애 진단

세션 시작/종료/부팅 복구 로그는 `C:\SunshineLogs\`에 저장됩니다.

문제 발생 시 가능하면 재부팅 전에:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

## 9. Sunshine Watchdog

Moonlight에서 PC가 회색/offline으로 보이지만 Windows는 살아 있는 상황에 대비해 Sunshine 전용 watchdog을 별도로 등록할 수 있습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1"
```

등록되는 작업:

```text
Sunshine Watchdog - Crash Event
Sunshine Watchdog - Hourly
```

동작 방식:

- Service Control Manager 7031/7034 이벤트 발생 시 즉시 Sunshine 상태 확인
- 1시간마다 한 번 보조 health check
- Sunshine 서비스/`sunshine.exe`/기본 47989·47990 TCP 포트를 확인
- 이상 시 Sunshine 서비스만 재시작
- VDD 및 모니터 토폴로지는 건드리지 않음
- 5분 restart cooldown으로 반복 crash 시 재시작 루프 방지

수동 확인:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-watchdog.ps1"
```

로그:

```text
C:\SunshineLogs\watchdog\sunshine-watchdog.log
```

제거:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1" -Remove
```

자세한 내용은 [Sunshine Watchdog](sunshine-watchdog.ko.md)를 참고하세요.

## 참고

- 실제 검증 환경은 물리 모니터 2대 + 필요할 때만 켜는 VDD 1대입니다.
- DISPLAY 번호는 바뀔 수 있습니다.
- watchdog은 Sunshine 가용성만 담당하고, 모니터 복구는 기존 boot recovery/on/off 스크립트가 담당합니다.

# 로컬 입력 자동 Takeover

Moonlight 원격 세션 중 집 PC의 실제 키보드/마우스를 사용하면 원격 세션을 정리하고 기존 로컬 물리 모니터 배치를 복구하는 보조 기능입니다.

## 설계

이 기능은 기존 v4.3 ON/OFF 토폴로지 로직을 변경하지 않습니다.

`sunshine-local-takeover.ps1`는 로그인한 사용자 세션에서 Windows Raw Input을 감시합니다.

- VDD가 꺼져 있고 물리 모니터가 활성인 정상 로컬 상태에서 실제 사용된 Raw Input 장치를 자동 학습합니다.
- 학습 정보는 `C:\SunshineLogs\local-takeover\known-local-devices.json`에 저장합니다.
- VDD 하나만 활성인 원격 모드에서는 학습된 장치의 입력만 takeover 후보로 인정합니다.
- 처음 보는 장치나 device handle이 없는 주입 입력은 로그만 남기고 무시합니다.
- 키보드 key-down 또는 마우스 버튼은 즉시 takeover 신호입니다.
- 마우스 이동은 1초 안에 raw delta 합계가 160 이상일 때 takeover로 판정합니다. 작은 진동/책상 충격을 줄이기 위한 threshold입니다.

Sunshine의 Windows 입력은 환경에 따라 SendInput fallback 또는 별도 virtual HID 경로를 사용할 수 있으므로, 단순한 “최근 입력 시간”만으로 로컬/원격을 구분하지 않습니다. 학습된 실제 Raw Input device path를 기준으로 구분합니다.

## Takeover 순서

1. takeover trigger와 device path를 로그에 기록
2. Sunshine Windows 서비스를 정상 stop 시도하여 Moonlight 연결을 끊음
3. 서비스 stop 과정의 기존 Undo가 물리 모니터를 이미 복구했는지 fresh MultiMonitorTool topology로 확인
4. 복구되지 않았다면 기존 `sunshine-remote-off.ps1` 실행
5. 물리 모니터 2대 이상 복구 확인
6. Sunshine 서비스 다시 시작

물리 모니터 복구가 확인되지 않으면 기존 OFF fail-safe를 존중하며 VDD를 억지로 제거하지 않습니다.

## 설치

두 스크립트를 다음 위치에 둡니다.

```text
C:\SunshineScripts\sunshine-local-takeover.ps1
C:\SunshineScripts\register-local-takeover.ps1
```

관리자 PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-local-takeover.ps1"
```

작업 확인:

```powershell
Get-ScheduledTask -TaskName "Sunshine Local Takeover"
```

로그:

```powershell
Get-Content "C:\SunshineLogs\local-takeover\local-takeover.log" -Tail 80
```

## 최초 학습

설치 직후 정상 로컬 모니터 상태에서 실제 키보드를 한 번 누르고 마우스를 움직이거나 클릭합니다.

로그에 다음처럼 나오면 학습 완료입니다.

```text
KNOWN_DEVICE_LEARNED kind='keyboard' ...
KNOWN_DEVICE_LEARNED kind='mouse' ...
```

그 뒤 Moonlight 원격 모드에서 같은 장치의 키 입력, 마우스 클릭 또는 의도적인 이동이 takeover를 발생시킵니다.

## 주요 로그

- `WATCHER_START`: watcher 시작
- `RAW_INPUT_READY`: Raw Input listener 준비 완료
- `MODE_CHANGE`: local/remote topology 변경
- `KNOWN_DEVICE_LEARNED`: 실제 로컬 장치 자동 학습
- `REMOTE_INPUT_IGNORED`: 미학습/주입/가상 입력 무시
- `TAKEOVER_TRIGGER`: 로컬 takeover 판정
- `SERVICE_STOP_RESULT`: Sunshine 연결 종료 단계
- `RECOVERY_VERIFY`: 물리 모니터 복구 검증
- `OFF_RECOVERY_RESULT`: 기존 OFF script fallback 결과
- `SERVICE_START_RESULT`: Sunshine 재기동
- `TAKEOVER_FINAL`: 최종 topology 및 단계별 결과
- `TAKEOVER_SUCCESS` / `TAKEOVER_FAILED`

watcher는 30분 간격 heartbeat를 남기며 로그가 5 MB를 넘으면 시작 시 이전 파일을 archive합니다.

## 제거

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-local-takeover.ps1" -Remove
```

기존 ON/OFF, boot recovery, Sunshine watchdog에는 영향을 주지 않습니다.

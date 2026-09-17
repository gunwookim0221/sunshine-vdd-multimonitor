# 설정 가이드

[English](setup.md)

## 1. 구성 요소 설치

다음을 설치합니다.

- Sunshine
- Moonlight
- Virtual Display Driver (VDD by MTT)
- NirSoft MultiMonitorTool

권장 경로:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

저장소의 스크립트는 다음 위치에 복사합니다.

```text
C:\SunshineScripts\sunshine-remote-on.ps1
C:\SunshineScripts\sunshine-remote-off.ps1
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

이유: 시작 스크립트가 VDD를 Windows 주 모니터로 직접 지정하므로 Sunshine은 현재 주 모니터를 자동 캡처하면 됩니다. VDD GUID를 고정하면 VDD 재생성/재연결 시 값이 달라져 접속이 실패할 수 있습니다.

Sunshine의 명령 준비(Prep Commands)에 관리자 권한으로 다음 한 세트를 추가합니다.

```text
명령 수행:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

명령 실행 취소:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

관리자 권한 실행 옵션을 체크합니다.

## 4. 자동화 연결 전 수동 왕복 테스트

관리자 PowerShell에서 시작 스크립트 실행:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"
```

기대 결과:

- VDD가 켜짐
- VDD 디스플레이 번호를 동적으로 탐색
- VDD가 주 모니터가 됨
- 물리 모니터가 비활성화됨

이후 복구 스크립트 실행:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

기대 결과:

- `local.cfg`로 물리 모니터 배치가 복원됨
- 물리 모니터가 실제로 돌아온 것을 확인함
- 마지막에 VDD가 꺼짐

이 수동 왕복이 성공한 뒤에만 Sunshine 명령 준비에 연결하는 것을 권장합니다.

## 5. 최종 동작 흐름

```text
Moonlight 접속
  -> Sunshine 명령 수행
  -> VDD ON
  -> VDD 동적 탐색
  -> VDD Primary
  -> 물리 모니터 OFF
  -> Sunshine은 현재 주 모니터 캡처

Moonlight 종료
  -> Sunshine 명령 실행 취소
  -> local.cfg 복원
  -> 물리 모니터 복귀 확인
  -> VDD OFF
```

## 참고

- VDD는 `DISPLAY5`, `DISPLAY7`, `DISPLAY8`처럼 번호가 바뀔 수 있으므로 번호를 고정하지 않습니다.
- 실제 검증 환경은 물리 모니터 2대 + 필요할 때만 켜는 VDD 1대였습니다.
- 시작 스크립트는 VDD를 제외한 나머지 모니터를 모두 끕니다. 다른 토폴로지에서는 반드시 수동 테스트 후 사용하세요.

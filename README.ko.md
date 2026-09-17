# Sunshine + VDD 멀티 모니터 자동화

[English](README.md)

물리 모니터가 2대 이상인 Windows PC에서 Sunshine/Moonlight 원격 접속 시 **폰에는 전용 가상 모니터 하나만 보이도록** 자동 전환하는 구성입니다.

## 해결하려는 문제

듀얼/멀티 모니터 PC를 그대로 스트리밍하면 폰 화면이 너무 넓어지고, 앱이 보이지 않는 물리 모니터에서 열리거나, 가상 모니터를 잘못 끄는 순간 Windows 출력 화면이 0개가 되는 문제가 생길 수 있습니다.

이 저장소는 다음 조합에서 실제로 동작한 절차를 정리합니다.

- Sunshine
- Moonlight
- Virtual Display Driver (VDD by MTT)
- NirSoft MultiMonitorTool
- PowerShell 시작/종료 스크립트

최종 구조는 다음과 같습니다.

```text
평소 로컬 사용
  물리 모니터 1 + 2 ON
  VDD OFF

Moonlight 접속 시작
  VDD ON
  VDD 모니터를 동적으로 탐색
  VDD 활성화 + 주 모니터 지정
  물리 모니터 비활성화

Moonlight 종료
  local.cfg로 물리 모니터 배치 복원
  물리 모니터 복구 확인
  VDD OFF
```

## 핵심 설계 원칙

- `DISPLAY5`, `DISPLAY7`, `DISPLAY8` 같은 번호를 하드코딩하지 않습니다. VDD를 껐다 켜면 번호가 바뀔 수 있습니다.
- Sunshine의 `output_name` / 디스플레이 장치 ID는 **빈칸**으로 둡니다. 현재 주 모니터를 자동 캡처하게 합니다.
- Sunshine의 디스플레이 장치 구성은 **사용 안 함**으로 둡니다. 모니터 토폴로지는 PowerShell 스크립트가 전담합니다.
- 이 구성에서는 Sunshine의 `ensure_only_display`에 의존하지 않습니다.
- 종료 시 반드시 **`local.cfg 복원 → 물리 모니터 복귀 확인 → VDD OFF`** 순서를 지킵니다. 순서를 거꾸로 하면 화면이 하나도 안 보이는 상태가 될 수 있습니다.

## 파일 구성

- `scripts/sunshine-remote-on.ps1` — 원격 세션 시작
- `scripts/sunshine-remote-off.ps1` — 원격 세션 종료/복구
- `docs/setup.ko.md` — 전체 설치 및 설정
- `docs/troubleshooting.ko.md` — 문제 해결
- `docs/recovery.ko.md` — 블랙스크린 복구
- `docs/lessons-learned.ko.md` — 시행착오와 원인

## 요구 사항

- Windows 11
- Sunshine
- Moonlight
- VDD by MTT / Virtual Display Driver
- NirSoft MultiMonitorTool

스크립트에서 사용하는 권장 경로:

```text
C:\SunshineScripts\
C:\SunshineTools\multimonitortool\MultiMonitorTool.exe
```

## 빠른 설정

1. VDD와 MultiMonitorTool을 설치합니다.
2. PowerShell 스크립트를 `C:\SunshineScripts\`에 둡니다.
3. VDD를 끄고 물리 모니터만 평소 배치로 정확히 맞춘 뒤 다음 명령으로 `local.cfg`를 저장합니다.

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /SaveConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

4. Sunshine 설정:
   - 디스플레이 장치 ID / `output_name`: **빈칸**
   - 디스플레이 장치 구성: **사용 안 함**
   - 명령 준비(관리자 권한):

```text
명령 수행:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-on.ps1"

명령 실행 취소:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"
```

5. Sunshine에 연결하기 전에 두 스크립트를 수동으로 왕복 테스트합니다.

자세한 절차는 [docs/setup.ko.md](docs/setup.ko.md)를 참고하세요.

## 안전 주의

이 구성은 원격 세션 중 물리 모니터를 의도적으로 비활성화합니다. 실험하기 전에 반드시 [docs/recovery.ko.md](docs/recovery.ko.md)의 복구 방법을 확인해 두세요.

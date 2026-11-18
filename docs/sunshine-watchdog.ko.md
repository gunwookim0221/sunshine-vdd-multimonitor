# Sunshine Watchdog

[English](sunshine-watchdog.md)

Moonlight에서 PC가 회색/오프라인처럼 보이지만 Windows PC 자체는 켜져 있는 상황을 줄이기 위한 Sunshine 전용 watchdog입니다.

## 설계

watchdog은 모니터 토폴로지나 VDD를 건드리지 않습니다. Sunshine 상태만 확인합니다.

자동 복구 판정 항목:

- Sunshine Windows 서비스가 존재하고 `Running`인지
- `sunshine.exe` 프로세스가 존재하는지
- 기본 Sunshine HTTP 포트 `47989/TCP`가 localhost에서 열려 있는지
- 기본 Web UI 포트 `47990/TCP`가 localhost에서 열려 있는지

추가 진단 로그(판정에는 사용하지 않음):

- Sunshine 관련 포트의 실제 LISTEN 주소와 owning PID
- Windows 네트워크 프로필/카테고리와 IPv4 연결 상태
- loopback/APIPA를 제외한 IPv4 주소
- Tailscale 어댑터 존재 여부와 상태

Sunshine의 기본 Web UI는 `https://localhost:47990`이며 기본 포트 패밀리는 HTTP 47989 / Web 47990입니다.

## 실행 방식

`register-sunshine-watchdog.ps1`은 예약 작업 2개를 등록합니다.

1. `Sunshine Watchdog - Crash Event`
   - Windows System 로그의 Service Control Manager 이벤트 7031/7034 발생 시 실행
   - 특정 서비스 이름을 이벤트 필터에 하드코딩하지 않고, watchdog 실행 후 Sunshine 상태를 확인
   - 다른 서비스가 죽어서 트리거되어도 Sunshine이 정상이면 즉시 종료

2. `Sunshine Watchdog - Hourly`
   - 1시간마다 한 번 보조 확인
   - 서비스가 Running인데 프로세스/포트가 비정상인 hang 계열을 잡기 위한 낮은 빈도의 safety check

## 자동 복구

Sunshine이 비정상이면 Windows 서비스를 재시작하고 최대 25초 동안 다음 조건을 확인합니다.

```text
서비스 Running
sunshine.exe 존재
47989/TCP 응답
47990/TCP 응답
```

모두 정상화되면 `RECOVERY_SUCCESS`를 기록합니다.

네트워크 진단 값은 `NET_DIAG_*` 로그로만 남으며 **Sunshine restart 여부를 바꾸지 않습니다.** 예를 들어 Tailscale이 내려가거나 이더넷이 Public이어도 서비스/프로세스/localhost 포트가 정상이면 watchdog은 Sunshine을 재시작하지 않습니다.

5분 restart cooldown이 있어 반복 crash 시 무한 재시작 루프를 피합니다.

## 설치

다음 파일을 PC에 복사합니다.

```text
C:\SunshineScripts\sunshine-watchdog.ps1
C:\SunshineScripts\register-sunshine-watchdog.ps1
```

관리자 PowerShell에서:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1"
```

등록 확인:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "Sunshine Watchdog*"
```

수동 health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-watchdog.ps1"
```

정상이면 로그에 `HEALTHY no action required.`가 기록됩니다.

## 로그

```text
C:\SunshineLogs\watchdog\sunshine-watchdog.log
C:\SunshineLogs\watchdog\last-restart.txt
```

Moonlight가 회색으로 보였던 시점에는 `CHECK`, `NET_DIAG_LISTENERS`, `NET_DIAG_PROFILES`, `NET_DIAG_IPV4`, `NET_DIAG_TAILSCALE`를 함께 확인합니다. 서비스/localhost는 정상인데 Moonlight만 offline이었다면 PC 외부 접근 경로의 상태를 좁히는 데 도움이 됩니다.

`RECOVERY_SUCCESS`, `RECOVERY_FAILED`, `WATCHDOG_ERROR`도 같이 확인하면 Sunshine 자체 장애 여부를 분리할 수 있습니다.

## 제거

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-sunshine-watchdog.ps1" -Remove
```

## 제한 사항

- 자동 복구 authority는 Sunshine 서비스/프로세스/localhost 포트 상태에만 있습니다.
- Tailscale, Wi-Fi, 라우팅, 방화벽 등 네트워크 경로 자체가 끊긴 경우는 진단 로그에 증거를 남길 수 있지만 Sunshine을 자동 재시작하지 않습니다.
- LISTEN 주소/네트워크 프로필/IPv4/Tailscale 상태는 diagnostic-only이며 동작이나 권한을 변경하지 않습니다.
- Sunshine 포트를 기본값에서 변경했다면 `sunshine-watchdog.ps1 -BasePort <포트>`로 실행하도록 예약 작업도 맞춰야 합니다.
- VDD/물리 모니터 복구는 기존 `sunshine-boot-recovery.ps1` 및 remote on/off 스크립트의 역할입니다.

# 문제 해결

[English](troubleshooting.md)

## Moonlight 접속 후 물리 모니터 하나가 같이 살아 있거나 여러 화면처럼 보임

v4 이전/초기 v4 스크립트에서 실제로 재현된 문제입니다. `\\.\DISPLAY1`, `\\.\DISPLAY2` 같은 이름으로 모니터를 한 대씩 순차 비활성화하면 첫 번째 변경 직후 Windows가 DISPLAY 번호를 다시 매길 수 있습니다. 그러면 두 번째 명령이 처음 의도한 모니터가 아닌 다른 대상을 가리킬 수 있습니다.

v4.1부터는 다음 방식으로 수정되었습니다.

- DISPLAY 번호가 아닌 Serial Number / full Monitor ID / Short Monitor ID를 사용
- 물리 모니터 식별자를 토폴로지 변경 전에 전부 수집
- 여러 물리 모니터를 한 번의 `/disable` 호출로 처리
- 전환 후 `Active=Yes`가 VDD 1개뿐인지 검증
- 검증 실패 시 `local.cfg` rollback 시도

최신 `scripts/sunshine-remote-on.ps1`을 `C:\SunshineScripts\sunshine-remote-on.ps1`에 다시 복사하세요.

장애 분석: [2026-10-04 RCA](rca-2026-10-04-display-renumbering.ko.md)

## Moonlight 접속 후에도 모니터가 3개 모두 살아 있음

이 구성에서는 Sunshine의 `ensure_only_display`에 의존하지 않습니다. 시작 스크립트가 직접 VDD를 주 모니터로 만들고 나머지 모니터를 비활성화해야 합니다.

Sunshine의 디스플레이 장치 구성이 **사용 안 함**인지, 명령 수행에 `sunshine-remote-on.ps1` 하나만 들어 있는지 확인하세요.

## VDD를 껐다 켠 뒤 Moonlight가 접속되지 않음

Sunshine에 디스플레이 장치 ID / `output_name`이 고정되어 있다면 비우세요. VDD를 재생성하면 DISPLAY 번호뿐 아니라 장치 식별자도 달라질 수 있습니다. 이 구성은 현재 주 모니터를 Sunshine이 자동 캡처하는 방식입니다.

## VDD가 DISPLAY5였다가 DISPLAY7/8로 바뀜

정상적으로 발생할 수 있습니다. DISPLAY 번호를 하드코딩하지 마세요. v4.1 시작 스크립트는 MultiMonitorTool 출력에서 VDD를 찾은 뒤 안정 식별자를 사용합니다.

## 평소 PC 사용 중 앱이 보이지 않는 가상 모니터에 열림

원격 세션이 아닌데 VDD가 켜져 있을 가능성이 큽니다. 평상시 목표 상태는 다음과 같습니다.

```text
물리 모니터 ON
VDD OFF
```

`local.cfg`를 복원한 뒤 VDD를 끄거나 종료 스크립트를 실행하세요.

## Moonlight 종료 후 물리 모니터가 돌아오지 않음

다음을 실행하세요.

```powershell
& "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /LoadConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

물리 모니터가 실제로 보이는 것을 확인한 뒤에만 VDD를 끄세요.

```powershell
Get-PnpDevice -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -like "*Virtual Display*" } |
  Disable-PnpDevice -Confirm:$false
```

`local.cfg`를 불러왔는데 주 모니터나 배치가 틀어지면 VDD를 끈 상태에서 물리 모니터 배치/주 모니터/해상도/배율을 정확히 맞추고 `local.cfg`를 다시 저장하세요.

## 문제 발생 시 로그를 먼저 남기고 싶음

가능하면 재부팅이나 복구 전에 다음을 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"
```

`C:\SunshineLogs\<timestamp>-diagnostics\`에 현재 토폴로지, PnP 상태, 최근 Display/Kernel-PnP/NVIDIA/Kernel-Power 이벤트가 저장됩니다.

## `Get-PnpDevice -HardwareID` 오류

Windows PowerShell 버전에 따라 `Get-PnpDevice`에 `-HardwareID` 매개 변수가 없습니다. 이 저장소의 스크립트는 해당 옵션을 사용하지 않고 `InstanceId`와 `FriendlyName`으로 VDD를 찾습니다.

## VDD Control에 `--help`, `-h`, `/?`를 줘도 GUI만 뜸

테스트한 VDD Control 버전은 일반적인 CLI처럼 동작하지 않았습니다. 따라서 이 구성은 PnP 장치 ON/OFF는 PowerShell로, 모니터 토폴로지는 MultiMonitorTool로 제어합니다.

## RTX 3080에서 Sunshine 로그에 AV1 오류가 보임

모니터 자동화와는 무관합니다. RTX 3080은 H.264/HEVC NVENC는 지원하지만 AV1 인코딩은 지원하지 않습니다. Sunshine이 H.264/HEVC 인코더를 정상 생성했다면 이 구성에는 문제가 없습니다.

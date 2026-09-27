# 안전장치 및 진단 로그

[English](safety-and-diagnostics.md)

원격 세션 중 비정상 종료, 강제 재부팅, 전원 손실, Sunshine Undo 미실행으로 물리 모니터가 복구되지 않는 경우를 대비합니다.

## 1. v4 로그 구조

세션 시작/종료 스크립트는 자동으로 `C:\SunshineLogs\` 아래에 실행 시각별 폴더를 만들고 다음 정보를 남깁니다.

- `operations.log`: 단계별 실행 결과와 성공/실패
- `*.csv`: MultiMonitorTool 토폴로지 스냅샷
- `*-pnp.txt`: Display 클래스 PnP 상태

핵심 판별 기준:

- `SESSION_START_SUCCESS`는 있는데 대응하는 `SESSION_END_START`가 없으면 Sunshine Undo가 실행되지 않았거나 세션이 비정상 종료됐을 가능성이 큽니다.
- `SESSION_END_START` 뒤 `FAIL_SAFE`가 나오면 `local.cfg` 복원은 시도했지만 물리 모니터 2개 복구 확인에 실패한 것입니다.
- `SESSION_END_SUCCESS`까지 있으면 종료 스크립트는 정상 완료한 것이므로 이후 Windows/GPU/PnP 단계에서 토폴로지가 다시 바뀌었는지 확인해야 합니다.

## 2. 로그인 시 자동 복구

`scripts/sunshine-boot-recovery.ps1`은 로그인 후 10초 기다린 다음:

1. 현재 상태와 최근 Windows 이벤트를 먼저 로그로 저장
2. `local.cfg` 로드
3. 활성 화면이 2개 이상인지 확인
4. 확인된 경우에만 VDD 비활성화
5. 확인 실패 시 VDD 상태를 건드리지 않고 종료

복구 실패 상태에서 VDD까지 꺼서 출력 화면이 0개가 되는 것을 피하도록 설계했습니다.

다음 파일을 복사합니다.

    C:\SunshineScripts\sunshine-boot-recovery.ps1
    C:\SunshineScripts\register-boot-recovery.ps1

관리자 PowerShell에서 등록:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1"

확인:

    Get-ScheduledTask -TaskName "Sunshine VDD Boot Recovery"

제거:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\register-boot-recovery.ps1" -Remove

> 이 작업은 사용자 로그인 시 실행됩니다. BIOS/부팅 로고 단계나 로그인 전 화면 자체를 복구하는 기능은 아닙니다.

## 3. 문제가 발생했을 때 수동 진단 수집

가능하면 강제 재부팅이나 복구 명령을 실행하기 전에:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\collect-display-diagnostics.ps1"

결과는 `C:\SunshineLogs\<timestamp>-diagnostics\`에 저장됩니다.

수집 항목:

- MultiMonitorTool 현재 토폴로지 CSV
- Display 클래스 PnP 상태
- Windows가 현재 활성 화면으로 인식하는 목록
- 최근 8시간 System 이벤트: Display, Kernel-PnP, nvlddmkm, Kernel-Power

## 4. 응급 수동 복구

물리 모니터가 안 보일 때:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SunshineTools\multimonitortool\MultiMonitorTool.exe' /LoadConfig 'C:\SunshineTools\multimonitortool\local.cfg'"

화면이 돌아온 것을 확인한 뒤 종료 스크립트를 실행합니다.

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SunshineScripts\sunshine-remote-off.ps1"

항상 **물리 모니터 복구 확인 → VDD OFF** 순서를 지키세요.
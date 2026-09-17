# 복구 가이드

[English](recovery.md)

모니터 전환 후 물리 모니터가 모두 검게 되거나 Windows 출력 화면이 없는 것처럼 보일 때 사용하는 절차입니다.

## 1차 복구: `local.cfg` 복원

화면이 안 보여도 `Win + R`을 누르고 다음을 실행할 수 있습니다.

```text
"C:\SunshineTools\multimonitortool\MultiMonitorTool.exe" /LoadConfig "C:\SunshineTools\multimonitortool\local.cfg"
```

몇 초 기다립니다.

## 그래도 안 돌아오면

Windows 확장 모드를 강제로 적용합니다.

```text
Win + R
DisplaySwitch.exe /extend
```

그래픽 드라이버 리셋도 시도할 수 있습니다.

```text
Win + Ctrl + Shift + B
```

그다음 다시 `DisplaySwitch.exe /extend`를 실행합니다.

## BIOS/부팅 화면은 보이는데 Windows 로그인부터 검은 화면인 경우

하드웨어/케이블보다 Windows 디스플레이 토폴로지 문제일 가능성이 높습니다.

Windows 복구 환경에서 안전 모드로 진입합니다.

1. Windows 부팅을 몇 차례 중단해 복구 환경 진입
2. 고급 옵션 -> 문제 해결 -> 고급 옵션 -> 시작 설정 -> 다시 시작
3. 안전 모드 선택
4. 장치 관리자 실행
5. `Virtual Display Driver` / VDD by MTT를 **사용 안 함**으로 변경
6. 정상 재부팅

복구 후에는 Moonlight를 다시 연결하기 전에 Sunshine 명령 준비 설정부터 수정하세요.

## 가장 중요한 규칙

Windows에서 물리 모니터가 연결 끊김 상태일 때 VDD를 먼저 끄지 마세요.

안전한 종료 순서:

```text
local.cfg 복원
-> 물리 모니터 복귀 확인
-> VDD OFF
```

이 순서가 화면 출력 0개 상태를 막는 핵심입니다.

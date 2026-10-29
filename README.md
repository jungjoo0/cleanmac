# cleanmac

맥이 느려진 원인을 진단하고 캐시/임시 파일 및 대용량 파일을 정리하는 Swift 도구입니다.
터미널 CLI(`cleanmac`)와 메뉴바 앱(`CleanMac.app`) 두 가지로 사용할 수 있으며, 진단/정리 로직은 `CleanMacCore` 라이브러리로 공유합니다.

## 빌드 및 설치

```bash
# CLI
swift build -c release
cp .build/release/cleanmac /usr/local/bin/   # 어디서든 실행하려면

# 메뉴바 앱 (CleanMac.app 생성)
./scripts/make-app.sh
open CleanMac.app
```

## 메뉴바 앱 (`CleanMac.app`)

메뉴바의 ✨ 아이콘(및 실시간 메모리 사용률 `%`)을 클릭하면 3개 탭으로 관리할 수 있습니다:

1. **상태 · 정리 탭**
   - CPU 로드 · 메모리 · 스왑 · 디스크 여유 공간을 게이지 바와 함께 한눈에 표시 (문제 항목은 주황색)
   - 진단 경고 목록 및 가동 시간 표시
   - 우측 상단 톱니바퀴(`⚙`)에서 **메뉴바 메모리 % 표시** 및 **10초 자동 새로고침** 토글 가능
   - **캐시 스캔** 버튼 → 정리 대상별 크기를 병렬로 빠르게 계산하고, 원하는 항목만 체크박스로 선택/해제하거나 폴더 아이콘을 눌러 Finder에서 바로 확인 가능
   - **휴지통 비우기 포함** 체크박스 → 휴지통도 정리 대상에 추가 (복구 불가)
   - **선택 항목 정리하기** 버튼 → 확인 후 선택한 캐시만 안전하게 삭제
2. **프로세스 탭**
   - CPU순 / 메모리순 상위 프로세스 및 PID 실시간 확인
   - 과점유 프로세스 옆의 `✕` 버튼으로 즉시 종료(`SIGTERM`) 가능
3. **대용량 파일 탭**
   - `~/Downloads` 폴더에서 50MB 이상인 대용량 파일/번들을 스캔하여 Finder에서 열거나 즉시 휴지통으로 이동 가능

로그인 시 자동 시작하려면: 시스템 설정 → 일반 → 로그인 항목에 `CleanMac.app` 추가.

## CLI 사용법

### 1. 진단 — 왜 느려졌는지 점검

```bash
cleanmac            # 또는 cleanmac diagnose
```

다음 항목을 네이티브 시스템 호출(`sysctlbyname`, `host_statistics64`, `getloadavg`)로 빠르게 점검하고 게이지 바와 경고를 표시합니다:

- **가동 시간** — 오래 재부팅하지 않았는지
- **CPU** — 로드 평균 게이지 바, CPU를 많이 쓰는 상위 5개 프로세스(PID 포함)
- **메모리** — 사용량 게이지 바, 압축 메모리, 스왑, 메모리 압박 수준, 상위 5개 프로세스(PID 포함)
- **디스크** — 여유 공간 게이지 바 (10% 미만이면 경고)
- **시작 항목** — 로그인 시 자동 실행되는 LaunchAgents/Daemons 목록

### 2. 정리 — 캐시/임시 파일 선택 및 삭제

```bash
cleanmac clean --dry-run            # 삭제하지 않고 크기만 확인 (먼저 실행해보세요)
cleanmac clean                      # 전체 삭제 또는 번호 선택(s) 후 삭제
cleanmac clean --interactive        # (-i) 삭제할 캐시 항목을 번호로 선택
cleanmac clean --only Xcode         # (-o) 특정 키워드가 포함된 캐시만 대상에 포함
cleanmac clean --exclude Homebrew   # (-e) 특정 키워드가 포함된 캐시는 제외
cleanmac clean --yes                # (-y) 확인 없이 바로 삭제
cleanmac clean --trash              # 휴지통 비우기도 포함
```

정리 대상 (`~/Library/Caches` 하위 개별 항목은 일반 앱 캐시 계산/삭제 시 자동 제외되어 중복 계산되지 않습니다):

| 대상 | 경로 |
|---|---|
| 사용자 앱 캐시 | `~/Library/Caches` (하위 분류 캐시 제외) |
| 사용자 로그 | `~/Library/Logs` |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| Xcode iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` |
| Xcode 시뮬레이터 캐시 | `~/Library/Developer/CoreSimulator/Caches` |
| SwiftPM 캐시 | `~/Library/Caches/org.swift.swiftpm` |
| Homebrew 캐시 | `~/Library/Caches/Homebrew` |
| npm 캐시 | `~/.npm/_cacache` |
| Yarn 캐시 | `~/Library/Caches/Yarn` |
| pnpm 캐시 | `~/Library/Caches/pnpm` |
| CocoaPods 캐시 | `~/Library/Caches/CocoaPods` |
| pip 캐시 | `~/Library/Caches/pip` |
| Gradle 캐시 | `~/.gradle/caches` |
| Cargo 캐시 | `~/.cargo/registry/cache` |
| 휴지통 (`--trash` 옵션 시) | `~/.Trash` |

### 3. 대용량 파일 탐색 (`~/Downloads`)

```bash
cleanmac large                 # ~/Downloads 내 50MB 이상 파일 목록 확인
cleanmac large --min-mb 100    # 100MB 이상 파일만 확인
cleanmac large -i              # 번호를 선택해 휴지통으로 바로 이동
```

시스템 디렉터리는 절대 건드리지 않으며, 사용 중이거나 보호된 파일은 자동으로 건너뜁니다.

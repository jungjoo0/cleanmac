# cleanmac

맥이 느려진 원인을 진단하고 캐시/임시 파일을 정리하는 Swift 도구입니다.
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

## 메뉴바 앱

메뉴바의 ✨ 아이콘을 클릭하면:

- CPU 로드 · 메모리 · 스왑 · 디스크 여유 공간을 한눈에 표시 (문제 항목은 주황색)
- 진단 경고 목록 표시
- **캐시 스캔** 버튼 → 정리 대상별 크기와 합계 표시
- **휴지통 비우기 포함** 체크박스 → 휴지통도 정리 대상에 추가 (복구 불가)
  - 휴지통은 macOS 보호 폴더라 Finder를 통해 비웁니다. 처음 사용할 때 "CleanMac이(가) Finder를 제어하려고 합니다" 권한 요청이 뜨면 **허용**을 눌러야 합니다.
- **정리하기** 버튼 → 확인 후 삭제, 확보한 용량 표시

로그인 시 자동 시작하려면: 시스템 설정 → 일반 → 로그인 항목에 `CleanMac.app` 추가.

## 사용법

### 진단 — 왜 느려졌는지 점검

```bash
cleanmac            # 또는 cleanmac diagnose
```

다음 항목을 점검하고 문제가 있으면 요약에 경고로 표시합니다:

- **가동 시간** — 오래 재부팅하지 않았는지
- **CPU** — 로드 평균, CPU를 많이 쓰는 상위 5개 프로세스
- **메모리** — 사용량, 압축 메모리, 스왑, 메모리 압박 수준, 상위 5개 프로세스
- **디스크** — 여유 공간 (10% 미만이면 경고)
- **시작 항목** — 로그인 시 자동 실행되는 LaunchAgents/Daemons 목록

### 정리 — 캐시/임시 파일 삭제

```bash
cleanmac clean --dry-run   # 삭제하지 않고 크기만 확인 (먼저 이걸 실행해보세요)
cleanmac clean             # 확인 후 삭제
cleanmac clean --yes       # 확인 없이 바로 삭제
cleanmac clean --trash     # 휴지통 비우기도 포함
```

정리 대상 (모두 사용자 홈 아래의 안전한 캐시 위치만):

| 대상 | 경로 |
|---|---|
| 사용자 앱 캐시 | `~/Library/Caches` |
| 사용자 로그 | `~/Library/Logs` |
| npm 캐시 | `~/.npm/_cacache` |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| CocoaPods 캐시 | `~/Library/Caches/CocoaPods` |
| Homebrew 캐시 | `~/Library/Caches/Homebrew` |
| pip 캐시 | `~/Library/Caches/pip` |
| 휴지통 (`--trash` 옵션 시) | `~/.Trash` |

시스템 디렉터리는 절대 건드리지 않으며, 사용 중이거나 보호된 파일은 자동으로 건너뜁니다.

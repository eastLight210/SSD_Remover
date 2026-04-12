# SSD Remover

[English](README.md)

macOS 메뉴바 유틸리티로, 외장 SSD/디스크를 안전하게 추출할 수 있도록 도와줍니다.

디스크를 사용 중인 프로세스를 자동으로 탐지하고, 선택적으로 종료한 뒤 안전하게 추출합니다.

## 스크린샷

| 볼륨 목록 | 프로세스 목록 |
|:-:|:-:|
| ![볼륨 목록](screenshots/volume-list.png) | ![프로세스 목록](screenshots/process-list.png) |

## 주요 기능

- **메뉴바 상주** - 메뉴바 아이콘으로 빠르게 접근
- **외장 디스크 자동 감지** - 연결된 외장 디스크를 실시간으로 탐지
- **차단 프로세스 스캔** - `lsof`를 사용하여 디스크를 점유하고 있는 프로세스를 식별
- **프로세스 분류** - Spotlight, 시스템, 사용자 프로세스로 자동 분류
- **선택적 프로세스 종료** - 체크박스로 종료할 프로세스를 선택
- **안전한 종료 절차** - SIGTERM 후 대기, 미종료 시 SIGKILL 적용
- **권한 상승** - root 프로세스 종료 시 관리자 권한 요청
- **Spotlight 경고** - mds/mds_stores 프로세스 감지 시 경고 배너 표시
- **로그인 시 자동 실행** - 시스템 시작 시 자동 실행 설정
- **CLI 모드** - 터미널에서 자동화 용도로 사용 가능

## 설치

1. [최신 릴리즈](https://github.com/eastLight210/SSD_Remover/releases/latest)에서 `SSD_Remover.zip` 다운로드
2. 압축 해제
3. `SSD_Remover.app`을 Applications 폴더로 이동
4. 처음 실행 시 "확인되지 않은 개발자" 경고가 뜨면 우클릭 > 열기로 실행

## 요구 사항

- macOS 14.0 (Sonoma) 이상

## 소스에서 빌드

Xcode 26.0 이상, Swift 6.2 필요.

[XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 프로젝트를 생성합니다.

```bash
# XcodeGen 설치 (미설치 시)
brew install xcodegen

# Xcode 프로젝트 생성
xcodegen generate

# Xcode에서 열기
open SSD_Remover.xcodeproj
```

## 프로젝트 구조

```
SSD_Remover/
├── App/              # 앱 진입점, 부트스트랩, 실행 모드 감지
├── Models/           # ExternalVolume, BlockingProcess, ProcessGroup
├── Services/         # 쉘 실행, 볼륨 모니터링, 프로세스 스캔/종료, 디스크 추출
│   └── Protocols/    # 서비스 인터페이스 (테스트를 위한 DI)
├── ViewModels/       # AppViewModel, EjectViewModel (상태 머신)
├── Views/            # SwiftUI 뷰 (볼륨 목록, 프로세스 목록, 진행 상황)
├── Utilities/        # lsof/diskutil 파서, 프로세스 분류기
├── CLI/              # CLI 명령어 파서 및 실행기
└── Resources/        # Info.plist, Assets
```

## 아키텍처

**MVVM + Service Layer** 패턴을 사용합니다.

- **@Observable ViewModel** - 상태 관리 및 UI 바인딩
- **Actor 기반 Services** - Swift Concurrency를 활용한 안전한 동시성 처리
- **Protocol 기반 DI** - 테스트 용이성을 위한 의존성 주입

## CLI 사용법

```bash
# 외장 볼륨 목록
SSD_Remover --list-volumes

# 특정 볼륨의 차단 프로세스 스캔
SSD_Remover --scan <볼륨경로>

# 프로세스 종료 후 추출
SSD_Remover --terminate-and-eject <볼륨경로>

# 도움말
SSD_Remover --help
```

## 테스트

```bash
xcodebuild test -scheme SSD_Remover -destination 'platform=macOS'
```

## 라이선스

MIT License

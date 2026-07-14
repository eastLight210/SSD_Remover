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

### CLI 명령 설치(선택 사항)

릴리스 앱에는 CLI 실행 파일이 포함되어 있습니다. `PATH`에서 사용할 안정적인
`ssd-remover` 명령을 생성합니다.

```bash
sudo mkdir -p /usr/local/bin
sudo ln -sfn "/Applications/SSD_Remover.app/Contents/MacOS/SSD_Remover" /usr/local/bin/ssd-remover
ssd-remover --help
```

앱을 다른 위치에 설치했다면 `/Applications/SSD_Remover.app`을 실제 경로로 바꾸세요.
앱은 그대로 두고 CLI 명령만 제거하려면 다음을 실행합니다.

```bash
sudo rm /usr/local/bin/ssd-remover
```

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
ssd-remover list

# 차단 프로세스와 잠긴 파일 스캔
ssd-remover scan <볼륨-쿼리>

# 선택한 프로세스 종료(--group과 --pid는 반복 가능)
ssd-remover terminate <볼륨-쿼리> --group user
ssd-remover terminate <볼륨-쿼리> --pid 123 --pid 456

# 변경 없이 전체 대상 미리보기
ssd-remover terminate-and-eject <볼륨-쿼리> --dry-run

# 모든 차단 프로세스를 명시적으로 종료한 뒤 추출
ssd-remover terminate-and-eject <볼륨-쿼리> --all

# 프로세스를 종료하지 않고 추출
ssd-remover eject <볼륨-쿼리>

# 안정적인 기계 판독용 출력
ssd-remover scan <볼륨-쿼리> --json

# 버전과 도움말
ssd-remover version
ssd-remover help
ssd-remover terminate --help
```

`<볼륨-쿼리>`에는 디바이스 식별자, 정확한 마운트 경로, 볼륨 이름 또는 고유한
대소문자 무시 부분 일치를 사용할 수 있습니다. 여러 볼륨이 일치하면 후보와 함께
오류를 반환합니다.

`terminate`와 `terminate-and-eject`에서 반복된 그룹끼리, 반복된 PID끼리 각각 합쳐지고,
그룹과 PID를 함께 쓰면 교집합이 선택됩니다. 필터가 없을 때는 프로세스에 시그널을
보내기 전에 `--all`이 필요합니다. `--dry-run`은 시그널 전송이나 디스크 추출 없이
해석된 볼륨과 대상을 안전하게 출력합니다. 기본 유예 시간은 3초이며
`--grace-period <초>`로 변경할 수 있습니다.

모든 운영 명령(`list`, `scan`, `terminate`, `eject`, `terminate-and-eject`)은 `--json`을
지원합니다. JSON 최상위 계약은 다음과 같습니다.

```json
{
  "schemaVersion": 1,
  "success": true,
  "command": "scan",
  "data": {}
}
```

성공한 명령 결과는 stdout에 기록됩니다. JSON 모드의 사용법·사전 검사 오류는 구조화된
객체로 stderr에 기록됩니다. 프로세스별 종료 또는 추출 실패가 있는 완료 결과도 stdout의
구조를 유지하고 0이 아닌 코드로 종료합니다. `scan` JSON에는 해석된 볼륨 메타데이터,
프로세스 카테고리, PID, 사용자, UID, 명령, root 소유 여부와 중복 제거된 잠긴 파일
경로가 포함됩니다.

종료 코드는 성공 `0`, 런타임·작업 실패 `1`, 명령행 사용법 오류 `64`입니다.

## 테스트

```bash
xcodebuild test -scheme SSD_Remover -destination 'platform=macOS'

# 빌드한 릴리스 앱을 설치된 명령 경로로 호출할 수 있는지 검증
script/test_cli_installation.sh \
  /path/to/SSD_Remover.app/Contents/MacOS/SSD_Remover
```

## 라이선스

MIT License

# SSD Remover - macOS 메뉴바 앱

## Context
외장 SSD를 제거할 때 "사용 중인 프로세스가 있어 제거할 수 없습니다" 에러가 빈번하게 발생.
어떤 프로세스가 디스크를 잡고 있는지 파악하고, 선택적으로 종료한 뒤 안전하게 제거하는 메뉴바 유틸리티 앱을 만든다.

## 기술 스택
- **SwiftUI** + MenuBarExtra (macOS 13+ 네이티브)
- **Xcode 프로젝트** (sandbox 비활성화, LSUIElement=YES)
- Swift Concurrency (async/await)

## 핵심 기능
1. 메뉴바 상주 → 클릭 시 팝오버 윈도우
2. 연결된 외장 디스크 자동 감지 (FileManager + diskutil + NSWorkspace 알림)
3. `lsof -F pcLun` 으로 해당 볼륨을 잡고 있는 프로세스 스캔
4. 프로세스 목록을 그룹별(Spotlight/시스템/사용자) 체크박스로 표시
5. 선택된 프로세스 종료 (SIGTERM → 3초 대기 → SIGKILL)
6. root 프로세스는 NSAppleScript `with administrator privileges`로 권한 상승
7. 종료 후 `diskutil eject`로 안전 제거
8. Spotlight(mds/mds_stores) 차단 시 별도 경고 배너

## UI 흐름
```
[메뉴바 아이콘 클릭]
    → 외장 디스크 목록 (VolumeListView)
        → 디스크 선택 → 프로세스 스캔
            → 프로세스 목록 + 체크박스 (ProcessListView)
                → "종료 & 제거" 버튼
                    → 진행 상황 표시 (EjectProgressView)
                        → 성공/실패 결과
```

## 프로젝트 구조
```
SSD_Remover/
├── SSD_Remover.xcodeproj/
├── SSD_Remover/
│   ├── App/
│   │   ├── SSDRemoverApp.swift          ← @main, MenuBarExtra 정의
│   │   └── Info.plist                   ← LSUIElement=YES
│   ├── Assets.xcassets/                 ← 메뉴바 아이콘
│   ├── Models/
│   │   ├── ExternalVolume.swift         ← 볼륨 데이터 모델
│   │   ├── BlockingProcess.swift        ← 프로세스 정보 모델
│   │   └── ProcessGroup.swift           ← 그룹(Spotlight/시스템/사용자)
│   ├── Services/
│   │   ├── ShellExecutor.swift          ← Process async 래퍼 (actor)
│   │   ├── VolumeMonitorService.swift   ← 외장 볼륨 감지/모니터링
│   │   ├── ProcessScannerService.swift  ← lsof 실행 + 파싱
│   │   ├── ProcessTerminatorService.swift ← 프로세스 종료 (SIGTERM/SIGKILL)
│   │   ├── DiskEjectService.swift       ← diskutil eject 실행
│   │   └── PrivilegedExecutor.swift     ← AppleScript 권한 상승
│   ├── ViewModels/
│   │   ├── AppViewModel.swift           ← 전체 상태 관리 + 네비게이션
│   │   ├── ProcessListViewModel.swift   ← 프로세스 스캔/선택 상태
│   │   └── EjectViewModel.swift         ← 종료→제거 상태머신
│   ├── Views/
│   │   ├── ContentView.swift            ← 루트 뷰 (라우터)
│   │   ├── VolumeListView.swift         ← 외장 디스크 목록
│   │   ├── VolumeRowView.swift          ← 디스크 행 (이름, 용량, 파일시스템)
│   │   ├── ProcessListView.swift        ← 프로세스 목록 + 체크박스
│   │   ├── ProcessRowView.swift         ← 프로세스 행 (이름, PID, 잠금 아이콘)
│   │   ├── SpotlightWarningView.swift   ← Spotlight 차단 경고 배너
│   │   ├── EjectProgressView.swift      ← 종료/제거 진행 상황
│   │   └── EmptyStateView.swift         ← 빈 상태 안내
│   └── Utilities/
│       ├── LsofOutputParser.swift       ← lsof -F 출력 파싱
│       ├── DiskInfoParser.swift         ← diskutil info -plist 파싱
│       └── ProcessClassifier.swift      ← 프로세스 분류 (시스템/사용자/Spotlight)
```

## 구현 순서

### Phase 1: 프로젝트 기반 구축
- Xcode 프로젝트 생성 (또는 파일 직접 작성)
- `SSDRemoverApp.swift`: MenuBarExtra + .window 스타일 설정
- Info.plist: LSUIElement=YES, 엔타이틀먼트 설정
- `ShellExecutor.swift`: Foundation.Process를 async/await로 감싸는 actor
- `Constants.swift`: 도구 경로 (/usr/sbin/lsof, /usr/sbin/diskutil)

### Phase 2: 외장 볼륨 감지
- `ExternalVolume` 모델
- `DiskInfoParser`: `diskutil info -plist` XML 파싱
- `VolumeMonitorService`: FileManager.mountedVolumeURLs + NSWorkspace 알림
- `VolumeListView`, `VolumeRowView`, `EmptyStateView`
- `ContentView` 라우팅 기본 구조

### Phase 3: 프로세스 스캔
- `BlockingProcess`, `ProcessGroup` 모델
- `LsofOutputParser`: lsof -F 필드 형식 파싱 (p=PID, c=command, L=user, u=uid, n=file)
- `ProcessClassifier`: Spotlight/시스템/사용자 분류
- `ProcessScannerService`: lsof 실행 + 파싱 + 필터링
- `ProcessListView`, `ProcessRowView`, `SpotlightWarningView`
- `ProcessListViewModel`: 스캔/선택 상태 관리

### Phase 4: 종료 및 제거
- `PrivilegedExecutor`: NSAppleScript로 관리자 권한 실행
- `ProcessTerminatorService`: SIGTERM → 3초 대기 → SIGKILL (사용자/root 분기)
- `DiskEjectService`: diskutil eject 실행
- `EjectViewModel`: 상태머신 (확인 → 종료 중 → 제거 중 → 완료/실패)
- `EjectProgressView`: 진행 상황 UI
- 종료 전 확인 알림

### Phase 5: 마무리
- 볼륨 작업 중 분리 감지 처리
- 차단 프로세스 없을 때 "바로 제거" 버튼
- 에러 처리 및 로깅 (os.Logger)
- 여러 외장 볼륨 동시 연결 테스트

## 핵심 구현 패턴

### lsof 실행 방식
```swift
// lsof -F pcLun /Volumes/외장SSD
// 출력: p<PID>\nc<command>\nL<user>\nu<uid>\nn<filepath>
shellExecutor.run("/usr/sbin/lsof", arguments: ["-F", "pcLun", volume.mountPoint])
```

### 권한 상승 (root 프로세스 종료)
```swift
// NSAppleScript로 macOS 기본 비밀번호 대화상자 표시
let script = NSAppleScript(source: "do shell script \"kill -TERM \(pid)\" with administrator privileges")
```

### 안전 제거
```swift
// 전체 디스크 단위로 eject (볼륨이 아닌 disk 번호 사용)
shellExecutor.run("/usr/sbin/diskutil", arguments: ["eject", volume.parentWholeDisk])
```

## 세션 분리 권장
- 작업량이 상당하므로 Phase 1~2 / Phase 3~4 / Phase 5 로 **3개 세션**에 나눠 진행 권장
- 각 세션 종료 시 빌드 가능한 상태를 유지

## 검증 방법
1. USB 외장 SSD 연결 후 메뉴바 앱에서 볼륨이 표시되는지 확인
2. 해당 볼륨에서 파일을 열어둔 상태에서 프로세스 스캔 → 해당 앱이 목록에 나오는지 확인
3. 프로세스 선택 종료 후 diskutil eject가 성공하는지 확인
4. Spotlight가 인덱싱 중인 볼륨에서 mds 프로세스 감지 + 경고 배너 표시 확인
5. 차단 프로세스가 없는 볼륨에서 바로 제거 동작 확인

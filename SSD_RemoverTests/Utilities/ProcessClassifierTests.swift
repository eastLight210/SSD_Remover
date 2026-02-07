import Testing
@testable import SSD_Remover

@Suite("ProcessClassifier Tests")
struct ProcessClassifierTests {

    @Test("빈 프로세스 배열은 빈 그룹을 반환한다")
    func emptyProcesses() {
        let result = ProcessClassifier.classify([])
        #expect(result.isEmpty)
    }

    @Test("mds 프로세스는 spotlight 그룹에 분류된다")
    func mdsIsSpotlight() {
        let process = BlockingProcess(pid: 1, command: "mds", user: "root", uid: 0, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .spotlight)
        #expect(result[0].processes.count == 1)
    }

    @Test("mds_stores 프로세스는 spotlight 그룹에 분류된다")
    func mdsStoresIsSpotlight() {
        let process = BlockingProcess(pid: 2, command: "mds_stores", user: "root", uid: 0, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .spotlight)
    }

    @Test("uid=0이고 비-Spotlight인 프로세스는 system 그룹에 분류된다")
    func rootNonSpotlightIsSystem() {
        let process = BlockingProcess(pid: 3, command: "launchd", user: "root", uid: 0, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .system)
    }

    @Test("uid != 0인 프로세스는 user 그룹에 분류된다")
    func nonRootIsUser() {
        let process = BlockingProcess(pid: 4, command: "vim", user: "user", uid: 501, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .user)
    }

    @Test("혼합된 프로세스를 올바르게 분류한다")
    func mixedProcesses() {
        let processes = [
            BlockingProcess(pid: 1, command: "mds", user: "root", uid: 0, lockedFiles: []),
            BlockingProcess(pid: 2, command: "mds_stores", user: "root", uid: 0, lockedFiles: []),
            BlockingProcess(pid: 3, command: "launchd", user: "root", uid: 0, lockedFiles: []),
            BlockingProcess(pid: 4, command: "vim", user: "user", uid: 501, lockedFiles: []),
            BlockingProcess(pid: 5, command: "finder", user: "user", uid: 501, lockedFiles: []),
        ]
        let result = ProcessClassifier.classify(processes)
        #expect(result.count == 3)

        let spotlightGroup = result.first { $0.category == .spotlight }
        let systemGroup = result.first { $0.category == .system }
        let userGroup = result.first { $0.category == .user }

        #expect(spotlightGroup?.processes.count == 2)
        #expect(systemGroup?.processes.count == 1)
        #expect(userGroup?.processes.count == 2)
    }

    @Test("빈 그룹은 결과에 포함되지 않는다")
    func emptyGroupsExcluded() {
        let processes = [
            BlockingProcess(pid: 1, command: "vim", user: "user", uid: 501, lockedFiles: []),
        ]
        let result = ProcessClassifier.classify(processes)
        #expect(result.count == 1)
        #expect(result[0].category == .user)
    }

    @Test("분류 결과의 기본 isSelected는 true")
    func defaultIsSelected() {
        let process = BlockingProcess(pid: 1, command: "mds", user: "root", uid: 0, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result[0].isSelected == true)
    }

    @Test("대문자 MDS는 system 그룹 (spotlightCommands는 소문자 전용, 의도적 설계)")
    func uppercaseMDSIsNotSpotlight() {
        // macOS Spotlight 프로세스는 항상 소문자(mds, mds_stores)로 실행됨
        // 따라서 대소문자 구분 매칭이 올바른 동작
        let process = BlockingProcess(pid: 10, command: "MDS", user: "root", uid: 0, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .system)
    }

    @Test("uid 음수값(-2)은 user 그룹으로 분류")
    func negativeUidIsUser() {
        let process = BlockingProcess(pid: 11, command: "nobody_proc", user: "nobody", uid: -2, lockedFiles: [])
        let result = ProcessClassifier.classify([process])
        #expect(result.count == 1)
        #expect(result[0].category == .user)
    }
}

import Testing
import Foundation
@testable import SSD_Remover

@Suite("EjectViewModel Tests")
struct EjectViewModelTests {

    // MARK: - Helpers

    private func makeSampleVolume() -> ExternalVolume {
        let url = URL(fileURLWithPath: "/Volumes/TestDrive")
        return ExternalVolume(
            id: url,
            name: "TestDrive",
            deviceIdentifier: "disk4s1",
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: url
        )
    }

    private func makeProcess(
        pid: Int32 = 100,
        command: String = "testcmd",
        user: String = "testuser",
        uid: Int32 = 501,
        lockedFiles: [String] = ["/Volumes/TestDrive/file.txt"]
    ) -> BlockingProcess {
        BlockingProcess(pid: pid, command: command, user: user, uid: uid, lockedFiles: lockedFiles)
    }

    private func makeGroups(
        includeSpotlight: Bool = false,
        includeUser: Bool = true
    ) -> [ProcessGroup] {
        var groups: [ProcessGroup] = []
        if includeSpotlight {
            groups.append(ProcessGroup(
                category: .spotlight,
                processes: [makeProcess(pid: 369, command: "mds", user: "root", uid: 0)]
            ))
        }
        if includeUser {
            groups.append(ProcessGroup(
                category: .user,
                processes: [
                    makeProcess(pid: 100, command: "vim"),
                    makeProcess(pid: 200, command: "code")
                ]
            ))
        }
        return groups
    }

    // MARK: - 초기 상태

    @Test("초기 상태는 confirming 페이즈")
    @MainActor
    func initialPhaseIsConfirming() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        #expect(vm.phase == .confirming)
    }

    // MARK: - 그룹 선택

    @Test("모든 그룹이 기본 선택됨")
    @MainActor
    func allGroupsSelectedByDefault() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: true, includeUser: true),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        #expect(vm.processGroups.allSatisfy { $0.isSelected })
    }

    @Test("그룹 선택 토글")
    @MainActor
    func toggleGroupSelection() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        vm.toggleGroupSelection(category: .user)
        #expect(vm.processGroups.first(where: { $0.category == .user })?.isSelected == false)

        vm.toggleGroupSelection(category: .user)
        #expect(vm.processGroups.first(where: { $0.category == .user })?.isSelected == true)
    }

    @Test("존재하지 않는 카테고리 토글은 무시")
    @MainActor
    func toggleNonexistentCategory() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        vm.toggleGroupSelection(category: .spotlight)
        #expect(vm.processGroups.count == 1)
    }

    // MARK: - selectedProcesses

    @Test("선택된 그룹의 프로세스만 반환")
    @MainActor
    func selectedProcessesReturnsOnlySelected() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: true, includeUser: true),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        // 초기: 모두 선택 → spotlight(1) + user(2) = 3
        #expect(vm.selectedProcesses.count == 3)

        // spotlight 해제 → user(2)만
        vm.toggleGroupSelection(category: .spotlight)
        #expect(vm.selectedProcesses.count == 2)
    }

    // MARK: - hasSpotlightProcesses

    @Test("Spotlight 그룹이 있으면 true")
    @MainActor
    func hasSpotlightWhenPresent() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: true),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        #expect(vm.hasSpotlightProcesses == true)
    }

    @Test("Spotlight 그룹이 없으면 false")
    @MainActor
    func noSpotlightWhenAbsent() {
        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false),
            processTerminator: MockProcessTerminator(),
            diskEjector: MockDiskEjector()
        )

        #expect(vm.hasSpotlightProcesses == false)
    }

    // MARK: - terminateAndEject

    @Test("프로세스 종료 후 eject 성공")
    @MainActor
    func terminateAndEjectSuccess() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.phase == .success)
        #expect(mockTerminator.terminatedProcesses.count == 2)
        #expect(mockEjector.ejectCalled)
    }

    @Test("프로세스 없이 바로 eject")
    @MainActor
    func ejectWithoutProcesses() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: [],
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.phase == .success)
        #expect(mockTerminator.terminatedProcesses.isEmpty)
        #expect(mockEjector.ejectCalled)
    }

    @Test("eject 실패 시 failure 페이즈")
    @MainActor
    func ejectFailure() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .failed("Disk is busy")

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.phase == .failure("Disk is busy"))
    }

    @Test("선택 해제된 그룹은 종료 대상에서 제외")
    @MainActor
    func deselectedGroupsNotTerminated() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: true, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        // spotlight 해제
        vm.toggleGroupSelection(category: .spotlight)

        await vm.terminateAndEject(gracePeriod: 0)

        // user 그룹의 2개만 종료
        #expect(mockTerminator.terminatedProcesses.count == 2)
        #expect(vm.phase == .success)
    }

    // MARK: - 종료 실패 추적

    @Test("프로세스 종료 실패 시 failedTerminations에 기록")
    @MainActor
    func terminationFailureTracked() async {
        let mockTerminator = MockProcessTerminator()
        mockTerminator.stubbedResults = [100: .terminated, 200: .failed("Permission denied")]
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.failedTerminations.count == 1)
        #expect(vm.failedTerminations[200] == "Permission denied")
        #expect(mockEjector.ejectCalled)
    }

    @Test("모든 그룹 선택 해제 시 바로 eject")
    @MainActor
    func noSelectedProcessesSkipsTermination() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        vm.toggleGroupSelection(category: .user)

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(mockTerminator.terminatedProcesses.isEmpty)
        #expect(mockEjector.ejectCalled)
        #expect(vm.phase == .success)
    }

    // MARK: - retry()

    @Test("retry() 호출 시 전체 흐름 재실행 → success")
    @MainActor
    func retryAfterFailureSucceeds() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .failed("Disk is busy")

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        // 첫 번째 시도 → 실패
        await vm.terminateAndEject(gracePeriod: 0)
        #expect(vm.phase == .failure("Disk is busy"))

        // 재시도 → 성공
        mockEjector.stubbedResult = .success
        await vm.retry(gracePeriod: 0)

        #expect(vm.phase == .success)
        #expect(vm.failedTerminations.isEmpty)
    }

    @Test("retry() 후에도 실패하면 failure 상태 유지")
    @MainActor
    func retryAfterFailureStillFails() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .failed("Disk is busy")

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: makeGroups(includeSpotlight: false, includeUser: true),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)
        #expect(vm.phase == .failure("Disk is busy"))

        mockEjector.stubbedResult = .failed("Still busy")
        await vm.retry(gracePeriod: 0)

        #expect(vm.phase == .failure("Still busy"))
    }
}

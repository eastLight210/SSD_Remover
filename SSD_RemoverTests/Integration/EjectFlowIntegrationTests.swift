import Testing
import Foundation
@testable import SSD_Remover

@Suite("EjectViewModel Flow Integration Tests")
struct EjectFlowIntegrationTests {

    private func makeSampleVolume() -> ExternalVolume {
        let url = URL(fileURLWithPath: "/Volumes/TestDrive")
        return ExternalVolume(
            id: url, name: "TestDrive", deviceIdentifier: "disk4s1",
            fileSystem: "APFS", totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000, mountPoint: url
        )
    }

    @Test("전체 흐름: confirming → terminatingProcesses → ejecting → success")
    @MainActor
    func fullFlowSuccess() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .success

        let processes = [
            BlockingProcess(pid: 100, command: "vim", user: "user", uid: 501, lockedFiles: ["/file1"]),
            BlockingProcess(pid: 200, command: "code", user: "user", uid: 501, lockedFiles: ["/file2"]),
        ]
        let groups = [ProcessGroup(category: .user, processes: processes)]

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: groups,
            processScanner: MockProcessScanner(),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        #expect(vm.phase == .confirming)

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.phase == .success)
        #expect(mockTerminator.terminatedProcesses.count == 2)
        #expect(mockEjector.ejectCalled)
    }

    @Test("전체 흐름: confirming → terminatingProcesses → ejecting → failure")
    @MainActor
    func fullFlowFailure() async {
        let mockTerminator = MockProcessTerminator()
        let mockEjector = MockDiskEjector()
        mockEjector.stubbedResult = .failed("Disk is busy")

        let processes = [
            BlockingProcess(pid: 100, command: "vim", user: "user", uid: 501, lockedFiles: ["/file"]),
        ]
        let groups = [ProcessGroup(category: .user, processes: processes)]

        let vm = EjectViewModel(
            volume: makeSampleVolume(),
            processGroups: groups,
            processScanner: MockProcessScanner(),
            processTerminator: mockTerminator,
            diskEjector: mockEjector
        )

        await vm.terminateAndEject(gracePeriod: 0)

        #expect(vm.phase == .failure("Disk is busy"))
        #expect(mockTerminator.terminatedProcesses.count == 1)
    }
}

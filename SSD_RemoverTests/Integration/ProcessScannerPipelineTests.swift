import Testing
import Foundation
@testable import SSD_Remover

@Suite("ProcessScanner Pipeline Integration Tests")
struct ProcessScannerPipelineTests {

    @Test("lsof 출력 → 파싱 → 분류 전체 파이프라인")
    func fullPipeline() async throws {
        let mockShell = MockShellExecutor()
        // 줄별 multiline string — 각 줄이 실제 개행으로 구분됨
        mockShell.stubbedResult = """
        p100
        cmds
        u0
        Lroot
        n/Volumes/SSD/.Spotlight-V100/store.db
        p200
        claunchd
        u0
        Lroot
        n/Volumes/SSD/daemon.sock
        p300
        cvim
        u501
        Luser
        n/Volumes/SSD/doc.txt
        n/Volumes/SSD/notes.md
        p400
        cmds_stores
        u0
        Lroot
        n/Volumes/SSD/.Spotlight-V100/index
        """

        let service = ProcessScannerService(shell: mockShell)
        let volume = ExternalVolume(
            id: URL(fileURLWithPath: "/Volumes/SSD"),
            name: "SSD", deviceIdentifier: "disk4s1",
            fileSystem: "APFS", totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            mountPoint: URL(fileURLWithPath: "/Volumes/SSD")
        )

        let groups = try await service.scanProcesses(for: volume)

        // spotlight: mds(100) + mds_stores(400) = 2
        // system: launchd(200) = 1
        // user: vim(300) = 1
        #expect(groups.count == 3)
        let spotlight = groups.first { $0.category == .spotlight }
        let system = groups.first { $0.category == .system }
        let user = groups.first { $0.category == .user }
        #expect(spotlight?.processes.count == 2)
        #expect(system?.processes.count == 1)
        #expect(user?.processes.count == 1)
        #expect(user?.processes[0].lockedFiles.count == 2)
    }
}

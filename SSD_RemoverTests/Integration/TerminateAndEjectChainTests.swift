import Testing
import Foundation
@testable import SSD_Remover

@Suite("Terminate and Eject Chain Integration Tests")
struct TerminateAndEjectChainTests {

    @Test("프로세스 종료 후 디스크 제거 순서 검증")
    func terminateThenEject() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // kill -15 성공 → kill -0 실패(종료됨) → diskutil eject 성공
        mockShell.stubbedResults = ["", "", "Disk disk4 ejected"]
        mockShell.stubbedErrors = [
            nil,
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),
            nil,
        ]

        let terminator = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let ejector = DiskEjectService(shell: mockShell)

        let process = BlockingProcess(pid: 1234, command: "vim", user: "user", uid: 501, lockedFiles: ["/Volumes/TestDrive/file.txt"])
        let volume = ExternalVolume(
            id: URL(fileURLWithPath: "/Volumes/TestDrive"),
            name: "TestDrive", deviceIdentifier: "disk4s1",
            fileSystem: "APFS", totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: URL(fileURLWithPath: "/Volumes/TestDrive")
        )

        // 1. 프로세스 종료
        let termResult = await terminator.terminate(process: process, gracePeriod: 0)
        #expect(termResult == .terminated)

        // 2. 디스크 제거
        let ejectResult = await ejector.eject(volume: volume)
        #expect(ejectResult == .success)

        // 순서 확인: kill -15, kill -0, diskutil eject
        #expect(mockShell.executedCommands.count == 3)
        #expect(mockShell.executedCommands[0].arguments.contains("-15"))
        #expect(mockShell.executedCommands[1].arguments.contains("-0"))
        #expect(mockShell.executedCommands[2].arguments.contains("eject"))
    }
}

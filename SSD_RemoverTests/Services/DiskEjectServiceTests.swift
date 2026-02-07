import Testing
import Foundation
@testable import SSD_Remover

@Suite("DiskEjectService Tests")
struct DiskEjectServiceTests {

    private func makeVolume(deviceIdentifier: String = "disk4s1") -> ExternalVolume {
        let url = URL(fileURLWithPath: "/Volumes/TestDrive")
        return ExternalVolume(
            id: url,
            name: "TestDrive",
            deviceIdentifier: deviceIdentifier,
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: url
        )
    }

    @Test("eject 성공")
    func ejectSuccess() async {
        let mockShell = MockShellExecutor()
        mockShell.stubbedResult = "Disk disk4 ejected"

        let service = DiskEjectService(shell: mockShell)
        let volume = makeVolume(deviceIdentifier: "disk4s1")
        let result = await service.eject(volume: volume)

        #expect(result == .success)
        #expect(mockShell.executedCommands.count == 1)
        #expect(mockShell.executedCommands[0].command == Constants.diskutilPath)
        #expect(mockShell.executedCommands[0].arguments == ["eject", "disk4"])
    }

    @Test("eject 실패 - shell error")
    func ejectFailure() async {
        let mockShell = MockShellExecutor()
        mockShell.stubbedError = ShellError.executionFailed(
            exitCode: 1,
            stderr: "Disk disk4 is in use by PID 1234"
        )

        let service = DiskEjectService(shell: mockShell)
        let result = await service.eject(volume: makeVolume())

        #expect(result == .failed("Disk disk4 is in use by PID 1234"))
    }

    @Test("eject 실패 - launch failed")
    func ejectLaunchFailure() async {
        let mockShell = MockShellExecutor()
        mockShell.stubbedError = ShellError.launchFailed("diskutil not found")

        let service = DiskEjectService(shell: mockShell)
        let result = await service.eject(volume: makeVolume())

        #expect(result == .failed("diskutil not found"))
    }

    @Test("whole disk 디바이스에서도 정상 동작")
    func ejectWholeDiskDevice() async {
        let mockShell = MockShellExecutor()
        mockShell.stubbedResult = "Disk disk2 ejected"

        let service = DiskEjectService(shell: mockShell)
        let volume = makeVolume(deviceIdentifier: "disk2")
        let result = await service.eject(volume: volume)

        #expect(result == .success)
        #expect(mockShell.executedCommands[0].arguments == ["eject", "disk2"])
    }
}

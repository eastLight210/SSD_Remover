import Testing
import Foundation
@testable import SSD_Remover

@Suite("ProcessScannerService Tests")
struct ProcessScannerServiceTests {

    private func makeSUT() -> (service: ProcessScannerService, shell: MockShellExecutor) {
        let shell = MockShellExecutor()
        let service = ProcessScannerService(shell: shell)
        return (service, shell)
    }

    private func makeVolume(name: String = "TestSSD", mountPath: String = "/Volumes/TestSSD") -> ExternalVolume {
        ExternalVolume(
            id: URL(fileURLWithPath: mountPath),
            name: name,
            deviceIdentifier: "disk2s1",
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            mountPoint: URL(fileURLWithPath: mountPath)
        )
    }

    @Test("lsof 명령을 올바른 인자로 실행한다")
    func executesLsofWithCorrectArguments() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = ""
        let volume = makeVolume()

        _ = try await service.scanProcesses(for: volume)

        #expect(shell.executedCommands.count == 1)
        #expect(shell.executedCommands[0].command == "/usr/sbin/lsof")
        #expect(shell.executedCommands[0].arguments == ["-F", "pcuLn", "+f", "--", "/Volumes/TestSSD"])
    }

    @Test("lsof 출력을 파싱하여 ProcessGroup으로 반환한다")
    func parsesLsofOutput() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = "p1234\ncmds\nu0\nLroot\nn/Volumes/TestSSD/.Spotlight-V100/store.db"
        let volume = makeVolume()

        let groups = try await service.scanProcesses(for: volume)

        #expect(groups.count == 1)
        #expect(groups[0].category == .spotlight)
        #expect(groups[0].processes[0].pid == 1234)
        #expect(groups[0].processes[0].command == "mds")
    }

    @Test("빈 lsof 출력은 빈 배열을 반환한다")
    func emptyLsofOutput() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = ""
        let volume = makeVolume()

        let groups = try await service.scanProcesses(for: volume)

        #expect(groups.isEmpty)
    }

    @Test("혼합된 프로세스를 올바르게 분류한다")
    func classifiesMixedProcesses() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = """
        p100
        cmds_stores
        u0
        Lroot
        n/Volumes/TestSSD/.Spotlight-V100/db
        p200
        claunchd
        u0
        Lroot
        n/Volumes/TestSSD/daemon.sock
        p300
        cvim
        u501
        Luser
        n/Volumes/TestSSD/doc.txt
        """
        let volume = makeVolume()

        let groups = try await service.scanProcesses(for: volume)

        #expect(groups.count == 3)
        let categories = groups.map(\.category)
        #expect(categories.contains(.spotlight))
        #expect(categories.contains(.system))
        #expect(categories.contains(.user))
    }

    @Test("shell 에러를 전파한다")
    func propagatesShellError() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedError = ShellError.executionFailed(exitCode: 2, stderr: "lsof failed")
        let volume = makeVolume()

        await #expect(throws: ShellError.self) {
            _ = try await service.scanProcesses(for: volume)
        }
    }

    // MARK: - Volume-scoped lsof Tests

    @Test("lsof에 볼륨 마운트 포인트 인자가 전달된다")
    func executesLsofWithVolumeMountPoint() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = ""
        let volume = makeVolume()

        _ = try await service.scanProcesses(for: volume)

        #expect(shell.executedCommands.count == 1)
        #expect(shell.executedCommands[0].command == "/usr/sbin/lsof")
        #expect(shell.executedCommands[0].arguments == ["-F", "pcuLn", "+f", "--", "/Volumes/TestSSD"])
    }

    @Test("공백/한글 포함 마운트 포인트도 lsof 인자에 올바르게 전달")
    func executesLsofWithSpecialCharacterMountPoint() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedResult = ""
        let volume = makeVolume(name: "삼성 T7", mountPath: "/Volumes/삼성 T7")

        _ = try await service.scanProcesses(for: volume)

        #expect(shell.executedCommands[0].arguments == ["-F", "pcuLn", "+f", "--", "/Volumes/삼성 T7"])
    }

    // MARK: - lsof Exit Code Handling Tests

    @Test("lsof exit code 1 (결과 없음) → 빈 배열 반환")
    func lsofExitCode1ReturnsEmptyArray() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedError = ShellError.executionFailed(exitCode: 1, stderr: "")
        let volume = makeVolume()

        let groups = try await service.scanProcesses(for: volume)

        #expect(groups.isEmpty)
    }

    @Test("lsof exit code 2 이상은 에러 전파")
    func lsofExitCode2OrHigherThrows() async throws {
        let (service, shell) = makeSUT()
        shell.stubbedError = ShellError.executionFailed(exitCode: 2, stderr: "permission denied")
        let volume = makeVolume()

        await #expect(throws: ShellError.self) {
            _ = try await service.scanProcesses(for: volume)
        }
    }
}

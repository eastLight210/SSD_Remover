import Testing
import Foundation
@testable import SSD_Remover

@Suite("ProcessTerminatorService Tests")
struct ProcessTerminatorServiceTests {

    private let userProcess = BlockingProcess(
        pid: 1234,
        command: "Finder",
        user: "testuser",
        uid: 501,
        lockedFiles: ["/Volumes/USB/file.txt"]
    )

    private let rootProcess = BlockingProcess(
        pid: 5678,
        command: "mds_stores",
        user: "root",
        uid: 0,
        lockedFiles: ["/Volumes/USB/.Spotlight-V100"]
    )

    // MARK: - SIGTERM 성공 케이스

    @Test("user 프로세스 SIGTERM 후 종료됨 → .terminated")
    func userProcessTerminatedBySigterm() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // 1st call: kill -15 → 성공
        // 2nd call: kill -0 → 실패 (프로세스 종료됨)
        mockShell.stubbedResults = [""]
        mockShell.stubbedErrors = [nil, ShellError.executionFailed(exitCode: 1, stderr: "No such process")]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockShell.executedCommands.count == 2)
        #expect(mockShell.executedCommands[0].arguments == ["-15", "1234"])
        #expect(mockShell.executedCommands[1].arguments == ["-0", "1234"])
        #expect(mockPrivileged.executedCommands.isEmpty)
    }

    // MARK: - SIGTERM 후 생존 → SIGKILL

    @Test("user 프로세스 SIGTERM 후 생존 → SIGKILL → .terminated")
    func userProcessRequiresSigkill() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // 1st call: kill -15 → 성공
        // 2nd call: kill -0 → 성공 (프로세스 생존)
        // 3rd call: kill -9 → 성공
        mockShell.stubbedResults = ["", "", ""]
        mockShell.stubbedErrors = [nil, nil, nil]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockShell.executedCommands.count == 3)
        #expect(mockShell.executedCommands[0].arguments == ["-15", "1234"])
        #expect(mockShell.executedCommands[1].arguments == ["-0", "1234"])
        #expect(mockShell.executedCommands[2].arguments == ["-9", "1234"])
    }

    // MARK: - 이미 종료된 프로세스

    @Test("SIGTERM 시 프로세스 없음 → .alreadyExited")
    func processAlreadyExited() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // 1st call: kill -15 → 실패 (No such process)
        mockShell.stubbedErrors = [ShellError.executionFailed(exitCode: 1, stderr: "No such process")]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .alreadyExited)
        #expect(mockShell.executedCommands.count == 1)
    }

    // MARK: - Root 프로세스

    @Test("root 프로세스 kill -0에서 No such process → SIGKILL 없이 .terminated")
    func rootProcessNotFoundAfterSigterm() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // kill -15는 privileged로 실행
        // kill -0는 일반 shell로 실행 → No such process (프로세스 종료됨)
        mockShell.stubbedErrors = [ShellError.executionFailed(exitCode: 1, stderr: "No such process")]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockPrivileged.executedCommands.count == 1)
        #expect(mockPrivileged.executedCommands[0].contains("kill -15 5678"))
        #expect(mockShell.executedCommands.count == 1)
        #expect(mockShell.executedCommands[0].arguments == ["-0", "5678"])
    }

    @Test("root 프로세스 kill -0에서 EPERM → 종료로 간주하지 않고 SIGKILL")
    func rootProcessPermissionDeniedDuringLivenessCheck() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // kill -15는 privileged로 성공하지만 일반 shell의 kill -0는 권한 부족
        mockShell.stubbedErrors = [
            ShellError.executionFailed(exitCode: 1, stderr: "Operation not permitted")
        ]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockShell.executedCommands.count == 1)
        #expect(mockShell.executedCommands[0].arguments == ["-0", "5678"])
        #expect(mockPrivileged.executedCommands.count == 2)
        #expect(mockPrivileged.executedCommands[0].contains("kill -15 5678"))
        #expect(mockPrivileged.executedCommands[1].contains("kill -9 5678"))
    }

    @Test("root 프로세스 SIGTERM 후 생존 → SIGKILL도 privileged")
    func rootProcessSigkillUsesPrivileged() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // kill -0은 일반 shell → 성공 (프로세스 생존)
        mockShell.stubbedResults = [""]
        mockShell.stubbedErrors = [nil]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        // privileged: kill -15, kill -9
        #expect(mockPrivileged.executedCommands.count == 2)
        #expect(mockPrivileged.executedCommands[0].contains("-15"))
        #expect(mockPrivileged.executedCommands[1].contains("-9"))
    }

    // MARK: - terminateAll

    @Test("terminateAll - 복수 프로세스 처리")
    func terminateAllProcesses() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // 프로세스1(user): kill -15 성공, kill -0 실패 → terminated
        // 프로세스2(root): kill -15 privileged 성공, kill -0 실패 → terminated
        mockShell.stubbedErrors = [
            nil,                                                                   // kill -15 pid1
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),    // kill -0 pid1
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),    // kill -0 pid2
        ]
        mockShell.stubbedResults = ["", "", ""]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let results = await service.terminateAll(
            processes: [userProcess, rootProcess],
            gracePeriod: 0
        )

        #expect(results.count == 2)
        #expect(results[userProcess.pid] == .terminated)
        #expect(results[rootProcess.pid] == .terminated)
    }

    // MARK: - 실패 케이스

    @Test("SIGTERM 실패 (권한 없음 등) → .failed")
    func sigtermFailure() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        mockShell.stubbedErrors = [ShellError.executionFailed(exitCode: 1, stderr: "Operation not permitted")]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .failed("Operation not permitted"))
    }

    @Test("root 프로세스 - 사용자가 권한 승인 취소 → .failed")
    func privilegedUserCancelled() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        mockPrivileged.stubbedError = PrivilegedExecutorError.userCancelled

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .failed("User cancelled privilege escalation"))
    }

    // MARK: - Edge Cases

    @Test("ShellError.launchFailed → .failed")
    func launchFailedError() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockShell.stubbedErrors = [ShellError.launchFailed("kill not found")]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .failed("kill not found"))
    }

    @Test("root 프로세스 - scriptError → .failed")
    func rootScriptError() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockPrivileged.stubbedError = PrivilegedExecutorError.scriptError("Permission denied")

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .failed("Permission denied"))
    }

    @Test("root 프로세스 - scriptError에 No such process 포함 → .alreadyExited")
    func rootScriptErrorNoSuchProcess() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockPrivileged.stubbedError = PrivilegedExecutorError.scriptError("No such process")

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .alreadyExited)
    }

    @Test("SIGTERM 성공 + 생존 + SIGKILL 실패 → .failed")
    func sigkillFailure() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // kill -15 성공, kill -0 성공(생존), kill -9 실패
        mockShell.stubbedResults = ["", "", ""]
        mockShell.stubbedErrors = [
            nil,
            nil,
            ShellError.executionFailed(exitCode: 1, stderr: "Operation not permitted")
        ]

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: userProcess, gracePeriod: 0)

        #expect(result == .failed("Operation not permitted"))
    }
}

import Testing
import Foundation
@testable import SSD_Remover

private actor PassthroughPrivilegedExecutor: PrivilegedExecuting {
    private let shell = ShellExecutor()
    private(set) var callCount = 0

    func executeWithPrivileges(command: String) async throws -> String {
        callCount += 1
        return try await shell.execute(command: "/bin/sh", arguments: ["-c", command])
    }
}

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
        mockPrivileged.stubbedResult = "terminated\t5678\n"

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockPrivileged.executedCommands.count == 1)
        #expect(mockPrivileged.executedCommands[0].contains("pids='5678'"))
        #expect(mockPrivileged.executedCommands[0].contains("kill -15 \"$pid\""))
        #expect(mockShell.executedCommands.isEmpty)
    }

    @Test("root 프로세스 kill -0에서 EPERM → 종료로 간주하지 않고 SIGKILL")
    func rootProcessPermissionDeniedDuringLivenessCheck() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockPrivileged.stubbedResult = "terminated\t5678\n"

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockShell.executedCommands.isEmpty)
        #expect(mockPrivileged.executedCommands.count == 1)
        #expect(mockPrivileged.executedCommands[0].contains("-15"))
        #expect(mockPrivileged.executedCommands[0].contains("-9"))
    }

    @Test("root 프로세스 SIGTERM 후 생존 → SIGKILL도 privileged")
    func rootProcessSigkillUsesPrivileged() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockPrivileged.stubbedResult = "terminated\t5678\n"

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let result = await service.terminate(process: rootProcess, gracePeriod: 0)

        #expect(result == .terminated)
        #expect(mockPrivileged.executedCommands.count == 1)
        #expect(mockPrivileged.executedCommands[0].contains("-15"))
        #expect(mockPrivileged.executedCommands[0].contains("-9"))
    }

    // MARK: - terminateAll

    @Test("terminateAll - 복수 프로세스 처리")
    func terminateAllProcesses() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()

        // user 프로세스는 일반 shell, root 프로세스는 하나의 privileged batch로 처리
        mockShell.stubbedErrors = [
            nil,                                                                   // kill -15 pid1
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),    // kill -0 pid1
        ]
        mockShell.stubbedResults = ["", ""]
        mockPrivileged.stubbedResult = "terminated\t5678\n"

        let service = ProcessTerminatorService(shell: mockShell, privilegedShell: mockPrivileged)
        let results = await service.terminateAll(
            processes: [userProcess, rootProcess],
            gracePeriod: 0
        )

        #expect(results.count == 2)
        #expect(results[userProcess.pid] == .terminated)
        #expect(results[rootProcess.pid] == .terminated)
        #expect(mockPrivileged.executedCommands.count == 1)
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

    @Test("headless non-root CLI는 root target에 GUI prompt 없이 즉시 실패")
    func headlessNonRootFailsFastForRootTarget() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: mockPrivileged,
            context: .headlessCLI(effectiveUserID: 501)
        )

        let result = await service.terminate(process: rootProcess, gracePeriod: 10)

        guard case .failed(let message) = result else {
            Issue.record("Expected an actionable privilege failure")
            return
        }
        #expect(message.contains("sudo"))
        #expect(message.contains("headless"))
        #expect(mockShell.executedCommands.isEmpty)
        #expect(mockPrivileged.executedCommands.isEmpty)
    }

    @Test("effective UID 0 CLI는 root target도 일반 shell로 처리")
    func rootCLIBypassesAppleScript() async {
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockShell.stubbedErrors = [
            nil,
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),
        ]
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: mockPrivileged,
            context: .headlessCLI(effectiveUserID: 0)
        )

        let result = await service.terminate(process: rootProcess, gracePeriod: 1)

        #expect(result == .terminated)
        #expect(mockPrivileged.executedCommands.isEmpty)
        #expect(mockShell.executedCommands.map(\.arguments) == [
            ["-15", "5678"],
            ["-0", "5678"],
        ])
    }

    @Test("interactive GUI는 여러 root target을 한 번의 권한 요청으로 처리")
    func interactiveRootBatchUsesOneAuthorization() async {
        let secondRoot = BlockingProcess(
            pid: 6789,
            command: "root-helper",
            user: "root",
            uid: 0,
            lockedFiles: []
        )
        let mockShell = MockShellExecutor()
        let mockPrivileged = MockPrivilegedExecutor()
        mockPrivileged.stubbedResult = "terminated\t5678\nterminated\t6789\n"
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: mockPrivileged,
            context: .interactiveGUI(effectiveUserID: 501)
        )

        let results = await service.terminateAll(
            processes: [rootProcess, secondRoot],
            gracePeriod: 0
        )

        #expect(results[rootProcess.pid] == .terminated)
        #expect(results[secondRoot.pid] == .terminated)
        #expect(mockPrivileged.executedCommands.count == 1)
        #expect(mockPrivileged.executedCommands[0].contains("pids='5678 6789'"))
        #expect(mockPrivileged.executedCommands[0].contains("-15 \"$pid\""))
        #expect(mockPrivileged.executedCommands[0].contains("-9 \"$pid\""))
    }

    @Test("privileged batch script는 실제 child의 조기 종료 결과를 반환")
    func privilegedBatchScriptRunsEndToEnd() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
            }
        }

        let target = BlockingProcess(
            pid: child.processIdentifier,
            command: "sleep",
            user: "root",
            uid: 0,
            lockedFiles: []
        )
        let privileged = PassthroughPrivilegedExecutor()
        let service = ProcessTerminatorService(
            shell: MockShellExecutor(),
            privilegedShell: privileged,
            context: .interactiveGUI(effectiveUserID: 501),
            pollInterval: 0.02
        )

        let result = await service.terminate(process: target, gracePeriod: 0.5)

        #expect(result == .terminated)
        #expect(await privileged.callCount == 1)
        for _ in 0..<20 where child.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(child.isRunning == false)
    }

    @Test("SIGTERM 직후 종료된 프로세스는 grace period보다 훨씬 빨리 완료")
    func fastExitReturnsBeforeGracePeriod() async {
        let mockShell = MockShellExecutor()
        mockShell.stubbedErrors = [
            nil,
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),
        ]
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: MockPrivilegedExecutor(),
            context: .headlessCLI(effectiveUserID: 501),
            pollInterval: 0.02
        )
        let start = ProcessInfo.processInfo.systemUptime

        let result = await service.terminate(process: userProcess, gracePeriod: 1)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(result == .terminated)
        #expect(elapsed < 0.25)
        #expect(!mockShell.executedCommands.contains { $0.arguments.first == "-9" })
    }

    @Test("grace period 동안 생존한 프로세스만 deadline 후 SIGKILL")
    func slowExitEscalatesAtDeadline() async {
        let mockShell = MockShellExecutor()
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: MockPrivilegedExecutor(),
            context: .headlessCLI(effectiveUserID: 501),
            pollInterval: 0.02
        )
        let start = ProcessInfo.processInfo.systemUptime

        let result = await service.terminate(process: userProcess, gracePeriod: 0.12)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(result == .terminated)
        #expect(elapsed >= 0.09)
        #expect(elapsed < 0.4)
        #expect(mockShell.executedCommands.last?.arguments == ["-9", "1234"])
    }

    @Test("mixed batch는 프로세스별 grace를 직렬로 기다리지 않음")
    func mixedBatchSharesOneGraceDeadline() async {
        let secondUser = BlockingProcess(
            pid: 2345,
            command: "Editor",
            user: "testuser",
            uid: 501,
            lockedFiles: []
        )
        let mockShell = MockShellExecutor()
        mockShell.stubbedErrors = [
            nil, nil,
            ShellError.executionFailed(exitCode: 1, stderr: "No such process"),
            nil,
        ]
        let service = ProcessTerminatorService(
            shell: mockShell,
            privilegedShell: MockPrivilegedExecutor(),
            context: .headlessCLI(effectiveUserID: 501),
            pollInterval: 0.02
        )
        let start = ProcessInfo.processInfo.systemUptime

        let results = await service.terminateAll(
            processes: [userProcess, secondUser],
            gracePeriod: 0.12
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(results[userProcess.pid] == .terminated)
        #expect(results[secondUser.pid] == .terminated)
        #expect(elapsed >= 0.09)
        #expect(elapsed < 0.4)
        #expect(mockShell.executedCommands.filter { $0.arguments.first == "-9" }.count == 1)
    }
}

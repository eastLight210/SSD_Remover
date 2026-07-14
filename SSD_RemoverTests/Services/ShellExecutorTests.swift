import Testing
import Foundation
import Darwin
@testable import SSD_Remover

@Suite("ShellExecutor Tests")
struct ShellExecutorTests {

    @Test("echo 명령어 실행 결과 반환")
    func executeEchoCommand() async throws {
        let executor = ShellExecutor()
        let result = try await executor.execute(
            command: "/bin/echo",
            arguments: ["hello"]
        )
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("64KB를 넘는 stdout과 stderr를 교착 없이 처리")
    func executeLargeOutput() async throws {
        let executor = ShellExecutor()
        let outputByteCount = 256 * 1024
        let script = """
        /usr/bin/yes stdout | /usr/bin/head -c \(outputByteCount)
        /usr/bin/yes stderr | /usr/bin/head -c \(outputByteCount) 1>&2
        """

        let result = try await executor.execute(
            command: "/bin/sh",
            arguments: ["-c", script]
        )

        #expect(result.utf8.count == outputByteCount)
    }

    @Test("존재하지 않는 명령어는 에러 발생")
    func executeNonExistentCommand() async {
        let executor = ShellExecutor()
        await #expect(throws: ShellError.self) {
            _ = try await executor.execute(
                command: "/usr/bin/nonexistent_command_xyz",
                arguments: []
            )
        }
    }

    @Test("종료 코드가 0이 아니면 에러 발생")
    func executeFailingCommand() async {
        let executor = ShellExecutor()
        await #expect(throws: ShellError.self) {
            _ = try await executor.execute(
                command: "/bin/ls",
                arguments: ["/nonexistent_path_xyz_123"]
            )
        }
    }

    @Test("ShellError.executionFailed에 종료 코드와 stderr 포함")
    func errorContainsDetails() async {
        let executor = ShellExecutor()
        do {
            _ = try await executor.execute(
                command: "/bin/ls",
                arguments: ["/nonexistent_path_xyz_123"]
            )
            Issue.record("Expected error not thrown")
        } catch let error as ShellError {
            switch error {
            case .executionFailed(let code, let stderr):
                #expect(code != 0)
                #expect(!stderr.isEmpty)
            case .launchFailed, .timedOut, .cancelled:
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("기본 timeout은 장기 실행 child를 종료하고 actionable error 반환")
    func defaultTimeoutStopsLongRunningChild() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pidFile = directory.appendingPathComponent("pid")
        let executor = ShellExecutor(defaultTimeout: 0.08, terminationGracePeriod: 0.02)
        let start = ProcessInfo.processInfo.systemUptime

        do {
            _ = try await executor.execute(
                command: "/bin/sh",
                arguments: ["-c", "echo $$ > '\(pidFile.path)'; exec /bin/sleep 5"]
            )
            Issue.record("Expected timeout")
        } catch let error as ShellError {
            guard case .timedOut(let command, let seconds) = error else {
                Issue.record("Expected timedOut, got \(error)")
                return
            }
            #expect(command == "sh")
            #expect(seconds == 0.08)
            #expect(error.localizedDescription.contains("did not respond"))
            #expect(error.localizedDescription.contains("unresponsive"))
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(elapsed < 0.5)

        try? await Task.sleep(for: .milliseconds(150))
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(pid_t(pidText))
        errno = 0
        #expect(Darwin.kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test("Task cancellation은 child cleanup 후 cancelled를 한 번만 반환")
    func taskCancellationStopsChild() async {
        let executor = ShellExecutor(defaultTimeout: 5, terminationGracePeriod: 0.02)
        let task = Task {
            try await executor.execute(command: "/bin/sleep", arguments: ["5"])
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch let error as ShellError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test("timeout과 cancellation race에서도 각 호출은 정확히 한 번 완료")
    func timeoutCancellationRaceCompletesExactlyOnce() async {
        let executor = ShellExecutor(defaultTimeout: 0.03, terminationGracePeriod: 0.01)

        for iteration in 0..<10 {
            let task = Task {
                try await executor.execute(command: "/bin/sleep", arguments: ["1"])
            }
            let cancellationDelay = iteration.isMultiple(of: 2) ? 20 : 35
            try? await Task.sleep(for: .milliseconds(cancellationDelay))
            task.cancel()

            do {
                _ = try await task.value
                Issue.record("Expected timeout or cancellation")
            } catch let error as ShellError {
                switch error {
                case .timedOut, .cancelled:
                    break
                case .executionFailed, .launchFailed:
                    Issue.record("Unexpected race result: \(error)")
                }
            } catch {
                Issue.record("Unexpected race error: \(error)")
            }
        }
    }

    @Test("timeout은 출력 pipe가 열려 있어도 caller를 deadline에 완료")
    func timeoutDoesNotWaitForOutputEOF() async {
        let executor = ShellExecutor(defaultTimeout: 0.06, terminationGracePeriod: 0.02)
        let start = ProcessInfo.processInfo.systemUptime

        do {
            _ = try await executor.execute(
                command: "/bin/sh",
                arguments: ["-c", "printf partial-output; exec /bin/sleep 5"]
            )
            Issue.record("Expected timeout")
        } catch let error as ShellError {
            guard case .timedOut = error else {
                Issue.record("Expected timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected timeout error: \(error)")
        }

        #expect(ProcessInfo.processInfo.systemUptime - start < 0.5)
    }
}

@Suite("MockShellExecutor Tests")
struct MockShellExecutorTests {

    @Test("Mock은 stubbed 결과를 반환")
    func mockReturnsStubbed() async throws {
        let mock = MockShellExecutor()
        mock.stubbedResult = "mocked output"

        let result = try await mock.execute(command: "/test", arguments: ["arg1"])
        #expect(result == "mocked output")
        #expect(mock.executedCommands.count == 1)
        #expect(mock.executedCommands[0].command == "/test")
        #expect(mock.executedCommands[0].arguments == ["arg1"])
    }

    @Test("Mock은 stubbed 에러를 발생")
    func mockThrowsStubbedError() async {
        let mock = MockShellExecutor()
        mock.stubbedError = ShellError.executionFailed(exitCode: 1, stderr: "mock error")

        await #expect(throws: ShellError.self) {
            _ = try await mock.execute(command: "/test", arguments: [])
        }
    }
}

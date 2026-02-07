import Testing
import Foundation
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
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

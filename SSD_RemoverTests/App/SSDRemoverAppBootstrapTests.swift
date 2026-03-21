import Foundation
import Testing
@testable import SSD_Remover

@Suite("SSDRemoverAppBootstrap Tests")
struct SSDRemoverAppBootstrapTests {
    private struct StubCLICommandExecutor: CLICommandExecuting {
        let result: CLIExecutionResult
        let delayNanoseconds: UInt64

        init(
            result: CLIExecutionResult,
            delayNanoseconds: UInt64 = 10_000_000
        ) {
            self.result = result
            self.delayNanoseconds = delayNanoseconds
        }

        func run(arguments: [String]) async -> CLIExecutionResult {
            try? await Task.sleep(for: .nanoseconds(delayNanoseconds))
            return result
        }
    }

    @Test("CLI 부트스트랩은 GUI 뷰모델을 만들지 않음")
    @MainActor
    func cliBootstrapSkipsMenuBarViewModel() {
        var viewModelBuildCount = 0

        let bootstrap = SSDRemoverAppBootstrap(arguments: []) {
            viewModelBuildCount += 1
            return AppViewModel(volumeMonitorService: VolumeMonitorService())
        }

        #expect(bootstrap.launchMode == .cli(arguments: []))
        #expect(bootstrap.viewModel == nil)
        #expect(viewModelBuildCount == 0)
    }

    @Test("메뉴바 부트스트랩은 GUI 뷰모델을 한 번만 만듦")
    @MainActor
    func menuBarBootstrapCreatesViewModelOnce() {
        var viewModelBuildCount = 0

        let bootstrap = SSDRemoverAppBootstrap(arguments: [
            "-psn_0_12345",
            "-ApplePersistenceIgnoreState", "YES",
        ]) {
            viewModelBuildCount += 1
            return AppViewModel(volumeMonitorService: VolumeMonitorService())
        }

        #expect(bootstrap.launchMode == .menuBar)
        #expect(bootstrap.viewModel != nil)
        #expect(viewModelBuildCount == 1)
    }

    @Test("알 수 없는 CLI 명령은 usage와 exit 64를 반환")
    func liveExecutorFormatsParseFailureAsUsageError() async {
        let result = await LiveCLICommandExecutor().run(arguments: ["not-a-command"])

        #expect(result.exitCode == 64)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Unknown command: not-a-command"))
        #expect(result.stderr.contains(CLICommandParser.usageText))
    }

    @Test("blocking executor는 비동기 CLI 결과를 동기적으로 기다림")
    func blockingExecutorWaitsForAsyncResult() {
        let expectedResult = CLIExecutionResult(
            exitCode: 7,
            stdout: "out",
            stderr: "err"
        )

        let result = BlockingCLICommandExecutor(
            executor: StubCLICommandExecutor(result: expectedResult)
        ).run(arguments: ["help"])

        #expect(result == expectedResult)
    }

    @Test("결과 emitter는 stdout/stderr 끝에 개행을 보장")
    func emitterAddsTrailingNewlines() throws {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let stdoutURL = directoryURL.appendingPathComponent("stdout.txt")
        let stderrURL = directoryURL.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: Data())
        FileManager.default.createFile(atPath: stderrURL.path, contents: Data())

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        CLIExecutionResultEmitter(
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle
        ).emit(
            CLIExecutionResult(exitCode: 0, stdout: "hello", stderr: "warning")
        )

        #expect(try String(contentsOf: stdoutURL) == "hello\n")
        #expect(try String(contentsOf: stderrURL) == "warning\n")
    }
}

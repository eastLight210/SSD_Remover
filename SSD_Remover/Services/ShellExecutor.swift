import Foundation

enum ShellError: Error, Equatable {
    case executionFailed(exitCode: Int32, stderr: String)
    case launchFailed(String)
}

private final class ShellExecutionState: @unchecked Sendable {
    private struct CompletedExecution {
        let continuation: CheckedContinuation<String, any Error>
        let stdoutData: Data
        let stderrData: Data
        let exitCode: Int32
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?
    private var stdoutData: Data?
    private var stderrData: Data?
    private var exitCode: Int32?
    private var hasLaunched = false

    init(continuation: CheckedContinuation<String, any Error>) {
        self.continuation = continuation
    }

    func didLaunch() {
        let completedExecution: CompletedExecution?

        lock.lock()
        hasLaunched = true
        completedExecution = takeCompletedExecution()
        lock.unlock()

        resume(completedExecution)
    }

    func didReadStdout(_ data: Data) {
        let completedExecution: CompletedExecution?

        lock.lock()
        stdoutData = data
        completedExecution = takeCompletedExecution()
        lock.unlock()

        resume(completedExecution)
    }

    func didReadStderr(_ data: Data) {
        let completedExecution: CompletedExecution?

        lock.lock()
        stderrData = data
        completedExecution = takeCompletedExecution()
        lock.unlock()

        resume(completedExecution)
    }

    func didTerminate(exitCode: Int32) {
        let completedExecution: CompletedExecution?

        lock.lock()
        self.exitCode = exitCode
        completedExecution = takeCompletedExecution()
        lock.unlock()

        resume(completedExecution)
    }

    func didFailToLaunch(message: String) {
        let continuation: CheckedContinuation<String, any Error>?

        lock.lock()
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(throwing: ShellError.launchFailed(message))
    }

    private func takeCompletedExecution() -> CompletedExecution? {
        guard hasLaunched,
              let continuation,
              let stdoutData,
              let stderrData,
              let exitCode else {
            return nil
        }

        self.continuation = nil
        return CompletedExecution(
            continuation: continuation,
            stdoutData: stdoutData,
            stderrData: stderrData,
            exitCode: exitCode
        )
    }

    private func resume(_ completedExecution: CompletedExecution?) {
        guard let completedExecution else { return }

        let stdout = String(data: completedExecution.stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: completedExecution.stderrData, encoding: .utf8) ?? ""

        if completedExecution.exitCode == 0 {
            completedExecution.continuation.resume(returning: stdout)
        } else {
            completedExecution.continuation.resume(throwing: ShellError.executionFailed(
                exitCode: completedExecution.exitCode,
                stderr: stderr
            ))
        }
    }
}

private final class ShellOutputDrain: @unchecked Sendable {
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let state: ShellExecutionState

    init(stdoutHandle: FileHandle, stderrHandle: FileHandle, state: ShellExecutionState) {
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
        self.state = state
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            state.didReadStdout(stdoutHandle.readDataToEndOfFile())
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            state.didReadStderr(stderrHandle.readDataToEndOfFile())
        }
    }
}

actor ShellExecutor: ShellExecuting {
    func execute(command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let state = ShellExecutionState(continuation: continuation)
            let outputDrain = ShellOutputDrain(
                stdoutHandle: stdoutPipe.fileHandleForReading,
                stderrHandle: stderrPipe.fileHandleForReading,
                state: state
            )

            process.terminationHandler = { terminatedProcess in
                state.didTerminate(exitCode: terminatedProcess.terminationStatus)
            }
            outputDrain.start()

            do {
                try process.run()
                state.didLaunch()
            } catch {
                process.terminationHandler = nil
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                state.didFailToLaunch(message: error.localizedDescription)
            }
        }
    }
}

import Darwin
import Foundation

enum ShellError: Error, Equatable {
    case executionFailed(exitCode: Int32, stderr: String)
    case launchFailed(String)
    case timedOut(command: String, seconds: TimeInterval)
    case cancelled
}

extension ShellError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executionFailed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Command failed with exit code \(exitCode)."
                : detail
        case .launchFailed(let message):
            return "Failed to launch command: \(message)"
        case .timedOut(let command, let seconds):
            return "\(command) did not respond within \(Self.formatted(seconds)) seconds. The target volume or process may be unresponsive."
        case .cancelled:
            return "Command execution was cancelled."
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        String(format: "%.3g", locale: Locale(identifier: "en_US_POSIX"), seconds)
    }
}

private final class ShellExecutionState: @unchecked Sendable {
    private struct CompletedExecution {
        let continuation: CheckedContinuation<String, any Error>
        let stdoutData: Data
        let stderrData: Data
        let exitCode: Int32
    }

    private let lock = NSLock()
    private let process: Process
    private let stdoutReadHandle: FileHandle
    private let stderrReadHandle: FileHandle
    private let stdoutWriteHandle: FileHandle
    private let stderrWriteHandle: FileHandle
    private let command: String
    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval

    private var continuation: CheckedContinuation<String, any Error>?
    private var stdoutData: Data?
    private var stderrData: Data?
    private var exitCode: Int32?
    private var hasLaunched = false
    private var launchAttempted = false
    private var isFinished = false
    private var stopError: ShellError?
    private var timeoutTask: Task<Void, Never>?
    private var cleanupStarted = false

    init(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        command: String,
        timeout: TimeInterval,
        terminationGracePeriod: TimeInterval
    ) {
        self.process = process
        stdoutReadHandle = stdoutPipe.fileHandleForReading
        stderrReadHandle = stderrPipe.fileHandleForReading
        stdoutWriteHandle = stdoutPipe.fileHandleForWriting
        stderrWriteHandle = stderrPipe.fileHandleForWriting
        self.command = command
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }

    func install(
        continuation: CheckedContinuation<String, any Error>
    ) -> Bool {
        let pendingError: ShellError?

        lock.lock()
        if isFinished {
            pendingError = stopError ?? .cancelled
        } else {
            self.continuation = continuation
            pendingError = nil
        }
        lock.unlock()

        if let pendingError {
            continuation.resume(throwing: pendingError)
            return false
        }
        return true
    }

    func beginLaunch() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return false
        }
        launchAttempted = true
        return true
    }

    func didLaunch() {
        let completedExecution: CompletedExecution?
        let shouldCleanup: Bool
        let shouldScheduleTimeout: Bool

        lock.lock()
        hasLaunched = true
        shouldCleanup = isFinished
        completedExecution = takeCompletedExecutionLocked()
        shouldScheduleTimeout = !isFinished && completedExecution == nil
        lock.unlock()

        if shouldCleanup {
            terminateAndCleanup()
        }
        finish(completedExecution)

        if shouldScheduleTimeout {
            let timeoutTask = Task.detached { [state = self, timeout] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                state.requestStop(.timedOut(command: state.command, seconds: timeout))
            }
            installTimeoutTask(timeoutTask)
        }
    }

    func didReadStdout(_ data: Data) {
        let completedExecution: CompletedExecution?

        lock.lock()
        stdoutData = data
        completedExecution = takeCompletedExecutionLocked()
        lock.unlock()

        finish(completedExecution)
    }

    func didReadStderr(_ data: Data) {
        let completedExecution: CompletedExecution?

        lock.lock()
        stderrData = data
        completedExecution = takeCompletedExecutionLocked()
        lock.unlock()

        finish(completedExecution)
    }

    func didTerminate(exitCode: Int32) {
        let completedExecution: CompletedExecution?

        lock.lock()
        self.exitCode = exitCode
        completedExecution = takeCompletedExecutionLocked()
        lock.unlock()

        finish(completedExecution)
    }

    func didFailToLaunch(message: String) {
        let continuation: CheckedContinuation<String, any Error>?
        let timeoutTask: Task<Void, Never>?

        lock.lock()
        if isFinished {
            continuation = nil
            timeoutTask = nil
        } else {
            isFinished = true
            continuation = self.continuation
            self.continuation = nil
            timeoutTask = self.timeoutTask
            self.timeoutTask = nil
        }
        lock.unlock()

        timeoutTask?.cancel()
        closeAllHandles()
        continuation?.resume(throwing: ShellError.launchFailed(message))
    }

    func cancel() {
        requestStop(.cancelled)
    }

    func shouldStopOutputDrain() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished && stopError != nil
    }

    private func requestStop(_ error: ShellError) {
        let continuation: CheckedContinuation<String, any Error>?
        let timeoutTask: Task<Void, Never>?
        let shouldCleanup: Bool

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        isFinished = true
        stopError = error
        continuation = self.continuation
        self.continuation = nil
        timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        shouldCleanup = hasLaunched || launchAttempted
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(throwing: error)

        if shouldCleanup {
            terminateAndCleanup()
        } else {
            closeAllHandles()
        }
    }

    private func takeCompletedExecutionLocked() -> CompletedExecution? {
        guard !isFinished,
              hasLaunched,
              let continuation,
              let stdoutData,
              let stderrData,
              let exitCode else {
            return nil
        }

        isFinished = true
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        timeoutTask?.cancel()

        return CompletedExecution(
            continuation: continuation,
            stdoutData: stdoutData,
            stderrData: stderrData,
            exitCode: exitCode
        )
    }

    private func finish(_ completedExecution: CompletedExecution?) {
        guard let completedExecution else {
            return
        }

        process.terminationHandler = nil

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

    private func installTimeoutTask(_ task: Task<Void, Never>) {
        let shouldCancel: Bool

        lock.lock()
        if isFinished {
            shouldCancel = true
        } else {
            timeoutTask = task
            shouldCancel = false
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    private func terminateAndCleanup() {
        lock.lock()
        guard !cleanupStarted else {
            lock.unlock()
            return
        }
        cleanupStarted = true
        lock.unlock()

        process.terminationHandler = nil
        closeWriteHandles()

        if process.isRunning {
            process.terminate()
            let process = self.process
            let gracePeriod = terminationGracePeriod

            Task.detached {
                if gracePeriod > 0 {
                    try? await Task.sleep(for: .seconds(gracePeriod))
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    private func closeAllHandles() {
        closeWriteHandles()
        closeReadHandles()
    }

    private func closeWriteHandles() {
        try? stdoutWriteHandle.close()
        try? stderrWriteHandle.close()
    }

    private func closeReadHandles() {
        try? stdoutReadHandle.close()
        try? stderrReadHandle.close()
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
            state.didReadStdout(readToEnd(from: stdoutHandle))
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            state.didReadStderr(readToEnd(from: stderrHandle))
        }
    }

    private func readToEnd(from handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let currentFlags = fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        defer {
            try? handle.close()
        }

        while true {
            if state.shouldStopOutputDrain() {
                return data
            }

            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }

            if bytesRead > 0 {
                data.append(contentsOf: buffer.prefix(bytesRead))
                continue
            }

            if bytesRead == 0 {
                return data
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                if state.shouldStopOutputDrain() {
                    return data
                }
                usleep(10_000)
                continue
            }

            return data
        }
    }
}

/// Executes child processes with a finite default deadline.
///
/// On timeout or cancellation the executor requests termination, escalates to SIGKILL after a
/// short cleanup grace period, and closes its pipe handles. A process blocked in an uninterruptible
/// kernel operation may remain visible to the OS after this method has returned, but the caller is
/// still completed exactly once and never waits indefinitely for that process's output pipes.
actor ShellExecutor: ShellExecuting {
    static let standardTimeout: TimeInterval = 30

    private let defaultTimeout: TimeInterval
    private let terminationGracePeriod: TimeInterval

    init(
        defaultTimeout: TimeInterval = ShellExecutor.standardTimeout,
        terminationGracePeriod: TimeInterval = 0.2
    ) {
        self.defaultTimeout = Self.normalizedTimeout(defaultTimeout)
        self.terminationGracePeriod = max(0, terminationGracePeriod)
    }

    func execute(command: String, arguments: [String]) async throws -> String {
        try await execute(
            command: command,
            arguments: arguments,
            timeout: defaultTimeout
        )
    }

    func execute(
        command: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String {
        let normalizedTimeout = Self.normalizedTimeout(timeout)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let state = ShellExecutionState(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            command: URL(fileURLWithPath: command).lastPathComponent,
            timeout: normalizedTimeout,
            terminationGracePeriod: terminationGracePeriod
        )
        let outputDrain = ShellOutputDrain(
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading,
            state: state
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation: continuation),
                      state.beginLaunch() else {
                    return
                }

                process.terminationHandler = { terminatedProcess in
                    state.didTerminate(exitCode: terminatedProcess.terminationStatus)
                }

                do {
                    try process.run()
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    outputDrain.start()
                    state.didLaunch()
                } catch {
                    process.terminationHandler = nil
                    state.didFailToLaunch(message: error.localizedDescription)
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func normalizedTimeout(_ timeout: TimeInterval) -> TimeInterval {
        guard timeout.isFinite else {
            return standardTimeout
        }
        return max(0, timeout)
    }
}

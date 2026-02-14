import Foundation

actor ProcessTerminatorService: ProcessTerminating {
    private let shell: ShellExecuting
    private let privilegedShell: PrivilegedExecuting

    init(shell: ShellExecuting, privilegedShell: PrivilegedExecuting) {
        self.shell = shell
        self.privilegedShell = privilegedShell
    }

    func terminate(process: BlockingProcess, gracePeriod: TimeInterval) async -> TerminationResult {
        // 1. SIGTERM 전송
        let sigTermResult = await sendSignal("-15", to: process)

        switch sigTermResult {
        case .processNotFound:
            return .alreadyExited
        case .failure(let message):
            return .failed(message)
        case .sent:
            break
        }

        // 2. gracePeriod 대기
        if gracePeriod > 0 {
            try? await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        }

        // 3. kill -0으로 생존 확인
        if await isProcessAlive(process) == false {
            return .terminated
        }

        // 4. SIGKILL 전송
        let sigKillResult = await sendSignal("-9", to: process)

        switch sigKillResult {
        case .processNotFound:
            return .terminated
        case .failure(let message):
            return .failed(message)
        case .sent:
            return .terminated
        }
    }

    func terminateAll(processes: [BlockingProcess], gracePeriod: TimeInterval) async -> [Int32: TerminationResult] {
        var results: [Int32: TerminationResult] = [:]
        for process in processes {
            results[process.pid] = await terminate(process: process, gracePeriod: gracePeriod)
        }
        return results
    }

    // MARK: - Private

    private enum SignalResult {
        case sent
        case processNotFound
        case failure(String)
    }

    private func sendSignal(_ signal: String, to process: BlockingProcess) async -> SignalResult {
        do {
            if process.isRoot {
                _ = try await privilegedShell.executeWithPrivileges(
                    command: "\(Constants.killPath) \(signal) \(process.pid)"
                )
            } else {
                _ = try await shell.execute(
                    command: Constants.killPath,
                    arguments: [signal, String(process.pid)]
                )
            }
            return .sent
        } catch let error as ShellError {
            switch error {
            case .executionFailed(_, let stderr):
                if stderr.contains("No such process") {
                    return .processNotFound
                }
                return .failure(stderr)
            case .launchFailed(let message):
                return .failure(message)
            }
        } catch let error as PrivilegedExecutorError {
            switch error {
            case .userCancelled:
                return .failure("User cancelled privilege escalation")
            case .scriptError(let message):
                if message.contains("No such process") {
                    return .processNotFound
                }
                return .failure(message)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func isProcessAlive(_ process: BlockingProcess) async -> Bool {
        do {
            if process.isRoot {
                _ = try await privilegedShell.executeWithPrivileges(
                    command: "\(Constants.killPath) -0 \(process.pid)"
                )
            } else {
                _ = try await shell.execute(
                    command: Constants.killPath,
                    arguments: ["-0", String(process.pid)]
                )
            }
            return true
        } catch let error as ShellError {
            if case .executionFailed(_, let stderr) = error,
               stderr.contains("No such process") {
                return false
            }
            return true
        } catch let error as PrivilegedExecutorError {
            if case .scriptError(let message) = error,
               message.contains("No such process") {
                return false
            }
            return true
        } catch {
            return true
        }
    }
}

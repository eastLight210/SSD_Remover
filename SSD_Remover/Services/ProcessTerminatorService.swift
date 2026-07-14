import Darwin
import Foundation

struct ProcessTerminationContext: Equatable, Sendable {
    let effectiveUserID: uid_t
    let allowsInteractivePrivilegeEscalation: Bool

    static func interactiveGUI(effectiveUserID: uid_t = geteuid()) -> Self {
        ProcessTerminationContext(
            effectiveUserID: effectiveUserID,
            allowsInteractivePrivilegeEscalation: true
        )
    }

    static func headlessCLI(effectiveUserID: uid_t = geteuid()) -> Self {
        ProcessTerminationContext(
            effectiveUserID: effectiveUserID,
            allowsInteractivePrivilegeEscalation: false
        )
    }
}

actor ProcessTerminatorService: ProcessTerminating {
    private static let maximumGracePeriod: TimeInterval = 86_400

    private let shell: ShellExecuting
    private let privilegedShell: PrivilegedExecuting
    private let context: ProcessTerminationContext
    private let pollInterval: TimeInterval

    init(
        shell: ShellExecuting,
        privilegedShell: PrivilegedExecuting,
        context: ProcessTerminationContext = .interactiveGUI(),
        pollInterval: TimeInterval = 0.1
    ) {
        self.shell = shell
        self.privilegedShell = privilegedShell
        self.context = context
        self.pollInterval = max(0.01, pollInterval)
    }

    func terminate(process: BlockingProcess, gracePeriod: TimeInterval) async -> TerminationResult {
        await terminateAll(processes: [process], gracePeriod: gracePeriod)[process.pid]
            ?? .failed("No termination result returned")
    }

    func terminateAll(
        processes: [BlockingProcess],
        gracePeriod: TimeInterval
    ) async -> [Int32: TerminationResult] {
        let uniqueProcesses = deduplicated(processes)
        guard !uniqueProcesses.isEmpty else {
            return [:]
        }

        let normalizedGracePeriod = normalizeGracePeriod(gracePeriod)
        let privilegedTargets = uniqueProcesses.filter {
            $0.isRoot && context.effectiveUserID != 0
        }
        let shellTargets = uniqueProcesses.filter {
            !$0.isRoot || context.effectiveUserID == 0
        }

        var immediateResults: [Int32: TerminationResult] = [:]
        var interactiveTargets: [BlockingProcess] = []

        if context.allowsInteractivePrivilegeEscalation {
            interactiveTargets = privilegedTargets
        } else {
            for process in privilegedTargets {
                immediateResults[process.pid] = .failed(
                    "PID \(process.pid) is owned by root. Re-run the CLI with sudo to terminate root-owned processes; headless CLI mode never opens an administrator dialog."
                )
            }
        }

        async let shellResults = terminateWithShell(
            processes: shellTargets,
            gracePeriod: normalizedGracePeriod
        )
        async let privilegedResults = terminateWithSinglePrivilegeRequest(
            processes: interactiveTargets,
            gracePeriod: normalizedGracePeriod
        )

        let (resolvedShellResults, resolvedPrivilegedResults) = await (
            shellResults,
            privilegedResults
        )

        immediateResults.merge(resolvedShellResults) { current, _ in current }
        immediateResults.merge(resolvedPrivilegedResults) { current, _ in current }
        return immediateResults
    }

    private func terminateWithShell(
        processes: [BlockingProcess],
        gracePeriod: TimeInterval
    ) async -> [Int32: TerminationResult] {
        guard !processes.isEmpty else {
            return [:]
        }

        var results: [Int32: TerminationResult] = [:]
        var pending: [BlockingProcess] = []

        for process in processes {
            switch await sendShellSignal("-15", to: process) {
            case .processNotFound:
                results[process.pid] = .alreadyExited
            case .failure(let message):
                results[process.pid] = .failed(message)
            case .sent:
                pending.append(process)
            }
        }

        let deadline = ProcessInfo.processInfo.systemUptime + gracePeriod

        while !pending.isEmpty {
            if Task.isCancelled {
                for process in pending {
                    results[process.pid] = .failed("Termination was cancelled")
                }
                return results
            }

            var survivors: [BlockingProcess] = []
            for process in pending {
                if await isProcessAlive(process) {
                    survivors.append(process)
                } else {
                    results[process.pid] = .terminated
                }
            }
            pending = survivors

            guard !pending.isEmpty else {
                break
            }

            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                break
            }

            let sleepDuration = min(pollInterval, remaining)
            do {
                try await Task.sleep(for: .seconds(sleepDuration))
            } catch {
                for process in pending {
                    results[process.pid] = .failed("Termination was cancelled")
                }
                return results
            }
        }

        for process in pending {
            switch await sendShellSignal("-9", to: process) {
            case .sent, .processNotFound:
                results[process.pid] = .terminated
            case .failure(let message):
                results[process.pid] = .failed(message)
            }
        }

        return results
    }

    private func terminateWithSinglePrivilegeRequest(
        processes: [BlockingProcess],
        gracePeriod: TimeInterval
    ) async -> [Int32: TerminationResult] {
        guard !processes.isEmpty else {
            return [:]
        }

        do {
            let output = try await privilegedShell.executeWithPrivileges(
                command: privilegedTerminationCommand(
                    for: processes,
                    gracePeriod: gracePeriod
                )
            )
            return parsePrivilegedResults(output, for: processes)
        } catch let error as PrivilegedExecutorError {
            let result: TerminationResult
            switch error {
            case .userCancelled:
                result = .failed("User cancelled privilege escalation")
            case .scriptError(let message):
                result = message.contains("No such process")
                    ? .alreadyExited
                    : .failed(message)
            }
            return Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, result) })
        } catch {
            let result = TerminationResult.failed(error.localizedDescription)
            return Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, result) })
        }
    }

    private enum SignalResult {
        case sent
        case processNotFound
        case failure(String)
    }

    private func sendShellSignal(
        _ signal: String,
        to process: BlockingProcess
    ) async -> SignalResult {
        do {
            _ = try await shell.execute(
                command: Constants.killPath,
                arguments: [signal, String(process.pid)]
            )
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
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func isProcessAlive(_ process: BlockingProcess) async -> Bool {
        do {
            _ = try await shell.execute(
                command: Constants.killPath,
                arguments: ["-0", String(process.pid)]
            )
            return true
        } catch let error as ShellError {
            if case .executionFailed(_, let stderr) = error,
               stderr.contains("No such process") {
                return false
            }

            // EPERM and verification failures do not prove that the process exited.
            return true
        } catch {
            // Only an explicit "No such process" response is safe to treat as dead.
            return true
        }
    }

    private func privilegedTerminationCommand(
        for processes: [BlockingProcess],
        gracePeriod: TimeInterval
    ) -> String {
        let pids = processes.map { String($0.pid) }.joined(separator: " ")
        let iterations = Int(ceil(gracePeriod / pollInterval))
        let sleepDuration = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            min(pollInterval, max(gracePeriod, 0))
        )

        return """
        pids='\(pids)'
        active=''
        for pid in $pids; do
          if \(Constants.killPath) -15 "$pid" 2>/dev/null; then
            active="$active $pid"
          elif \(Constants.killPath) -0 "$pid" 2>/dev/null; then
            printf 'failed\\t%s\\tUnable to send SIGTERM\\n' "$pid"
          else
            printf 'already_exited\\t%s\\n' "$pid"
          fi
        done
        iteration=0
        while [ "$iteration" -lt \(iterations) ] && [ -n "$active" ]; do
          next=''
          for pid in $active; do
            if \(Constants.killPath) -0 "$pid" 2>/dev/null; then
              next="$next $pid"
            else
              printf 'terminated\\t%s\\n' "$pid"
            fi
          done
          active="$next"
          [ -z "$active" ] && break
          /bin/sleep \(sleepDuration)
          iteration=$((iteration + 1))
        done
        for pid in $active; do
          if \(Constants.killPath) -0 "$pid" 2>/dev/null; then
            if \(Constants.killPath) -9 "$pid" 2>/dev/null; then
              printf 'terminated\\t%s\\n' "$pid"
            else
              printf 'failed\\t%s\\tUnable to send SIGKILL\\n' "$pid"
            fi
          else
            printf 'terminated\\t%s\\n' "$pid"
          fi
        done
        """
    }

    private func parsePrivilegedResults(
        _ output: String,
        for processes: [BlockingProcess]
    ) -> [Int32: TerminationResult] {
        var results: [Int32: TerminationResult] = [:]
        let normalizedOutput = output.replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalizedOutput.split(separator: "\n") {
            let fields = rawLine.split(
                separator: "\t",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            guard fields.count >= 2, let pid = Int32(fields[1]) else {
                continue
            }

            switch fields[0] {
            case "terminated":
                results[pid] = .terminated
            case "already_exited":
                results[pid] = .alreadyExited
            case "failed":
                let message = fields.count == 3
                    ? String(fields[2])
                    : "Privileged termination failed"
                results[pid] = .failed(message)
            default:
                continue
            }
        }

        for process in processes where results[process.pid] == nil {
            results[process.pid] = .failed(
                "Privileged termination returned no result for PID \(process.pid)"
            )
        }

        return results
    }

    private func deduplicated(_ processes: [BlockingProcess]) -> [BlockingProcess] {
        var seen: Set<Int32> = []
        return processes.filter { seen.insert($0.pid).inserted }
    }

    private func normalizeGracePeriod(_ gracePeriod: TimeInterval) -> TimeInterval {
        guard gracePeriod.isFinite, gracePeriod > 0 else {
            return 0
        }
        return min(gracePeriod, Self.maximumGracePeriod)
    }
}

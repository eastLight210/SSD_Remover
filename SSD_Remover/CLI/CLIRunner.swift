import Foundation

struct CLIExecutionResult: Equatable, Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String

    static func success(_ stdout: String = "") -> Self {
        CLIExecutionResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    static func failure(_ stderr: String, exitCode: Int = 1, stdout: String = "") -> Self {
        CLIExecutionResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}

struct CLIRunner: Sendable {
    private let volumeMonitor: VolumeMonitoring
    private let processScanner: ProcessScanning
    private let processTerminator: ProcessTerminating
    private let diskEjector: DiskEjecting

    init(
        volumeMonitor: VolumeMonitoring,
        processScanner: ProcessScanning,
        processTerminator: ProcessTerminating,
        diskEjector: DiskEjecting
    ) {
        self.volumeMonitor = volumeMonitor
        self.processScanner = processScanner
        self.processTerminator = processTerminator
        self.diskEjector = diskEjector
    }

    func run(_ command: CLICommand) async -> CLIExecutionResult {
        switch command {
        case .help:
            return .success(CLICommandParser.usageText)
        case .listVolumes:
            return await listVolumes()
        case .scan(let volumeQuery):
            return await scan(volumeQuery: volumeQuery)
        case .terminate(let volumeQuery, let selection, let gracePeriod):
            return await terminate(
                volumeQuery: volumeQuery,
                selection: selection,
                gracePeriod: gracePeriod
            )
        case .eject(let volumeQuery):
            return await eject(volumeQuery: volumeQuery)
        case .terminateAndEject(let volumeQuery, let selection, let gracePeriod):
            return await terminateAndEject(
                volumeQuery: volumeQuery,
                selection: selection,
                gracePeriod: gracePeriod
            )
        }
    }

    private func listVolumes() async -> CLIExecutionResult {
        let volumes = await refreshVolumes()
        guard !volumes.isEmpty else {
            return .success("No external volumes found.")
        }

        let lines = volumes
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { volume in
                "\(volume.name) | \(volume.deviceIdentifier) | \(volume.mountPoint.path)"
            }

        return .success(lines.joined(separator: "\n"))
    }

    private func scan(volumeQuery: String) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return .failure(message)
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return .failure(message)
            case .success(let groups):
                return .success(formatScanOutput(volume: volume, groups: groups))
            }
        }
    }

    private func terminate(
        volumeQuery: String,
        selection: CLIProcessSelection,
        gracePeriod: TimeInterval
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return .failure(message)
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return .failure(message)
            case .success(let groups):
                if groups.isEmpty {
                    return .success("No blocking processes found on \(volume.name).")
                }

                let targets = selection.matchingProcesses(in: groups)
                guard !targets.isEmpty else {
                    return .failure("No matching processes for the provided selection.")
                }

                let results = await processTerminator.terminateAll(
                    processes: targets,
                    gracePeriod: gracePeriod
                )
                let summary = summarizeTerminationResults(targets: targets, results: results)
                return CLIExecutionResult(
                    exitCode: summary.hasFailures ? 1 : 0,
                    stdout: summary.stdout.joined(separator: "\n"),
                    stderr: summary.stderr.joined(separator: "\n")
                )
            }
        }
    }

    private func eject(volumeQuery: String) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return .failure(message)
        case .success(let volume):
            switch await diskEjector.eject(volume: volume) {
            case .success:
                return .success("Ejected \(volume.name).")
            case .failed(let message):
                return .failure("Failed to eject \(volume.name): \(message)")
            }
        }
    }

    private func terminateAndEject(
        volumeQuery: String,
        selection: CLIProcessSelection,
        gracePeriod: TimeInterval
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return .failure(message)
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return .failure(message)
            case .success(let groups):
                let targets = selection.matchingProcesses(in: groups)

                if !groups.isEmpty && targets.isEmpty {
                    return .failure("No matching processes for the provided selection.")
                }

                let workflow = TerminateAndEjectService(
                    processTerminator: processTerminator,
                    diskEjector: diskEjector
                )
                let outcome = await workflow.execute(
                    volume: volume,
                    processes: targets,
                    gracePeriod: gracePeriod
                )

                var stdout: [String] = []
                var stderr: [String] = []
                var hasTerminationFailures = false

                if groups.isEmpty {
                    stdout.append("No blocking processes found on \(volume.name).")
                } else {
                    let summary = summarizeTerminationResults(targets: targets, results: outcome.terminationResults)
                    stdout.append(contentsOf: summary.stdout)
                    stderr.append(contentsOf: summary.stderr)
                    hasTerminationFailures = summary.hasFailures
                }

                switch outcome.ejectResult {
                case .success:
                    stdout.append("Ejected \(volume.name).")
                    return CLIExecutionResult(
                        exitCode: hasTerminationFailures ? 1 : 0,
                        stdout: stdout.joined(separator: "\n"),
                        stderr: stderr.joined(separator: "\n")
                    )
                case .failed(let message):
                    stderr.append("Failed to eject \(volume.name): \(message)")
                    return CLIExecutionResult(
                        exitCode: 1,
                        stdout: stdout.joined(separator: "\n"),
                        stderr: stderr.joined(separator: "\n")
                    )
                }
            }
        }
    }

    private func refreshVolumes() async -> [ExternalVolume] {
        await volumeMonitor.refreshVolumes()
        return await volumeMonitor.volumes
    }

    private func loadVolume(matching query: String) async -> VolumeLookupResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .failure("Volume query cannot be blank.")
        }

        let volumes = await refreshVolumes()
        return resolveVolume(matching: trimmedQuery, in: volumes)
    }

    private func scanGroups(for: volume: ExternalVolume) async -> GroupLookupResult {
        do {
            return .success(try await processScanner.scanProcesses(for: volume))
        } catch {
            return .failure("Failed to scan \(volume.name): \(errorMessage(for: error))")
        }
    }

    private func formatScanOutput(
        volume: ExternalVolume,
        groups: [ProcessGroup]
    ) -> String {
        var lines = [
            "Volume: \(volume.name) (\(volume.deviceIdentifier))",
            "Mount point: \(volume.mountPoint.path)",
        ]

        guard !groups.isEmpty else {
            lines.append("No blocking processes found.")
            return lines.joined(separator: "\n")
        }

        if groups.contains(where: { $0.category == .spotlight }) {
            lines.append("Spotlight warning: Spotlight is currently blocking this volume.")
        }

        for group in groups {
            lines.append("[\(group.category.rawValue)]")
            for process in group.processes {
                lines.append("PID \(process.pid) | \(process.user) | \(process.command)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summarizeTerminationResults(
        targets: [BlockingProcess],
        results: [Int32: TerminationResult]
    ) -> (stdout: [String], stderr: [String], hasFailures: Bool) {
        var stdout: [String] = []
        var stderr: [String] = []
        var hasFailures = false

        for process in targets {
            let result = results[process.pid] ?? .failed("No termination result returned")
            switch result {
            case .terminated:
                stdout.append("PID \(process.pid) terminated (\(process.command)).")
            case .alreadyExited:
                stdout.append("PID \(process.pid) already exited (\(process.command)).")
            case .failed(let message):
                hasFailures = true
                stderr.append("PID \(process.pid) failed (\(process.command)): \(message)")
            }
        }

        return (stdout, stderr, hasFailures)
    }

    private func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func resolveUniqueVolumeMatch(
        for query: String,
        matches: [ExternalVolume]
    ) -> VolumeLookupResult? {
        switch matches.count {
        case 0:
            return nil
        case 1:
            return .success(matches[0])
        default:
            return .failure(ambiguousVolumeMessage(for: query, matches: matches))
        }
    }

    private func ambiguousVolumeMessage(
        for query: String,
        matches: [ExternalVolume]
    ) -> String {
        let candidates = matches
            .map { volume in
                "\(volume.name) [\(volume.deviceIdentifier)] @ \(volume.mountPoint.path)"
            }
            .sorted()
            .joined(separator: ", ")

        return "Volume query is ambiguous: \(query) (\(candidates))"
    }
}

private enum VolumeLookupResult {
    case success(ExternalVolume)
    case failure(String)
}

private enum GroupLookupResult {
    case success([ProcessGroup])
    case failure(String)
}

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

    private func
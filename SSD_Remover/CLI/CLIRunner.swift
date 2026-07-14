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

struct CLIAppVersion: Equatable, Sendable, Encodable {
    let marketingVersion: String
    let buildNumber: String

    static func current(bundle: Bundle = .main) -> CLIAppVersion? {
        if let version = version(in: bundle) {
            return version
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let appBundleURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard appBundleURL.pathExtension == "app",
              let executableBundle = Bundle(url: appBundleURL) else {
            return nil
        }

        return version(in: executableBundle)
    }

    private static func version(in bundle: Bundle) -> CLIAppVersion? {
        guard let marketingVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        !marketingVersion.isEmpty,
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        !buildNumber.isEmpty else {
            return nil
        }

        return CLIAppVersion(
            marketingVersion: marketingVersion,
            buildNumber: buildNumber
        )
    }
}

struct CLIJSONErrorContext: Encodable, Sendable {
    let volume: CLIJSONVolume?
    let targets: [CLIJSONProcess]?

    init(volume: CLIJSONVolume? = nil, targets: [CLIJSONProcess]? = nil) {
        self.volume = volume
        self.targets = targets
    }
}

enum CLIJSONOutput {
    static let schemaVersion = 1

    static func result<Payload: Encodable>(
        command: String,
        success: Bool,
        data: Payload
    ) -> String {
        encode(CLIJSONResultEnvelope(
            schemaVersion: schemaVersion,
            success: success,
            command: command,
            data: data
        ))
    }

    static func error(
        command: String,
        code: String,
        message: String,
        usage: String? = nil,
        context: CLIJSONErrorContext? = nil
    ) -> String {
        encode(CLIJSONErrorEnvelope(
            schemaVersion: schemaVersion,
            success: false,
            command: command,
            error: CLIJSONError(code: code, message: message, usage: usage),
            context: context
        ))
    }

    private static func encode<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            return "{\"command\":\"unknown\",\"error\":{\"code\":\"encoding_failed\",\"message\":\"Failed to encode CLI JSON output.\"},\"schemaVersion\":1,\"success\":false}"
        }
    }
}

private struct CLIJSONResultEnvelope<Payload: Encodable>: Encodable {
    let schemaVersion: Int
    let success: Bool
    let command: String
    let data: Payload
}

private struct CLIJSONErrorEnvelope: Encodable {
    let schemaVersion: Int
    let success: Bool
    let command: String
    let error: CLIJSONError
    let context: CLIJSONErrorContext?
}

private struct CLIJSONError: Encodable {
    let code: String
    let message: String
    let usage: String?
}

struct CLIJSONVolume: Encodable, Sendable {
    let name: String
    let deviceIdentifier: String
    let fileSystem: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let mountPoint: String

    init(_ volume: ExternalVolume) {
        name = volume.name
        deviceIdentifier = volume.deviceIdentifier
        fileSystem = volume.fileSystem
        totalCapacity = volume.totalCapacity
        availableCapacity = volume.availableCapacity
        mountPoint = volume.mountPoint.path
    }
}

struct CLIJSONProcess: Encodable, Sendable {
    let category: String
    let pid: Int32
    let user: String
    let uid: Int32
    let command: String
    let isRoot: Bool
    let lockedFiles: [String]
}

private struct CLIJSONProcessGroup: Encodable {
    let category: String
    let processes: [CLIJSONProcess]
}

private struct CLIJSONVolumeList: Encodable {
    let volumes: [CLIJSONVolume]
}

private struct CLIJSONScanResult: Encodable {
    let volume: CLIJSONVolume
    let groups: [CLIJSONProcessGroup]
}

private struct CLIJSONTerminationRecord: Encodable {
    let pid: Int32
    let command: String
    let status: String
    let message: String?
}

private struct CLIJSONTerminationResult: Encodable {
    let volume: CLIJSONVolume
    let dryRun: Bool
    let targets: [CLIJSONProcess]
    let results: [CLIJSONTerminationRecord]
}

private struct CLIJSONEjectResult: Encodable {
    let volume: CLIJSONVolume
    let ejected: Bool
    let error: String?
}

private struct CLIJSONTerminateAndEjectResult: Encodable {
    let volume: CLIJSONVolume
    let dryRun: Bool
    let targets: [CLIJSONProcess]
    let terminationResults: [CLIJSONTerminationRecord]
    let ejected: Bool
    let ejectError: String?
}

struct CLIRunner: Sendable {
    private let volumeMonitor: VolumeMonitoring
    private let processScanner: ProcessScanning
    private let processTerminator: ProcessTerminating
    private let diskEjector: DiskEjecting
    private let versionProvider: @Sendable () -> CLIAppVersion?

    init(
        volumeMonitor: VolumeMonitoring,
        processScanner: ProcessScanning,
        processTerminator: ProcessTerminating,
        diskEjector: DiskEjecting,
        versionProvider: @escaping @Sendable () -> CLIAppVersion? = { CLIAppVersion.current() }
    ) {
        self.volumeMonitor = volumeMonitor
        self.processScanner = processScanner
        self.processTerminator = processTerminator
        self.diskEjector = diskEjector
        self.versionProvider = versionProvider
    }

    func run(_ command: CLICommand) async -> CLIExecutionResult {
        switch command.action {
        case .help(let topic):
            return .success(CLICommandParser.helpText(for: topic))
        case .version:
            return version()
        case .listVolumes:
            return await listVolumes(outputFormat: command.outputFormat)
        case .scan(let volumeQuery):
            return await scan(volumeQuery: volumeQuery, outputFormat: command.outputFormat)
        case .terminate(let volumeQuery, let options):
            return await terminate(
                volumeQuery: volumeQuery,
                options: options,
                outputFormat: command.outputFormat
            )
        case .eject(let volumeQuery):
            return await eject(volumeQuery: volumeQuery, outputFormat: command.outputFormat)
        case .terminateAndEject(let volumeQuery, let options):
            return await terminateAndEject(
                volumeQuery: volumeQuery,
                options: options,
                outputFormat: command.outputFormat
            )
        }
    }

    private func version() -> CLIExecutionResult {
        guard let version = versionProvider() else {
            return .failure("Unable to read the app version from the bundle.")
        }

        return .success(
            "SSD_Remover \(version.marketingVersion) (build \(version.buildNumber))"
        )
    }

    private func listVolumes(outputFormat: CLIOutputFormat) async -> CLIExecutionResult {
        let volumes = await refreshVolumes().sorted(by: volumeSort)

        if outputFormat == .json {
            return jsonResult(
                command: "list",
                success: true,
                data: CLIJSONVolumeList(volumes: volumes.map(CLIJSONVolume.init))
            )
        }

        guard !volumes.isEmpty else {
            return .success("No external volumes found.")
        }

        let lines = volumes.map { volume in
            "\(volume.name) | \(volume.deviceIdentifier) | \(volume.mountPoint.path)"
        }

        return .success(lines.joined(separator: "\n"))
    }

    private func scan(
        volumeQuery: String,
        outputFormat: CLIOutputFormat
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return failure(
                outputFormat: outputFormat,
                command: "scan",
                code: "volume_lookup_failed",
                message: message
            )
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return failure(
                    outputFormat: outputFormat,
                    command: "scan",
                    code: "scan_failed",
                    message: message,
                    volume: volume
                )
            case .success(let groups):
                if outputFormat == .json {
                    return jsonResult(
                        command: "scan",
                        success: true,
                        data: CLIJSONScanResult(
                            volume: CLIJSONVolume(volume),
                            groups: jsonGroups(groups)
                        )
                    )
                }
                return .success(formatScanOutput(volume: volume, groups: groups))
            }
        }
    }

    private func terminate(
        volumeQuery: String,
        options: CLITerminationOptions,
        outputFormat: CLIOutputFormat
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return failure(
                outputFormat: outputFormat,
                command: "terminate",
                code: "volume_lookup_failed",
                message: message
            )
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return failure(
                    outputFormat: outputFormat,
                    command: "terminate",
                    code: "scan_failed",
                    message: message,
                    volume: volume
                )
            case .success(let groups):
                if groups.isEmpty {
                    if outputFormat == .json {
                        return jsonResult(
                            command: "terminate",
                            success: true,
                            data: CLIJSONTerminationResult(
                                volume: CLIJSONVolume(volume),
                                dryRun: options.dryRun,
                                targets: [],
                                results: []
                            )
                        )
                    }
                    return .success("No blocking processes found on \(volume.name).")
                }

                let targets = options.selection.matchingProcesses(in: groups)
                guard !targets.isEmpty else {
                    return failure(
                        outputFormat: outputFormat,
                        command: "terminate",
                        code: "no_matching_processes",
                        message: "No matching processes for the provided selection.",
                        volume: volume
                    )
                }

                let targetPayloads = jsonProcesses(targets, in: groups)
                if !options.selection.hasFilters,
                   !options.explicitlyIncludesAll,
                   !options.dryRun {
                    return unsafeUnfilteredFailure(
                        command: "terminate",
                        volume: volume,
                        targets: targets,
                        targetPayloads: targetPayloads,
                        outputFormat: outputFormat
                    )
                }

                if options.dryRun {
                    return dryRunResult(
                        command: "terminate",
                        volume: volume,
                        targets: targets,
                        targetPayloads: targetPayloads,
                        groups: groups,
                        outputFormat: outputFormat,
                        includesEject: false
                    )
                }

                let results = await processTerminator.terminateAll(
                    processes: targets,
                    gracePeriod: options.gracePeriod
                )
                let summary = summarizeTerminationResults(targets: targets, results: results)

                if outputFormat == .json {
                    return jsonResult(
                        command: "terminate",
                        success: !summary.hasFailures,
                        exitCode: summary.hasFailures ? 1 : 0,
                        data: CLIJSONTerminationResult(
                            volume: CLIJSONVolume(volume),
                            dryRun: false,
                            targets: targetPayloads,
                            results: jsonTerminationRecords(targets: targets, results: results)
                        )
                    )
                }

                return CLIExecutionResult(
                    exitCode: summary.hasFailures ? 1 : 0,
                    stdout: summary.stdout.joined(separator: "\n"),
                    stderr: summary.stderr.joined(separator: "\n")
                )
            }
        }
    }

    private func eject(
        volumeQuery: String,
        outputFormat: CLIOutputFormat
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return failure(
                outputFormat: outputFormat,
                command: "eject",
                code: "volume_lookup_failed",
                message: message
            )
        case .success(let volume):
            switch await diskEjector.eject(volume: volume) {
            case .success:
                if outputFormat == .json {
                    return jsonResult(
                        command: "eject",
                        success: true,
                        data: CLIJSONEjectResult(
                            volume: CLIJSONVolume(volume),
                            ejected: true,
                            error: nil
                        )
                    )
                }
                return .success("Ejected \(volume.name).")
            case .failed(let message):
                if outputFormat == .json {
                    return jsonResult(
                        command: "eject",
                        success: false,
                        exitCode: 1,
                        data: CLIJSONEjectResult(
                            volume: CLIJSONVolume(volume),
                            ejected: false,
                            error: message
                        )
                    )
                }
                return .failure("Failed to eject \(volume.name): \(message)")
            }
        }
    }

    private func terminateAndEject(
        volumeQuery: String,
        options: CLITerminationOptions,
        outputFormat: CLIOutputFormat
    ) async -> CLIExecutionResult {
        switch await loadVolume(matching: volumeQuery) {
        case .failure(let message):
            return failure(
                outputFormat: outputFormat,
                command: "terminate-and-eject",
                code: "volume_lookup_failed",
                message: message
            )
        case .success(let volume):
            switch await scanGroups(for: volume) {
            case .failure(let message):
                return failure(
                    outputFormat: outputFormat,
                    command: "terminate-and-eject",
                    code: "scan_failed",
                    message: message,
                    volume: volume
                )
            case .success(let groups):
                let targets = options.selection.matchingProcesses(in: groups)

                if !groups.isEmpty && targets.isEmpty {
                    return failure(
                        outputFormat: outputFormat,
                        command: "terminate-and-eject",
                        code: "no_matching_processes",
                        message: "No matching processes for the provided selection.",
                        volume: volume
                    )
                }

                let targetPayloads = jsonProcesses(targets, in: groups)
                if !groups.isEmpty,
                   !options.selection.hasFilters,
                   !options.explicitlyIncludesAll,
                   !options.dryRun {
                    return unsafeUnfilteredFailure(
                        command: "terminate-and-eject",
                        volume: volume,
                        targets: targets,
                        targetPayloads: targetPayloads,
                        outputFormat: outputFormat
                    )
                }

                if options.dryRun {
                    return dryRunResult(
                        command: "terminate-and-eject",
                        volume: volume,
                        targets: targets,
                        targetPayloads: targetPayloads,
                        groups: groups,
                        outputFormat: outputFormat,
                        includesEject: true
                    )
                }

                let workflow = TerminateAndEjectService(
                    processTerminator: processTerminator,
                    diskEjector: diskEjector
                )
                let outcome = await workflow.execute(
                    volume: volume,
                    processes: targets,
                    gracePeriod: options.gracePeriod
                )

                let summary = summarizeTerminationResults(
                    targets: targets,
                    results: outcome.terminationResults
                )
                let ejectError: String?
                let ejected: Bool

                switch outcome.ejectResult {
                case .success:
                    ejected = true
                    ejectError = nil
                case .failed(let message):
                    ejected = false
                    ejectError = message
                }

                let hasFailures = summary.hasFailures || !ejected
                if outputFormat == .json {
                    return jsonResult(
                        command: "terminate-and-eject",
                        success: !hasFailures,
                        exitCode: hasFailures ? 1 : 0,
                        data: CLIJSONTerminateAndEjectResult(
                            volume: CLIJSONVolume(volume),
                            dryRun: false,
                            targets: targetPayloads,
                            terminationResults: jsonTerminationRecords(
                                targets: targets,
                                results: outcome.terminationResults
                            ),
                            ejected: ejected,
                            ejectError: ejectError
                        )
                    )
                }

                var stdout: [String] = []
                var stderr = summary.stderr

                if groups.isEmpty {
                    stdout.append("No blocking processes found on \(volume.name).")
                } else {
                    stdout.append(contentsOf: summary.stdout)
                }

                if ejected {
                    stdout.append("Ejected \(volume.name).")
                } else if let ejectError {
                    stderr.append("Failed to eject \(volume.name): \(ejectError)")
                }

                return CLIExecutionResult(
                    exitCode: hasFailures ? 1 : 0,
                    stdout: stdout.joined(separator: "\n"),
                    stderr: stderr.joined(separator: "\n")
                )
            }
        }
    }

    private func refreshVolumes() async -> [ExternalVolume] {
        await volumeMonitor.refreshVolumes()
        return await volumeMonitor.volumes
    }

    private func loadVolume(matching query: String) async -> VolumeLookupResult {
        let volumes = await refreshVolumes()
        return resolveVolume(matching: query, in: volumes)
    }

    private func scanGroups(for volume: ExternalVolume) async -> GroupLookupResult {
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
                let files = canonicalLockedFiles(process.lockedFiles)
                if files.isEmpty {
                    lines.append("  Locked files: none")
                } else {
                    lines.append(contentsOf: files.map { "  Locked file: \(escapedPath($0))" })
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func unsafeUnfilteredFailure(
        command: String,
        volume: ExternalVolume,
        targets: [BlockingProcess],
        targetPayloads: [CLIJSONProcess],
        outputFormat: CLIOutputFormat
    ) -> CLIExecutionResult {
        let message = "Refusing to terminate every blocking process without explicit --all. Use --dry-run to preview targets safely."

        if outputFormat == .json {
            return .failure(CLIJSONOutput.error(
                command: command,
                code: "confirmation_required",
                message: message,
                context: CLIJSONErrorContext(
                    volume: CLIJSONVolume(volume),
                    targets: targetPayloads
                )
            ), exitCode: 64)
        }

        return .failure(
            "\(message)\n\nResolved targets:\n\(formatTargetPreview(targets: targets, groups: []))",
            exitCode: 64
        )
    }

    private func dryRunResult(
        command: String,
        volume: ExternalVolume,
        targets: [BlockingProcess],
        targetPayloads: [CLIJSONProcess],
        groups: [ProcessGroup],
        outputFormat: CLIOutputFormat,
        includesEject: Bool
    ) -> CLIExecutionResult {
        if outputFormat == .json {
            if includesEject {
                return jsonResult(
                    command: command,
                    success: true,
                    data: CLIJSONTerminateAndEjectResult(
                        volume: CLIJSONVolume(volume),
                        dryRun: true,
                        targets: targetPayloads,
                        terminationResults: [],
                        ejected: false,
                        ejectError: nil
                    )
                )
            }

            return jsonResult(
                command: command,
                success: true,
                data: CLIJSONTerminationResult(
                    volume: CLIJSONVolume(volume),
                    dryRun: true,
                    targets: targetPayloads,
                    results: []
                )
            )
        }

        var lines = [
            "Dry run: no processes will be signaled\(includesEject ? " and the volume will not be ejected" : "").",
            "Volume: \(volume.name) (\(volume.deviceIdentifier))",
            "Resolved targets:",
        ]
        lines.append(formatTargetPreview(targets: targets, groups: groups))
        return .success(lines.joined(separator: "\n"))
    }

    private func formatTargetPreview(
        targets: [BlockingProcess],
        groups: [ProcessGroup]
    ) -> String {
        guard !targets.isEmpty else {
            return "  none"
        }

        let categories = categoryByPID(in: groups)
        return targets.map { process in
            let category = categories[process.pid]?.rawValue ?? inferredCategory(for: process).rawValue
            return "  PID \(process.pid) | \(category) | \(process.user) | \(process.command)"
        }.joined(separator: "\n")
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

    private func jsonGroups(_ groups: [ProcessGroup]) -> [CLIJSONProcessGroup] {
        groups.map { group in
            CLIJSONProcessGroup(
                category: group.category.rawValue,
                processes: group.processes.map { jsonProcess($0, category: group.category) }
            )
        }
    }

    private func jsonProcesses(
        _ processes: [BlockingProcess],
        in groups: [ProcessGroup]
    ) -> [CLIJSONProcess] {
        let categories = categoryByPID(in: groups)
        return processes.map { process in
            jsonProcess(
                process,
                category: categories[process.pid] ?? inferredCategory(for: process)
            )
        }
    }

    private func jsonProcess(
        _ process: BlockingProcess,
        category: ProcessCategory
    ) -> CLIJSONProcess {
        CLIJSONProcess(
            category: category.rawValue,
            pid: process.pid,
            user: process.user,
            uid: process.uid,
            command: process.command,
            isRoot: process.isRoot,
            lockedFiles: canonicalLockedFiles(process.lockedFiles)
        )
    }

    private func jsonTerminationRecords(
        targets: [BlockingProcess],
        results: [Int32: TerminationResult]
    ) -> [CLIJSONTerminationRecord] {
        targets.map { process in
            switch results[process.pid] ?? .failed("No termination result returned") {
            case .terminated:
                return CLIJSONTerminationRecord(
                    pid: process.pid,
                    command: process.command,
                    status: "terminated",
                    message: nil
                )
            case .alreadyExited:
                return CLIJSONTerminationRecord(
                    pid: process.pid,
                    command: process.command,
                    status: "already_exited",
                    message: nil
                )
            case .failed(let message):
                return CLIJSONTerminationRecord(
                    pid: process.pid,
                    command: process.command,
                    status: "failed",
                    message: message
                )
            }
        }
    }

    private func categoryByPID(in groups: [ProcessGroup]) -> [Int32: ProcessCategory] {
        var result: [Int32: ProcessCategory] = [:]
        for group in groups {
            for process in group.processes where result[process.pid] == nil {
                result[process.pid] = group.category
            }
        }
        return result
    }

    private func inferredCategory(for process: BlockingProcess) -> ProcessCategory {
        if process.command == "mds" || process.command == "mds_stores" {
            return .spotlight
        }
        return process.isRoot ? .system : .user
    }

    private func canonicalLockedFiles(_ paths: [String]) -> [String] {
        Array(Set(paths)).sorted()
    }

    private func escapedPath(_ path: String) -> String {
        var escaped = "\""
        for scalar in path.unicodeScalars {
            switch scalar.value {
            case 0x22:
                escaped += "\\\""
            case 0x5C:
                escaped += "\\\\"
            case 0x08:
                escaped += "\\b"
            case 0x09:
                escaped += "\\t"
            case 0x0A:
                escaped += "\\n"
            case 0x0C:
                escaped += "\\f"
            case 0x0D:
                escaped += "\\r"
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }

    private func jsonResult<Payload: Encodable>(
        command: String,
        success: Bool,
        exitCode: Int = 0,
        data: Payload
    ) -> CLIExecutionResult {
        CLIExecutionResult(
            exitCode: exitCode,
            stdout: CLIJSONOutput.result(command: command, success: success, data: data),
            stderr: ""
        )
    }

    private func failure(
        outputFormat: CLIOutputFormat,
        command: String,
        code: String,
        message: String,
        exitCode: Int = 1,
        volume: ExternalVolume? = nil
    ) -> CLIExecutionResult {
        guard outputFormat == .json else {
            return .failure(message, exitCode: exitCode)
        }

        let context = volume.map {
            CLIJSONErrorContext(volume: CLIJSONVolume($0))
        }
        return .failure(
            CLIJSONOutput.error(
                command: command,
                code: code,
                message: message,
                context: context
            ),
            exitCode: exitCode
        )
    }

    private func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func volumeSort(_ lhs: ExternalVolume, _ rhs: ExternalVolume) -> Bool {
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.deviceIdentifier < rhs.deviceIdentifier
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

    private func resolveVolume(
        matching query: String,
        in volumes: [ExternalVolume]
    ) -> VolumeLookupResult {
        guard !volumes.isEmpty else {
            return .failure("No external volumes found.")
        }

        if let exactDeviceIdentifierMatch = resolveUniqueVolumeMatch(
            for: query,
            matches: volumes.filter { $0.deviceIdentifier.localizedCaseInsensitiveCompare(query) == .orderedSame }
        ) {
            return exactDeviceIdentifierMatch
        }

        if let exactMountPointMatch = resolveUniqueVolumeMatch(
            for: query,
            matches: volumes.filter { $0.mountPoint.path == query }
        ) {
            return exactMountPointMatch
        }

        if let exactNameMatch = resolveUniqueVolumeMatch(
            for: query,
            matches: volumes.filter { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
        ) {
            return exactNameMatch
        }

        let fuzzyMatches = volumes.filter { volume in
            volume.name.localizedCaseInsensitiveContains(query)
                || volume.deviceIdentifier.localizedCaseInsensitiveContains(query)
                || volume.mountPoint.path.localizedCaseInsensitiveContains(query)
        }

        if let fuzzyMatch = resolveUniqueVolumeMatch(for: query, matches: fuzzyMatches) {
            return fuzzyMatch
        }

        return .failure("No external volume matched query: \(query)")
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

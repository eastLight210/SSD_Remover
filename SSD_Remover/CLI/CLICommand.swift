import Foundation

enum CLIOutputFormat: String, Equatable, Sendable {
    case human
    case json
}

enum CLIHelpTopic: String, Equatable, Sendable {
    case global
    case list
    case scan
    case terminate
    case eject
    case terminateAndEject = "terminate-and-eject"
    case version
}

struct CLITerminationOptions: Equatable, Sendable {
    let selection: CLIProcessSelection
    let gracePeriod: TimeInterval
    let explicitlyIncludesAll: Bool
    let dryRun: Bool

    init(
        selection: CLIProcessSelection = .unfiltered,
        gracePeriod: TimeInterval = 3,
        explicitlyIncludesAll: Bool = false,
        dryRun: Bool = false
    ) {
        self.selection = selection
        self.gracePeriod = gracePeriod
        self.explicitlyIncludesAll = explicitlyIncludesAll
        self.dryRun = dryRun
    }
}

enum CLICommandAction: Equatable, Sendable {
    case help(CLIHelpTopic)
    case version
    case listVolumes
    case scan(volumeQuery: String)
    case terminate(volumeQuery: String, options: CLITerminationOptions)
    case eject(volumeQuery: String)
    case terminateAndEject(volumeQuery: String, options: CLITerminationOptions)
}

struct CLICommand: Equatable, Sendable {
    let action: CLICommandAction
    let outputFormat: CLIOutputFormat

    init(action: CLICommandAction, outputFormat: CLIOutputFormat = .human) {
        self.action = action
        self.outputFormat = outputFormat
    }

    static let help = CLICommand(action: .help(.global))
    static let version = CLICommand(action: .version)
    static let listVolumes = CLICommand(action: .listVolumes)

    static func help(topic: CLIHelpTopic) -> CLICommand {
        CLICommand(action: .help(topic))
    }

    static func listVolumes(outputFormat: CLIOutputFormat) -> CLICommand {
        CLICommand(action: .listVolumes, outputFormat: outputFormat)
    }

    static func scan(
        volumeQuery: String,
        outputFormat: CLIOutputFormat = .human
    ) -> CLICommand {
        CLICommand(
            action: .scan(volumeQuery: volumeQuery),
            outputFormat: outputFormat
        )
    }

    static func terminate(
        volumeQuery: String,
        selection: CLIProcessSelection,
        gracePeriod: TimeInterval,
        explicitlyIncludesAll: Bool = false,
        dryRun: Bool = false,
        outputFormat: CLIOutputFormat = .human
    ) -> CLICommand {
        CLICommand(
            action: .terminate(
                volumeQuery: volumeQuery,
                options: CLITerminationOptions(
                    selection: selection,
                    gracePeriod: gracePeriod,
                    explicitlyIncludesAll: explicitlyIncludesAll,
                    dryRun: dryRun
                )
            ),
            outputFormat: outputFormat
        )
    }

    static func eject(
        volumeQuery: String,
        outputFormat: CLIOutputFormat = .human
    ) -> CLICommand {
        CLICommand(
            action: .eject(volumeQuery: volumeQuery),
            outputFormat: outputFormat
        )
    }

    static func terminateAndEject(
        volumeQuery: String,
        selection: CLIProcessSelection,
        gracePeriod: TimeInterval,
        explicitlyIncludesAll: Bool = false,
        dryRun: Bool = false,
        outputFormat: CLIOutputFormat = .human
    ) -> CLICommand {
        CLICommand(
            action: .terminateAndEject(
                volumeQuery: volumeQuery,
                options: CLITerminationOptions(
                    selection: selection,
                    gracePeriod: gracePeriod,
                    explicitlyIncludesAll: explicitlyIncludesAll,
                    dryRun: dryRun
                )
            ),
            outputFormat: outputFormat
        )
    }

    var name: String {
        switch action {
        case .help:
            return "help"
        case .version:
            return "version"
        case .listVolumes:
            return "list"
        case .scan:
            return "scan"
        case .terminate:
            return "terminate"
        case .eject:
            return "eject"
        case .terminateAndEject:
            return "terminate-and-eject"
        }
    }
}

struct CLIProcessSelection: Equatable, Sendable {
    let categories: Set<ProcessCategory>
    let pids: Set<Int32>

    static let unfiltered = CLIProcessSelection()

    init(
        categories: [ProcessCategory] = [],
        pids: [Int32] = []
    ) {
        self.categories = Set(categories)
        self.pids = Set(pids)
    }

    var hasFilters: Bool {
        !categories.isEmpty || !pids.isEmpty
    }

    func matchingProcesses(in groups: [ProcessGroup]) -> [BlockingProcess] {
        let scopedGroups = categories.isEmpty
            ? groups
            : groups.filter { categories.contains($0.category) }

        let scopedProcesses = scopedGroups.flatMap(\.processes)
        guard !pids.isEmpty else {
            return scopedProcesses
        }

        return scopedProcesses.filter { pids.contains($0.pid) }
    }
}

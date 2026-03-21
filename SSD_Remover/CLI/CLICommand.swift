import Foundation

enum CLICommand: Equatable, Sendable {
    case help
    case listVolumes
    case scan(volumeQuery: String)
    case terminate(volumeQuery: String, selection: CLIProcessSelection, gracePeriod: TimeInterval)
    case eject(volumeQuery: String)
    case terminateAndEject(volumeQuery: String, selection: CLIProcessSelection, gracePeriod: TimeInterval)
}

struct CLIProcessSelection: Equatable, Sendable {
    let categories: Set<ProcessCategory>
    let pids: Set<Int32>

    static let all = CLIProcessSelection()

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

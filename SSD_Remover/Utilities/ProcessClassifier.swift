import Foundation

enum ProcessClassifier {

    private static let spotlightCommands: Set<String> = ["mds", "mds_stores"]

    static func classify(_ processes: [BlockingProcess]) -> [ProcessGroup] {
        var spotlight: [BlockingProcess] = []
        var system: [BlockingProcess] = []
        var user: [BlockingProcess] = []

        for process in processes {
            if spotlightCommands.contains(process.command) {
                spotlight.append(process)
            } else if process.uid == 0 {
                system.append(process)
            } else {
                user.append(process)
            }
        }

        var groups: [ProcessGroup] = []
        if !spotlight.isEmpty {
            groups.append(ProcessGroup(category: .spotlight, processes: spotlight))
        }
        if !system.isEmpty {
            groups.append(ProcessGroup(category: .system, processes: system))
        }
        if !user.isEmpty {
            groups.append(ProcessGroup(category: .user, processes: user))
        }

        return groups
    }
}

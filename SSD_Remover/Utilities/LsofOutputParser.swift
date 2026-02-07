import Foundation

enum LsofOutputParser {

    static func parse(_ output: String) -> [BlockingProcess] {
        guard !output.isEmpty else { return [] }

        var processes: [BlockingProcess] = []
        var currentPID: Int32?
        var currentCommand: String = ""
        var currentUser: String = ""
        var currentUID: Int32 = 0
        var currentFiles: [String] = []

        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }

            let prefix = line.first!
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                if let pid = currentPID {
                    processes.append(BlockingProcess(
                        pid: pid,
                        command: currentCommand,
                        user: currentUser,
                        uid: currentUID,
                        lockedFiles: currentFiles
                    ))
                }
                currentPID = Int32(value)
                currentCommand = ""
                currentUser = ""
                currentUID = 0
                currentFiles = []
            case "c":
                currentCommand = value
            case "u":
                currentUID = Int32(value) ?? 0
            case "L":
                currentUser = value
            case "n":
                currentFiles.append(value)
            default:
                break
            }
        }

        if let pid = currentPID {
            processes.append(BlockingProcess(
                pid: pid,
                command: currentCommand,
                user: currentUser,
                uid: currentUID,
                lockedFiles: currentFiles
            ))
        }

        return processes
    }
}

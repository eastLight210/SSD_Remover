import Foundation

enum CLIParseError: Error, Equatable {
    case unknownCommand(String)
    case unknownOption(String)
    case missingVolumeQuery(String)
    case unexpectedArguments(command: String, arguments: [String])
    case missingValue(String)
    case invalidGroup(String)
    case invalidPID(String)
    case invalidGracePeriod(String)
}

extension CLIParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            "Unknown command: \(command)"
        case .unknownOption(let option):
            "Unknown option: \(option)"
        case .missingVolumeQuery(let command):
            "Missing volume query for command: \(command)"
        case .unexpectedArguments(let command, let arguments):
            "Unexpected extra arguments for command \(command): \(arguments.joined(separator: " "))"
        case .missingValue(let option):
            "Missing value for option: \(option)"
        case .invalidGroup(let group):
            "Invalid group: \(group)"
        case .invalidPID(let value):
            "Invalid PID: \(value)"
        case .invalidGracePeriod(let value):
            "Invalid grace period: \(value)"
        }
    }
}

struct CLICommandParser {
    static let usageText = """
    Usage: SSD_Remover <command> [arguments] [options]

    Commands:
      list
      scan <volume-query>
      terminate <volume-query> [--group <user|system|spotlight>]... [--pid <pid>]... [--grace-period <seconds>]
      eject <volume-query>
      terminate-and-eject <volume-query> [--group <user|system|spotlight>]... [--pid <pid>]... [--grace-period <seconds>]
      help
    """

    func parse(arguments: [String]) throws -> CLICommand {
        guard let rawCommand = arguments.first else {
            return .help
        }

        switch rawCommand {
        case "help", "-h", "--help":
            return .help
        case "list", "ls":
            return .listVolumes
        case "scan":
            let volumeQuery = try parseVolumeQuery(for: rawCommand, arguments: Array(arguments.dropFirst()))
            return .scan(volumeQuery: volumeQuery)
        case "eject":
            let volumeQuery = try parseVolumeQuery(for: rawCommand, arguments: Array(arguments.dropFirst()))
            return .eject(volumeQuery: volumeQuery)
        case "terminate":
            let parsed = try parseTerminationArguments(
                command: rawCommand,
                arguments: Array(arguments.dropFirst())
            )
            return .terminate(
                volumeQuery: parsed.volumeQuery,
                selection: parsed.selection,
                gracePeriod: parsed.gracePeriod
            )
        case "terminate-and-eject":
            let parsed = try parseTerminationArguments(
                command: rawCommand,
                arguments: Array(arguments.dropFirst())
            )
            return .terminateAndEject(
                volumeQuery: parsed.volumeQuery,
                selection: parsed.selection,
                gracePeriod: parsed.gracePeriod
            )
        default:
            throw CLIParseError.unknownCommand(rawCommand)
        }
    }

    private func parseVolumeQuery(for command: String, arguments: [String]) throws -> String {
        guard let volumeQuery = arguments.first else {
            throw CLIParseError.missingVolumeQuery(command)
        }

        let extraArguments = Array(arguments.dropFirst())
        guard extraArguments.isEmpty else {
            throw CLIParseError.unexpectedArguments(command: command, arguments: extraArguments)
        }

        return volumeQuery
    }

    private func parseTerminationArguments(
        command: String,
        arguments: [String]
    ) throws -> (volumeQuery: String, selection: CLIProcessSelection, gracePeriod: TimeInterval) {
        guard let volumeQuery = arguments.first else {
            throw CLIParseError.missingVolumeQuery(command)
        }

        var categories: [ProcessCategory] = []
        var pids: [Int32] = []
        var gracePeriod: TimeInterval = 3.0
        var index = 1

        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--group":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.missingValue(option)
                }
                let rawGroup = arguments[index].lowercased()
                guard let group = ProcessCategory(rawValue: rawGroup) else {
                    throw CLIParseError.invalidGroup(arguments[index])
                }
                categories.append(group)
            case "--pid":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.missingValue(option)
                }
                guard let pid = Int32(arguments[index]), pid > 0 else {
                    throw CLIParseError.invalidPID(arguments[index])
                }
                pids.append(pid)
            case "--grace-period":
                index += 1
                guard index < arguments.count else {
                    throw CLIParseError.missingValue(option)
                }
                guard let parsedGracePeriod = TimeInterval(arguments[index]),
                      parsedGracePeriod.isFinite,
                      parsedGracePeriod >= 0 else {
                    throw CLIParseError.invalidGracePeriod(arguments[index])
                }
                gracePeriod = parsedGracePeriod
            default:
                throw CLIParseError.unknownOption(option)
            }
            index += 1
        }

        return (
            volumeQuery,
            CLIProcessSelection(categories: categories, pids: pids),
            gracePeriod
        )
    }
}

import Foundation

enum CLIParseError: Error, Equatable {
    case unknownCommand(String)
    case unknownOption(String)
    case duplicateOption(String)
    case conflictingOptions(String, String)
    case missingVolumeQuery(String)
    case invalidVolumeQuery(String)
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
            return "Unknown command: \(command)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .duplicateOption(let option):
            return "Option may only be provided once: \(option)"
        case .conflictingOptions(let first, let second):
            return "Options cannot be combined: \(first) and \(second)"
        case .missingVolumeQuery(let command):
            return "Missing volume query for command: \(command)"
        case .invalidVolumeQuery(let value):
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayValue = trimmedValue.isEmpty ? "<blank>" : value
            return "Invalid volume query: \(displayValue)"
        case .unexpectedArguments(let command, let arguments):
            return "Unexpected extra arguments for command \(command): \(arguments.joined(separator: " "))"
        case .missingValue(let option):
            return "Missing value for option: \(option)"
        case .invalidGroup(let group):
            return "Invalid group: \(group)"
        case .invalidPID(let value):
            return "Invalid PID: \(value)"
        case .invalidGracePeriod(let value):
            return "Invalid grace period: \(value)"
        }
    }
}

struct CLICommandParser {
    static let usageText = """
    Usage: SSD_Remover <command> [arguments] [options]

    Commands:
      list                   List mounted external volumes
      scan                   Show processes and files blocking a volume
      terminate              Terminate selected blocking processes
      eject                  Eject a volume without terminating processes
      terminate-and-eject    Terminate selected blockers, then eject
      version                Print app version and build number
      help                   Show this help

    Run 'SSD_Remover <command> --help' for command details and examples.
    Operational commands accept --json for schema-versioned machine output.
    """

    static func helpText(for topic: CLIHelpTopic) -> String {
        switch topic {
        case .global:
            return usageText
        case .list:
            return """
            Usage: SSD_Remover list [--json]

            Lists mounted external volumes with their names, device identifiers, and mount paths.

            Options:
              --json    Emit the stable JSON schema instead of human-readable text.

            Example:
              SSD_Remover list

            Exit codes: 0 success, 1 runtime failure, 64 command-line usage error.
            """
        case .scan:
            return """
            Usage: SSD_Remover scan <volume-query> [--json]

            Scans a resolved external volume and prints each blocking process and locked file.
            <volume-query> may be a device identifier, exact mount path, volume name, or a unique
            case-insensitive partial match. Ambiguous matches list candidates for disambiguation.

            Options:
              --json    Emit the stable JSON schema, including process categories and locked files.

            Examples:
              SSD_Remover scan disk4s1
              SSD_Remover scan '/Volumes/Backup SSD' --json

            Exit codes: 0 success, 1 runtime failure, 64 command-line usage error.
            """
        case .terminate:
            return terminationHelp(command: "terminate", ejects: false)
        case .eject:
            return """
            Usage: SSD_Remover eject <volume-query> [--json]

            Ejects the resolved volume without terminating blocking processes. The volume query
            uses exact device identifier, mount path, or name matching before a unique fuzzy match.

            Options:
              --json    Emit the stable JSON schema instead of human-readable text.

            Example:
              SSD_Remover eject disk4s1

            Safety: this command invokes diskutil and may fail while processes still hold files.
            Exit codes: 0 success, 1 runtime failure, 64 command-line usage error.
            """
        case .terminateAndEject:
            return terminationHelp(command: "terminate-and-eject", ejects: true)
        case .version:
            return """
            Usage: SSD_Remover version
                   SSD_Remover --version

            Prints CFBundleShortVersionString and CFBundleVersion from the installed app bundle.

            Example:
              SSD_Remover version

            Exit codes: 0 success, 1 when bundle version metadata is unavailable, 64 usage error.
            """
        }
    }

    func parse(arguments: [String]) throws -> CLICommand {
        guard let rawCommand = arguments.first else {
            return .help
        }

        let commandArguments = Array(arguments.dropFirst())

        switch rawCommand {
        case "help", "-h", "--help":
            try requireNoArguments(command: rawCommand, arguments: commandArguments)
            return .help
        case "version", "--version", "-v":
            if isScopedHelp(commandArguments) {
                return .help(topic: .version)
            }
            try requireNoArguments(command: rawCommand, arguments: commandArguments)
            return .version
        case "list", "ls":
            if isScopedHelp(commandArguments) {
                return .help(topic: .list)
            }
            let parsed = try extractOutputFormat(from: commandArguments)
            try requireNoArguments(command: rawCommand, arguments: parsed.arguments)
            return .listVolumes(outputFormat: parsed.outputFormat)
        case "scan":
            if isScopedHelp(commandArguments) {
                return .help(topic: .scan)
            }
            let parsed = try extractOutputFormat(from: commandArguments)
            let volumeQuery = try parseVolumeQuery(for: rawCommand, arguments: parsed.arguments)
            return .scan(volumeQuery: volumeQuery, outputFormat: parsed.outputFormat)
        case "eject":
            if isScopedHelp(commandArguments) {
                return .help(topic: .eject)
            }
            let parsed = try extractOutputFormat(from: commandArguments)
            let volumeQuery = try parseVolumeQuery(for: rawCommand, arguments: parsed.arguments)
            return .eject(volumeQuery: volumeQuery, outputFormat: parsed.outputFormat)
        case "terminate":
            if isScopedHelp(commandArguments) {
                return .help(topic: .terminate)
            }
            let parsed = try extractOutputFormat(from: commandArguments)
            let termination = try parseTerminationArguments(
                command: rawCommand,
                arguments: parsed.arguments
            )
            return .terminate(
                volumeQuery: termination.volumeQuery,
                selection: termination.options.selection,
                gracePeriod: termination.options.gracePeriod,
                explicitlyIncludesAll: termination.options.explicitlyIncludesAll,
                dryRun: termination.options.dryRun,
                outputFormat: parsed.outputFormat
            )
        case "terminate-and-eject":
            if isScopedHelp(commandArguments) {
                return .help(topic: .terminateAndEject)
            }
            let parsed = try extractOutputFormat(from: commandArguments)
            let termination = try parseTerminationArguments(
                command: rawCommand,
                arguments: parsed.arguments
            )
            return .terminateAndEject(
                volumeQuery: termination.volumeQuery,
                selection: termination.options.selection,
                gracePeriod: termination.options.gracePeriod,
                explicitlyIncludesAll: termination.options.explicitlyIncludesAll,
                dryRun: termination.options.dryRun,
                outputFormat: parsed.outputFormat
            )
        default:
            throw CLIParseError.unknownCommand(rawCommand)
        }
    }

    private static func terminationHelp(command: String, ejects: Bool) -> String {
        let effect = ejects
            ? "Terminates the selected blockers, then attempts to eject the resolved volume."
            : "Terminates the selected blockers without ejecting the resolved volume."
        let exampleAction = ejects ? "terminate-and-eject" : "terminate"

        return """
        Usage: SSD_Remover \(command) <volume-query> [options]

        \(effect)
        <volume-query> uses exact device identifier, mount path, or name matching before a unique
        case-insensitive partial match. Ambiguous matches are rejected with candidate details.

        Selection options:
          --group <user|system|spotlight>    Repeatable process category filter.
          --pid <pid>                       Repeatable positive PID filter.
          --all                             Explicitly select every blocker when no filters are used.

        Other options:
          --grace-period <seconds>    Wait before SIGKILL (default: 3 seconds).
          --dry-run                   Resolve and print targets without sending signals or ejecting.
          --json                      Emit the stable JSON schema.

        Repeated group values are combined, repeated PID values are combined, and group plus PID
        filters form an intersection. With no filters, --all is required before any blocker is
        terminated. Use --dry-run without --all to preview the complete target set safely.

        Examples:
          SSD_Remover \(exampleAction) disk4s1 --group user
          SSD_Remover \(exampleAction) disk4s1 --pid 123 --pid 456 --grace-period 1.5
          SSD_Remover \(exampleAction) disk4s1 --dry-run --json
          SSD_Remover \(exampleAction) disk4s1 --all

        Safety: this command sends signals to processes.
        \(ejects ? "Disk ejection follows the termination attempt." : "No disk is ejected.")
        Exit codes: 0 success, 1 runtime/operation failure, 64 command-line usage error.
        """
    }

    private func isScopedHelp(_ arguments: [String]) -> Bool {
        arguments == ["--help"] || arguments == ["-h"]
    }

    private func requireNoArguments(command: String, arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIParseError.unexpectedArguments(command: command, arguments: arguments)
        }
    }

    private func extractOutputFormat(
        from arguments: [String]
    ) throws -> (arguments: [String], outputFormat: CLIOutputFormat) {
        var filteredArguments: [String] = []
        var foundJSON = false

        for argument in arguments {
            if argument == "--json" {
                guard !foundJSON else {
                    throw CLIParseError.duplicateOption(argument)
                }
                foundJSON = true
            } else {
                filteredArguments.append(argument)
            }
        }

        return (filteredArguments, foundJSON ? .json : .human)
    }

    private func parseVolumeQuery(for command: String, arguments: [String]) throws -> String {
        guard let volumeQuery = arguments.first else {
            throw CLIParseError.missingVolumeQuery(command)
        }
        if volumeQuery.hasPrefix("-") {
            throw CLIParseError.unknownOption(volumeQuery)
        }

        let trimmedVolumeQuery = volumeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVolumeQuery.isEmpty else {
            throw CLIParseError.invalidVolumeQuery(volumeQuery)
        }

        let extraArguments = Array(arguments.dropFirst())
        guard extraArguments.isEmpty else {
            throw CLIParseError.unexpectedArguments(command: command, arguments: extraArguments)
        }

        return trimmedVolumeQuery
    }

    private func parseTerminationArguments(
        command: String,
        arguments: [String]
    ) throws -> (volumeQuery: String, options: CLITerminationOptions) {
        guard let volumeQuery = arguments.first, !volumeQuery.hasPrefix("-") else {
            throw CLIParseError.missingVolumeQuery(command)
        }
        let trimmedVolumeQuery = volumeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVolumeQuery.isEmpty else {
            throw CLIParseError.invalidVolumeQuery(volumeQuery)
        }

        var categories: [ProcessCategory] = []
        var pids: [Int32] = []
        var gracePeriod: TimeInterval = 3
        var didSetGracePeriod = false
        var explicitlyIncludesAll = false
        var dryRun = false
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
                guard !didSetGracePeriod else {
                    throw CLIParseError.duplicateOption(option)
                }
                didSetGracePeriod = true
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
            case "--all":
                guard !explicitlyIncludesAll else {
                    throw CLIParseError.duplicateOption(option)
                }
                explicitlyIncludesAll = true
            case "--dry-run":
                guard !dryRun else {
                    throw CLIParseError.duplicateOption(option)
                }
                dryRun = true
            default:
                if option.hasPrefix("-") {
                    throw CLIParseError.unknownOption(option)
                }
                throw CLIParseError.unexpectedArguments(command: command, arguments: [option])
            }
            index += 1
        }

        let selection = CLIProcessSelection(categories: categories, pids: pids)
        if explicitlyIncludesAll && selection.hasFilters {
            throw CLIParseError.conflictingOptions("--all", "--group/--pid")
        }

        return (
            trimmedVolumeQuery,
            CLITerminationOptions(
                selection: selection,
                gracePeriod: gracePeriod,
                explicitlyIncludesAll: explicitlyIncludesAll,
                dryRun: dryRun
            )
        )
    }
}

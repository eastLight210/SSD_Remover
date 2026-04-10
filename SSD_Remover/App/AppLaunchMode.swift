import Foundation

enum AppLaunchMode: Equatable, Sendable {
    case menuBar
    case cli(arguments: [String])

    private static let systemArgumentPrefixes = ["-psn_", "-NS", "-Apple"]
    private static let systemArgumentPrefixesWithTrailingValues = ["-NS", "-Apple"]

    var isMenuBar: Bool {
        if case .menuBar = self {
            return true
        }
        return false
    }

    static func detect(arguments: [String]) -> AppLaunchMode {
        var filteredArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            guard let matchedPrefix = systemArgumentPrefixes.first(where: { argument.hasPrefix($0) }) else {
                filteredArguments.append(argument)
                index += 1
                continue
            }

            if systemArgumentPrefixesWithTrailingValues.contains(matchedPrefix),
               index + 1 < arguments.count,
               arguments[index + 1].hasPrefix("-") == false {
                index += 2
                continue
            }

            index += 1
        }

        if filteredArguments.isEmpty {
            return .menuBar
        }

        return .cli(arguments: filteredArguments)
    }
}

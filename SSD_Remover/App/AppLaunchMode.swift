import Foundation

enum AppLaunchMode: Equatable, Sendable {
    case menuBar
    case cli(arguments: [String])

    private static let systemArgumentPrefixes = ["-psn_", "-NS", "-Apple"]

    var isMenuBar: Bool {
        if case .menuBar = self {
            return true
        }
        return false
    }

    static func detect(arguments: [String]) -> AppLaunchMode {
        let filteredArguments = arguments.filter { argument in
            !systemArgumentPrefixes.contains(where: { argument.hasPrefix($0) })
        }

        if filteredArguments.isEmpty {
            return .menuBar
        }

        return .cli(arguments: filteredArguments)
    }
}

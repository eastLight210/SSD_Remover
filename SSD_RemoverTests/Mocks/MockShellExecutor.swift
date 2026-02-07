import Foundation
@testable import SSD_Remover

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    var stubbedResult: String = ""
    var stubbedError: Error?
    private(set) var executedCommands: [(command: String, arguments: [String])] = []

    func execute(command: String, arguments: [String]) async throws -> String {
        executedCommands.append((command: command, arguments: arguments))
        if let error = stubbedError {
            throw error
        }
        return stubbedResult
    }
}

import Foundation
@testable import SSD_Remover

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    var stubbedResult: String = ""
    var stubbedError: Error?
    var stubbedResults: [String] = []
    var stubbedErrors: [Error?] = []
    private(set) var executedCommands: [(command: String, arguments: [String])] = []
    private var callIndex: Int = 0

    func execute(command: String, arguments: [String]) async throws -> String {
        executedCommands.append((command: command, arguments: arguments))
        let currentIndex = callIndex
        callIndex += 1

        if currentIndex < stubbedErrors.count, let error = stubbedErrors[currentIndex] {
            throw error
        } else if stubbedErrors.isEmpty, let error = stubbedError {
            throw error
        }

        if currentIndex < stubbedResults.count {
            return stubbedResults[currentIndex]
        }
        return stubbedResult
    }
}

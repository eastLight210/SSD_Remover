import Foundation
@testable import SSD_Remover

final class MockPrivilegedExecutor: PrivilegedExecuting, @unchecked Sendable {
    var stubbedResult: String = ""
    var stubbedError: Error?
    private(set) var executedCommands: [String] = []

    func executeWithPrivileges(command: String) async throws -> String {
        executedCommands.append(command)
        if let error = stubbedError { throw error }
        return stubbedResult
    }
}

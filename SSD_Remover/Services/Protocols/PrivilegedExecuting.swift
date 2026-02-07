import Foundation

protocol PrivilegedExecuting: Sendable {
    func executeWithPrivileges(command: String) async throws -> String
}

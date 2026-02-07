import Foundation

protocol ShellExecuting: Sendable {
    func execute(command: String, arguments: [String]) async throws -> String
}

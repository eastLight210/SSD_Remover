import Foundation

protocol ProcessScanning: Sendable {
    func scanProcesses(for volume: ExternalVolume) async throws -> [ProcessGroup]
}

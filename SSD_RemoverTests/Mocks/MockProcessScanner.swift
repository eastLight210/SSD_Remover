import Foundation
@testable import SSD_Remover

final class MockProcessScanner: ProcessScanning, @unchecked Sendable {
    var stubbedResult: [ProcessGroup] = []
    var stubbedError: Error?
    private(set) var scannedVolumes: [ExternalVolume] = []

    func scanProcesses(for volume: ExternalVolume) async throws -> [ProcessGroup] {
        scannedVolumes.append(volume)
        if let error = stubbedError { throw error }
        return stubbedResult
    }
}

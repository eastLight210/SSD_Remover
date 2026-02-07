import Foundation
@testable import SSD_Remover

final class MockDiskEjector: DiskEjecting, @unchecked Sendable {
    var stubbedResult: EjectResult = .success
    private(set) var ejectCalled = false
    private(set) var ejectedVolume: ExternalVolume?

    func eject(volume: ExternalVolume) async -> EjectResult {
        ejectCalled = true
        ejectedVolume = volume
        return stubbedResult
    }
}

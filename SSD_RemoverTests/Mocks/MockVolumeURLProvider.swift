import Foundation
@testable import SSD_Remover

final class MockVolumeURLProvider: VolumeURLProviding, @unchecked Sendable {
    var stubbedURLs: [URL]? = []

    func mountedVolumeURLs(
        includingResourceValuesForKeys keys: [URLResourceKey]?,
        options: FileManager.VolumeEnumerationOptions
    ) -> [URL]? {
        stubbedURLs
    }
}

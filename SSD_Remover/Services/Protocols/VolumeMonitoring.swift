import Foundation

protocol VolumeURLProviding: Sendable {
    func mountedVolumeURLs(
        includingResourceValuesForKeys keys: [URLResourceKey]?,
        options: FileManager.VolumeEnumerationOptions
    ) -> [URL]?
}

extension FileManager: VolumeURLProviding {}
extension FileManager: @retroactive @unchecked Sendable {}

protocol VolumeMonitoring: Sendable {
    var volumes: [ExternalVolume] { get async }
    func startMonitoring() async
    func stopMonitoring() async
    func refreshVolumes() async
    func volumeUpdates() async -> AsyncStream<[ExternalVolume]>
}

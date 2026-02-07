import Foundation

struct ExternalVolume: Identifiable, Equatable, Hashable, Sendable {
    let id: URL
    let name: String
    let deviceIdentifier: String
    let fileSystem: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let mountPoint: URL

    var formattedCapacity: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let total = formatter.string(fromByteCount: totalCapacity)
        let available = formatter.string(fromByteCount: availableCapacity)
        return "\(available) / \(total)"
    }
}

import Foundation

struct ExternalVolume: Identifiable, Equatable, Hashable, Sendable {
    let id: URL
    let name: String
    let deviceIdentifier: String
    let fileSystem: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let mountPoint: URL

    var parentWholeDisk: String {
        deviceIdentifier.replacingOccurrences(
            of: "s\\d+$",
            with: "",
            options: .regularExpression
        )
    }

    var formattedCapacity: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let used = formatter.string(fromByteCount: totalCapacity - availableCapacity)
        let total = formatter.string(fromByteCount: totalCapacity)
        return "\(used) / \(total)"
    }
}

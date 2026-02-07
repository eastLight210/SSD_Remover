import Foundation

enum DiskInfoParserError: Error {
    case invalidPlistData
    case missingRequiredField(String)
}

struct DiskInfo: Sendable {
    let deviceIdentifier: String
    let fileSystem: String
    let isInternal: Bool
    let mountPoint: String
    let volumeName: String
    let totalSize: Int64
    let freeSpace: Int64

    func toExternalVolume() -> ExternalVolume {
        let url = URL(fileURLWithPath: mountPoint)
        return ExternalVolume(
            id: url,
            name: volumeName,
            deviceIdentifier: deviceIdentifier,
            fileSystem: fileSystem,
            totalCapacity: totalSize,
            availableCapacity: freeSpace,
            mountPoint: url
        )
    }
}

enum DiskInfoParser {
    static func parse(plistString: String) throws -> DiskInfo {
        guard let data = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskInfoParserError.invalidPlistData
        }

        guard let deviceIdentifier = plist["DeviceIdentifier"] as? String else {
            throw DiskInfoParserError.missingRequiredField("DeviceIdentifier")
        }
        guard let mountPoint = plist["MountPoint"] as? String else {
            throw DiskInfoParserError.missingRequiredField("MountPoint")
        }
        guard let volumeName = plist["VolumeName"] as? String else {
            throw DiskInfoParserError.missingRequiredField("VolumeName")
        }
        guard let totalSize = plist["TotalSize"] as? Int64 else {
            throw DiskInfoParserError.missingRequiredField("TotalSize")
        }
        guard let freeSpace = plist["FreeSpace"] as? Int64 else {
            throw DiskInfoParserError.missingRequiredField("FreeSpace")
        }

        let fileSystem = plist["FilesystemName"] as? String ?? "Unknown"
        let isInternal = plist["Internal"] as? Bool ?? false

        return DiskInfo(
            deviceIdentifier: deviceIdentifier,
            fileSystem: fileSystem,
            isInternal: isInternal,
            mountPoint: mountPoint,
            volumeName: volumeName,
            totalSize: totalSize,
            freeSpace: freeSpace
        )
    }
}

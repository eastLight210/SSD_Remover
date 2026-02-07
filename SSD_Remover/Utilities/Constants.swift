import Foundation

enum Constants {
    static let diskutilPath = "/usr/sbin/diskutil"
    static let lsofPath = "/usr/sbin/lsof"
    static let killPath = "/bin/kill"
    static let volumesMountPoint = "/Volumes"

    static let volumeResourceKeys: Set<URLResourceKey> = [
        .volumeNameKey,
        .volumeIsInternalKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeLocalizedFormatDescriptionKey,
    ]
}

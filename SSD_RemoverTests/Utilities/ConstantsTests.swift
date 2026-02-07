import Testing
import Foundation
@testable import SSD_Remover

@Suite("Constants Tests")
struct ConstantsTests {

    @Test("diskutil 경로가 올바름")
    func diskutilPath() {
        #expect(Constants.diskutilPath == "/usr/sbin/diskutil")
    }

    @Test("lsof 경로가 올바름")
    func lsofPath() {
        #expect(Constants.lsofPath == "/usr/sbin/lsof")
    }

    @Test("kill 경로가 올바름")
    func killPath() {
        #expect(Constants.killPath == "/bin/kill")
    }

    @Test("볼륨 리소스 키 세트가 필요한 키를 포함")
    func volumeResourceKeysContainsRequired() {
        let keys = Constants.volumeResourceKeys
        #expect(keys.contains(.volumeNameKey))
        #expect(keys.contains(.volumeIsInternalKey))
        #expect(keys.contains(.volumeTotalCapacityKey))
        #expect(keys.contains(.volumeAvailableCapacityKey))
        #expect(keys.contains(.volumeLocalizedFormatDescriptionKey))
    }

    @Test("Volumes 마운트 포인트 경로가 올바름")
    func volumesMountPoint() {
        #expect(Constants.volumesMountPoint == "/Volumes")
    }
}

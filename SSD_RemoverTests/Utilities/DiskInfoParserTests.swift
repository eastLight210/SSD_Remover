import Testing
import Foundation
@testable import SSD_Remover

@Suite("DiskInfoParser Tests")
struct DiskInfoParserTests {

    // MARK: - Sample plist data

    static let sampleExternalAPFS = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>DeviceIdentifier</key>
        <string>disk4s1</string>
        <key>DeviceNode</key>
        <string>/dev/disk4s1</string>
        <key>FilesystemName</key>
        <string>APFS</string>
        <key>Internal</key>
        <false/>
        <key>MountPoint</key>
        <string>/Volumes/Samsung T7</string>
        <key>VolumeName</key>
        <string>Samsung T7</string>
        <key>TotalSize</key>
        <integer>1000000000000</integer>
        <key>FreeSpace</key>
        <integer>500000000000</integer>
        <key>Ejectable</key>
        <true/>
    </dict>
    </plist>
    """

    static let sampleInternalDisk = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>DeviceIdentifier</key>
        <string>disk1s1</string>
        <key>DeviceNode</key>
        <string>/dev/disk1s1</string>
        <key>FilesystemName</key>
        <string>APFS</string>
        <key>Internal</key>
        <true/>
        <key>MountPoint</key>
        <string>/</string>
        <key>VolumeName</key>
        <string>Macintosh HD</string>
        <key>TotalSize</key>
        <integer>500000000000</integer>
        <key>FreeSpace</key>
        <integer>100000000000</integer>
    </dict>
    </plist>
    """

    static let sampleExternalExFAT = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>DeviceIdentifier</key>
        <string>disk5s1</string>
        <key>DeviceNode</key>
        <string>/dev/disk5s1</string>
        <key>FilesystemName</key>
        <string>ExFAT</string>
        <key>Internal</key>
        <false/>
        <key>MountPoint</key>
        <string>/Volumes/USB Drive</string>
        <key>VolumeName</key>
        <string>USB Drive</string>
        <key>TotalSize</key>
        <integer>64000000000</integer>
        <key>FreeSpace</key>
        <integer>32000000000</integer>
    </dict>
    </plist>
    """

    // MARK: - Tests

    @Test("외장 APFS 볼륨 파싱 성공")
    func parseExternalAPFS() throws {
        let result = try DiskInfoParser.parse(plistString: Self.sampleExternalAPFS)

        #expect(result.deviceIdentifier == "disk4s1")
        #expect(result.fileSystem == "APFS")
        #expect(result.isInternal == false)
        #expect(result.mountPoint == "/Volumes/Samsung T7")
        #expect(result.volumeName == "Samsung T7")
        #expect(result.totalSize == 1_000_000_000_000)
        #expect(result.freeSpace == 500_000_000_000)
    }

    @Test("내장 디스크 파싱 - isInternal이 true")
    func parseInternalDisk() throws {
        let result = try DiskInfoParser.parse(plistString: Self.sampleInternalDisk)

        #expect(result.deviceIdentifier == "disk1s1")
        #expect(result.isInternal == true)
        #expect(result.volumeName == "Macintosh HD")
    }

    @Test("외장 ExFAT 볼륨 파싱 성공")
    func parseExternalExFAT() throws {
        let result = try DiskInfoParser.parse(plistString: Self.sampleExternalExFAT)

        #expect(result.deviceIdentifier == "disk5s1")
        #expect(result.fileSystem == "ExFAT")
        #expect(result.isInternal == false)
        #expect(result.volumeName == "USB Drive")
        #expect(result.totalSize == 64_000_000_000)
        #expect(result.freeSpace == 32_000_000_000)
    }

    @Test("잘못된 plist 문자열은 에러 발생")
    func parseInvalidPlist() {
        #expect(throws: DiskInfoParserError.self) {
            _ = try DiskInfoParser.parse(plistString: "not a plist")
        }
    }

    @Test("필수 필드 누락 시 에러 발생")
    func parseMissingFields() {
        let incomplete = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key>
            <string>disk4s1</string>
        </dict>
        </plist>
        """

        #expect(throws: DiskInfoParserError.self) {
            _ = try DiskInfoParser.parse(plistString: incomplete)
        }
    }

    @Test("DiskInfo를 ExternalVolume으로 변환")
    func convertToExternalVolume() throws {
        let result = try DiskInfoParser.parse(plistString: Self.sampleExternalAPFS)
        let volume = result.toExternalVolume()

        #expect(volume.name == "Samsung T7")
        #expect(volume.deviceIdentifier == "disk4s1")
        #expect(volume.fileSystem == "APFS")
        #expect(volume.totalCapacity == 1_000_000_000_000)
        #expect(volume.availableCapacity == 500_000_000_000)
        #expect(volume.mountPoint.path == "/Volumes/Samsung T7")
    }

    // MARK: - Edge Case Tests

    @Test("TotalSize가 문자열이면 missingRequiredField 에러")
    func totalSizeAsStringThrows() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key><string>disk4s1</string>
            <key>MountPoint</key><string>/Volumes/Test</string>
            <key>VolumeName</key><string>Test</string>
            <key>TotalSize</key><string>not_a_number</string>
            <key>FreeSpace</key><integer>100</integer>
        </dict>
        </plist>
        """
        #expect(throws: DiskInfoParserError.self) {
            _ = try DiskInfoParser.parse(plistString: plist)
        }
    }

    @Test("FilesystemName 누락 시 Unknown 기본값")
    func filesystemNameMissingDefaultsToUnknown() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key><string>disk4s1</string>
            <key>MountPoint</key><string>/Volumes/Test</string>
            <key>VolumeName</key><string>Test</string>
            <key>TotalSize</key><integer>1000</integer>
            <key>FreeSpace</key><integer>500</integer>
        </dict>
        </plist>
        """
        let result = try DiskInfoParser.parse(plistString: plist)
        #expect(result.fileSystem == "Unknown")
    }

    @Test("특수문자 경로 (공백, 한글) 파싱 성공")
    func specialCharacterMountPoint() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key><string>disk4s1</string>
            <key>MountPoint</key><string>/Volumes/삼성 T7 외장</string>
            <key>VolumeName</key><string>삼성 T7 외장</string>
            <key>TotalSize</key><integer>1000000000000</integer>
            <key>FreeSpace</key><integer>500000000000</integer>
        </dict>
        </plist>
        """
        let result = try DiskInfoParser.parse(plistString: plist)
        #expect(result.mountPoint == "/Volumes/삼성 T7 외장")
        #expect(result.volumeName == "삼성 T7 외장")
    }
}

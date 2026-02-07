import Testing
import Foundation
@testable import SSD_Remover

@Suite("VolumeMonitorService Tests")
struct VolumeMonitorServiceTests {

    // MARK: - Helpers

    private func makeSamplePlist(
        deviceId: String = "disk4s1",
        name: String = "TestDrive",
        fileSystem: String = "APFS",
        isInternal: Bool = false,
        mountPoint: String = "/Volumes/TestDrive",
        totalSize: Int64 = 1_000_000_000_000,
        freeSpace: Int64 = 500_000_000_000
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key>
            <string>\(deviceId)</string>
            <key>FilesystemName</key>
            <string>\(fileSystem)</string>
            <key>Internal</key>
            <\(isInternal)/>
            <key>MountPoint</key>
            <string>\(mountPoint)</string>
            <key>VolumeName</key>
            <string>\(name)</string>
            <key>TotalSize</key>
            <integer>\(totalSize)</integer>
            <key>FreeSpace</key>
            <integer>\(freeSpace)</integer>
        </dict>
        </plist>
        """
    }

    // MARK: - Tests

    @Test("외장 볼륨이 없으면 빈 배열 반환")
    func noExternalVolumes() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = [
            URL(fileURLWithPath: "/")
        ]

        let mockShell = MockShellExecutor()
        // 내장 디스크 결과 반환
        mockShell.stubbedResult = makeSamplePlist(
            deviceId: "disk1s1", name: "Macintosh HD",
            isInternal: true, mountPoint: "/"
        )

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        await service.refreshVolumes()
        let volumes = await service.volumes

        #expect(volumes.isEmpty)
    }

    @Test("외장 볼륨이 있으면 목록에 포함")
    func externalVolumeDetected() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = [
            URL(fileURLWithPath: "/Volumes/Samsung T7")
        ]

        let mockShell = MockShellExecutor()
        mockShell.stubbedResult = makeSamplePlist(
            deviceId: "disk4s1", name: "Samsung T7",
            isInternal: false, mountPoint: "/Volumes/Samsung T7"
        )

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        await service.refreshVolumes()
        let volumes = await service.volumes

        #expect(volumes.count == 1)
        #expect(volumes[0].name == "Samsung T7")
        #expect(volumes[0].deviceIdentifier == "disk4s1")
        #expect(volumes[0].fileSystem == "APFS")
    }

    @Test("diskutil 실패 시 해당 볼륨 건너뜀")
    func diskutilFailureSkipsVolume() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = [
            URL(fileURLWithPath: "/Volumes/FailDrive")
        ]

        let mockShell = MockShellExecutor()
        mockShell.stubbedError = ShellError.executionFailed(exitCode: 1, stderr: "error")

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        await service.refreshVolumes()
        let volumes = await service.volumes

        #expect(volumes.isEmpty)
    }

    @Test("/ 및 /System/Volumes 경로 필터링")
    func systemPathsFiltered() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System/Volumes/Data"),
            URL(fileURLWithPath: "/Volumes/External")
        ]

        let mockShell = MockShellExecutor()
        mockShell.stubbedResult = makeSamplePlist(
            deviceId: "disk4s1", name: "External",
            isInternal: false, mountPoint: "/Volumes/External"
        )

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        await service.refreshVolumes()
        let volumes = await service.volumes

        // / 와 /System/Volumes/Data는 필터링되어야 함
        // diskutil은 /Volumes/External에 대해서만 호출
        #expect(mockShell.executedCommands.count == 1)
        #expect(volumes.count == 1)
        #expect(volumes[0].name == "External")
    }
}

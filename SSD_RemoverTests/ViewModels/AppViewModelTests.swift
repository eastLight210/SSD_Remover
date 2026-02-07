import Testing
import Foundation
@testable import SSD_Remover

@Suite("AppViewModel Tests")
struct AppViewModelTests {

    // MARK: - Helpers

    private func makeMockService(volumes: [ExternalVolume] = []) -> (MockVolumeURLProvider, MockShellExecutor, VolumeMonitorService) {
        let mockProvider = MockVolumeURLProvider()
        let mockShell = MockShellExecutor()

        // 각 볼륨에 대한 URL 설정
        mockProvider.stubbedURLs = volumes.map { $0.mountPoint }

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        return (mockProvider, mockShell, service)
    }

    private func makeSampleVolume(
        name: String = "TestDrive",
        deviceId: String = "disk4s1"
    ) -> ExternalVolume {
        let url = URL(fileURLWithPath: "/Volumes/\(name)")
        return ExternalVolume(
            id: url,
            name: name,
            deviceIdentifier: deviceId,
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: url
        )
    }

    // MARK: - Tests

    @Test("초기 상태에서 볼륨 목록이 비어있음")
    @MainActor
    func initialStateEmpty() async {
        let (_, _, service) = makeMockService()
        let vm = AppViewModel(volumeMonitorService: service)

        #expect(vm.volumes.isEmpty)
        #expect(vm.selectedVolume == nil)
    }

    @Test("refreshVolumes 후 볼륨 목록 업데이트")
    @MainActor
    func refreshUpdatesVolumes() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = [
            URL(fileURLWithPath: "/Volumes/Samsung T7")
        ]

        let mockShell = MockShellExecutor()
        mockShell.stubbedResult = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DeviceIdentifier</key>
            <string>disk4s1</string>
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
        </dict>
        </plist>
        """

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        let vm = AppViewModel(volumeMonitorService: service)
        await vm.refreshVolumes()

        #expect(vm.volumes.count == 1)
        #expect(vm.volumes[0].name == "Samsung T7")
    }

    @Test("볼륨 선택")
    @MainActor
    func selectVolume() async {
        let (_, _, service) = makeMockService()
        let vm = AppViewModel(volumeMonitorService: service)
        let volume = makeSampleVolume()

        vm.selectVolume(volume)

        #expect(vm.selectedVolume == volume)
    }

    @Test("볼륨 선택 해제")
    @MainActor
    func deselectVolume() async {
        let (_, _, service) = makeMockService()
        let vm = AppViewModel(volumeMonitorService: service)
        let volume = makeSampleVolume()

        vm.selectVolume(volume)
        #expect(vm.selectedVolume != nil)

        vm.deselectVolume()
        #expect(vm.selectedVolume == nil)
    }

    @Test("isLoading 상태 관리")
    @MainActor
    func loadingState() async {
        let mockProvider = MockVolumeURLProvider()
        mockProvider.stubbedURLs = []
        let mockShell = MockShellExecutor()

        let service = VolumeMonitorService(
            volumeURLProvider: mockProvider,
            shellExecutor: mockShell
        )

        let vm = AppViewModel(volumeMonitorService: service)

        #expect(vm.isLoading == false)
        await vm.refreshVolumes()
        #expect(vm.isLoading == false)
    }
}

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

    @Test("선택한 볼륨이 목록에서 사라지면 선택과 스캔 상태 초기화")
    @MainActor
    func removedSelectedVolumeClearsReviewState() async {
        let monitor = MockVolumeMonitor()
        let selectedVolume = makeSampleVolume(name: "Selected", deviceId: "disk4s1")
        let remainingVolume = makeSampleVolume(name: "Remaining", deviceId: "disk5s1")
        await monitor.setVolumes([selectedVolume, remainingVolume])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [
                    BlockingProcess(
                        pid: 100,
                        command: "Finder",
                        user: "testuser",
                        uid: 501,
                        lockedFiles: [selectedVolume.mountPoint.appendingPathComponent("file.txt").path]
                    )
                ]
            )
        ]

        let vm = AppViewModel(volumeMonitorService: monitor, processScanner: scanner)
        await vm.refreshVolumes()
        await vm.scanProcesses(for: selectedVolume)
        #expect(vm.scanState == .blocked(selectedVolume, processCount: 1))

        await monitor.setVolumes([remainingVolume])
        await vm.refreshVolumes()

        #expect(vm.volumes == [remainingVolume])
        #expect(vm.selectedVolume == nil)
        #expect(vm.processGroups.isEmpty)
        #expect(vm.scanState == .idle)
    }

    @Test("선택한 볼륨이 유지되면 최신 메타데이터로 교체")
    @MainActor
    func retainedSelectedVolumeUsesRefreshedMetadata() async {
        let monitor = MockVolumeMonitor()
        let originalVolume = makeSampleVolume()
        let refreshedVolume = ExternalVolume(
            id: originalVolume.id,
            name: originalVolume.name,
            deviceIdentifier: originalVolume.deviceIdentifier,
            fileSystem: originalVolume.fileSystem,
            totalCapacity: originalVolume.totalCapacity,
            availableCapacity: 250_000_000_000,
            mountPoint: originalVolume.mountPoint
        )
        await monitor.setVolumes([originalVolume])

        let vm = AppViewModel(volumeMonitorService: monitor)
        await vm.refreshVolumes()
        vm.selectVolume(originalVolume)

        await monitor.setVolumes([refreshedVolume])
        await vm.refreshVolumes()

        #expect(vm.selectedVolume == refreshedVolume)
    }

    // MARK: - Process Scanning Tests

    @Test("scanProcesses로 프로세스 그룹 업데이트")
    @MainActor
    func scanProcessesUpdatesGroups() async {
        let (_, _, service) = makeMockService()
        let mockScanner = MockProcessScanner()
        mockScanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [
                    BlockingProcess(pid: 100, command: "vim", user: "testuser", uid: 501, lockedFiles: ["/Volumes/TestDrive/file.txt"])
                ]
            )
        ]

        let vm = AppViewModel(volumeMonitorService: service, processScanner: mockScanner)
        let volume = makeSampleVolume()

        await vm.scanProcesses(for: volume)

        #expect(vm.processGroups.count == 1)
        #expect(vm.processGroups[0].category == .user)
        #expect(vm.processGroups[0].isSelected == false)
        #expect(vm.scanState == .blocked(volume, processCount: 1))
        #expect(vm.isScanning == false)
    }

    @Test("scanProcesses 에러 시 빈 그룹")
    @MainActor
    func scanProcessesErrorClearsGroups() async {
        let (_, _, service) = makeMockService()
        let mockScanner = MockProcessScanner()
        mockScanner.stubbedError = ShellError.executionFailed(exitCode: 1, stderr: "error")

        let vm = AppViewModel(volumeMonitorService: service, processScanner: mockScanner)
        let volume = makeSampleVolume()

        await vm.scanProcesses(for: volume)

        #expect(vm.processGroups.isEmpty)
        if case .failed(let failedVolume, _) = vm.scanState {
            #expect(failedVolume == volume)
        } else {
            Issue.record("scanState should be failed")
        }
        #expect(vm.isScanning == false)
    }

    @Test("deselectVolume은 processGroups 초기화")
    @MainActor
    func deselectClearsProcessGroups() async {
        let (_, _, service) = makeMockService()
        let mockScanner = MockProcessScanner()
        mockScanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [
                    BlockingProcess(pid: 100, command: "vim", user: "testuser", uid: 501, lockedFiles: [])
                ]
            )
        ]

        let vm = AppViewModel(volumeMonitorService: service, processScanner: mockScanner)
        let volume = makeSampleVolume()

        await vm.scanProcesses(for: volume)
        #expect(!vm.processGroups.isEmpty)

        vm.deselectVolume()
        #expect(vm.processGroups.isEmpty)
    }

    // MARK: - Edge Case Tests

    @Test("scanProcesses - launchFailed 에러도 빈 그룹 처리")
    @MainActor
    func scanProcessesLaunchFailedError() async {
        let (_, _, service) = makeMockService()
        let mockScanner = MockProcessScanner()
        mockScanner.stubbedError = ShellError.launchFailed("lsof not found")

        let vm = AppViewModel(volumeMonitorService: service, processScanner: mockScanner)
        let volume = makeSampleVolume()

        await vm.scanProcesses(for: volume)

        #expect(vm.processGroups.isEmpty)
        #expect(vm.isScanning == false)
    }
}

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    private(set) var volumes: [ExternalVolume] = []
    var selectedVolume: ExternalVolume?
    private(set) var isLoading = false
    private(set) var isScanning = false
    private(set) var processGroups: [ProcessGroup] = []

    private let volumeMonitorService: VolumeMonitorService
    private let processScanner: ProcessScanning

    init(
        volumeMonitorService: VolumeMonitorService,
        processScanner: ProcessScanning? = nil
    ) {
        self.volumeMonitorService = volumeMonitorService
        self.processScanner = processScanner ?? ProcessScannerService(shell: ShellExecutor())
    }

    func startMonitoring() async {
        await volumeMonitorService.startMonitoring()
        await refreshVolumes()
    }

    func stopMonitoring() async {
        await volumeMonitorService.stopMonitoring()
    }

    func refreshVolumes() async {
        isLoading = true
        await volumeMonitorService.refreshVolumes()
        volumes = await volumeMonitorService.volumes
        isLoading = false
    }

    func selectVolume(_ volume: ExternalVolume) {
        selectedVolume = volume
    }

    func deselectVolume() {
        selectedVolume = nil
        processGroups = []
    }

    func scanProcesses(for volume: ExternalVolume) async {
        isScanning = true
        do {
            processGroups = try await processScanner.scanProcesses(for: volume)
        } catch {
            processGroups = []
        }
        isScanning = false
    }
}

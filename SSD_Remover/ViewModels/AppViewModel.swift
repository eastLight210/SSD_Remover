import Foundation
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    private(set) var volumes: [ExternalVolume] = []
    var selectedVolume: ExternalVolume?
    private(set) var isLoading = false

    private let volumeMonitorService: VolumeMonitorService

    init(volumeMonitorService: VolumeMonitorService) {
        self.volumeMonitorService = volumeMonitorService
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
    }
}

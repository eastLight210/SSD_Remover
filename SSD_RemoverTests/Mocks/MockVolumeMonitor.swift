import Foundation
@testable import SSD_Remover

actor MockVolumeMonitor: VolumeMonitoring {
    private(set) var stubbedVolumes: [ExternalVolume] = []
    private(set) var startMonitoringCallCount = 0
    private(set) var stopMonitoringCallCount = 0
    private(set) var refreshCallCount = 0

    var volumes: [ExternalVolume] {
        stubbedVolumes
    }

    func setVolumes(_ volumes: [ExternalVolume]) {
        stubbedVolumes = volumes
    }

    func startMonitoring() async {
        startMonitoringCallCount += 1
    }

    func stopMonitoring() async {
        stopMonitoringCallCount += 1
    }

    func refreshVolumes() async {
        refreshCallCount += 1
    }
}

import Foundation
import SwiftUI

enum ScanState: Equatable, Sendable {
    case idle
    case scanning(ExternalVolume)
    case ready(ExternalVolume)
    case blocked(ExternalVolume, processCount: Int)
    case failed(ExternalVolume, message: String)
}

@MainActor
@Observable
final class AppViewModel {
    private(set) var volumes: [ExternalVolume] = []
    var selectedVolume: ExternalVolume?
    private(set) var isLoading = false
    private(set) var processGroups: [ProcessGroup] = []
    private(set) var scanState: ScanState = .idle

    private let volumeMonitorService: any VolumeMonitoring
    private let processScanner: ProcessScanning
    private var volumeUpdatesTask: Task<Void, Never>?

    init(
        volumeMonitorService: any VolumeMonitoring,
        processScanner: ProcessScanning? = nil
    ) {
        self.volumeMonitorService = volumeMonitorService
        self.processScanner = processScanner ?? ProcessScannerService(shell: ShellExecutor())
    }

    func startMonitoring() async {
        await volumeMonitorService.startMonitoring()
        let updates = await volumeMonitorService.volumeUpdates()
        volumeUpdatesTask?.cancel()
        volumeUpdatesTask = Task { [weak self] in
            for await volumes in updates {
                guard !Task.isCancelled else { break }
                self?.applyVolumeUpdate(volumes)
            }
        }
        await refreshVolumes()
    }

    func stopMonitoring() async {
        volumeUpdatesTask?.cancel()
        volumeUpdatesTask = nil
        await volumeMonitorService.stopMonitoring()
    }

    func refreshVolumes() async {
        isLoading = true
        await volumeMonitorService.refreshVolumes()
        applyVolumeUpdate(await volumeMonitorService.volumes)
        isLoading = false
    }

    func selectVolume(_ volume: ExternalVolume) {
        selectedVolume = volume
    }

    func deselectVolume() {
        selectedVolume = nil
        processGroups = []
        scanState = .idle
    }

    func scanProcesses(for volume: ExternalVolume) async {
        selectedVolume = volume
        processGroups = []
        scanState = .scanning(volume)

        do {
            let groups = try await processScanner.scanProcesses(for: volume)
            guard !Task.isCancelled else { return }

            processGroups = groups.map { group in
                ProcessGroup(
                    category: group.category,
                    processes: group.processes,
                    isSelected: false
                )
            }

            let processCount = processGroups.reduce(0) { $0 + $1.processes.count }
            scanState = processCount == 0
                ? .ready(volume)
                : .blocked(volume, processCount: processCount)
        } catch {
            guard !Task.isCancelled else { return }
            processGroups = []
            scanState = .failed(volume, message: error.localizedDescription)
        }
    }

    func cancelScan() {
        processGroups = []
        scanState = .idle
    }

    var isScanning: Bool {
        if case .scanning = scanState {
            return true
        }
        return false
    }

    func affectedVolumes(for volume: ExternalVolume) -> [ExternalVolume] {
        volumes.filter { $0.parentWholeDisk == volume.parentWholeDisk }
    }

    private func applyVolumeUpdate(_ updatedVolumes: [ExternalVolume]) {
        volumes = updatedVolumes

        guard let selectedVolume else { return }
        guard let refreshedVolume = updatedVolumes.first(where: { $0.id == selectedVolume.id }) else {
            deselectVolume()
            return
        }

        self.selectedVolume = refreshedVolume
        switch scanState {
        case .idle:
            break
        case .scanning:
            scanState = .scanning(refreshedVolume)
        case .ready:
            scanState = .ready(refreshedVolume)
        case .blocked(_, let processCount):
            scanState = .blocked(refreshedVolume, processCount: processCount)
        case .failed(_, let message):
            scanState = .failed(refreshedVolume, message: message)
        }
    }

    #if DEBUG
    func configurePreview(scanState: ScanState, processGroups: [ProcessGroup] = []) {
        self.scanState = scanState
        self.processGroups = processGroups

        switch scanState {
        case .idle:
            break
        case .scanning(let volume), .ready(let volume), .failed(let volume, _):
            selectedVolume = volume
        case .blocked(let volume, _):
            selectedVolume = volume
        }
    }
    #endif
}

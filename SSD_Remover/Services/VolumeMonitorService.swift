import AppKit
import Foundation

actor VolumeMonitorService: VolumeMonitoring {
    private let volumeURLProvider: VolumeURLProviding
    private let shellExecutor: ShellExecuting
    private let notificationCenter: NotificationCenter
    private var _volumes: [ExternalVolume] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var updateContinuations: [UUID: AsyncStream<[ExternalVolume]>.Continuation] = [:]

    var volumes: [ExternalVolume] {
        _volumes
    }

    init(
        volumeURLProvider: VolumeURLProviding = FileManager.default,
        shellExecutor: ShellExecuting = ShellExecutor(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.volumeURLProvider = volumeURLProvider
        self.shellExecutor = shellExecutor
        self.notificationCenter = notificationCenter
    }

    func startMonitoring() {
        let mountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshVolumes() }
        }

        let unmountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshVolumes() }
        }

        notificationObservers = [mountObserver, unmountObserver]
    }

    func stopMonitoring() {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    func volumeUpdates() -> AsyncStream<[ExternalVolume]> {
        let id = UUID()
        return AsyncStream { continuation in
            updateContinuations[id] = continuation
            continuation.yield(_volumes)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    func refreshVolumes() async {
        let urls = volumeURLProvider.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(Constants.volumeResourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        let candidateURLs = urls.filter { url in
            let path = url.path
            guard path.hasPrefix(Constants.volumesMountPoint) else { return false }
            guard !path.hasPrefix("/System/Volumes") else { return false }
            return true
        }

        var detected: [ExternalVolume] = []

        for url in candidateURLs {
            do {
                let plistOutput = try await shellExecutor.execute(
                    command: Constants.diskutilPath,
                    arguments: ["info", "-plist", url.path]
                )
                let diskInfo = try DiskInfoParser.parse(plistString: plistOutput)

                guard !diskInfo.isInternal else { continue }

                detected.append(diskInfo.toExternalVolume())
            } catch {
                continue
            }
        }

        _volumes = detected
        for continuation in updateContinuations.values {
            continuation.yield(detected)
        }
    }

    private func removeContinuation(id: UUID) {
        updateContinuations[id] = nil
    }
}

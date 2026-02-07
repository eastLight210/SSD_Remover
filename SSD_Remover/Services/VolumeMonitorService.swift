import AppKit
import Foundation

actor VolumeMonitorService: VolumeMonitoring {
    private let volumeURLProvider: VolumeURLProviding
    private let shellExecutor: ShellExecuting
    private var _volumes: [ExternalVolume] = []
    private var notificationObservers: [NSObjectProtocol] = []

    var volumes: [ExternalVolume] {
        _volumes
    }

    init(
        volumeURLProvider: VolumeURLProviding = FileManager.default,
        shellExecutor: ShellExecuting = ShellExecutor()
    ) {
        self.volumeURLProvider = volumeURLProvider
        self.shellExecutor = shellExecutor
    }

    func startMonitoring() {
        let mountObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshVolumes() }
        }

        let unmountObserver = NotificationCenter.default.addObserver(
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
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
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
    }
}

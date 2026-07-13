import AppKit
import ServiceManagement
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    private let autoSelectFirstVolume: Bool
    @State private var ejectViewModel: EjectViewModel?
    @State private var scanTask: Task<Void, Never>?
    @State private var ejectTask: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isQuitConfirmationPresented = false

    init(viewModel: AppViewModel, autoSelectFirstVolume: Bool = false) {
        self.viewModel = viewModel
        self.autoSelectFirstVolume = autoSelectFirstVolume
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeaderView(title: headerTitle) {
                headerTrailingContent
            }

            Divider()

            screenContent
        }
        .frame(width: 320, height: 360)
        .task {
            await viewModel.startMonitoring()
            if autoSelectFirstVolume,
               viewModel.selectedVolume == nil,
               let firstVolume = viewModel.volumes.first {
                viewModel.selectVolume(firstVolume)
            }
            #if DEBUG
            configurePreviewIfRequested()
            #endif
        }
        .onDisappear {
            scanTask?.cancel()
            ejectTask?.cancel()
            Task { await viewModel.stopMonitoring() }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            updateLaunchAtLogin(newValue)
        }
        .onChange(of: viewModel.scanState) { _, state in
            announceScanState(state)
        }
        .onChange(of: viewModel.selectedVolume?.id) { _, selectedVolumeID in
            guard selectedVolumeID == nil else { return }
            scanTask?.cancel()
            scanTask = nil

            guard let phase = ejectViewModel?.phase else { return }
            switch phase {
            case .confirming, .failure:
                ejectTask?.cancel()
                ejectTask = nil
                ejectViewModel = nil
            case .terminatingProcesses, .ejecting, .success:
                break
            }
        }
        .onChange(of: ejectViewModel?.phase) { _, phase in
            announceEjectPhase(phase)
        }
        .alert("Quit SSD Remover?", isPresented: $isQuitConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) {
                quitApplication()
            }
        } message: {
            Text("A disk removal is in progress. Quitting now may interrupt it.")
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        if let ejectViewModel {
            if ejectViewModel.phase == .confirming {
                ProcessListView(
                    viewModel: ejectViewModel,
                    affectedVolumes: viewModel.affectedVolumes(for: ejectViewModel.volume),
                    onCancel: dismissEject,
                    onConfirm: performEject
                )
            } else {
                EjectProgressView(
                    phase: ejectViewModel.phase,
                    volumeName: ejectViewModel.volume.name,
                    failedTerminations: ejectViewModel.failedTerminations,
                    onDismiss: dismissEject,
                    onRetry: retryEject
                )
            }
        } else {
            switch viewModel.scanState {
            case .idle:
                volumeScreen

            case .scanning(let volume):
                ScanningView(volume: volume, onCancel: cancelScan)

            case .failed(let volume, let message):
                ScanFailureView(
                    message: message,
                    onCancel: cancelScan,
                    onRetry: { beginScan(for: volume) }
                )

            case .ready, .blocked:
                loadingScreen
            }
        }
    }

    @ViewBuilder
    private var volumeScreen: some View {
        if viewModel.isLoading {
            loadingScreen
        } else if viewModel.volumes.isEmpty {
            VStack(spacing: 0) {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appCanvas)

                AppActionFooter {
                    Button {
                        Task { await viewModel.refreshVolumes() }
                    } label: {
                        AppButtonLabel("Refresh Drives", width: 160)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .controlSize(.regular)
                }
            }
        } else {
            VolumeListView(viewModel: viewModel, onReview: beginScan)
        }
    }

    private var loadingScreen: some View {
        VStack(spacing: 0) {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appCanvas)

            AppActionFooter {
                EmptyView()
            }
        }
    }

    private var headerTrailingContent: some View {
        HStack(spacing: 6) {
            Text(headerDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Menu {
                Button("Refresh Drives", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refreshVolumes() }
                }
                .disabled(ejectViewModel != nil || viewModel.scanState != .idle)

                Toggle("Launch at Login", isOn: $launchAtLogin)

                Divider()

                Button("Quit SSD Remover", systemImage: "power") {
                    requestQuit()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open app actions")
            .accessibilityLabel("App actions")
        }
    }

    private var headerTitle: String {
        if let ejectViewModel {
            switch ejectViewModel.phase {
            case .confirming:
                return ejectViewModel.totalProcessCount == 0 ? "Ready to Eject" : "Review Processes"
            case .terminatingProcesses:
                return "Terminating Processes"
            case .ejecting:
                return "Ejecting"
            case .success:
                return "Ejected"
            case .failure:
                return "Eject Failed"
            }
        }

        return switch viewModel.scanState {
        case .idle: "SSD Remover"
        case .scanning: "Scanning"
        case .ready: "Ready to Eject"
        case .blocked: "Review Processes"
        case .failed: "Scan Failed"
        }
    }

    private var headerDetail: String {
        if let ejectViewModel {
            if ejectViewModel.phase == .confirming, ejectViewModel.totalProcessCount > 0 {
                return "\(ejectViewModel.selectedProcessCount) selected"
            }
            return ejectViewModel.volume.parentWholeDisk
        }

        switch viewModel.scanState {
        case .scanning(let volume), .ready(let volume), .failed(let volume, _):
            return volume.parentWholeDisk
        case .blocked(let volume, _):
            return volume.parentWholeDisk
        case .idle:
            return driveCountLabel
        }
    }

    private var driveCountLabel: String {
        "\(viewModel.volumes.count) \(viewModel.volumes.count == 1 ? "drive" : "drives")"
    }

    private var isDiskRemovalInProgress: Bool {
        guard let phase = ejectViewModel?.phase else { return false }
        switch phase {
        case .terminatingProcesses, .ejecting:
            return true
        case .confirming, .success, .failure:
            return false
        }
    }

    private func requestQuit() {
        if isDiskRemovalInProgress {
            isQuitConfirmationPresented = true
        } else {
            quitApplication()
        }
    }

    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func beginScan(for volume: ExternalVolume) {
        scanTask?.cancel()
        scanTask = Task {
            await startEjectFlow(for: volume)
            scanTask = nil
        }
    }

    private func startEjectFlow(for volume: ExternalVolume) async {
        await viewModel.scanProcesses(for: volume)
        guard !Task.isCancelled else { return }

        switch viewModel.scanState {
        case .ready, .blocked:
            ejectViewModel = makeEjectViewModel(volume: volume, processGroups: viewModel.processGroups)
        case .idle, .scanning, .failed:
            break
        }
    }

    private func performEject() {
        guard let ejectViewModel, ejectViewModel.phase == .confirming else { return }
        ejectTask?.cancel()
        ejectTask = Task {
            await ejectViewModel.terminateAndEject()
            if ejectViewModel.phase == .success {
                await viewModel.refreshVolumes()
            }
            ejectTask = nil
        }
    }

    private func retryEject() {
        guard let ejectViewModel else { return }
        ejectTask?.cancel()
        ejectTask = Task {
            await ejectViewModel.retry()
            if ejectViewModel.phase == .success {
                await viewModel.refreshVolumes()
            }
            ejectTask = nil
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        viewModel.cancelScan()
    }

    private func dismissEject() {
        ejectTask?.cancel()
        ejectTask = nil
        ejectViewModel = nil
        viewModel.deselectVolume()
    }

    private func makeEjectViewModel(
        volume: ExternalVolume,
        processGroups: [ProcessGroup]
    ) -> EjectViewModel {
        EjectViewModel(
            volume: volume,
            processGroups: processGroups,
            processScanner: ProcessScannerService(shell: ShellExecutor()),
            processTerminator: ProcessTerminatorService(
                shell: ShellExecutor(),
                privilegedShell: PrivilegedExecutor()
            ),
            diskEjector: DiskEjectService(shell: ShellExecutor())
        )
    }

    #if DEBUG
    private func configurePreviewIfRequested() {
        guard autoSelectFirstVolume,
              let volume = viewModel.selectedVolume ?? viewModel.volumes.first,
              let previewState = UserDefaults.standard.string(forKey: "NSSSDRemoverPreviewState")
        else { return }

        switch previewState {
        case "scanning":
            viewModel.configurePreview(scanState: .scanning(volume))

        case "ready":
            viewModel.configurePreview(scanState: .ready(volume))
            ejectViewModel = makeEjectViewModel(volume: volume, processGroups: [])

        case "blocked":
            let groups = [
                ProcessGroup(
                    category: .user,
                    processes: [
                        BlockingProcess(
                            pid: 582,
                            command: "Finder",
                            user: NSUserName(),
                            uid: 501,
                            lockedFiles: [volume.mountPoint.appendingPathComponent("Project.mov").path]
                        ),
                    ]
                ),
                ProcessGroup(
                    category: .spotlight,
                    processes: [
                        BlockingProcess(
                            pid: 412,
                            command: "mds",
                            user: "root",
                            uid: 0,
                            lockedFiles: [volume.mountPoint.appendingPathComponent(".Spotlight-V100").path]
                        ),
                    ]
                ),
                ProcessGroup(
                    category: .system,
                    processes: [
                        BlockingProcess(
                            pid: 944,
                            command: "backupd",
                            user: "root",
                            uid: 0,
                            lockedFiles: [volume.mountPoint.appendingPathComponent(".backup").path]
                        ),
                    ]
                ),
            ]
            viewModel.configurePreview(scanState: .blocked(volume, processCount: 3), processGroups: groups)
            let previewViewModel = makeEjectViewModel(volume: volume, processGroups: groups)
            if let firstProcess = previewViewModel.allProcesses.first {
                previewViewModel.toggleProcessSelection(firstProcess)
            }
            ejectViewModel = previewViewModel

        case "failure":
            viewModel.configurePreview(
                scanState: .failed(
                    volume,
                    message: "lsof exited with code 1. No process result is available."
                )
            )

        default:
            break
        }
    }
    #endif

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !isEnabled
        }
    }

    private func announceScanState(_ state: ScanState) {
        switch state {
        case .idle:
            break
        case .scanning(let volume):
            AccessibilityAnnouncer.announce("Scanning \(volume.name) for blocking processes")
        case .ready:
            AccessibilityAnnouncer.announce("Scan complete. No blocking processes found")
        case .blocked(_, let processCount):
            AccessibilityAnnouncer.announce("Scan complete. \(processCount) blocking processes found")
        case .failed(_, let message):
            AccessibilityAnnouncer.announce("Scan failed. \(message)")
        }
    }

    private func announceEjectPhase(_ phase: EjectPhase?) {
        switch phase {
        case .success:
            AccessibilityAnnouncer.announce("Disk ejected successfully")
        case .failure(let message):
            AccessibilityAnnouncer.announce("Eject failed. \(message)")
        case .terminatingProcesses(let completed, let total):
            AccessibilityAnnouncer.announce("Terminated \(completed) of \(total) processes")
        case .ejecting:
            AccessibilityAnnouncer.announce("Ejecting physical disk")
        case .confirming, .none:
            break
        }
    }
}

enum AccessibilityAnnouncer {
    @MainActor
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp!,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

struct AppHeaderView<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.background)
    }
}

struct AppActionFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            content()
        }
        .padding(12)
        .frame(height: 56)
        .background(.background)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct AppButtonLabel: View {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    var body: some View {
        Text(title)
            .lineLimit(1)
            .frame(width: width - 24, height: 20)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                configuration.isPressed ? Color.appPrimaryPressed : Color.appPrimary,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                configuration.isPressed ? Color.appSecondaryPressed : Color.appSecondary,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.appSecondaryBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension Color {
    static let appPrimary = Color(red: 0, green: 102 / 255, blue: 204 / 255)
    static let appPrimaryPressed = Color(red: 0, green: 82 / 255, blue: 164 / 255)

    static var appSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.controlBackgroundColor : .white
        })
    }

    static var appSecondaryPressed: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        })
    }

    static var appSecondaryBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.36, green: 0.36, blue: 0.38, alpha: 1)
                : NSColor(srgbRed: 0.76, green: 0.76, blue: 0.78, alpha: 1)
        })
    }

    static var appCanvas: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            }
            return NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
        })
    }
}

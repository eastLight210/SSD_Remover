import AppKit
import Sparkle

/// In-app updates via Sparkle. The feed URL and EdDSA public key live in Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`); `script/release.sh` publishes the matching appcast.
@MainActor
final class AppUpdater {
    private let userDriverDelegate = MenuBarUserDriverDelegate()
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        // A menu bar app is never frontmost on its own; bring Sparkle's window forward.
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Unit tests host the app bundle; they must not start the updater or hit the network.
    static var isSupportedInCurrentProcess: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}

/// SSD Remover is an `LSUIElement` app, so a scheduled update alert would otherwise
/// open behind the frontmost app. Opting into gentle reminders and activating the app
/// when Sparkle shows an update keeps the alert visible. Sparkle calls this delegate
/// on the main thread, hence the `@preconcurrency` conformance.
@MainActor
private final class MenuBarUserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

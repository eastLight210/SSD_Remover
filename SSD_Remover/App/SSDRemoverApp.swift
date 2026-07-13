import AppKit
import SwiftUI

@main
struct SSDRemoverApp: App {
    private let bootstrap: SSDRemoverAppBootstrap
    private let isUIPreviewEnabled: Bool

    init() {
        #if DEBUG
        isUIPreviewEnabled = ProcessInfo.processInfo.environment["SSD_REMOVER_UI_PREVIEW"] == "1"
            || CommandLine.arguments.contains("-NSSSDRemoverUIPreview")
            || UserDefaults.standard.bool(forKey: "NSSSDRemoverUIPreview")
        if isUIPreviewEnabled {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        #else
        isUIPreviewEnabled = false
        #endif

        let bootstrap = SSDRemoverAppBootstrap(arguments: AppProcessEnvironment.launchArguments)

        switch bootstrap.launchMode {
        case .menuBar:
            self.bootstrap = bootstrap
        case .cli(let arguments):
            let result = BlockingCLICommandExecutor(executor: LiveCLICommandExecutor())
                .run(arguments: arguments)
            CLIExecutionResultFinalizer().finalize(result)
        }

        #if DEBUG
        if isUIPreviewEnabled, let viewModel = self.bootstrap.viewModel {
            UIPreviewWindow.schedule(viewModel: viewModel)
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra(
            "SSD Remover",
            systemImage: "externaldrive",
            isInserted: .constant(bootstrap.launchMode.isMenuBar)
        ) {
            if let viewModel = bootstrap.viewModel {
                ContentView(viewModel: viewModel)
            } else {
                EmptyView()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

#if DEBUG
@MainActor
private enum UIPreviewWindow {
    private static var window: NSWindow?
    private static var launchObserver: NSObjectProtocol?

    static func schedule(viewModel: AppViewModel) {
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: NSApplication.shared,
            queue: .main
        ) { _ in
            Task { @MainActor in
                show(viewModel: viewModel)
                if let launchObserver {
                    NotificationCenter.default.removeObserver(launchObserver)
                    self.launchObserver = nil
                }
            }
        }
    }

    private static func show(viewModel: AppViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SSD Remover"
        window.contentView = NSHostingView(
            rootView: ContentView(viewModel: viewModel, autoSelectFirstVolume: true)
                .preferredColorScheme(.light)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}
#endif

import AppKit
import Darwin
import SwiftUI

final class SSDRemoverAppDelegate: NSObject, NSApplicationDelegate {
    static var launchMode: AppLaunchMode = .menuBar

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case .cli(let arguments) = Self.launchMode else {
            return
        }

        Task {
            let result = await runCLI(arguments: arguments)
            write(result.stdout, to: .standardOutput)
            write(result.stderr, to: .standardError)
            Darwin.exit(Int32(result.exitCode))
        }
    }

    private func runCLI(arguments: [String]) async -> CLIExecutionResult {
        let parser = CLICommandParser()

        do {
            let command = try parser.parse(arguments: arguments)
            let shell = ShellExecutor()
            let runner = CLIRunner(
                volumeMonitor: VolumeMonitorService(shellExecutor: shell),
                processScanner: ProcessScannerService(shell: shell),
                processTerminator: ProcessTerminatorService(
                    shell: shell,
                    privilegedShell: PrivilegedExecutor()
                ),
                diskEjector: DiskEjectService(shell: shell)
            )
            return await runner.run(command)
        } catch let error as CLIParseError {
            return .failure(
                "\(error.localizedDescription)\n\n\(CLICommandParser.usageText)",
                exitCode: 64
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func write(_ output: String, to handle: FileHandle) {
        guard !output.isEmpty else {
            return
        }

        let line = output.hasSuffix("\n") ? output : output + "\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

@main
struct SSDRemoverApp: App {
    @NSApplicationDelegateAdaptor(SSDRemoverAppDelegate.self) private var appDelegate
    @State private var isMenuBarInserted: Bool
    @State private var viewModel: AppViewModel
    private let launchMode: AppLaunchMode

    init() {
        let launchMode = AppLaunchMode.detect(arguments: Array(CommandLine.arguments.dropFirst()))
        self.launchMode = launchMode
        SSDRemoverAppDelegate.launchMode = launchMode
        _isMenuBarInserted = State(initialValue: launchMode.isMenuBar)
        _viewModel = State(initialValue: AppViewModel(volumeMonitorService: VolumeMonitorService()))
    }

    var body: some Scene {
        MenuBarExtra(
            "SSD Remover",
            systemImage: "externaldrive",
            isInserted: $isMenuBarInserted
        ) {
            ContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

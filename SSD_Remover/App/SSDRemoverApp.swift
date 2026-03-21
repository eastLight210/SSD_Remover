import SwiftUI

@main
struct SSDRemoverApp: App {
    private let bootstrap: SSDRemoverAppBootstrap

    init() {
        let bootstrap = SSDRemoverAppBootstrap(arguments: AppProcessEnvironment.launchArguments)

        switch bootstrap.launchMode {
        case .menuBar:
            self.bootstrap = bootstrap
        case .cli(let arguments):
            let result = BlockingCLICommandExecutor(executor: LiveCLICommandExecutor())
                .run(arguments: arguments)
            CLIExecutionResultFinalizer().finalize(result)
        }
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

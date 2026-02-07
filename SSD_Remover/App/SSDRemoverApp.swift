import SwiftUI

@main
struct SSDRemoverApp: App {
    @State private var viewModel = AppViewModel(
        volumeMonitorService: VolumeMonitorService()
    )

    var body: some Scene {
        MenuBarExtra("SSD Remover", systemImage: "externaldrive") {
            ContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

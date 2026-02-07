import SwiftUI
import ServiceManagement

struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    @State private var ejectViewModel: EjectViewModel?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let ejectVM = ejectViewModel {
                if ejectVM.phase == .confirming {
                    ProcessListView(viewModel: ejectVM, onCancel: { dismissEject() })
                } else {
                    EjectProgressView(
                        phase: ejectVM.phase,
                        volumeName: ejectVM.volume.name,
                        failedTerminations: ejectVM.failedTerminations,
                        onDismiss: { dismissEject() },
                        onRetry: {
                            Task { await ejectVM.retry() }
                        }
                    )
                }
            } else if viewModel.isLoading || viewModel.isScanning {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.volumes.isEmpty {
                EmptyStateView()
            } else {
                VolumeListView(viewModel: viewModel)
            }
        }
        .frame(width: 320, height: 360)
        .task {
            await viewModel.startMonitoring()
        }
        .onChange(of: viewModel.selectedVolume) { _, newVolume in
            if let volume = newVolume {
                Task { await startEjectFlow(for: volume) }
            } else {
                ejectViewModel = nil
            }
        }
    }

    private var header: some View {
        HStack {
            if ejectViewModel != nil {
                Button {
                    dismissEject()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
            }

            Text("SSD Remover")
                .font(.headline)
            Spacer()
            Button {
                Task { await viewModel.refreshVolumes() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(ejectViewModel != nil)

            Toggle(isOn: $launchAtLogin) {
                Image(systemName: "power")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("로그인 시 자동 실행")
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = !newValue
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func startEjectFlow(for volume: ExternalVolume) async {
        await viewModel.scanProcesses(for: volume)

        let ejectVM = EjectViewModel(
            volume: volume,
            processGroups: viewModel.processGroups,
            processTerminator: ProcessTerminatorService(
                shell: ShellExecutor(),
                privilegedShell: PrivilegedExecutor()
            ),
            diskEjector: DiskEjectService(shell: ShellExecutor())
        )
        ejectViewModel = ejectVM
    }

    private func dismissEject() {
        ejectViewModel = nil
        viewModel.deselectVolume()
    }
}

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.isLoading {
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
    }

    private var header: some View {
        HStack {
            Text("SSD Remover")
                .font(.headline)
            Spacer()
            Button {
                Task { await viewModel.refreshVolumes() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

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
}

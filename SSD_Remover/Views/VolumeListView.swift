import SwiftUI

struct VolumeListView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.volumes) { volume in
                    VolumeRowView(
                        volume: volume,
                        isSelected: viewModel.selectedVolume == volume
                    )
                    .onTapGesture {
                        if viewModel.selectedVolume == volume {
                            viewModel.deselectVolume()
                        } else {
                            viewModel.selectVolume(volume)
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}

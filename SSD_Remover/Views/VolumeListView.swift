import SwiftUI

struct VolumeListView: View {
    @Bindable var viewModel: AppViewModel
    let onReview: (ExternalVolume) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let scopeSummary {
                        Text(scopeSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                    }

                    ForEach(viewModel.volumes) { volume in
                        Button {
                            if viewModel.selectedVolume == volume {
                                viewModel.deselectVolume()
                            } else {
                                viewModel.selectVolume(volume)
                            }
                        } label: {
                            VolumeRowView(
                                volume: volume,
                                isSelected: viewModel.selectedVolume == volume
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Select \(volume.name) for review")
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)

            AppActionFooter {
                Button {
                    if let volume = viewModel.selectedVolume {
                        onReview(volume)
                    }
                } label: {
                    AppButtonLabel("Review & Eject", width: 160)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .disabled(viewModel.selectedVolume == nil)
                .help("Scan the selected disk before ejection")
            }
        }
    }

    private var scopeSummary: String? {
        guard let volume = viewModel.selectedVolume ?? viewModel.volumes.first else { return nil }
        let affectedCount = viewModel.affectedVolumes(for: volume).count
        return "Physical disk \(volume.parentWholeDisk) · affects \(affectedCount) \(affectedCount == 1 ? "volume" : "volumes")"
    }
}

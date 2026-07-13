import SwiftUI

struct ProcessListView: View {
    @Bindable var viewModel: EjectViewModel
    let affectedVolumes: [ExternalVolume]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.totalProcessCount == 0 {
                    noBlockersContent
                } else {
                    blockersContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, viewModel.totalProcessCount == 0 ? 16 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appCanvas)
            .overlay {
                if viewModel.isRescanning {
                    ProgressView("Scanning…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }

            AppActionFooter {
                Button(action: onCancel) {
                    AppButtonLabel("Cancel", width: 100)
                }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button(action: onConfirm) {
                    AppButtonLabel(primaryActionTitle, width: 160)
                }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
                    .help(primaryActionHelp)
            }
        }
    }

    private var noBlockersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusBanner(
                style: .success,
                title: "No blocking processes",
                message: "\(viewModel.volume.name) is ready for safe ejection."
            )

            Text(scopeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var blockersContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasSpotlightProcesses {
                SpotlightWarningView(blockingProcessCount: viewModel.totalProcessCount)
            } else {
                StatusBanner(
                    style: .warning,
                    title: "\(viewModel.totalProcessCount) blocking processes",
                    message: "Choose only processes you want to terminate."
                )
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.allProcesses) { process in
                        ProcessRowView(
                            process: process,
                            isSelected: viewModel.isProcessSelected(process),
                            onToggle: {
                                viewModel.toggleProcessSelection(process)
                                AccessibilityAnnouncer.announce(selectionAnnouncement)
                            }
                        )
                    }
                }
            }
            .frame(height: 120)

            Text("\(viewModel.selectedProcessCount) of \(viewModel.totalProcessCount) processes selected")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }

    private var scopeDescription: String {
        let names = affectedVolumes.map(\.name).joined(separator: ", ")
        return "Confirming will eject physical disk \(viewModel.volume.parentWholeDisk).\nAffected volumes · \(names)"
    }

    private var primaryActionTitle: String {
        if viewModel.totalProcessCount == 0 {
            return "Confirm Eject"
        }
        if viewModel.selectedProcessCount == 0 {
            return "Eject Without Terminating"
        }
        return "Terminate \(viewModel.selectedProcessCount) & Eject"
    }

    private var primaryActionHelp: String {
        viewModel.selectedProcessCount == 0 && viewModel.totalProcessCount > 0
            ? "Attempt ejection without terminating any process"
            : "Eject physical disk \(viewModel.volume.parentWholeDisk)"
    }

    private var selectionAnnouncement: String {
        "\(viewModel.selectedProcessCount) of \(viewModel.totalProcessCount) processes selected"
    }
}

extension ProcessCategory {
    var displayName: String {
        switch self {
        case .spotlight: "Spotlight"
        case .system: "System"
        case .user: "User"
        }
    }

    var iconName: String {
        switch self {
        case .spotlight: "magnifyingglass"
        case .system: "gearshape"
        case .user: "person"
        }
    }
}

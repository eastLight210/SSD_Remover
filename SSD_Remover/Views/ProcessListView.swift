import SwiftUI

struct ProcessListView: View {
    @Bindable var viewModel: EjectViewModel
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasSpotlightProcesses {
                SpotlightWarningView()
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.processGroups) { group in
                        ProcessGroupSection(
                            group: group,
                            onToggle: {
                                viewModel.toggleGroupSelection(category: group.category)
                            }
                        )
                    }
                }
                .padding(12)
            }
            .overlay {
                if viewModel.isRescanning {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel?()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Terminate & Eject") {
                    Task {
                        await viewModel.terminateAndEject()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedProcesses.isEmpty)
            }
            .padding(12)
        }
    }
}

private struct ProcessGroupSection: View {
    let group: ProcessGroup
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: Binding(
                    get: { group.isSelected },
                    set: { _ in onToggle() }
                )) {
                    Label(group.category.displayName, systemImage: group.category.iconName)
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.checkbox)

                Spacer()

                Text("\(group.processes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }

            ForEach(group.processes) { process in
                ProcessRowView(process: process)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
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

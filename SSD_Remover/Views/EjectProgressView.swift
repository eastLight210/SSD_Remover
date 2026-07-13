import SwiftUI

struct EjectProgressView: View {
    let phase: EjectPhase
    let volumeName: String
    let failedTerminations: [Int32: String]
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                statusContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appCanvas)

            footer
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch phase {
        case .terminatingProcesses(let completed, let total):
            StatusBanner(
                style: .info,
                title: "Terminating processes",
                message: "Completed \(completed) of \(total)."
            )
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .accessibilityLabel("Process termination progress")

        case .ejecting:
            StatusBanner(
                style: .info,
                title: "Ejecting \(volumeName)",
                message: "The physical disk is being unmounted safely."
            )
            ProgressView()
                .controlSize(.small)

        case .success:
            StatusBanner(
                style: .success,
                title: "Ejected successfully",
                message: "\(volumeName) can be safely removed."
            )

        case .failure(let message):
            StatusBanner(
                style: .danger,
                title: "Eject failed",
                message: message
            )

            if !failedTerminations.isEmpty {
                Text("Failed to terminate \(failedTerminations.count) process(es).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .confirming:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .terminatingProcesses, .ejecting:
            AppActionFooter {
                Text("Please wait…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .success:
            AppActionFooter {
                Button(action: onDismiss) {
                    AppButtonLabel("Done", width: 160)
                }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
            }

        case .failure:
            AppActionFooter {
                Button(action: onDismiss) {
                    AppButtonLabel("Cancel", width: 100)
                }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button(action: onRetry) {
                    AppButtonLabel("Retry", width: 160)
                }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
            }

        case .confirming:
            EmptyView()
        }
    }
}

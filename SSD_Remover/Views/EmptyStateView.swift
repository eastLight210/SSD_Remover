import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No External Drives")
                .font(.headline)
            Text("Connect an external SSD to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView()
        .frame(width: 320, height: 300)
}

struct ScanningView: View {
    let volume: ExternalVolume
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                StatusBanner(
                    style: .info,
                    title: "Scanning \(volume.name)",
                    message: "Checking open files and active processes…"
                )

                VolumeRowView(volume: volume, isSelected: false)

                Text("Eject remains locked until inspection completes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appCanvas)

            AppActionFooter {
                Button(action: onCancel) {
                    AppButtonLabel("Cancel", width: 100)
                }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)
                    .help("Cancel the process scan")
            }
        }
    }
}

struct ScanFailureView: View {
    let message: String
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                StatusBanner(
                    style: .danger,
                    title: "Couldn’t scan open files",
                    message: message
                )

                Text("No process was terminated. Eject remains locked until a scan succeeds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appCanvas)

            AppActionFooter {
                Button(action: onCancel) {
                    AppButtonLabel("Cancel", width: 100)
                }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Button(action: onRetry) {
                    AppButtonLabel("Retry Scan", width: 160)
                }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
            }
        }
    }
}

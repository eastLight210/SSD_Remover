import SwiftUI

struct EjectProgressView: View {
    let phase: EjectPhase
    let volumeName: String
    let failedTerminations: [Int32: String]
    var onDismiss: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            icon
            statusText

            // 종료 실패 프로세스 표시
            if !failedTerminations.isEmpty {
                Text("Failed to terminate \(failedTerminations.count) process(es)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if isCompleted {
                HStack(spacing: 12) {
                    if case .failure = phase {
                        Button("Retry") {
                            onRetry?()
                        }
                    }
                    Button("Done") {
                        onDismiss?()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .terminatingProcesses:
            ProgressView()
                .controlSize(.large)
        case .ejecting:
            ProgressView()
                .controlSize(.large)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
        case .confirming:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch phase {
        case .terminatingProcesses(let completed, let total):
            VStack(spacing: 4) {
                Text("Terminating processes...")
                    .font(.headline)
                Text("\(completed) / \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ejecting:
            Text("Ejecting \(volumeName)...")
                .font(.headline)
        case .success:
            VStack(spacing: 4) {
                Text("Ejected Successfully")
                    .font(.headline)
                Text("\(volumeName) can be safely removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failure(let message):
            VStack(spacing: 4) {
                Text("Eject Failed")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .confirming:
            EmptyView()
        }
    }

    private var isCompleted: Bool {
        switch phase {
        case .success, .failure: true
        default: false
        }
    }
}

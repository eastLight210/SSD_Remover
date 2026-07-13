import SwiftUI

struct ProcessRowView: View {
    let process: BlockingProcess
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(
                "Select \(process.command)",
                isOn: Binding(
                    get: { isSelected },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.command)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(process.lockedFiles.first ?? "No locked path reported")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("PID \(process.pid)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(process.command), PID \(process.pid), locked file \(process.lockedFiles.first ?? "not reported")")
        .accessibilityValue(isSelected ? "Selected for termination" : "Not selected")
    }
}

import SwiftUI

struct ProcessRowView: View {
    let process: BlockingProcess

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: process.isRoot ? "lock.shield" : "terminal")
                .font(.caption)
                .foregroundStyle(process.isRoot ? .orange : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(process.command)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    Text("PID \(process.pid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(process.user)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !process.lockedFiles.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("\(process.lockedFiles.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

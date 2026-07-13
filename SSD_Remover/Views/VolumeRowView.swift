import SwiftUI

struct VolumeRowView: View {
    let volume: ExternalVolume
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("SSD")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(volume.fileSystem) · \(volume.formattedTotalCapacity) · \(volume.parentWholeDisk)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(volume.name), \(volume.fileSystem), \(volume.formattedTotalCapacity), physical disk \(volume.parentWholeDisk)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#Preview {
    let url = URL(fileURLWithPath: "/Volumes/Samsung T7")
    let volume = ExternalVolume(
        id: url, name: "Samsung T7", deviceIdentifier: "disk4s1",
        fileSystem: "APFS", totalCapacity: 1_000_000_000_000,
        availableCapacity: 500_000_000_000, mountPoint: url
    )

    VStack {
        VolumeRowView(volume: volume, isSelected: false)
        VolumeRowView(volume: volume, isSelected: true)
    }
    .padding()
    .frame(width: 320)
}

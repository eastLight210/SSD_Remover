import SwiftUI

struct VolumeRowView: View {
    let volume: ExternalVolume
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                HStack(spacing: 8) {
                    Text(volume.fileSystem)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                        )
                    Text(volume.formattedCapacity)
                        .font(.caption)
                }
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
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

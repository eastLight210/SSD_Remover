import SwiftUI

enum StatusBannerStyle {
    case info
    case success
    case warning
    case danger

    var tint: Color {
        switch self {
        case .info: .accentColor
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }

    var background: Color {
        switch self {
        case .info: .accentColor.opacity(0.08)
        case .success, .danger: Color(nsColor: .textBackgroundColor)
        case .warning: Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.18, green: 0.15, blue: 0.08, alpha: 1)
                : NSColor(srgbRed: 1, green: 0.98, blue: 0.91, alpha: 1)
        })
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark"
        case .warning: "exclamationmark"
        case .danger: "xmark"
        }
    }
}

struct StatusBanner: View {
    let style: StatusBannerStyle
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(style.tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(style.tint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSummaryElement)
    }
}

struct SpotlightWarningView: View {
    let blockingProcessCount: Int

    var body: some View {
        StatusBanner(
            style: .warning,
            title: "\(blockingProcessCount) blocking processes",
            message: "Spotlight is indexing this volume. Terminating mds may interrupt indexing."
        )
    }
}

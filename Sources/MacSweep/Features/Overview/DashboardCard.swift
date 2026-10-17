import SwiftUI

/// Uniform dashboard tile: icon + title header, content, optional footer action.
struct DashboardCard<Content: View>: View {
    @Environment(\.appAccent) private var accent
    /// Every tile shares one height so the grid reads as a clean, even layout.
    static var height: CGFloat { 236 }

    let title: String
    let symbol: String
    var tint: Color? = nil
    var action: (title: String, run: () -> Void)? = nil
    /// Dashboard tiles share one height; detail pages pass false so content sets the height and never spills out.
    var isFixedHeight = true
    @ViewBuilder var content: Content

    var body: some View {
        let tint = self.tint ?? accent
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.headline)
                Spacer()
                if let action {
                    Button(action: action.run) {
                        Text(action.title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: isFixedHeight ? Self.height : nil, maxHeight: isFixedHeight ? Self.height : .infinity,
               alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct MetricLine: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color)
        }
        .font(.callout)
    }
}

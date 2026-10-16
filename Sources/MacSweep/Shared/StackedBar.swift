import SwiftUI

struct BarSegment: Identifiable {
    let label: String
    let value: Double
    let color: Color
    var detail: String = ""

    var id: String { label }
}

/// Horizontal proportional bar with a legend underneath (Activity Monitor / About This Mac style).
struct StackedBar: View {
    let segments: [BarSegment]
    var height: CGFloat = 14
    var showsLegend = true

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(proxy.size.width * segment.value / total - 2, segment.value > 0 ? 2 : 0))
                            .help("\(segment.label): \(segment.detail)")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityLabel(segments.map { "\($0.label) \($0.detail)" }.joined(separator: ", "))

            if showsLegend {
                HStack(spacing: 16) {
                    ForEach(segments) { segment in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(segment.color).frame(width: 9, height: 9)
                            Text(segment.label).foregroundStyle(.secondary)
                            Text(segment.detail).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

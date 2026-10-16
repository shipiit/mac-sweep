import SwiftUI

/// Compact "x% left" bar for tight spaces such as the menu bar tiles.
struct LimitMiniBar: View {
    let title: String
    /// Fraction remaining, 0...1.
    let fraction: Double
    let trailing: String?
    @Environment(\.appAccent) private var accent

    var body: some View {
        let left = min(max(fraction, 0), 1)
        let color: Color = left <= 0.1 ? .red : left <= 0.3 ? .orange : accent
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.caption2.weight(.medium))
                Spacer(minLength: 4)
                Text("\(Int((left * 100).rounded()))% left").font(.caption2.monospacedDigit().weight(.semibold))
                if let trailing { Text("· \(trailing)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: proxy.size.width * left)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Int((left * 100).rounded())) percent left")
    }
}

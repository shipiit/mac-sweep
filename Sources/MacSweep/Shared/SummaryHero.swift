import SwiftUI

/// Page header that answers "how much, and of what" at a glance: one headline figure, the actions
/// that go with it, and a proportional bar with its legend.
struct SummaryHero<Actions: View>: View {
    @Environment(\.appAccent) private var accent
    let symbol: String
    let eyebrow: String
    let value: String
    let caption: String
    var tint: Color? = nil
    var isLoading = false
    let segments: [BarSegment]
    @ViewBuilder var actions: Actions

    var body: some View {
        let tint = self.tint ?? accent
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    if isLoading {
                        SkeletonBar(width: 170, height: 34).shimmering()
                    } else {
                        FigureText(value: value, size: 38)
                    }
                    Text(caption).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) { actions }.controlSize(.large)
            }
            if isLoading {
                SkeletonBar(height: 12).shimmering()
            } else if !segments.isEmpty {
                StackedBar(segments: segments.filter { $0.value > 0 }, height: 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// "9.98 GB" set as a large rounded number with a smaller, quieter unit.
struct FigureText: View {
    let value: String
    var size: CGFloat = 26

    var body: some View {
        // Only a figure is split into number and unit; a phrase ("Off", "Malware blocking") stays whole.
        let parts = value.first?.isNumber == true ? value.split(separator: " ", maxSplits: 1).map(String.init) : [value]
        HStack(alignment: .firstTextBaseline, spacing: size * 0.16) {
            Text(parts.first ?? value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            if parts.count > 1 {
                Text(parts[1]).font(.system(size: size * 0.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement()
        .accessibilityLabel(value)
    }
}

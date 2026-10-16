import SwiftUI

/// Icon + title tabs with an optional count, in a single rounded bar. Scrolls if there are many.
struct PillTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let symbol: (Tab) -> String
    var badge: (Tab) -> String? = { _ in nil }
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    let isOn = tab == selection
                    Button { selection = tab } label: {
                        HStack(spacing: 6) {
                            Image(systemName: symbol(tab)).font(.system(size: 12, weight: .semibold))
                            Text(title(tab)).fontWeight(isOn ? .semibold : .regular)
                            if let badge = badge(tab) {
                                Text(badge).font(.caption2.monospacedDigit().weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(isOn ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? accent : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
        .fixedSize(horizontal: false, vertical: true)
    }
}

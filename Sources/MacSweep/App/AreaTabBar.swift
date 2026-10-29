import SwiftUI

/// The pages of the current sidebar area as tabs along the top of the content.
struct AreaTabBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    @AppStorage(SettingsKeys.hiddenSections) private var hiddenRaw = ""

    var body: some View {
        let current = app.section ?? .smartScan
        let hidden = SidebarVisibility.hidden(hiddenRaw)
        let pages = SidebarSection.groups.first { !$0.title.isEmpty && $0.sections.contains(current) }?.sections.filter { !hidden.contains($0) } ?? []
        if pages.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pages) { page in
                        let isOn = page == current
                        Button { app.section = page } label: {
                            Label(page.rawValue, systemImage: page.symbol)
                                .font(.callout.weight(isOn ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(isOn ? .white : .primary)
                                .background(isOn ? accent : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

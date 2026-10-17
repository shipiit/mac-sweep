import MacSweepCore
import SwiftUI

/// Every page under small group headers, with the app header on top.
struct SidebarList: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.hiddenSections) private var hiddenRaw = ""
    let badge: (SidebarSection) -> String?

    var body: some View {
        let hidden = SidebarVisibility.hidden(hiddenRaw)
        let current = app.section ?? .smartScan
        List {
            ForEach(SidebarSection.groups.map { ($0.title, $0.sections.filter { !hidden.contains($0) }) }.filter { !$0.1.isEmpty }, id: \.0) { title, sections in
                if title.isEmpty {
                    ForEach(sections) { row($0, current: current) }
                } else {
                    Section {
                        ForEach(sections) { row($0, current: current) }
                    } header: {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { AppHeader().padding(.horizontal, 14).padding(.bottom, 6) }
    }

    private func row(_ section: SidebarSection, current: SidebarSection) -> some View {
        SidebarRow(section: section, badge: badge(section), isSelected: current == section) {
            app.section = section
        }
    }
}

/// App icon, name and tagline at the top of the sidebar.
private struct AppHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacSweep").font(.headline)
                Text("Keep your Mac healthy").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

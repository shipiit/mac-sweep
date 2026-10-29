import MacSweepCore
import SwiftUI

/// A short sidebar: the main pages, then one row per area. An area's pages open as tabs along the top.
struct SidebarList: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.hiddenSections) private var hiddenRaw = ""
    let badge: (SidebarSection) -> String?

    static func symbol(forArea title: String) -> String {
        switch title {
        case "Cleanup": "trash"
        case "Protection": "checkmark.shield"
        case "Performance": "gauge.with.dots.needle.67percent"
        case "Developer": "hammer"
        case "Applications": "square.stack.3d.up"
        case "Insights": "chart.line.uptrend.xyaxis"
        default: "circle"
        }
    }

    var body: some View {
        let hidden = SidebarVisibility.hidden(hiddenRaw)
        let current = app.section ?? .smartScan
        let areas = SidebarSection.groups.map { ($0.title, $0.sections.filter { !hidden.contains($0) }) }.filter { !$0.1.isEmpty }
        List {
            Section {
                ForEach(areas.first { $0.0.isEmpty }?.1 ?? []) { row($0, current: current) }
            } header: {
                SidebarHeader("Workspace")
            }
            Section {
                ForEach(areas.filter { !$0.0.isEmpty }, id: \.0) { title, sections in
                    AreaRow(title: title, symbol: Self.symbol(forArea: title), count: sections.count,
                            badge: sections.lazy.compactMap(badge).first, isSelected: sections.contains(current)) {
                        app.section = app.lastInArea[title].flatMap { sections.contains($0) ? $0 : nil } ?? sections.first
                    }
                }
            } header: {
                SidebarHeader("Tools")
            }
            Section {
                MoreAppRow(name: "Snappilot", detail: "Capture · Annotate · OCR", symbol: "camera.viewfinder", tint: .indigo,
                           bundleID: "ai.snappilot.mac", releases: "https://github.com/shipiit/snappilot/releases/latest")
                MoreAppRow(name: "KeyVault", detail: "Password manager, no server", symbol: "key.fill", tint: .green,
                           bundleID: nil, releases: "https://shipiit.github.io/keyvault/")
            } header: {
                SidebarHeader("More apps")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { SidebarStorageCard().padding(10) }
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
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacSweep").font(.title3.weight(.bold))
                Text("Clean · Protect · Speed · AI").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// One sidebar row for a whole area (Cleanup, Protection…), highlighted while any of its pages is open.
private struct AreaRow: View {
    let title: String
    let symbol: String
    let count: Int
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarItemLabel(symbol: symbol, title: title, badge: badge ?? "\(count)", isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityLabel("\(title), \(count) pages")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

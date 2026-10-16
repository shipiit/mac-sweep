import MacSweepCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.backgroundStyle) private var backgroundStyle: BackgroundStyle = .plain
    /// Comma-separated titles of folded sidebar groups.
    @AppStorage("sidebarCollapsed") private var collapsedRaw = "Protection,Performance,Developer,Applications,Insights"

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List {
                ForEach(SidebarSection.groups, id: \.title) { group in
                    if group.title.isEmpty {
                        rows(group.sections)
                    } else {
                        Section(isExpanded: expanded(group.title)) {
                            rows(group.sections)
                        } header: {
                            HStack {
                                Text(group.title)
                                if !expanded(group.title).wrappedValue {
                                    Text("\(group.sections.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(backgroundStyle == .plain ? .automatic : .hidden)
            .background { if backgroundStyle != .plain { AppBackground() } }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detail
                .frame(minWidth: 760, minHeight: 560)
                .background(AppBackground())
        }
        .appAccent()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
        }
    }

    private func rows(_ sections: [SidebarSection]) -> some View {
        ForEach(sections) { section in
            SidebarRow(section: section, badge: badge(for: section), isSelected: (app.section ?? .smartScan) == section) {
                app.section = section
            }
        }
    }

    /// The group holding the current page always stays open.
    private func expanded(_ title: String) -> Binding<Bool> {
        let collapsed = Set(collapsedRaw.split(separator: ",").map(String.init))
        let holdsSelection = SidebarSection.groups.first { $0.title == title }?.sections.contains(app.section ?? .smartScan) ?? false
        return Binding(get: { holdsSelection || !collapsed.contains(title) }, set: { isOpen in
            var next = collapsed
            if isOpen { next.remove(title) } else { next.insert(title) }
            collapsedRaw = next.sorted().joined(separator: ",")
        })
    }

    private func badge(for section: SidebarSection) -> String? {
        switch section {
        case .storage: app.cleanup.total(.safe) > 0 ? Format.bytes(app.cleanup.total(.safe)) : nil
        case .processes: app.processes.growingCount > 0 ? "\(app.processes.growingCount)" : nil
        case .ports: app.ports.ports.isEmpty ? nil : "\(app.ports.ports.count)"
        case .security: app.security.highFindings > 0 ? "\(app.security.highFindings)" : nil
        case .updater: app.updates.updates.isEmpty ? nil : "\(app.updates.updates.count)"
        case .ai: app.ai.todayTotals.total > 0 ? TokenFormat.compact(app.ai.todayTotals.total) : nil
        default: nil
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.section ?? .smartScan {
        case .smartScan: SmartScanView()
        case .overview: OverviewView()
        case .systemInfo: SystemInfoView()
        case .ai: AIUsageView()
        case .usage: UsageView()
        case .alerts: AlertsView()
        case .duplicates: DuplicatesView()
        case .developer: DeveloperHubView()
        case .timeline: InsightsTimelineView()
        case .growth: GrowthView()
        case .storage: StorageView()
        case .files: LargeFilesView()
        case .mail: MailAttachmentsView()
        case .trash: TrashBinsView()
        case .shredder: ShredderView()
        case .privacy: PrivacyView()
        case .security: SecurityView()
        case .extensions: ExtensionsView()
        case .optimization: OptimizationView()
        case .maintenance: MaintenanceView()
        case .processes: ProcessesView()
        case .ports: PortsView()
        case .startup: StartupView()
        case .uninstaller: UninstallerView()
        case .updater: UpdaterView()
        }
    }
}

/// Sidebar row that draws its own selection, so the highlight follows Settings › Appearance
/// (the system List highlight always uses the macOS accent).
private struct SidebarRow: View {
    let section: SidebarSection
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.appAccent) private var accent
    @AppStorage(SettingsKeys.sidebarHex) private var sidebarHex = ""

    var body: some View {
        let highlight = Color(hex: sidebarHex) ?? accent
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .white : highlight)
                Text(section.rawValue)
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? highlight : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

import MacSweepCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.backgroundStyle) private var backgroundStyle: BackgroundStyle = .plain

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            SidebarList(badge: badge(for:))
            .scrollContentBackground(backgroundStyle == .plain ? .automatic : .hidden)
            .background { if backgroundStyle != .plain { AppBackground() } }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                AreaTabBar()
                detail
            }
                .frame(minWidth: 760, minHeight: 560)
                .background(AppBackground())
        }
        .appAccent()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
        }
    }

    private func badge(for section: SidebarSection) -> String? {
        switch section {
        case .storage: app.cleanup.total(.safe) > 0 ? Format.bytes(app.cleanup.total(.safe)) : nil
        case .processes: app.processes.growingCount > 0 ? "\(app.processes.growingCount)" : nil
        case .ports: app.ports.ports.isEmpty ? nil : "\(app.ports.ports.count)"
        case .security: SecurityAdvisor.badge(hasRun: app.security.lastRun != nil, protectionsOff: app.security.protectionsOff, findings: app.security.highFindings)
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
        case .malware: MalwareScanView()
        case .permissions: PrivacyPermissionsView()
        case .network: NetworkMonitorView()
        case .sharing: SharingAuditView()
        case .backups: BackupStatusView()
        case .gitSlimming: ScrollView { GitSlimmingView().padding(20) }.navigationTitle("Git Repos")
        case .appFootprint: ScrollView { AppFootprintView().padding(20) }.navigationTitle("App Footprint")
        case .browserProfiles: BrowserProfilesView().navigationTitle("Browser Profiles")
        case .memoryGuard: MemoryGuardView()
        case .startupGuard: StartupGuardView(startupGuard: app.startupGuard).navigationTitle("Startup Guard")
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
struct SidebarRow: View {
    let section: SidebarSection
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarItemLabel(symbol: section.symbol, title: section.rawValue, badge: badge, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Sidebar row look: soft highlight with an accent bar on the left, counts in small rounded badges.
struct SidebarItemLabel: View {
    let symbol: String
    let title: String
    let badge: String?
    let isSelected: Bool
    @Environment(\.appAccent) private var accent
    @AppStorage(SettingsKeys.sidebarHex) private var sidebarHex = ""

    var body: some View {
        let highlight = Color(hex: sidebarHex) ?? accent
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 20)
                .foregroundStyle(isSelected ? highlight : .secondary)
            Text(title).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 4)
            if let badge {
                Text(badge).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .leading) {
            if isSelected { Capsule().fill(highlight).frame(width: 3, height: 18).offset(x: -6) }
        }
        .contentShape(Rectangle())
    }
}

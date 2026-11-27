import MacSweepCore
import SwiftUI

/// Dashboard for the whole Mac: hero summary, live gauges, and one card per subsystem.
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @State private var killRequest: KillRequest?
    @AppStorage(SettingsKeys.dashboardCards) private var layout = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !app.hasFullDiskAccess { FullDiskAccessBanner(onRecheck: app.refreshPermissions) }
                OverviewHero()
                let cards = DashboardLayout.decode(layout)
                if cards.contains(.activity) {
                    ActivityChartCard(cpu: app.monitor.cpuHistory, memory: app.monitor.memoryHistory)
                }
                EqualHeightGrid(items: cards.filter { $0 != .activity }, columns: 3) { card($0) }
            }
            .padding(20)
        }
        .background(OverviewBackground())
        .navigationTitle("Dashboard")
        .toolbar {
            SettingsLink { Label("Customize", systemImage: "slider.horizontal.3") }
                .help("Choose and reorder dashboard cards")
        }
        .navigationSubtitle(Host.current().localizedName ?? "This Mac")
        .killFlow($killRequest) { Task { await app.processes.refresh() } }
    }

    @ViewBuilder private func card(_ kind: DashboardCardKind) -> some View {
        switch kind {
        case .activity: EmptyView()
        case .storage: StorageOverviewCard()
        case .memory: MemoryOverviewCard()
        case .battery: BatteryCard()
        case .network: NetworkOverviewCard()
        case .security: SecurityOverviewCard()
        case .devices: DevicesCard()
        case .topMemory: TopProcessesCard(title: "Top memory", rows: topMemory, value: { Format.bytes($0.snapshot.memory) }) { killRequest = $0 }
        case .topCPU: TopProcessesCard(title: "Top CPU", rows: topCPU, value: { Format.percent($0.cpu) + "%" }) { killRequest = $0 }
        case .ports: PortsOverviewCard()
        case .usage: UsageTodayCard()
        }
    }

    private var topMemory: [ProcessRow] {
        Array(app.processes.rows.sorted { $0.memory > $1.memory }.prefix(5))
    }

    private var topCPU: [ProcessRow] {
        Array(app.processes.rows.sorted { $0.cpu > $1.cpu }.prefix(5))
    }
}

/// Soft colour wash behind the dashboard; adapts to light and dark mode.
struct OverviewBackground: View {
    @Environment(\.appAccent) private var accent
    var body: some View {
        Color.clear
    }
}

/// The Mac at a glance: what it is, how it's doing, the three live gauges and where the disk went.
struct OverviewHero: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let mac = app.system.mac
        let volume = app.monitor.volume
        let cleanable = min(app.cleanup.total(.safe) + app.cleanup.total(.review), volume?.used ?? 0)
        let kept = (volume?.used ?? 0) - cleanable
        SummaryHero(
            symbol: "macbook", eyebrow: "This Mac · live", value: mac.modelName, caption: caption(mac),
            tint: app.processes.memory?.pressure.color == .red || app.system.thermal == .critical ? .red : nil,
            segments: [
                BarSegment(label: "In use", value: Double(kept), color: .blue, detail: Format.bytes(kept)),
                BarSegment(label: "Cleanable", value: Double(cleanable), color: .orange, detail: Format.bytes(cleanable)),
                BarSegment(label: "Free", value: Double(volume?.available ?? 0), color: .gray.opacity(0.35), detail: Format.bytes(volume?.available ?? 0)),
            ]
        ) {
            HStack(spacing: 22) {
                RingGauge(value: app.monitor.cpu, label: "CPU", size: 78, lineWidth: 8)
                RingGauge(value: memoryFraction, label: "Memory", size: 78, lineWidth: 8)
                RingGauge(value: diskFraction, label: "Disk", size: 78, lineWidth: 8)
            }
        }
    }

    private func caption(_ mac: MacInfo) -> String {
        var parts = ["\(mac.chip) · \(Format.memory(mac.memory)) memory · \(mac.osVersion)", "up \(app.system.uptime)", "thermal \(app.system.thermal.rawValue.lowercased())"]
        if let memory = app.processes.memory { parts.append("memory pressure \(memory.pressure.rawValue.lowercased())") }
        return parts.joined(separator: " · ")
    }

    private var memoryFraction: Double {
        app.processes.memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
    }

    private var diskFraction: Double {
        app.monitor.volume.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
    }
}

struct TopProcessesCard: View {
    let title: String
    let rows: [ProcessRow]
    let value: (ProcessRow) -> String
    let onKill: (KillRequest) -> Void

    var body: some View {
        DashboardCard(title: title, symbol: "list.number") {
            VStack(spacing: 7) {
                if rows.isEmpty { Text("Sampling…").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        ProcessIcon(pid: row.pid, path: row.snapshot.path)
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text(value(row)).monospacedDigit().foregroundStyle(.secondary)
                        Button { onKill(KillRequest(pid: row.pid, name: row.name, force: false)) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Quit \(row.name)")
                        .accessibilityLabel("Quit \(row.name)")
                    }
                    .font(.callout)
                }
            }
        }
    }
}

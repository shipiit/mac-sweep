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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard").font(.system(size: 30, weight: .bold))
                        Text("Your Mac's health, performance and security at a glance.").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Live · updates every few seconds", systemImage: "dot.radiowaves.left.and.right").font(.callout).foregroundStyle(.secondary)
                }
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

struct OverviewHero: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app

    var body: some View {
        let mac = app.system.mac
        Panel(padding: 22) {
            HStack(spacing: 26) {
                Image(systemName: "macbook")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 150)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(mac.modelName).font(.system(size: 28, weight: .bold))
                    Text("\(mac.chip) · \(Format.memory(mac.memory)) memory · \(mac.osVersion)")
                        .font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        StatusChip(text: "Up \(app.system.uptime)", symbol: "clock", color: .secondary)
                        StatusChip(text: "Thermal: \(app.system.thermal.rawValue)", symbol: "circle.fill", color: thermalColor)
                        if let memory = app.processes.memory {
                            StatusChip(text: "Memory pressure: \(memory.pressure.rawValue)", symbol: "circle.fill", color: memory.pressure.color)
                        }
                    }
                    .padding(.top, 6)
                }
                Spacer()
                HStack(spacing: 26) {
                    RingGauge(value: app.monitor.cpu, label: "CPU", size: 86, lineWidth: 9)
                    RingGauge(value: memoryFraction, label: "Memory", size: 86, lineWidth: 9)
                    RingGauge(value: diskFraction, label: "Disk", size: 86, lineWidth: 9)
                }
            }
        }
    }

    private var memoryFraction: Double {
        app.processes.memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
    }

    private var diskFraction: Double {
        app.monitor.volume.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
    }

    private var thermalColor: Color {
        switch app.system.thermal {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
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

/// Small rounded status label with an icon, for the dashboard hero.
struct StatusChip: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .imageScale(.small)
            .foregroundStyle(color == .secondary ? .secondary : color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((color == .secondary ? Color.secondary : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

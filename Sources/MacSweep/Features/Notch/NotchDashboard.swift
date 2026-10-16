import Darwin
import MacSweepCore
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case system = "System"
    case apps = "Apps"
    case ports = "Ports"
    case ai = "AI"
    case clean = "Clean"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .system: "gauge.with.dots.needle.50percent"
        case .apps: "square.stack.3d.up"
        case .ports: "network"
        case .ai: "flame"
        case .clean: "sparkles"
        }
    }
}

/// The hover panel, NotchNook-style: tab chips on top, one focused view per tab.
struct NotchDashboard: View {
    let topInset: CGFloat
    @Environment(AppModel.self) private var app
    @AppStorage("notchTab") private var tab: NotchTab = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(NotchTab.allCases) { item in
                    Button { withAnimation(.snappy) { tab = item } } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tab == item ? Color.white.opacity(0.16) : .clear, in: Capsule())
                            .foregroundStyle(tab == item ? .white : .white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { open(.overview) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Open MacSweep")
                    .accessibilityLabel("Open MacSweep")
            }
            Group {
                switch tab {
                case .system: NotchSystemTab()
                case .apps: NotchAppsTab(onQuit: quit)
                case .ports: NotchPortsTab(onQuit: quit)
                case .ai: NotchAITab(open: open)
                case .clean: NotchCleanTab(open: open)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, topInset + 8)
        .padding(.bottom, 16)
    }

    private func open(_ section: SidebarSection) {
        app.section = section
        app.openMainWindow?()
    }

    private func quit(_ pid: Int32, _ name: String) {
        _ = ProcessKiller.send(SIGTERM, to: pid, name: name)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await app.processes.refresh()
            await app.ports.refresh()
        }
    }
}

private struct NotchSystemTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let memory = app.processes.memory
        let volume = app.monitor.volume
        HStack(alignment: .center, spacing: 22) {
            RingGauge(value: app.monitor.cpu, label: "CPU", caption: app.system.thermal.rawValue, size: 58, lineWidth: 6)
            RingGauge(value: memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, label: "Memory",
                      caption: memory.map { Format.memory($0.used) }, size: 58, lineWidth: 6)
            RingGauge(value: volume.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, label: "Disk",
                      caption: volume.map { Format.bytes($0.available) + " free" }, size: 58, lineWidth: 6)
            if let battery = app.system.battery {
                RingGauge(value: Double(battery.percent) / 100, label: battery.isCharging ? "Charging" : "Battery",
                          caption: battery.health.map { "Health \(Int(($0 * 100).rounded()))%" }, size: 58, lineWidth: 6, invertColors: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Sparkline(values: app.monitor.cpuHistory, color: .cyan)
                    Sparkline(values: app.monitor.memoryHistory, color: .purple)
                }
                .frame(width: 180, height: 46)
                HStack(spacing: 12) {
                    Label(Format.bytes(UInt64(max(app.monitor.downloadRate, 0))) + "/s", systemImage: "arrow.down").foregroundStyle(.teal)
                    Label(Format.bytes(UInt64(max(app.monitor.uploadRate, 0))) + "/s", systemImage: "arrow.up").foregroundStyle(.orange)
                }
                .monospacedDigit()
                Text(app.system.network?.wifiName ?? app.system.network?.interface ?? "Offline").foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, 6)
    }
}

private struct NotchAppsTab: View {
    @Environment(AppModel.self) private var app
    let onQuit: (Int32, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            column("Top memory", rows: app.processes.rows.sorted { $0.memory > $1.memory }) { Format.bytes($0.snapshot.memory) }
            column("Top CPU", rows: app.processes.rows.sorted { $0.cpu > $1.cpu }) { Format.percent($0.cpu) + "%" }
        }
    }

    private func column(_ title: String, rows: [ProcessRow], value: @escaping (ProcessRow) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            ForEach(rows.prefix(6)) { row in
                HStack(spacing: 6) {
                    ProcessIcon(pid: row.pid, path: row.snapshot.path, size: 14)
                    Text(row.name).lineLimit(1)
                    if row.trend.isSteadilyGrowing {
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).accessibilityLabel("Memory growing")
                    }
                    Spacer(minLength: 2)
                    Text(value(row)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    InlineConfirmButton(help: "Quit \(row.name)") { onQuit(row.pid, row.name) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotchPortsTab: View {
    @Environment(AppModel.self) private var app
    let onQuit: (Int32, String) -> Void

    var body: some View {
        let ports = Array(app.ports.ports.prefix(10))
        if ports.isEmpty {
            Text("Nothing is listening right now.").foregroundStyle(.white.opacity(0.6))
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 6) {
            ForEach(ports) { port in
                HStack(spacing: 6) {
                    Text(":\(port.port)").font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 50, alignment: .leading)
                    Text(port.command).lineLimit(1)
                    Image(systemName: port.isLocalOnly ? "lock.fill" : "globe")
                        .foregroundStyle(port.isLocalOnly ? .green : .orange)
                        .accessibilityLabel(port.isLocalOnly ? "Local only" : "Exposed")
                    Spacer(minLength: 2)
                    if port.proto == "TCP" {
                        Button { FileActions.open(url: URL(string: "http://localhost:\(port.port)")) } label: { Image(systemName: "safari") }
                            .buttonStyle(.plain)
                            .help("Open http://localhost:\(port.port)")
                            .accessibilityLabel("Open port \(port.port)")
                    }
                    InlineConfirmButton(help: "Stop \(port.command)") { onQuit(port.pid, port.command) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct NotchCleanTab: View {
    @Environment(AppModel.self) private var app
    let open: (SidebarSection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Format.bytes(app.cleanup.total(.safe))).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("safe to clean · \(Format.bytes(app.cleanup.total(.review))) to review").foregroundStyle(.white.opacity(0.6))
                HStack {
                    Button { open(.storage) } label: { Label("Review & Clean", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button { app.disk.scan() } label: { Label(app.disk.isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise") }
                        .disabled(app.disk.isScanning)
                }
                .controlSize(.small)
                if let result = app.disk.result {
                    Text("Last scan \(Format.relative(result.finishedAt))").foregroundStyle(.white.opacity(0.5))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(app.cleanup.items(.safe).prefix(5)) { item in
                    HStack {
                        Text(item.rule.title).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

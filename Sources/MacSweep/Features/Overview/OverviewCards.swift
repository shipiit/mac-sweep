import MacSweepCore
import SwiftUI

struct StorageOverviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Storage", symbol: "internaldrive", tint: .blue, action: ("Open", { app.section = .storage })) {
            if let volume = app.monitor.volume {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(volume.available)).font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("free of \(Format.bytes(volume.total))").foregroundStyle(.secondary)
                        if let days = app.insights.storageForecast?.daysUntilFull {
                            Label("Full \(StorageForecast.phrase(days: days))", systemImage: "chart.line.downtrend.xyaxis")
                                .font(.caption).foregroundStyle(days < 30 ? .orange : .secondary)
                        }
                    }
                    ProgressView(value: Double(volume.used), total: Double(max(volume.total, 1))).tint(.blue)
                    if app.cleanup.total(.safe) > 0 {
                        Button { app.section = .storage } label: {
                            Label("\(Format.bytes(app.cleanup.total(.safe))) safe to clean", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                    } else if app.disk.result == nil {
                        Button("Scan Home Folder") { app.disk.scan(root: app.home); app.section = .storage }.controlSize(.small)
                    }
                    if let result = app.disk.result {
                        Text("Scanned \(Format.relative(result.finishedAt))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct MemoryOverviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Memory", symbol: "memorychip", tint: .purple, action: ("Processes", { app.section = .processes })) {
            if let memory = app.processes.memory {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.memory(memory.total > memory.used ? memory.total - memory.used : 0))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("available").foregroundStyle(.secondary)
                    }
                    StackedBar(segments: [
                        BarSegment(label: "App", value: Double(memory.app), color: .blue, detail: Format.memory(memory.app)),
                        BarSegment(label: "Wired", value: Double(memory.wired), color: .orange, detail: Format.memory(memory.wired)),
                        BarSegment(label: "Compressed", value: Double(memory.compressed), color: .purple, detail: Format.memory(memory.compressed)),
                        BarSegment(label: "Free", value: Double(memory.free + memory.cached), color: Color(nsColor: .quaternaryLabelColor), detail: Format.memory(memory.free + memory.cached)),
                    ], height: 10, showsLegend: false)
                    MetricLine(label: "Pressure", value: memory.pressure.rawValue, color: memory.pressure.color)
                    MetricLine(label: "Swap used", value: Format.memory(memory.swapUsed))
                    if app.processes.growingCount > 0 {
                        MetricLine(label: "Growing steadily", value: "\(app.processes.growingCount) processes", color: .orange)
                    }
                }
            }
        }
    }
}

struct BatteryCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Battery", symbol: symbol, tint: .green) {
            if let battery = app.system.battery {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(battery.percent)%").font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text(state(battery)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(battery.percent), total: 100).tint(battery.percent < 20 ? .red : .green)
                    if let health = battery.health {
                        MetricLine(label: "Health", value: "\(Int((health * 100).rounded()))%", color: health < 0.8 ? .orange : .primary)
                    }
                    if let cycles = battery.cycleCount { MetricLine(label: "Cycle count", value: "\(cycles)") }
                    if let temperature = battery.temperatureCelsius {
                        MetricLine(label: "Temperature", value: temperature.formatted(.number.precision(.fractionLength(1))) + " °C")
                    }
                }
            } else {
                Text("No battery. This Mac runs on mains power.").foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        guard let battery = app.system.battery else { return "powerplug" }
        if battery.isCharging { return "battery.100percent.bolt" }
        return battery.percent > 50 ? "battery.75percent" : "battery.25percent"
    }

    private func state(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return "Charging" + (battery.adapterWatts.map { " · \($0) W" } ?? "") }
        if battery.isPluggedIn { return "Plugged in" }
        return battery.minutesRemaining.map { "\($0 / 60)h \($0 % 60)m left" } ?? "On battery"
    }
}

struct NetworkOverviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Network", symbol: "wifi", tint: .teal, action: ("Test Speed", { app.system.runSpeedTest() })) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.system.network?.wifiName ?? (app.system.network?.isWiFi == true ? "Wi-Fi" : app.system.network?.interface ?? "Offline"))
                    .font(.title3.weight(.semibold))
                HStack(spacing: 16) {
                    Label(Format.bytes(UInt64(max(app.monitor.downloadRate, 0))) + "/s", systemImage: "arrow.down").foregroundStyle(.teal)
                    Label(Format.bytes(UInt64(max(app.monitor.uploadRate, 0))) + "/s", systemImage: "arrow.up").foregroundStyle(.orange)
                }
                .font(.callout.monospacedDigit())
                Sparkline(values: normalized(app.monitor.downloadHistory), color: .teal).frame(height: 28)
                if let ip = app.system.network?.ipv4 { MetricLine(label: "IP address", value: ip) }
                speedResult
            }
        }
    }

    @ViewBuilder private var speedResult: some View {
        switch app.system.speedTest {
        case .idle: EmptyView()
        case .running:
            HStack { ProgressView().controlSize(.small); Text("Testing… about 20 seconds").foregroundStyle(.secondary) }.font(.callout)
        case .done(let result):
            MetricLine(label: "Speed test", value: "↓ \(Int(result.downloadMbps)) · ↑ \(Int(result.uploadMbps)) Mbps")
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func normalized(_ values: [Double]) -> [Double] {
        let peak = max(values.max() ?? 1, 1)
        return values.map { $0 / peak }
    }
}

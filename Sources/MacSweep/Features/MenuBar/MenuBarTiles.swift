import MacSweepCore
import SwiftUI

/// One tile in the menu bar dropdown grid.
struct MenuTile<Content: View>: View {
    @Environment(\.appAccent) private var accent
    let title: String
    let symbol: String
    var tint: Color? = nil
    var action: (title: String, run: () -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint ?? accent).accessibilityHidden(true)
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            }
            content
            Spacer(minLength: 0)
            if let action {
                HStack {
                    Spacer()
                    Button(action.title, action: action.run)
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint ?? accent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

struct MenuBarTileGrid: View {
    @Environment(AppModel.self) private var app
    let open: (SidebarSection) -> Void
    @State private var purgeMessage: String?

    var body: some View {
        let memory = app.processes.memory
        let volume = app.monitor.volume
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            MenuTile(title: "Macintosh HD", symbol: "internaldrive", tint: .blue, action: ("Free Up", { open(.storage) })) {
                Text("Available: \(Format.bytes(volume?.available ?? 0))").font(.caption).foregroundStyle(.orange)
                if app.cleanup.total(.safe) > 0 {
                    Text("\(Format.bytes(app.cleanup.total(.safe))) safe to clean").font(.caption).foregroundStyle(.secondary)
                }
            }
            MenuTile(title: "Memory", symbol: "memorychip", tint: .purple, action: ("Free Up", purge)) {
                Text("Available: \(Format.memory(memory.map { $0.total > $0.used ? $0.total - $0.used : 0 } ?? 0))").font(.caption).foregroundStyle(.secondary)
                if let memory { Text("Pressure: \(memory.pressure.rawValue)").font(.caption).foregroundStyle(memory.pressure.color) }
                if let purgeMessage { Text(purgeMessage).font(.caption2).foregroundStyle(.secondary) }
            }
            MenuTile(title: "Battery", symbol: batterySymbol, tint: .green) {
                if let battery = app.system.battery {
                    HStack {
                        Text(battery.isCharging ? "Charging" : battery.isPluggedIn ? "Plugged in" : "On battery").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(battery.percent)%").font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    if let health = battery.health {
                        Text("Health \(Int((health * 100).rounded()))% · \(battery.cycleCount ?? 0) cycles").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Mains power").font(.caption).foregroundStyle(.secondary)
                }
            }
            MenuTile(title: "CPU", symbol: "cpu", tint: .cyan) {
                HStack {
                    Text("Load: \(Int((app.monitor.cpu * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(app.system.thermal.rawValue).font(.caption.weight(.semibold))
                        .foregroundStyle(app.system.thermal == .nominal ? .green : .orange)
                }
                Sparkline(values: app.monitor.cpuHistory, color: .cyan).frame(height: 24)
            }
            MenuTile(title: app.system.network?.wifiName ?? (app.system.network?.isWiFi == true ? "Wi-Fi" : "Network"),
                     symbol: "wifi", tint: .teal, action: ("Test Speed", { app.system.runSpeedTest() })) {
                Label(Format.bytes(UInt64(max(app.monitor.uploadRate, 0))) + "/s", systemImage: "arrow.up").font(.caption)
                Label(Format.bytes(UInt64(max(app.monitor.downloadRate, 0))) + "/s", systemImage: "arrow.down").font(.caption)
                speed
            }
            MenuTile(title: "AI today", symbol: "flame", tint: .orange, action: ("Details", { open(.ai) })) {
                HStack {
                    Text(TokenFormat.compact(app.ai.todayTotals.total) + " tokens").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(TokenFormat.cost(app.ai.todayCost)).font(.callout.weight(.semibold)).monospacedDigit()
                }
                ForEach(app.ai.limitLines(for: AIUsageModel.defaultTool)) { line in
                    LimitMiniBar(title: line.title, fraction: line.left,
                                 trailing: line.resetsAt.map { "resets \($0.formatted(date: .omitted, time: .shortened))" })
                }
            }
        }
    }

    @ViewBuilder private var speed: some View {
        switch app.system.speedTest {
        case .idle: EmptyView()
        case .running: Text("Testing…").font(.caption2).foregroundStyle(.secondary)
        case .done(let result): Text("↓\(Int(result.downloadMbps)) ↑\(Int(result.uploadMbps)) Mbps").font(.caption2.monospacedDigit())
        case .failed: Text("Test failed").font(.caption2).foregroundStyle(.red)
        }
    }

    private var batterySymbol: String {
        guard let battery = app.system.battery else { return "powerplug" }
        return battery.isCharging ? "battery.100percent.bolt" : "battery.75percent"
    }

    /// macOS manages memory well on its own; purge only flushes disk caches, so say that honestly.
    private func purge() {
        Task {
            do {
                try await AdminRunner.purgeMemory()
                purgeMessage = "Disk caches flushed"
            } catch AdminRunner.AdminError.cancelled {
                return
            } catch {
                purgeMessage = error.localizedDescription
            }
        }
    }
}

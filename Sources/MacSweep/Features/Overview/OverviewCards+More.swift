import MacSweepCore
import SwiftUI

struct SecurityOverviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let security = app.security
        DashboardCard(title: "Security", symbol: "checkmark.shield", tint: .indigo, action: ("Details", { app.section = .security })) {
            HStack(spacing: 16) {
                RingGauge(value: Double(security.score) / 100, label: "Score", size: 64, invertColors: true)
                VStack(alignment: .leading, spacing: 6) {
                    MetricLine(label: "Protections off", value: "\(security.protectionsOff)", color: security.protectionsOff > 0 ? .red : .green)
                    MetricLine(label: "Findings", value: "\(security.highFindings)", color: security.highFindings > 0 ? .orange : .green)
                    MetricLine(label: "High-access extensions", value: "\(security.highAccessExtensions)")
                    if security.isRunning { Text("Checking…").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct DevicesCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Connected devices", symbol: "cable.connector", tint: .orange) {
            VStack(alignment: .leading, spacing: 7) {
                if app.system.devices.isEmpty {
                    Text("No USB or Bluetooth devices").foregroundStyle(.secondary)
                }
                ForEach(app.system.devices.prefix(6)) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.kind == .bluetooth ? "dot.radiowaves.left.and.right" : "cable.connector.horizontal")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityLabel(device.kind.rawValue)
                        Text(device.name).lineLimit(1)
                        Spacer()
                        if let detail = device.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .font(.callout)
                }
                ForEach(NSScreen.screens.dropFirst(), id: \.self) { screen in
                    HStack(spacing: 8) {
                        Image(systemName: "display").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                        Text(screen.localizedName).lineLimit(1)
                        Spacer()
                        Text("\(Int(screen.frame.width))×\(Int(screen.frame.height))").font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct PortsOverviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DashboardCard(title: "Listening ports", symbol: "network", tint: .pink, action: ("All Ports", { app.section = .ports })) {
            VStack(alignment: .leading, spacing: 7) {
                if app.ports.ports.isEmpty { Text("Nothing listening").foregroundStyle(.secondary) }
                ForEach(app.ports.ports.prefix(5)) { port in
                    HStack(spacing: 8) {
                        Text(":\(port.port)").font(.system(.callout, design: .monospaced).weight(.semibold)).frame(width: 60, alignment: .leading)
                        Text(port.command).lineLimit(1)
                        Spacer()
                        Image(systemName: port.isLocalOnly ? "lock.fill" : "globe")
                            .foregroundStyle(port.isLocalOnly ? .green : .orange)
                            .help(port.isLocalOnly ? "This Mac only" : "Reachable from the network")
                            .accessibilityLabel(port.isLocalOnly ? "Local only" : "Exposed to network")
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct UsageTodayCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let today = app.usage.log.summary(days: 1)
        DashboardCard(title: "App usage today", symbol: "hourglass", tint: .mint, action: ("Details", { app.section = .usage })) {
            VStack(alignment: .leading, spacing: 7) {
                Text(duration(today.reduce(0) { $0 + $1.seconds })).font(.system(size: 26, weight: .semibold, design: .rounded))
                if today.isEmpty { Text("Collecting…").foregroundStyle(.secondary) }
                ForEach(today.prefix(4)) { item in
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text(duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

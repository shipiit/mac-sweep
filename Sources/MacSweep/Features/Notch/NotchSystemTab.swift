import Charts
import MacSweepCore
import SwiftUI

/// Four big rings, then live network throughput with a chart.
struct NotchSystemTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let memory = app.processes.memory
        let volume = app.monitor.volume
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ring(app.monitor.cpu, "CPU", app.system.thermal.rawValue)
                ring(memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, "Memory", memory.map { Format.memory($0.used) })
                ring(volume.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, "Disk", volume.map { Format.bytes($0.available) + " free" })
                if let battery = app.system.battery {
                    ring(Double(battery.percent) / 100, battery.isCharging ? "Charging" : "Battery",
                         battery.health.map { "Health \(Int(($0 * 100).rounded()))%" }, invert: true)
                }
            }
            NotchNetworkCard()
        }
    }

    private func ring(_ value: Double, _ label: String, _ caption: String?, invert: Bool = false) -> some View {
        RingGauge(value: value, label: label, caption: caption, size: 74, lineWidth: 8, invertColors: invert)
            .frame(maxWidth: .infinity)
    }
}

private struct NotchNetworkCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let down = app.monitor.downloadHistory
        let up = app.monitor.uploadHistory
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Network", systemImage: "arrow.up.arrow.down").font(.system(size: 14, weight: .semibold))
                Text(app.system.network?.wifiName ?? app.system.network?.interface ?? "Offline")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                rate("arrow.down", .cyan, app.monitor.downloadRate, "Download")
                rate("arrow.up", .purple, app.monitor.uploadRate, "Upload")
            }
            .frame(width: 150, alignment: .leading)
            Chart {
                ForEach(Array(down.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("t", index), y: .value("Download", value), series: .value("s", "down"))
                        .foregroundStyle(.cyan.opacity(0.25))
                    LineMark(x: .value("t", index), y: .value("Download", value), series: .value("s", "down")).foregroundStyle(.cyan)
                }
                ForEach(Array(up.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("Upload", value), series: .value("s", "up")).foregroundStyle(.purple)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel { Text(Format.bytes(UInt64(max(value.as(Double.self) ?? 0, 0))) + "/s").foregroundStyle(.white.opacity(0.5)) }
                }
            }
            .frame(height: 120)
            .accessibilityLabel("Network throughput over the last minutes")
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rate(_ symbol: String, _ color: Color, _ value: Double, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.bytes(UInt64(max(value, 0))) + "/s").font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(color).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

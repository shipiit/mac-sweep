import Charts
import MacSweepCore
import SwiftUI

enum TimelineMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory used", disk = "Disk free", network = "Download"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cpu: .green
        case .memory: .purple
        case .disk: .teal
        case .network: .blue
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.down.circle"
        }
    }

    func value(_ point: TimelinePoint) -> Double {
        switch self {
        case .cpu: point.cpu * 100
        case .memory: Double(point.memoryUsed) / 1_073_741_824
        case .disk: Double(point.diskFree) / 1_000_000_000
        case .network: point.downloadRate / 1_000_000
        }
    }

    func label(_ value: Double) -> String {
        switch self {
        case .cpu: "\(Int(value.rounded()))%"
        case .memory, .disk: String(format: "%.1f GB", value)
        case .network: String(format: "%.1f MB/s", value)
        }
    }
}

/// Averages, peaks and change over the chosen range.
struct TimelineSummary: View {
    let points: [TimelinePoint]
    let rangeTitle: String

    var body: some View {
        let peak = points.max { $0.cpuPeak < $1.cpuPeak }
        let averageCPU = points.reduce(0) { $0 + $1.cpu } / Double(max(points.count, 1))
        let averageMemory = points.reduce(0) { $0 + Double($1.memoryUsed) } / Double(max(points.count, 1))
        let diskChange = Int64(clamping: points.last?.diskFree ?? 0) - Int64(clamping: points.first?.diskFree ?? 0)
        StatStrip {
            StatTile(title: "Average CPU", value: "\(Int((averageCPU * 100).rounded()))%", detail: "over \(rangeTitle)")
            StatTile(title: "Peak CPU", value: "\(Int(((peak?.cpuPeak ?? 0) * 100).rounded()))%",
                     detail: peak.map { "\($0.topProcess) · \($0.time.formatted(date: .omitted, time: .shortened))" } ?? "—")
            StatTile(title: "Average memory", value: Format.bytes(UInt64(averageMemory)), detail: "in use")
            StatTile(title: "Disk free change", value: (diskChange >= 0 ? "+" : "−") + Format.bytes(UInt64(diskChange.magnitude)),
                     detail: diskChange < 0 ? "used up over \(rangeTitle)" : "freed over \(rangeTitle)", dot: diskChange < -5_000_000_000 ? .orange : nil)
        }
    }
}

/// Filled area chart for one metric; hover shows the exact value and time.
struct TimelineChartCard: View {
    let metric: TimelineMetric
    let points: [TimelinePoint]
    let color: Color
    @State private var hovered: TimelinePoint?

    var body: some View {
        let shown = hovered ?? points.last
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(metric.rawValue, systemImage: metric.symbol).font(.headline)
                    Spacer()
                    if let shown {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(metric.label(metric.value(shown))).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                            Text(hovered == nil ? "now" : shown.time.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Time", point.time), y: .value(metric.rawValue, metric.value(point)), series: .value("Segment", point.segment))
                            .foregroundStyle(color.opacity(0.18))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", point.time), y: .value(metric.rawValue, metric.value(point)), series: .value("Segment", point.segment))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                    // Lone points between gaps (the Mac was asleep) show as dots instead of stray dashes.
                    ForEach(isolated) { point in
                        PointMark(x: .value("Time", point.time), y: .value(metric.rawValue, metric.value(point))).foregroundStyle(color).symbolSize(12)
                    }
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.time)).foregroundStyle(.secondary.opacity(0.5))
                        PointMark(x: .value("Time", hovered.time), y: .value(metric.rawValue, metric.value(hovered))).foregroundStyle(color).symbolSize(40)
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = location.x - geometry[frame].origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        hovered = points.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
                                    }
                                case .ended: hovered = nil
                                }
                            }
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("\(metric.rawValue) over time, now \(points.last.map { metric.label(metric.value($0)) } ?? "unknown")")
            }
        }
    }

    private var isolated: [TimelinePoint] {
        let counts = Dictionary(grouping: points, by: \.segment).mapValues(\.count)
        return points.filter { counts[$0.segment] == 1 }
    }
}

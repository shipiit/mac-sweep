import Charts
import MacSweepCore
import SwiftUI

/// CPU, memory, disk and network over 24 h / 7 d / 14 d, with spikes labelled by the busiest process.
struct InsightsTimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    @State private var range: TimelineRange = .day

    var body: some View {
        let points = TimelineAggregator.points(app.insights.samplesIncludingCurrent, range: range, now: Date())
        let spikes = TimelineAggregator.spikes(points)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if points.isEmpty {
                    ModuleIntro(title: "Timeline", subtitle: "See what your Mac was doing at any time in the last 14 days.",
                                symbol: "chart.xyaxis.line", tint: accent,
                                bullets: [("cpu", "CPU, memory, disk and network", "A point every 5 minutes, kept for 14 days in under 2 MB."),
                                          ("bolt", "Spikes explained", "Each CPU spike shows the process that was busiest at the time.")],
                                actionTitle: "Record now") { app.insights.recordNow(app) }
                        .frame(minHeight: 460)
                } else {
                    chart("CPU", points, value: { $0.cpu * 100 }, unit: "%", color: accent)
                    chart("Memory used", points, value: { Double($0.memoryUsed) / 1_073_741_824 }, unit: "GB", color: .purple)
                    chart("Disk free", points, value: { Double($0.diskFree) / 1_000_000_000 }, unit: "GB", color: .teal)
                    chart("Download", points, value: { $0.downloadRate / 1_000_000 }, unit: "MB/s", color: .blue)
                    if !spikes.isEmpty { spikeList(spikes) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Timeline")
        .navigationSubtitle("CPU, memory, disk and network · a point every 5 minutes")
        .sectionTabs(TimelineRange.allCases, selection: $range, title: \.title)
    }

    private func chart(_ title: String, _ points: [TimelinePoint], value: @escaping (TimelinePoint) -> Double, unit: String, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let last = points.last { Text(String(format: "%.1f %@", value(last), unit)).monospacedDigit().foregroundStyle(.secondary) }
                }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.time), y: .value(title, value(point)), series: .value("Segment", point.segment))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks(position: .trailing) }
                .frame(height: 120)
            }
        }
    }

    private func spikeList(_ spikes: [TimelinePoint]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "CPU spikes", subtitle: "And what was busiest at the time")
                ForEach(spikes) { spike in
                    HStack {
                        Text(spike.time.formatted(date: .abbreviated, time: .shortened)).monospacedDigit()
                        Spacer()
                        Text("\(Int((spike.cpuPeak * 100).rounded()))% CPU").monospacedDigit().fontWeight(.semibold)
                        Text("· \(spike.topProcess)").foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

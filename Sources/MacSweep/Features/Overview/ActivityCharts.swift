import Charts
import MacSweepCore
import SwiftUI

private struct SeriesPoint: Identifiable {
    let series: String
    let index: Int
    let value: Double

    var id: String { "\(series)-\(index)" }
}

/// CPU and memory as percentages over the last two minutes.
struct ActivityChartCard: View {
    let cpu: [Double]
    let memory: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "System Activity", subtitle: "CPU and memory usage, last 2 minutes")
                    Spacer()
                    Label("CPU \(Int((cpu.last ?? 0) * 100))%", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
                    Label("Memory \(Int((memory.last ?? 0) * 100))%", systemImage: "circle.fill").foregroundStyle(.purple).font(.caption)
                }
                Chart(points) { point in
                    AreaMark(x: .value("Time", point.index), y: .value("Percent", point.value * 100), series: .value("Series", point.series), stacking: .unstacked)
                        .foregroundStyle(by: .value("Series", point.series))
                        .opacity(0.3)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.index), y: .value("Percent", point.value * 100), series: .value("Series", point.series))
                        .foregroundStyle(by: .value("Series", point.series))
                        .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale(["CPU": Color.blue, "Memory": Color.purple])
                .chartXAxis(.hidden)
                .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                .chartYAxisLabel("%")
                .chartLegend(.hidden)
                .frame(height: 180)
                .accessibilityLabel("CPU \(Int((cpu.last ?? 0) * 100)) percent, memory \(Int((memory.last ?? 0) * 100)) percent")
            }
        }
    }

    private var points: [SeriesPoint] {
        let offset = { (values: [Double]) in SystemMonitor.historyLength - values.count }
        return cpu.enumerated().map { SeriesPoint(series: "CPU", index: $0.offset + offset(cpu), value: $0.element) }
            + memory.enumerated().map { SeriesPoint(series: "Memory", index: $0.offset + offset(memory), value: $0.element) }
    }
}

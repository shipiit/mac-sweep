import AppKit
import Charts
import MacSweepCore
import SwiftUI

struct UsageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    @State private var range = 1

    private static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .green, .gray]

    var body: some View {
        let log = app.usage.log
        let summary = log.summary(days: range)
        let total = summary.reduce(0) { $0 + $1.seconds }
        let previous = previousTotal(log)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !app.usage.isEnabled {
                    ContentUnavailableView("App usage tracking is off", systemImage: "hourglass",
                                           description: Text("Turn it on in Settings › Privacy."))
                } else if summary.isEmpty {
                    ContentUnavailableView("Collecting usage…", systemImage: "hourglass",
                                           description: Text("Switch between a few apps and come back."))
                } else {
                    header(total: total, previous: previous, summary: summary)
                    EqualHeightGrid(items: Panel.allCases, columns: 2) { panel in
                        switch panel {
                        case .share: shareCard(summary, total: total)
                        case .hours: hoursCard(log.hourly(days: range))
                        }
                    }
                    if range > 1 { dailyCard(log) }
                    appsCard(summary, total: total)
                }
            }
            .padding(20)
        }
        .navigationTitle("App Usage")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Range", selection: $range) {
                    Text("Today").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    enum Panel: String, CaseIterable, Identifiable {
        case share, hours
        var id: String { rawValue }
    }

    private func header(total: Double, previous: Double, summary: [AppUsageSummary]) -> some View {
        let delta = total - previous
        return Card(padding: 20) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(range == 1 ? "Screen time today" : "Screen time, last \(range) days").foregroundStyle(.secondary)
                    Text(duration(total)).font(.system(size: 40, weight: .bold, design: .rounded))
                    if previous > 0 {
                        Label("\(duration(abs(delta))) \(delta >= 0 ? "more" : "less") than the previous \(range == 1 ? "day" : "\(range) days")",
                              systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.callout).foregroundStyle(delta >= 0 ? .orange : .green)
                    }
                }
                Divider().frame(height: 60)
                metric("Apps used", "\(summary.count)")
                metric("App switches", "\(summary.reduce(0) { $0 + $1.activations })")
                metric("Most used", summary.first?.name ?? "—")
                Spacer()
                Label("Only on this Mac", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).lineLimit(1)
        }
    }

    private func shareCard(_ summary: [AppUsageSummary], total: Double) -> some View {
        let top = Array(summary.prefix(6))
        let other = total - top.reduce(0) { $0 + $1.seconds }
        let slices = top.map { ($0.name, $0.seconds) } + (other > 60 ? [("Other", other)] : [])
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Where your time went")
                HStack(spacing: 20) {
                    Chart(Array(slices.enumerated()), id: \.offset) { index, slice in
                        SectorMark(angle: .value("Time", slice.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(Self.palette[index % Self.palette.count])
                    }
                    .frame(width: 150, height: 150)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(duration(total)).font(.headline)
                            Text("total").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            HStack(spacing: 8) {
                                Circle().fill(Self.palette[index % Self.palette.count]).frame(width: 9, height: 9)
                                Text(slice.0).lineLimit(1)
                                Spacer()
                                Text("\(Int((slice.1 / max(total, 1) * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }

    private func hoursCard(_ hours: [Double]) -> some View {
        let current = Calendar.current.component(.hour, from: Date())
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: range == 1 ? "Today by hour" : "Average day by hour")
                Chart(Array(hours.enumerated()), id: \.offset) { hour, seconds in
                    BarMark(x: .value("Hour", hour), y: .value("Minutes", seconds / 60))
                        .foregroundStyle(range == 1 && hour == current ? accent : accent.opacity(0.45))
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { value in AxisValueLabel { Text("\(value.as(Int.self) ?? 0):00") } } }
                .chartYAxisLabel("min")
                .frame(height: 150)
            }
        }
    }

    private func dailyCard(_ log: UsageLog) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Daily screen time")
                Chart(log.dailyTotals(days: range), id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.seconds / 3_600))
                        .foregroundStyle(accent)
                        .cornerRadius(4)
                }
                .chartYAxisLabel("hours")
                .frame(height: 150)
            }
        }
    }

    private func appsCard(_ summary: [AppUsageSummary], total: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Apps")
                ForEach(summary.prefix(25)) { item in
                    let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)?.path
                    HStack(spacing: 12) {
                        if let path { FileIcon(path: path, size: 30) } else { Image(systemName: "app.dashed").frame(width: 30) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).fontWeight(.medium)
                            Text(category(path)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 210, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(accent).frame(width: max(proxy.size.width * item.seconds / max(summary.first?.seconds ?? 1, 1), 4))
                            }
                        }
                        .frame(height: 8)
                        Text(duration(item.seconds)).monospacedDigit().fontWeight(.semibold).frame(width: 70, alignment: .trailing)
                        Text("\(Int((item.seconds / max(total, 1) * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                        Text("\(item.activations)×").monospacedDigit().foregroundStyle(.tertiary).frame(width: 44, alignment: .trailing)
                            .help("Times you switched to it")
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func previousTotal(_ log: UsageLog) -> Double {
        let totals = log.dailyTotals(days: range * 2)
        return totals.prefix(range).reduce(0) { $0 + $1.seconds }
    }

    /// App Store category from the app's Info.plist ("public.app-category.developer-tools" → "Developer Tools").
    private func category(_ path: String?) -> String {
        guard let path, let info = Bundle(path: path)?.infoDictionary,
              let raw = info["LSApplicationCategoryType"] as? String
        else { return "App" }
        return raw.replacingOccurrences(of: "public.app-category.", with: "")
            .split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

func duration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "<1m" }
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

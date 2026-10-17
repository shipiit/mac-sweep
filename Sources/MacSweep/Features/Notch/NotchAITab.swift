import Charts
import MacSweepCore
import SwiftUI

/// AI usage at a glance: today's spend, and the 5-hour and weekly limits for both tools.
struct NotchAITab: View {
    let open: (SidebarSection) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let ai = app.ai
        VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").foregroundStyle(.white.opacity(0.6))
                Text(TokenFormat.cost(ai.todayCost)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("\(TokenFormat.compact(ai.todayTotals.total)) tokens").foregroundStyle(.white.opacity(0.6))
                if let updated = ai.lastRefreshed {
                    Text("Updated \(Format.relative(updated))").foregroundStyle(.white.opacity(0.4))
                }
                if let block = ai.claudeBlock, block.isActive {
                    Text("\(TokenFormat.compact(Int(block.burnPerHour)))/h burn").foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await ai.refresh()
                            await ai.refreshPlan(force: true)
                        }
                    } label: {
                        Label(ai.isRefreshing ? "Updating" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .disabled(ai.isRefreshing)
                    Button("Details") { open(.ai) }.buttonStyle(.link)
                }
            }
            .frame(width: 130, alignment: .leading)
            ForEach(AIProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Text(provider.rawValue).font(.system(size: 12, weight: .semibold))
                        if provider == AIUsageModel.defaultTool {
                            Text("default").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                    let lines = ai.limitLines(for: provider)
                    if lines.isEmpty {
                        Text("No limit data yet").foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(lines) { line in
                        LimitMiniBar(title: line.title.replacingOccurrences(of: provider == .codex ? "Codex " : "Claude ", with: ""),
                                     fraction: line.left,
                                     trailing: line.resetsAt.map { $0.formatted(date: .omitted, time: .shortened) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        NotchCostChart(entries: ai.index.entries)
        }
        .padding(.top, 6)
    }
}

/// Last 7 days of API-equivalent cost, today highlighted.
private struct NotchCostChart: View {
    let entries: [UsageEntry]

    var body: some View {
        let days = AIUsageSummary.daily(entries, days: 7)
        let total = days.reduce(0) { $0 + $1.cost }
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 7 days").font(.caption).foregroundStyle(.white.opacity(0.55))
                Text(TokenFormat.cost(total)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("\(TokenFormat.cost(total / 7)) a day").font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 130, alignment: .leading)
            Chart(days, id: \.day) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Cost", day.cost))
                    .foregroundStyle(Calendar.current.isDateInToday(day.day) ? Color.orange : Color.orange.opacity(0.45))
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(height: 96)
            .accessibilityLabel("AI cost per day for the last week")
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

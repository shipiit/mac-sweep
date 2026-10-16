import Charts
import MacSweepCore
import SwiftUI

/// Cost for whatever the page filter selects: a donut by model, spend insights and a daily trend.
struct AICostCard: View {
    let entries: [UsageEntry]
    /// Same tool filter but at least 7 days, so the trend has context even when the range is Today.
    let trendEntries: [UsageEntry]
    let days: Int
    @Environment(\.appAccent) private var accent

    var body: some View {
        let shares = AIUsageInsights.byModel(entries)
        let spend = AIUsageInsights.spend(entries, days: days)
        let hasUnpriced = AIUsageSummary.cost(of: entries).hasUnknown
        let trendDays = max(days, 7)
        let trend = AIUsageSummary.daily(trendEntries, days: trendDays)
        DashboardCard(title: "Cost", symbol: "dollarsign.circle", tint: accent, isFixedHeight: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    donut(shares, total: spend.total)
                    legend(shares, hasUnpriced: hasUnpriced)
                }
                HStack(spacing: 0) {
                    insight("Avg / active day", TokenFormat.cost(spend.averagePerActiveDay), detail: "\(spend.activeDays) active day\(spend.activeDays == 1 ? "" : "s")")
                    Divider().frame(height: 30)
                    insight("Peak day", spend.peakDay.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "—",
                            detail: spend.peakDay == nil ? "no priced use" : TokenFormat.cost(spend.peakCost))
                    Divider().frame(height: 30)
                    insight("Per 1M tokens", spend.costPerMillion.map(TokenFormat.cost) ?? "—", detail: "blended, incl. cache")
                }
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(days < 7 ? "Daily cost · last 7 days" : "Daily cost · \(days) days").font(.caption).foregroundStyle(.secondary)
                    Chart(trend, id: \.day) { point in
                        BarMark(x: .value("Day", point.day, unit: .day), y: .value("Cost", point.cost))
                            .foregroundStyle(Calendar.current.isDateInToday(point.day) ? accent : accent.opacity(0.55))
                            .cornerRadius(2)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 44)
                    .clipped()
                    .accessibilityLabel("Daily cost over \(trendDays) days")
                }
            }
        }
    }

    private func donut(_ shares: [ModelShare], total: Double) -> some View {
        Chart(shares) { share in
            SectorMark(angle: .value("Cost", max(share.cost ?? 0, 0.0001)), innerRadius: .ratio(0.72), angularInset: 1.5)
                .foregroundStyle(color(at: shares.firstIndex(of: share) ?? 0))
                .cornerRadius(3)
        }
        .frame(width: 118, height: 118)
        .overlay {
            VStack(spacing: 0) {
                Text(TokenFormat.cost(total)).font(.title3.weight(.semibold).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                Text("API value").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
        }
    }

    private func legend(_ shares: [ModelShare], hasUnpriced: Bool) -> some View {
        let priced = shares.compactMap(\.cost).reduce(0, +)
        return VStack(alignment: .leading, spacing: 7) {
            if shares.isEmpty {
                Text("No usage in this range").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(color(at: index)).frame(width: 9, height: 9).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(share.name).font(.callout).lineLimit(1)
                        Text("\(TokenFormat.compact(share.tokens)) tokens").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(share.cost.map(TokenFormat.cost) ?? "not priced").font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(share.cost == nil ? .secondary : .primary)
                        if let cost = share.cost, priced > 0 {
                            Text("\(Int((cost / priced * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if hasUnpriced {
                Text("Models without a published price show tokens only.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insight(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).lineLimit(1)
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private func color(at index: Int) -> Color {
        [accent, .teal, .orange, .purple, .gray][min(index, 4)]
    }
}

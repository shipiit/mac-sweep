import MacSweepCore
import SwiftUI

/// Limits in the "x% left · resets in …" style.
struct AILimitsCard: View {
    let block: UsageBlock?
    let codex: CodexRateLimits?
    /// Tools picked in the page filter; only their limits are shown.
    var providers: [AIProvider] = AIProvider.allCases
    /// Real plan limits, present only when the user enabled them in Settings.
    var plan: ClaudePlanUsage?
    @Environment(\.appAccent) private var accent

    var body: some View {
        DashboardCard(title: "Limits", symbol: "gauge.with.needle", tint: accent, isFixedHeight: false) {
            VStack(alignment: .leading, spacing: 12) {
                if providers.contains(.claudeCode) { claude }
                if providers.count > 1 { Divider() }
                if providers.contains(.codex) { codexSection }
            }
        }
    }

    @ViewBuilder private var claude: some View {
        HStack(spacing: 6) {
            Text("Claude Code").font(.subheadline.weight(.semibold))
            if let name = plan?.plan { Text(name).font(.caption).foregroundStyle(.secondary) }
        }
        if let plan {
            planRows(plan)
        } else {
            blockRows
            Text("Turn on real plan limits in Settings → AI to see session and weekly %.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func planRows(_ plan: ClaudePlanUsage) -> some View {
        ForEach([plan.session, plan.weekly].compactMap { $0 } + plan.modelWeekly) { window in
            let left = Double(window.percentLeft) / 100
            limitRow(window.name == "Session" ? "Session (5h)" : window.name, fraction: left,
                     left: window.percentLeft == 0 ? "Limit reached" : "\(window.percentLeft)% left",
                     right: window.resetsAt.map { $0 > Date() ? "Resets in \(countdown($0))" : "Reset" } ?? "Not started",
                     color: left <= 0.1 ? .red : left <= 0.3 ? .orange : accent)
        }
        if let extra = plan.extra {
            MetricLine(label: "Extra usage", value: extra.isEnabled
                       ? "\(Int(extra.usedCredits)) credits used\(extra.monthlyLimit.map { " of \(Int($0))" } ?? "")"
                       : "Off")
        }
        if let block, block.isActive {
            MetricLine(label: "Burn rate", value: "\(TokenFormat.compact(Int(block.burnPerHour)))/h")
        }
    }

    @ViewBuilder private var blockRows: some View {
        if let block, block.isActive {
            let left = 1 - min(max(Date().timeIntervalSince(block.start) / (5 * 3_600), 0), 1)
            limitRow("5-hour block", fraction: left, left: "\(Int((left * 100).rounded()))% of time left",
                     right: "Resets in \(countdown(block.end))", color: accent)
            MetricLine(label: "This block", value: "\(TokenFormat.compact(block.totals.total)) tokens · \(TokenFormat.cost(block.cost))")
            MetricLine(label: "Burn rate", value: "\(TokenFormat.compact(Int(block.burnPerHour)))/h")
        } else {
            limitRow("5-hour block", fraction: 1, left: "100% left", right: "Starts with your next request", color: accent)
        }
    }

    @ViewBuilder private var codexSection: some View {
        Text("Codex").font(.subheadline.weight(.semibold))
        if let primary = codex?.primary { codexRow("Session (5h)", primary) }
        if let weekly = codex?.secondary { codexRow("Weekly", weekly) }
        if codex == nil { Text("No Codex data yet").font(.caption).foregroundStyle(.secondary) }
    }

    private func codexRow(_ title: String, _ window: RateLimitWindow) -> some View {
        // Codex only reports limits when it runs, so a window past its reset time shows as fresh.
        let hasReset = window.hasReset()
        let used = window.usedFraction()
        let reset = hasReset ? "Reset · updates on next Codex run" : window.resetsAt.map { "Resets in \(countdown($0))" } ?? ""
        return limitRow(title, fraction: 1 - used,
                        left: used >= 1 ? "Limit reached" : "\(Int(((1 - used) * 100).rounded()))% left",
                        right: reset, color: used >= 0.9 ? .red : used >= 0.7 ? .orange : accent)
    }

    private func limitRow(_ title: String, fraction: Double, left: String, right: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)
            HStack {
                Text(left).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(right).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func countdown(_ date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSinceNow / 60), 0)
        if minutes >= 1_440 { return "\(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

enum UsageTimeKey {
    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// User-chosen session names, kept only in MacSweep's preferences.
enum SessionNames {
    private static let key = "aiSessionNames"

    static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func set(_ name: String, for session: String) {
        var names = all()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[session] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(names, forKey: key)
    }
}

import Charts
import MacSweepCore
import SwiftUI

struct DailyUsageChart: View {
    let entries: [UsageEntry]
    let days: Int
    @Environment(\.appAccent) private var accent

    var body: some View {
        let byProvider = AIProvider.allCases.flatMap { provider in
            AIUsageSummary.daily(entries.filter { $0.provider == provider }, days: max(days, 7)).map { (provider, $0.day, $0.tokens) }
        }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Tokens per day", subtitle: "Including cache reads")
                Chart(byProvider, id: \.1) { provider, day, tokens in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Tokens", tokens))
                        .foregroundStyle(by: .value("Tool", provider.rawValue))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(["Claude Code": accent, "Codex": Color.teal])
                .chartYAxis { AxisMarks { value in AxisGridLine(); AxisValueLabel { Text(TokenFormat.compact(value.as(Int.self) ?? 0)) } } }
                .frame(height: 180)
            }
        }
    }
}

enum Breakdown: String, CaseIterable, Identifiable {
    case model = "By model"
    case project = "By project"

    var id: String { rawValue }
}

struct BreakdownCard: View {
    let breakdown: Breakdown
    let entries: [UsageEntry]
    @Environment(\.appAccent) private var accent

    var body: some View {
        let groups = breakdown == .model
            ? AIUsageSummary.group(entries, by: \.model)
            : AIUsageSummary.group(entries, by: \.project)
        let top = groups.first?.totals.total ?? 1
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: breakdown.rawValue)
                if groups.isEmpty { Text("No usage in this range").foregroundStyle(.secondary) }
                ForEach(groups.prefix(8)) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(breakdown == .model ? AIPricing.displayName(group.key) : group.key).lineLimit(1)
                            Spacer()
                            Text(TokenFormat.compact(group.totals.total)).monospacedDigit().foregroundStyle(.secondary)
                            Text(TokenFormat.cost(group.cost)).monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                        .font(.callout)
                        GeometryReader { proxy in
                            Capsule().fill(accent.opacity(0.8))
                                .frame(width: max(proxy.size.width * Double(group.totals.total) / Double(max(top, 1)), 3))
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }
}

struct TopSessionsCard: View {
    let entries: [UsageEntry]
    let titles: [String: String]
    @State private var names = SessionNames.all()
    @State private var renaming: UsageGroup?
    @State private var draft = ""

    var body: some View {
        let sessions = AIUsageSummary.group(entries, by: \.session) { "\($0.provider.rawValue) · \($0.project) · \(AIPricing.displayName($0.model))" }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Sessions", subtitle: "Biggest first · rename any session to recognise it later")
                ForEach(sessions.prefix(12)) { session in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(names[session.key] ?? titles[session.key] ?? session.detail.components(separatedBy: " · ").dropFirst().first ?? "Session")
                                .fontWeight(.medium).lineLimit(1)
                            Text("\(session.detail) · \(session.first.formatted(date: .abbreviated, time: .shortened)) · \(durationText(session.last.timeIntervalSince(session.first))) · \(session.totals.requests) requests · \(Int((session.totals.cacheHitRate * 100).rounded()))% cached")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(TokenFormat.compact(session.totals.total)).monospacedDigit().foregroundStyle(.secondary)
                        Text(TokenFormat.cost(session.cost)).monospacedDigit().fontWeight(.semibold).frame(width: 70, alignment: .trailing)
                        Button {
                            draft = names[session.key] ?? titles[session.key] ?? ""
                            renaming = session
                        } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Rename session").accessibilityLabel("Rename session")
                    }
                    .padding(.vertical, 3)
                    .contextMenu { Button("Copy Session ID") { FileActions.copy(session.key) } }
                }
            }
        }
        .alert("Rename session", isPresented: isPresented($renaming), presenting: renaming) { session in
            TextField("Name", text: $draft)
            Button("Save") {
                SessionNames.set(draft, for: session.key)
                names = SessionNames.all()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("Only stored in MacSweep. Leave empty to use Claude's title.") }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(minutes, 1))m"
    }
}

import MacSweepCore
import SwiftUI

struct AIUsageView: View {
    @Environment(AppModel.self) private var app
    @State private var provider: AIProvider?
    @State private var days = 7
    @State private var tab: AITab = .overview

    /// Sub-pages so each view fits without long scrolling; the filter above applies to all of them.
    enum AITab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case activity = "Activity"
        case sessions = "Sessions"
        case storage = "Storage"
        var id: String { rawValue }
    }

    var body: some View {
        let model = app.ai
        let all = model.index.entries
        let entries = AIUsageSummary.filter(all, provider: provider, days: days)
        let totals = AIUsageSummary.totals(entries)
        let cost = AIUsageSummary.cost(of: entries)
        let trendEntries = AIUsageSummary.filter(all, provider: provider, days: max(days, 7))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.index.files.isEmpty {
                    ModuleIntro(title: "AI Usage", subtitle: "See exactly how many tokens Claude Code and Codex burn, what it would cost on the API, and your live limits.",
                                symbol: "flame.fill", tint: .orange,
                                bullets: [("chart.bar.xaxis", "Every session, model and project", "Read from the transcripts on your Mac; only the usage numbers, never your conversations."),
                                          ("gauge.with.needle", "Live limits", "Claude 5-hour blocks with burn rate, and Codex's 5-hour and weekly limits.")],
                                actionTitle: model.isRefreshing ? "Reading transcripts…" : "Analyse Usage", isWorking: model.isRefreshing) {
                        Task { await model.refresh() }
                    }
                    .frame(minHeight: 520)
                } else {
                    Picker("Section", selection: $tab) { ForEach(AITab.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                    ServiceStatusBadges(model: model, providers: provider.map { [$0] } ?? AIProvider.allCases)
                    controls(model)
                    switch tab {
                    case .overview:
                        EqualHeightGrid(items: Hero.allCases, columns: 2) { hero in
                            switch hero {
                            case .cost: AICostCard(entries: entries, trendEntries: trendEntries, days: days)
                            case .limits: AILimitsCard(block: model.claudeBlock, codex: model.codexLimits,
                                                       providers: provider.map { [$0] } ?? AIProvider.allCases, plan: model.planUsage)
                            }
                        }
                        StatStrip {
                            StatTile(title: "Tokens", value: TokenFormat.compact(totals.total), detail: "\(totals.requests) requests")
                            StatTile(title: "API value", value: TokenFormat.cost(cost.known), detail: cost.hasUnknown ? "some models unpriced" : "at list prices")
                            StatTile(title: "Output", value: TokenFormat.compact(totals.output), detail: "tokens generated")
                            StatTile(title: "Cache hits", value: "\(Int((totals.cacheHitRate * 100).rounded()))%", detail: "of prompt tokens")
                            StatTile(title: "Sessions", value: "\(Set(entries.map(\.session)).count)", detail: "\(Set(entries.map(\.project)).count) projects")
                        }
                    case .activity:
                        DailyUsageChart(entries: trendEntries, days: days)
                        EqualHeightGrid(items: Breakdown.allCases, columns: 2) { BreakdownCard(breakdown: $0, entries: entries) }
                    case .sessions:
                        TopSessionsCard(entries: entries, titles: model.index.sessionTitles)
                    case .storage:
                        TranscriptStorageCard()
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("AI Usage")
        .navigationSubtitle(model.lastRefreshed.map { "Updated \(Format.relative($0))" } ?? "Claude Code · Codex")
        .overlay(alignment: .bottom) {
            if model.isRefreshing, let progress = model.progress {
                Label("Reading transcripts \(progress.filesDone) of \(progress.filesTotal)…", systemImage: "doc.text.magnifyingglass")
                    .padding(10).background(.regularMaterial, in: Capsule()).padding()
            }
        }
    }

    /// One filter for the whole page: every card below follows the tool and range chosen here.
    private func controls(_ model: AIUsageModel) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Tool", selection: $provider) {
                Text("All tools").tag(AIProvider?.none)
                ForEach(AIProvider.allCases) { Text($0.rawValue).tag(AIProvider?.some($0)) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Range", selection: $days) {
                Text("Today").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Label(model.isRefreshing ? "Updating…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }

    enum Hero: String, CaseIterable, Identifiable {
        case cost, limits
        var id: String { rawValue }
    }
}

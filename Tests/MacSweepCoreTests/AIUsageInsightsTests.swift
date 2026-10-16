import Foundation
import Testing
@testable import MacSweepCore

@Suite struct AIUsageInsightsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    func entry(_ model: String, tokens: Int, daysAgo: Int = 0, provider: AIProvider = .claudeCode) -> UsageEntry {
        var totals = TokenTotals()
        totals.input = tokens
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return UsageEntry(provider: provider, day: UsageTime.dayKey(date, calendar: calendar), model: model,
                          project: "p", session: "s", totals: totals, first: date, last: date)
    }

    @Test func groupsByModelLargestCostFirst() {
        let shares = AIUsageInsights.byModel([entry("claude-sonnet-5-5", tokens: 1_000_000), entry("claude-opus-5-5", tokens: 1_000_000),
                                              entry("claude-opus-5-5-20261001", tokens: 1_000_000)])
        #expect(shares.map(\.name) == ["Opus 5.5", "Sonnet 5.5"])
        #expect(shares[0].tokens == 2_000_000)
        #expect((shares[0].cost ?? 0) > (shares[1].cost ?? 0))
    }

    @Test func unpricedModelsKeepNilCost() {
        let shares = AIUsageInsights.byModel([entry("gpt-4o", tokens: 500, provider: .codex)])
        #expect(shares.count == 1 && shares[0].cost == nil && shares[0].tokens == 500)
    }

    @Test func foldsLongTailIntoOther() {
        let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5", "claude-sonnet-5", "gpt-6.1-sol"]
        let shares = AIUsageInsights.byModel(models.map { entry($0, tokens: 1_000) }, limit: 3)
        #expect(shares.count == 4)
        #expect(shares.last?.name == "Other" && shares.last?.tokens == 3_000)
    }

    @Test func emptyAndZeroInputs() {
        #expect(AIUsageInsights.byModel([]).isEmpty)
        #expect(AIUsageInsights.byModel([entry("claude-opus-5-5", tokens: 0)]).isEmpty)
        #expect(AIUsageInsights.byModel([entry("claude-opus-5-5", tokens: 1), entry("claude-sonnet-5-5", tokens: 1)], limit: 0).count == 2)
        let spend = AIUsageInsights.spend([], days: 7, now: now, calendar: calendar)
        #expect(spend.total == 0 && spend.activeDays == 0 && spend.averagePerActiveDay == 0)
        #expect(spend.peakDay == nil && spend.costPerMillion == nil)
    }

    @Test func spendAveragesOverActiveDaysAndFindsPeak() {
        let entries = [entry("claude-opus-5-5", tokens: 1_000_000), entry("claude-opus-5-5", tokens: 3_000_000, daysAgo: 2),
                       entry("claude-opus-5-5", tokens: 9_000_000, daysAgo: 20)]
        let spend = AIUsageInsights.spend(entries, days: 7, now: now, calendar: calendar)
        #expect(spend.activeDays == 2)
        #expect(abs(spend.total - 16) < 0.0001)
        #expect(abs(spend.averagePerActiveDay - 8) < 0.0001)
        #expect(abs(spend.peakCost - 12) < 0.0001)
        #expect(spend.peakDay.map { calendar.isDate($0, inSameDayAs: calendar.date(byAdding: .day, value: -2, to: now) ?? now) } == true)
        #expect(spend.costPerMillion.map { abs($0 - 4) < 0.0001 } == true)
    }

    @Test func codexOnlyHasNoCostPerMillion() {
        let spend = AIUsageInsights.spend([entry("gpt-4o", tokens: 1_000, provider: .codex)], days: 1, now: now, calendar: calendar)
        #expect(spend.activeDays == 1 && spend.total == 0 && spend.costPerMillion == nil && spend.peakDay == nil)
    }
}

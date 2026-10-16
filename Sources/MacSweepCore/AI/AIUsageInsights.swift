import Foundation

/// One slice of the cost breakdown: a model, or "Other" for the long tail.
public struct ModelShare: Identifiable, Sendable, Equatable {
    public let name: String
    public let tokens: Int
    /// API-list-price value; nil when no model in the slice is priced (e.g. Codex).
    public let cost: Double?

    public var id: String { name }
}

public struct SpendInsights: Sendable, Equatable {
    public let total: Double
    public let activeDays: Int
    public let averagePerActiveDay: Double
    public let peakDay: Date?
    public let peakCost: Double
    /// Cost per million tokens across priced usage, nil when nothing is priced.
    public let costPerMillion: Double?
}

public enum AIUsageInsights {
    /// Tokens and cost per model, largest first, with everything past `limit` folded into "Other".
    public static func byModel(_ entries: [UsageEntry], limit: Int = 4) -> [ModelShare] {
        var tokens: [String: Int] = [:]
        var costs: [String: Double] = [:]
        for entry in entries where entry.totals.total > 0 {
            let name = AIPricing.displayName(entry.model)
            tokens[name, default: 0] += entry.totals.total
            if let cost = AIPricing.cost(entry.totals, model: entry.model) { costs[name, default: 0] += cost }
        }
        let shares = tokens.map { ModelShare(name: $0.key, tokens: $0.value, cost: costs[$0.key]) }
            .sorted { ($0.cost ?? 0, $0.tokens) > ($1.cost ?? 0, $1.tokens) }
        guard limit > 0, shares.count > limit else { return shares }
        let tail = shares[limit...]
        let tailCost = tail.compactMap(\.cost)
        let other = ModelShare(name: "Other", tokens: tail.reduce(0) { $0 + $1.tokens },
                               cost: tailCost.isEmpty ? nil : tailCost.reduce(0, +))
        return Array(shares[..<limit]) + [other]
    }

    public static func spend(_ entries: [UsageEntry], days: Int, now: Date = Date(), calendar: Calendar = .current) -> SpendInsights {
        let daily = AIUsageSummary.daily(entries, days: days, now: now, calendar: calendar)
        let active = daily.filter { $0.tokens > 0 }
        let total = daily.reduce(0) { $0 + $1.cost }
        let peak = daily.max { $0.cost < $1.cost }
        let inRange = AIUsageSummary.filter(entries, provider: nil, days: days, now: now, calendar: calendar)
        let pricedTokens = inRange.filter { AIPricing.cost($0.totals, model: $0.model) != nil }.reduce(0) { $0 + $1.totals.total }
        return SpendInsights(total: total, activeDays: active.count,
                             averagePerActiveDay: active.isEmpty ? 0 : total / Double(active.count),
                             peakDay: (peak?.cost ?? 0) > 0 ? peak?.day : nil, peakCost: peak?.cost ?? 0,
                             costPerMillion: pricedTokens > 0 ? total / Double(pricedTokens) * 1_000_000 : nil)
    }
}

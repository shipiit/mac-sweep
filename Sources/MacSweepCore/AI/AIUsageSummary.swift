import Foundation

public struct UsageGroup: Identifiable, Sendable, Equatable {
    public let key: String
    public var totals: TokenTotals
    public var cost: Double?
    public var first: Date
    public var last: Date
    public var detail: String

    public var id: String { key }
}

public struct UsageBlock: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let totals: TokenTotals
    public let cost: Double?
    /// Non-cached tokens per hour over the last hour of activity.
    public let burnPerHour: Double
    public let isActive: Bool
}

/// Aggregations for the AI Usage tab. Costs are API-list-price estimates for Claude models and nil
/// where a price isn't known (Codex, unknown models) rather than a guess.
public enum AIUsageSummary {
    public static func filter(_ entries: [UsageEntry], provider: AIProvider?, days: Int, now: Date = Date(),
                              calendar: Calendar = .current) -> [UsageEntry] {
        guard let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: calendar.startOfDay(for: now)) else { return [] }
        let startKey = UsageTime.dayKey(start, calendar: calendar)
        return entries.filter { ($0.day >= startKey) && (provider == nil || $0.provider == provider) }
    }

    public static func cost(of entries: [UsageEntry]) -> (known: Double, hasUnknown: Bool) {
        var known = 0.0
        var unknown = false
        for entry in entries {
            if let cost = AIPricing.cost(entry.totals, model: entry.model) { known += cost } else if entry.totals.total > 0 { unknown = true }
        }
        return (known, unknown)
    }

    public static func totals(_ entries: [UsageEntry]) -> TokenTotals {
        entries.reduce(TokenTotals()) { $0 + $1.totals }
    }

    public static func group(_ entries: [UsageEntry], by key: (UsageEntry) -> String, detail: (UsageEntry) -> String = { _ in "" }) -> [UsageGroup] {
        var groups: [String: UsageGroup] = [:]
        for entry in entries {
            let name = key(entry)
            let entryCost = AIPricing.cost(entry.totals, model: entry.model)
            if var group = groups[name] {
                group.totals = group.totals + entry.totals
                group.cost = entryCost.map { ($0) + (group.cost ?? 0) } ?? group.cost
                group.first = min(group.first, entry.first)
                group.last = max(group.last, entry.last)
                groups[name] = group
            } else {
                groups[name] = UsageGroup(key: name, totals: entry.totals, cost: entryCost, first: entry.first, last: entry.last, detail: detail(entry))
            }
        }
        return groups.values.sorted { $0.totals.total > $1.totals.total }
    }

    /// Daily totals for the last `days` days (oldest first), including empty days.
    public static func daily(_ entries: [UsageEntry], days: Int, now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, tokens: Int, cost: Double)] {
        let byDay = Dictionary(grouping: entries, by: \.day)
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { return nil }
            let items = byDay[UsageTime.dayKey(date, calendar: calendar)] ?? []
            return (date, items.reduce(0) { $0 + $1.totals.total }, cost(of: items).known)
        }
    }

    /// Claude-style 5-hour blocks: a block starts at the hour of the first request after a 5-hour gap
    /// and lasts 5 hours. Returns the block containing `now` (or the latest one).
    public static func currentBlock(_ events: [UsageEvent], provider: AIProvider = .claudeCode, now: Date = Date(),
                                    calendar: Calendar = .current) -> UsageBlock? {
        let sorted = events.filter { $0.provider == provider }.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return nil }
        var blockStart: Date?
        var blockEvents: [UsageEvent] = []
        for event in sorted {
            if let start = blockStart, event.time < start.addingTimeInterval(5 * 3_600) {
                blockEvents.append(event)
            } else {
                blockStart = calendar.dateInterval(of: .hour, for: event.time)?.start ?? event.time
                blockEvents = [event]
            }
        }
        guard let start = blockStart else { return nil }
        let end = start.addingTimeInterval(5 * 3_600)
        let totals = blockEvents.reduce(TokenTotals()) { $0 + $1.totals }
        var cost: Double? = 0
        for event in blockEvents {
            if let value = AIPricing.cost(event.totals, model: event.model) { cost = (cost ?? 0) + value } else { cost = nil; break }
        }
        let lastHour = blockEvents.filter { $0.time >= now.addingTimeInterval(-3_600) }
        let burn = Double(lastHour.reduce(0) { $0 + $1.totals.input + $1.totals.output + $1.totals.cacheWrite })
        return UsageBlock(start: start, end: end, totals: totals, cost: cost, burnPerHour: burn, isActive: now < end)
    }
}

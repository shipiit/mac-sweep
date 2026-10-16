import Foundation

public struct AppUsageDay: Codable, Sendable, Equatable {
    /// bundle ID → seconds in the foreground
    public var seconds: [String: Double] = [:]
    /// bundle ID → number of times it became the active app
    public var activations: [String: Int] = [:]
    public var names: [String: String] = [:]
    /// Hour of day (0-23) → foreground seconds across all apps.
    public var hours: [Int: Double] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey { case seconds, activations, names, hours }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent([String: Double].self, forKey: .seconds) ?? [:]
        activations = try c.decodeIfPresent([String: Int].self, forKey: .activations) ?? [:]
        names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        hours = try c.decodeIfPresent([Int: Double].self, forKey: .hours) ?? [:]
    }
}

public struct AppUsageSummary: Identifiable, Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public let seconds: Double
    public let activations: Int

    public var id: String { bundleID }
}

/// Foreground time per app, recorded only on this Mac and only while MacSweep runs.
/// Days are keyed `yyyy-MM-dd` in the local calendar; history older than `retentionDays` is dropped.
public struct UsageLog: Codable, Sendable, Equatable {
    public static let retentionDays = 30
    public var days: [String: AppUsageDay] = [:]
    /// Last time each app was in front, kept across launches so idle detection survives restarts.
    public var lastActive: [String: Date] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey { case days, lastActive }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([String: AppUsageDay].self, forKey: .days) ?? [:]
        lastActive = try container.decodeIfPresent([String: Date].self, forKey: .lastActive) ?? [:]
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Credits `bundleID` with the time between `start` and `end`, splitting across midnight.
    public mutating func record(bundleID: String, name: String, from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            // Slice at each hour boundary so both the day totals and the hourly timeline stay exact.
            let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? end
            let sliceEnd = min(end, nextHour)
            let key = Self.dayKey(cursor, calendar: calendar)
            let slice = sliceEnd.timeIntervalSince(cursor)
            days[key, default: AppUsageDay()].seconds[bundleID, default: 0] += slice
            days[key, default: AppUsageDay()].hours[calendar.component(.hour, from: cursor), default: 0] += slice
            days[key, default: AppUsageDay()].names[bundleID] = name
            cursor = sliceEnd
        }
    }

    public mutating func recordActivation(bundleID: String, name: String, at date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar)
        days[key, default: AppUsageDay()].activations[bundleID, default: 0] += 1
        days[key, default: AppUsageDay()].names[bundleID] = name
    }

    public mutating func prune(now: Date = Date(), calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        days = days.filter { $0.key >= cutoffKey }
        lastActive = lastActive.filter { $0.value >= cutoff }
    }

    /// Totals over the last `dayCount` days including today, most used first.
    public func summary(days dayCount: Int, now: Date = Date(), calendar: Calendar = .current) -> [AppUsageSummary] {
        var seconds: [String: Double] = [:]
        var activations: [String: Int] = [:]
        var names: [String: String] = [:]
        for offset in 0..<max(dayCount, 1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now), let day = days[Self.dayKey(date, calendar: calendar)] else { continue }
            seconds.merge(day.seconds, uniquingKeysWith: +)
            activations.merge(day.activations, uniquingKeysWith: +)
            names.merge(day.names) { current, _ in current }
        }
        return seconds.map { AppUsageSummary(bundleID: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value, activations: activations[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Average foreground seconds per hour of day (0-23) over the last `dayCount` days.
    public func hourly(days dayCount: Int, now: Date = Date(), calendar: Calendar = .current) -> [Double] {
        var totals = Array(repeating: 0.0, count: 24)
        for offset in 0..<max(dayCount, 1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now),
                  let day = days[Self.dayKey(date, calendar: calendar)] else { continue }
            for (hour, seconds) in day.hours where (0..<24).contains(hour) { totals[hour] += seconds }
        }
        return totals.map { $0 / Double(max(dayCount, 1)) }
    }

    /// Total foreground seconds per day for the last `dayCount` days, oldest first.
    public func dailyTotals(days dayCount: Int, now: Date = Date(), calendar: Calendar = .current) -> [(date: Date, seconds: Double)] {
        (0..<max(dayCount, 1)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let total = days[Self.dayKey(date, calendar: calendar)]?.seconds.values.reduce(0, +) ?? 0
            return (calendar.startOfDay(for: date), total)
        }
    }
}

public struct UsageLogStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var standard: UsageLogStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return UsageLogStore(url: base.appendingPathComponent("MacSweep/app-usage.json"))
    }

    public func load() -> UsageLog {
        guard let data = try? Data(contentsOf: url), let log = try? JSONDecoder().decode(UsageLog.self, from: data) else { return UsageLog() }
        return log
    }

    public func save(_ log: UsageLog) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(log).write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

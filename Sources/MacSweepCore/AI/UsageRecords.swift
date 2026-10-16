import Foundation

public enum AIProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case codex = "Codex"

    public var id: String { rawValue }
}

/// Usage for one (day, model, project, session) combination within one transcript file.
public struct UsageEntry: Codable, Sendable, Equatable {
    public var provider: AIProvider
    public var day: String
    public var model: String
    public var project: String
    public var session: String
    public var totals: TokenTotals
    public var first: Date
    public var last: Date
}

/// A single timestamped request, kept only for the recent past (burn rate and 5-hour blocks).
public struct UsageEvent: Codable, Sendable, Equatable {
    public var provider: AIProvider
    public var time: Date
    public var model: String
    public var totals: TokenTotals
}

public struct RateLimitWindow: Codable, Sendable, Equatable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    /// True once the reset time has passed: the last reading is stale and the window is fresh again.
    public func hasReset(now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }

    /// Fraction used (0...1), treating a window that has already reset as unused.
    public func usedFraction(now: Date = Date()) -> Double {
        hasReset(now: now) ? 0 : min(max(usedPercent / 100, 0), 1)
    }
}

public struct CodexRateLimits: Codable, Sendable, Equatable {
    public var observedAt: Date
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
}

public struct FileUsage: Codable, Sendable, Equatable {
    public var size: UInt64
    public var modified: Date
    public var entries: [UsageEntry]
    public var events: [UsageEvent]
    public var rateLimits: CodexRateLimits?
    /// Session id → title (Claude Code `/rename` title, else its auto-generated title). Nil = parsed before titles existed.
    public var titles: [String: String]?
    /// Parser revision that produced this record; older records are re-read when the parser learns new fields.
    public var parserVersion: Int?

    public static let currentParserVersion = 2
}

enum UsageTime {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Accumulates entries keyed by (day, model, project, session).
struct EntryAccumulator {
    private var entries: [String: UsageEntry] = [:]
    var events: [UsageEvent] = []
    let recentCutoff: Date

    init(recentCutoff: Date) {
        self.recentCutoff = recentCutoff
    }

    mutating func add(provider: AIProvider, time: Date, model: String, project: String, session: String,
                      totals: TokenTotals, calendar: Calendar) {
        let day = UsageTime.dayKey(time, calendar: calendar)
        let key = [day, model, project, session].joined(separator: "|")
        if var entry = entries[key] {
            entry.totals = entry.totals + totals
            entry.first = min(entry.first, time)
            entry.last = max(entry.last, time)
            entries[key] = entry
        } else {
            entries[key] = UsageEntry(provider: provider, day: day, model: model, project: project, session: session,
                                      totals: totals, first: time, last: time)
        }
        if time >= recentCutoff { events.append(UsageEvent(provider: provider, time: time, model: model, totals: totals)) }
    }

    var all: [UsageEntry] { entries.values.sorted { $0.first < $1.first } }
}

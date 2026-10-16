import Foundation

public enum TimelineRange: Int, CaseIterable, Sendable, Identifiable {
    case day = 1
    case week = 7
    case fortnight = 14

    public var id: Int { rawValue }
    public var title: String { self == .day ? "24h" : "\(rawValue)d" }
    public var duration: TimeInterval { TimeInterval(rawValue) * 86_400 }

    /// Bucket width keeping every range around 300 points.
    public var bucket: TimeInterval {
        switch self {
        case .day: 300
        case .week: 1_800
        case .fortnight: 3_600
        }
    }
}

/// A downsampled chart point. `segment` changes across gaps so charts don't draw through sleep.
public struct TimelinePoint: Identifiable, Sendable, Equatable {
    public let time: Date
    public let cpu: Double
    public let cpuPeak: Double
    public let memoryUsed: UInt64
    public let diskFree: UInt64
    public let downloadRate: Double
    public let uploadRate: Double
    public let topProcess: String
    public let topProcessCPU: Double
    public let segment: Int

    public var id: Date { time }
}

public struct DailyCost: Identifiable, Sendable, Equatable {
    public let day: Date
    public let cost: Double
    public var id: Date { day }
}

public enum TimelineAggregator {
    /// Samples inside `range` ending at `now`, averaged into fixed buckets (peaks keep their maximum).
    public static func points(_ samples: [TimelineSample], range: TimelineRange, now: Date) -> [TimelinePoint] {
        let start = now.addingTimeInterval(-range.duration)
        let width = range.bucket
        var groups: [(key: Double, members: [TimelineSample])] = []
        for sample in samples where sample.time > start && sample.time <= now {
            let key = (sample.time.timeIntervalSince1970 / width).rounded(.down) * width
            if let last = groups.last, last.key == key {
                groups[groups.count - 1].members.append(sample)
            } else {
                groups.append((key, [sample]))
            }
        }
        var segment = 0
        var previousKey: Double?
        return groups.compactMap { group in
            guard let peak = group.members.max(by: { $0.cpuPeak < $1.cpuPeak }),
                  let last = group.members.last else { return nil }
            if let previousKey, group.key - previousKey > 2 * width { segment += 1 }
            previousKey = group.key
            let count = Double(group.members.count)
            func mean(_ value: (TimelineSample) -> Double) -> Double { group.members.reduce(0) { $0 + value($1) } / count }
            return TimelinePoint(
                time: Date(timeIntervalSince1970: group.key),
                cpu: mean(\.cpu),
                cpuPeak: peak.cpuPeak,
                memoryUsed: UInt64(mean { Double($0.memoryUsed) }),
                diskFree: last.diskFree,
                downloadRate: mean(\.downloadRate),
                uploadRate: mean(\.uploadRate),
                topProcess: peak.topProcess,
                topProcessCPU: peak.topProcessCPU,
                segment: segment
            )
        }
    }

    /// Up to `limit` local CPU peaks that stand out: above `minimum` and two standard deviations
    /// over the mean. Returned in time order.
    public static func spikes(_ points: [TimelinePoint], limit: Int = 5, minimum: Double = 0.5) -> [TimelinePoint] {
        guard points.count >= 3, limit > 0 else { return [] }
        let values = points.map(\.cpuPeak)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let threshold = max(minimum, mean + 2 * variance.squareRoot())
        let candidates = points.indices.filter { index in
            let value = values[index]
            guard value >= threshold, value - mean > 1e-6 else { return false }
            let left = index > 0 ? values[index - 1] : -1
            let right = index < values.count - 1 ? values[index + 1] : -1
            return value >= left && value > right
        }
        return candidates.map { points[$0] }
            .sorted { $0.cpuPeak > $1.cpuPeak }
            .prefix(limit)
            .sorted { $0.time < $1.time }
    }

    /// AI spend per day: samples carry the running total for their day, so the day's maximum is its total.
    public static func dailyCosts(_ samples: [TimelineSample], calendar: Calendar = .current) -> [DailyCost] {
        var totals: [Date: Double] = [:]
        for sample in samples {
            guard let cost = sample.aiCost, cost.isFinite else { continue }
            let day = calendar.startOfDay(for: sample.time)
            totals[day] = max(totals[day] ?? 0, cost)
        }
        return totals.map { DailyCost(day: $0.key, cost: $0.value) }.sorted { $0.day < $1.day }
    }
}

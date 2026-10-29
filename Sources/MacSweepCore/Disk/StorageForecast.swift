import Foundation

/// "At this rate the disk is full in about N weeks", from free-space samples (a least-squares line).
public enum StorageForecast {
    public struct Result: Sendable, Equatable {
        /// Bytes of free space lost per day (positive means the disk is filling up).
        public let bytesPerDay: Double
        /// Days until free space reaches zero; nil when free space isn't shrinking.
        public let daysUntilFull: Double?
    }

    /// Needs at least two days of data and 4 samples; noise under 50 MB a day counts as flat.
    public static func forecast(_ samples: [(date: Date, free: UInt64)], now: Date = Date()) -> Result? {
        guard samples.count >= 4, let first = samples.map(\.date).min(), let last = samples.map(\.date).max(),
              last.timeIntervalSince(first) >= 2 * 86_400 else { return nil }
        let xs = samples.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = samples.map { Double($0.free) }
        let count = Double(samples.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard variance > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / variance
        let lossPerDay = -slope
        guard lossPerDay > 50_000_000, let latest = samples.max(by: { $0.date < $1.date }) else {
            return Result(bytesPerDay: lossPerDay, daysUntilFull: nil)
        }
        return Result(bytesPerDay: lossPerDay, daysUntilFull: Double(latest.free) / lossPerDay)
    }

    /// "in about 3 days", "in about 6 weeks", "in about 4 months".
    public static func phrase(days: Double) -> String {
        switch days {
        case ..<2: "within a couple of days"
        case ..<14: "in about \(Int(days.rounded())) days"
        case ..<70: "in about \(Int((days / 7).rounded())) weeks"
        default: "in about \(Int((days / 30).rounded())) months"
        }
    }
}

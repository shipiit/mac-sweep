import Foundation

public struct MemorySample: Sendable, Equatable {
    public let time: TimeInterval
    public let bytes: UInt64

    public init(time: TimeInterval, bytes: UInt64) {
        self.time = time
        self.bytes = bytes
    }
}

public struct MemoryTrendSummary: Sendable, Equatable {
    public let bytesPerMinute: Double
    public let growth: Int64
    public let isSteadilyGrowing: Bool

    public static let flat = MemoryTrendSummary(bytesPerMinute: 0, growth: 0, isSteadilyGrowing: false)
}

/// Flags processes whose memory climbs consistently while MacSweep watches. This is a hint
/// worth investigating, not proof of a leak (caches also grow).
public enum MemoryTrend {
    public static let minimumSamples = 10
    public static let minimumGrowth: Int64 = 50 << 20
    public static let minimumRisingFraction = 0.7

    public static func summarize(_ samples: [MemorySample]) -> MemoryTrendSummary {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return .flat }
        let slope = slopePerSecond(samples)
        let growth = Int64(bitPattern: last.bytes) - Int64(bitPattern: first.bytes)

        var rising = 0
        for (previous, current) in zip(samples, samples.dropFirst()) where current.bytes >= previous.bytes {
            rising += 1
        }
        let risingFraction = Double(rising) / Double(samples.count - 1)
        let growing = samples.count >= minimumSamples
            && slope > 0
            && growth >= minimumGrowth
            && risingFraction >= minimumRisingFraction
        return MemoryTrendSummary(bytesPerMinute: slope * 60, growth: growth, isSteadilyGrowing: growing)
    }

    /// Least-squares slope in bytes per second.
    static func slopePerSecond(_ samples: [MemorySample]) -> Double {
        let n = Double(samples.count)
        guard n >= 2 else { return 0 }
        let meanT = samples.reduce(0) { $0 + $1.time } / n
        let meanB = samples.reduce(0) { $0 + Double($1.bytes) } / n
        var numerator = 0.0
        var denominator = 0.0
        for sample in samples {
            let dt = sample.time - meanT
            numerator += dt * (Double(sample.bytes) - meanB)
            denominator += dt * dt
        }
        return denominator > 0 ? numerator / denominator : 0
    }
}

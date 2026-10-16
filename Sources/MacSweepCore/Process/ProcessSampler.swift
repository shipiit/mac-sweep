import Foundation

public enum ProcessSampler {
    public static func sample() -> [ProcessSnapshot] {
        var userNames: [UInt32: String] = [:]
        return ProcReader.allPIDs().compactMap { ProcReader.snapshot(pid: $0, userNames: &userNames) }
    }

    /// CPU percent of one core between two samples (can exceed 100 on multi-core).
    public static func cpuPercent(previous: UInt64?, current: UInt64?, elapsed: TimeInterval) -> Double? {
        guard let previous, let current, current >= previous, elapsed > 0 else { return nil }
        return Double(current - previous) / (elapsed * 1_000_000_000) * 100
    }
}

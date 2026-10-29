import Foundation

/// Weekly automatic cleanup of safe junk only.
public enum AutoClean {
    public static let interval: TimeInterval = 7 * 86_400

    /// Due when it has never run or the last run was a week or more ago.
    public static func isDue(lastRun: Date?, now: Date = Date()) -> Bool {
        lastRun.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    /// Only items from safe rules, minus anything in use; review-first items are never cleaned automatically.
    public static func targets(_ items: [CleanupItem], inUse: Set<String>) -> [CleanupTarget] {
        OptimizePlan.junkTargets(items.filter { $0.rule.safety == .safe }.flatMap(\.targets), inUse: inUse)
    }
}

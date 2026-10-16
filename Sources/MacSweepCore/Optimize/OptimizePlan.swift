import Foundation

/// The clean-up steps Smart Scan can run, in the order they execute.
public enum OptimizeStep: String, CaseIterable, Sendable, Identifiable {
    case systemJunk, trashBins, maintenance, flushDNSAndRAM

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .systemJunk: "System Junk"
        case .trashBins: "Trash Bins"
        case .maintenance: "Run Maintenance Scripts"
        case .flushDNSAndRAM: "Flush DNS Cache & Free Up RAM"
        }
    }

    public var requiresAdmin: Bool { self == .flushDNSAndRAM }
    /// Trash emptying can't be undone; junk goes to the Trash first, so it can.
    public var isPermanent: Bool { self == .trashBins }
}

public enum OptimizeStepState: Sendable, Equatable {
    case pending
    case running
    case done(freed: UInt64, note: String?)
    case warning(String)
    case skipped(String)

    public var isFinished: Bool {
        switch self {
        case .pending, .running: false
        case .done, .warning, .skipped: true
        }
    }
}

public enum OptimizePlan {
    /// Enabled steps in execution order. Junk runs before Trash so the junk just moved there is emptied too.
    public static func steps(enabled: Set<OptimizeStep>) -> [OptimizeStep] {
        OptimizeStep.allCases.filter(enabled.contains)
    }

    /// Fraction 0...1 for the progress ring; a running step counts as half done.
    public static func progress(_ states: [OptimizeStep: OptimizeStepState], steps: [OptimizeStep]) -> Double {
        guard !steps.isEmpty else { return 0 }
        let units = steps.reduce(0.0) { sum, step in
            switch states[step] ?? .pending {
            case .pending: sum
            case .running: sum + 0.5
            default: sum + 1
            }
        }
        return min(units / Double(steps.count), 1)
    }

    public static func freed(_ states: [OptimizeStep: OptimizeStepState]) -> UInt64 {
        states.values.reduce(0) { sum, state in
            if case .done(let freed, _) = state { return sum + freed }
            return sum
        }
    }

    /// Paths to clean: safe targets minus anything an app or process is using right now.
    public static func junkTargets(_ targets: [CleanupTarget], inUse: Set<String>) -> [CleanupTarget] {
        targets.filter { target in !inUse.contains { target.path == $0 || target.path.hasPrefix($0 + "/") } }
    }
}

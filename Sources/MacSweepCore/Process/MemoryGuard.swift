import Foundation

public enum MemoryGuardMode: String, CaseIterable, Sendable, Identifiable {
    case off = "Off"
    case notify = "Notify me"
    case quitIdle = "Quit idle apps"

    public var id: String { rawValue }
}

public struct MemoryGuardPlan: Sendable, Equatable {
    /// Apps to quit politely (like ⌘Q), biggest first.
    public let quit: [IdleApp]
    /// Apps to mention in the notification.
    public let suggest: [IdleApp]
    public var freesAtLeast: UInt64 { quit.reduce(0) { $0 + $1.memory } }
}

/// Decides what to do when memory runs low. It never acts on a brief spike, never touches the frontmost app
/// or system processes (IdleApps already excludes those), and quits at most three apps.
public enum MemoryGuard {
    /// Pressure has to stay up this long before anything happens.
    public static let sustainedThreshold: TimeInterval = 60

    /// Memory to win back: more when pressure is critical.
    public static func target(for pressure: MemoryPressure) -> UInt64 {
        pressure == .critical ? 4 << 30 : 2 << 30
    }

    public static func plan(pressure: MemoryPressure, sustainedFor: TimeInterval, idle: [IdleApp], mode: MemoryGuardMode) -> MemoryGuardPlan? {
        guard mode != .off, pressure != .normal, sustainedFor >= sustainedThreshold, !idle.isEmpty else { return nil }
        let ranked = idle.sorted { $0.memory > $1.memory }
        guard mode == .quitIdle else { return MemoryGuardPlan(quit: [], suggest: Array(ranked.prefix(3))) }
        var quit: [IdleApp] = []
        var freed: UInt64 = 0
        for app in ranked where quit.count < 3 && freed < target(for: pressure) {
            quit.append(app)
            freed += app.memory
        }
        let quitIDs = Set(quit.map(\.id))
        return MemoryGuardPlan(quit: quit, suggest: Array(ranked.filter { !quitIDs.contains($0.id) }.prefix(3)))
    }
}

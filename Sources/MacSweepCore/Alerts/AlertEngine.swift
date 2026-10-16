import Foundation

/// What the engine remembers between evaluations (and launches) so each condition fires once.
public struct AlertEngineState: Codable, Sendable, Equatable {
    struct Streak: Codable, Sendable, Equatable {
        var since: Date
        var lastSeen: Date
        var name: String
    }

    /// Conditions that have fired and not yet cleared.
    var active: Set<String> = []
    var lastFired: [String: Date] = [:]
    var cpuStreaks: [String: Streak] = [:]
    var batteryBaseline: Double?
    /// Nil until the first startup-item scan, which only records a baseline.
    var startupBaseline: [String: StartupFingerprint]?

    public init() {}
}

/// Pure rules engine: feed it snapshots, it returns the alerts that should be shown now.
public struct AlertEngine: Sendable {
    public var config: AlertConfig
    public internal(set) var state: AlertEngineState

    /// Fired-at times older than this are forgotten so the state stays small.
    static let memory: TimeInterval = 3 * 86_400

    public init(config: AlertConfig = AlertConfig(), state: AlertEngineState = AlertEngineState()) {
        self.config = config
        self.state = state
    }

    public mutating func evaluate(_ snapshot: AlertSnapshot, enabled: Set<AlertRule> = Set(AlertRule.allCases)) -> [SmartAlert] {
        var fired: [SmartAlert] = []
        if let volume = snapshot.volume { fired += lowDisk(volume, at: snapshot.date, enabled: enabled) }
        if let processes = snapshot.processes {
            let sampledAt = snapshot.processesSampledAt ?? snapshot.date
            fired += memoryLeaks(processes, at: snapshot.date, enabled: enabled)
            fired += sustainedCPU(processes, sampledAt: sampledAt, at: snapshot.date, enabled: enabled)
        }
        if let thermal = snapshot.thermal { fired += self.thermal(thermal, at: snapshot.date, enabled: enabled) }
        if let health = snapshot.batteryHealth { fired += battery(health, at: snapshot.date, enabled: enabled) }
        if let items = snapshot.startupItems { fired += startup(items, at: snapshot.date, enabled: enabled) }
        if let trash = snapshot.trashBytes { fired += self.trash(trash, at: snapshot.date, enabled: enabled) }
        state.lastFired = state.lastFired.filter { snapshot.date.timeIntervalSince($0.value) < Self.memory }
        return fired
    }

    /// One-subject condition: fires when it becomes true, re-arms only when `rearm` is true.
    mutating func track(_ rule: AlertRule, key: String, isActive: Bool, rearm: Bool, at now: Date,
                        enabled: Set<AlertRule>, make: () -> SmartAlert) -> SmartAlert? {
        if isActive {
            return fire(rule, key: key, at: now, enabled: enabled, make: make)
        }
        if rearm { state.active.remove(key) }
        return nil
    }

    /// Many-subject condition (one key per process): fires for new keys, re-arms keys that cleared.
    mutating func trackAll(_ rule: AlertRule, prefix: String, activeKeys: [String: () -> SmartAlert],
                           at now: Date, enabled: Set<AlertRule>) -> [SmartAlert] {
        let cleared = state.active.filter { $0.hasPrefix(prefix) && activeKeys[$0] == nil }
        state.active.subtract(cleared)
        return activeKeys.keys.sorted().compactMap { key in
            activeKeys[key].flatMap { make in fire(rule, key: key, at: now, enabled: enabled, make: make) }
        }
    }

    private mutating func fire(_ rule: AlertRule, key: String, at now: Date, enabled: Set<AlertRule>,
                               make: () -> SmartAlert) -> SmartAlert? {
        guard enabled.contains(rule), !state.active.contains(key) else { return nil }
        if let last = state.lastFired[key], now.timeIntervalSince(last) < config.cooldown(rule) { return nil }
        state.active.insert(key)
        state.lastFired[key] = now
        return make()
    }

    /// Event rules (new startup item, battery drop) have no ongoing condition, only a cooldown.
    mutating func event(_ rule: AlertRule, key: String, at now: Date, make: () -> SmartAlert) -> SmartAlert? {
        if let last = state.lastFired[key], now.timeIntervalSince(last) < config.cooldown(rule) { return nil }
        state.lastFired[key] = now
        return make()
    }
}

enum AlertText {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func memory(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

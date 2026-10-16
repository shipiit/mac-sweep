import Foundation

/// One process as the alert rules see it.
public struct ProcessLoad: Sendable, Equatable {
    public let pid: Int32
    public let started: Date?
    public let name: String
    public let path: String?
    /// Percent of one core (can exceed 100 on multi-core).
    public let cpuPercent: Double
    public let memoryTrend: MemoryTrendSummary

    public init(pid: Int32, started: Date?, name: String, path: String?, cpuPercent: Double,
                memoryTrend: MemoryTrendSummary = .flat) {
        self.pid = pid
        self.started = started
        self.name = name
        self.path = path
        self.cpuPercent = cpuPercent
        self.memoryTrend = memoryTrend
    }

    /// Stable across samples and safe against PID reuse.
    var identity: String { "\(pid)@\(started?.timeIntervalSince1970 ?? 0)" }
}

/// Something that will run automatically: a launch agent/daemon plist or a login item.
public struct StartupFingerprint: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case loginItem
        case userAgent
        case globalAgent
        case daemon

        public var label: String {
            switch self {
            case .loginItem: "login item"
            case .userAgent: "launch agent"
            case .globalAgent: "launch agent (all users)"
            case .daemon: "launch daemon"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let name: String
    public let executable: String?

    public init(id: String, kind: Kind, name: String, executable: String?) {
        self.id = id
        self.kind = kind
        self.name = name
        self.executable = executable
    }

    public init(_ item: LaunchItem) {
        let kind: Kind = switch item.scope {
        case .userAgent: .userAgent
        case .globalAgent: .globalAgent
        case .daemon: .daemon
        }
        self.init(id: item.plistPath, kind: kind, name: item.label, executable: item.executable)
    }

    public init(_ item: LoginItem) {
        self.init(id: "login:" + item.id, kind: .loginItem, name: item.name, executable: item.path.isEmpty ? nil : item.path)
    }
}

/// Everything the rules look at for one evaluation. Nil means "not sampled this time": the
/// matching rule neither fires nor re-arms.
public struct AlertSnapshot: Sendable {
    public var date: Date
    public var volume: VolumeStats?
    /// Process list plus the time it was sampled (CPU streaks are timed from sample times).
    public var processes: [ProcessLoad]?
    public var processesSampledAt: Date?
    public var thermal: ThermalLevel?
    /// Full-charge capacity as a fraction of design capacity.
    public var batteryHealth: Double?
    public var startupItems: [StartupFingerprint]?
    public var trashBytes: UInt64?

    public init(date: Date, volume: VolumeStats? = nil, processes: [ProcessLoad]? = nil, processesSampledAt: Date? = nil,
                thermal: ThermalLevel? = nil, batteryHealth: Double? = nil, startupItems: [StartupFingerprint]? = nil,
                trashBytes: UInt64? = nil) {
        self.date = date
        self.volume = volume
        self.processes = processes
        self.processesSampledAt = processesSampledAt
        self.thermal = thermal
        self.batteryHealth = batteryHealth
        self.startupItems = startupItems
        self.trashBytes = trashBytes
    }
}

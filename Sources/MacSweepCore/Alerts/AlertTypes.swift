import Foundation

public enum AlertRule: String, CaseIterable, Codable, Sendable, Identifiable {
    case lowDisk
    case memoryLeak
    case sustainedCPU
    case thermal
    case batteryHealth
    case newStartupItem
    case largeTrash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lowDisk: "Low disk space"
        case .memoryLeak: "App memory keeps growing"
        case .sustainedCPU: "Sustained high CPU"
        case .thermal: "Thermal throttling"
        case .batteryHealth: "Battery health drop"
        case .newStartupItem: "New login item or launch agent"
        case .largeTrash: "Large Trash"
        }
    }

    public var explanation: String {
        switch self {
        case .lowDisk: "Free space falls under 10% or 15 GB."
        case .memoryLeak: "An app's memory climbs steadily for minutes (possible leak)."
        case .sustainedCPU: "One process stays above 80% CPU for 2 minutes."
        case .thermal: "macOS reports the Mac is hot enough to slow down."
        case .batteryHealth: "Maximum battery capacity drops since the last reading."
        case .newStartupItem: "Something new will start automatically: a common malware trick."
        case .largeTrash: "More than 5 GB is sitting in the Trash."
        }
    }

    public var symbol: String {
        switch self {
        case .lowDisk: "internaldrive"
        case .memoryLeak: "memorychip"
        case .sustainedCPU: "cpu"
        case .thermal: "thermometer.high"
        case .batteryHealth: "battery.50percent"
        case .newStartupItem: "exclamationmark.shield"
        case .largeTrash: "trash"
        }
    }
}

public enum AlertSeverity: String, Codable, Sendable, Comparable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rank < rhs.rank }
}

public struct SmartAlert: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let rule: AlertRule
    /// Identifies the condition (e.g. `cpu:Xcode`) so the same problem fires once.
    public let key: String
    public let severity: AlertSeverity
    public let title: String
    public let message: String
    public let date: Date
    /// File or app the alert is about, so the UI can reveal it.
    public let subjectPath: String?

    public init(id: UUID = UUID(), rule: AlertRule, key: String, severity: AlertSeverity, title: String,
                message: String, date: Date, subjectPath: String? = nil) {
        self.id = id
        self.rule = rule
        self.key = key
        self.severity = severity
        self.title = title
        self.message = message
        self.date = date
        self.subjectPath = subjectPath
    }
}

/// Thresholds and per-rule cooldowns. Sizes are decimal (1 GB = 10^9 bytes), matching Finder.
public struct AlertConfig: Sendable, Equatable {
    public var lowDiskFraction = 0.10
    public var lowDiskBytes: UInt64 = 15_000_000_000
    /// Low disk re-arms only once free space is comfortably back above the line, so hovering
    /// around the threshold doesn't flap.
    public var lowDiskRearmFraction = 0.12
    public var lowDiskRearmBytes: UInt64 = 18_000_000_000
    public var cpuPercent = 80.0
    public var cpuDuration: TimeInterval = 120
    /// A longer gap between process samples (sleep, paused sampling) restarts a CPU streak.
    public var cpuMaxSampleGap: TimeInterval = 30
    public var leakMinimumGrowth: Int64 = 100_000_000
    public var batteryDrop = 0.02
    public var trashBytes: UInt64 = 5_000_000_000
    public var cooldowns: [AlertRule: TimeInterval] = [
        .lowDisk: 6 * 3_600,
        .memoryLeak: 3_600,
        .sustainedCPU: 30 * 60,
        .thermal: 30 * 60,
        .batteryHealth: 0,
        .newStartupItem: 0,
        .largeTrash: 24 * 3_600,
    ]

    public init() {}

    public func cooldown(_ rule: AlertRule) -> TimeInterval { cooldowns[rule] ?? 3_600 }
}

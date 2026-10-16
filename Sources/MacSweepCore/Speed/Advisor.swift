import Foundation

public struct AdvisorInput: Sendable {
    public var memory: SystemMemoryStats?
    public var heavyProcesses: [(pid: Int32, name: String, memory: UInt64, cpu: Double, growing: Bool)]
    public var loginItemCount: Int
    public var disk: VolumeStats?
    public var battery: BatteryInfo?
    public var safeCleanupBytes: UInt64
    public var trashBytes: UInt64
    public var protectionsOff: [String]
    public var securityFindings: Int
    public var uptimeDays: Int
    public var lastScan: Date?
    public var now: Date

    public init(memory: SystemMemoryStats? = nil, heavyProcesses: [(pid: Int32, name: String, memory: UInt64, cpu: Double, growing: Bool)] = [],
                loginItemCount: Int = 0, disk: VolumeStats? = nil, battery: BatteryInfo? = nil, safeCleanupBytes: UInt64 = 0,
                trashBytes: UInt64 = 0, protectionsOff: [String] = [], securityFindings: Int = 0, uptimeDays: Int = 0,
                lastScan: Date? = nil, now: Date = Date()) {
        self.memory = memory
        self.heavyProcesses = heavyProcesses
        self.loginItemCount = loginItemCount
        self.disk = disk
        self.battery = battery
        self.safeCleanupBytes = safeCleanupBytes
        self.trashBytes = trashBytes
        self.protectionsOff = protectionsOff
        self.securityFindings = securityFindings
        self.uptimeDays = uptimeDays
        self.lastScan = lastScan
        self.now = now
    }
}

public struct Advice: Identifiable, Sendable, Equatable {
    public enum Impact: Int, Sendable, Comparable {
        case low = 0, medium = 1, high = 2
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Action: Sendable, Equatable {
        case openStorage, openStartup, openSecurity, openProcesses, openMaintenance
        case quitProcess(pid: Int32, name: String)
        case emptyTrash
        case scanDisk
        case none
    }

    public let id: String
    public let impact: Impact
    public let title: String
    public let detail: String
    public let actionTitle: String?
    public let action: Action
}

/// Turns live measurements into a ranked, plain-English to-do list for a faster, healthier Mac.
public enum Advisor {
    static let gib: UInt64 = 1 << 30

    public static func advise(_ input: AdvisorInput) -> [Advice] {
        var advice: [Advice] = []
        let gb = { (bytes: UInt64) in ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file) }

        if let disk = input.disk, disk.total > 0 {
            let freeFraction = Double(disk.available) / Double(disk.total)
            if freeFraction < 0.1 {
                advice.append(Advice(id: "disk-low", impact: .high, title: "Disk almost full",
                                     detail: "Only \(gb(disk.available)) free. macOS slows down and can't update below about 10% free.",
                                     actionTitle: "Free Up Space", action: .openStorage))
            }
        }
        if input.safeCleanupBytes >= gib {
            advice.append(Advice(id: "cleanup", impact: input.safeCleanupBytes >= 10 * gib ? .high : .medium,
                                 title: "\(gb(input.safeCleanupBytes)) of caches can go",
                                 detail: "Build output and package caches that rebuild themselves.", actionTitle: "Review", action: .openStorage))
        }
        if input.trashBytes >= 500 << 20 {
            advice.append(Advice(id: "trash", impact: .medium, title: "Trash holds \(gb(input.trashBytes))",
                                 detail: "Space isn't freed until the Trash is emptied.", actionTitle: "Empty Trash", action: .emptyTrash))
        }
        if let memory = input.memory {
            if memory.pressure != .normal {
                advice.append(Advice(id: "pressure", impact: .high, title: "Memory pressure is \(memory.pressure.rawValue.lowercased())",
                                     detail: "Apps are being compressed or swapped. Quit the heaviest apps below.",
                                     actionTitle: "Processes", action: .openProcesses))
            }
            if memory.swapUsed >= 4 * gib {
                advice.append(Advice(id: "swap", impact: .medium, title: "\(gb(memory.swapUsed)) of swap in use",
                                     detail: "Your Mac is using the SSD as extra memory. Closing big apps or restarting clears it.",
                                     actionTitle: "Processes", action: .openProcesses))
            }
        }
        for process in input.heavyProcesses where process.growing {
            advice.append(Advice(id: "grow-\(process.pid)", impact: .medium, title: "\(process.name) keeps using more memory",
                                 detail: "Now \(gb(process.memory)) and climbing. Restarting it usually releases the memory.",
                                 actionTitle: "Quit", action: .quitProcess(pid: process.pid, name: process.name)))
        }
        for process in input.heavyProcesses where process.cpu >= 80 && !process.growing {
            advice.append(Advice(id: "cpu-\(process.pid)", impact: .medium, title: "\(process.name) is busy (\(Int(process.cpu))% CPU)",
                                 detail: "High sustained CPU drains the battery and heats the Mac. Quit it if you're not using it.",
                                 actionTitle: "Quit", action: .quitProcess(pid: process.pid, name: process.name)))
        }
        if input.loginItemCount >= 15 {
            advice.append(Advice(id: "login", impact: .medium, title: "\(input.loginItemCount) items start at login",
                                 detail: "Each one slows startup and runs in the background. Disable the ones you don't need.",
                                 actionTitle: "Startup Items", action: .openStartup))
        }
        if !input.protectionsOff.isEmpty {
            advice.append(Advice(id: "protection", impact: .high, title: "\(input.protectionsOff.joined(separator: ", ")) off",
                                 detail: "A built-in macOS protection is disabled.", actionTitle: "Security", action: .openSecurity))
        }
        if input.securityFindings > 0 {
            advice.append(Advice(id: "findings", impact: .high, title: "\(input.securityFindings) security findings to review",
                                 detail: "Unsigned or suspicious programs that start automatically.", actionTitle: "Review", action: .openSecurity))
        }
        if input.uptimeDays >= 7 {
            advice.append(Advice(id: "restart", impact: .low, title: "Running for \(input.uptimeDays) days",
                                 detail: "A restart clears swap, finishes pending updates and releases leaked memory.",
                                 actionTitle: nil, action: .none))
        }
        if let battery = input.battery, let health = battery.health, health < 0.8 {
            advice.append(Advice(id: "battery", impact: .low, title: "Battery health \(Int((health * 100).rounded()))%",
                                 detail: "Below 80% Apple recommends a battery service. Optimised Charging slows further wear.",
                                 actionTitle: nil, action: .none))
        }
        if input.lastScan.map({ input.now.timeIntervalSince($0) > 7 * 86_400 }) ?? true {
            advice.append(Advice(id: "scan", impact: .low, title: "Disk not scanned recently",
                                 detail: "Scan to find new caches and large files.", actionTitle: "Scan", action: .scanDisk))
        }
        return advice.sorted { $0.impact > $1.impact }
    }
}

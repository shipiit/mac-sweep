import Foundation

/// One thing Smart Scan found, with either a step that fixes it or the page where you decide.
public struct SmartFinding: Sendable, Equatable, Identifiable {
    public enum Level: Int, Sendable, Comparable {
        /// Your call: real data, or a change only you can make.
        case review = 0
        /// Fixable here with nothing lost.
        case safe = 1
        /// A security gap.
        case urgent = 2

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let id: String
    public let title: String
    public let detail: String
    public let bytes: UInt64
    public let level: Level
    /// The clean-up step that fixes it, when Smart Scan can.
    public let step: OptimizeStep?
    /// The page (by its sidebar name) that shows it in full.
    public let page: String
}

/// Everything the scan measured, gathered so the findings list is a pure function of it.
public struct SmartScanInput: Sendable, Equatable {
    public var safeJunk: UInt64 = 0
    public var reviewJunk: UInt64 = 0
    public var trash: UInt64 = 0
    public var appCaches: UInt64 = 0
    public var sandboxes: UInt64 = 0
    public var browserCopies: UInt64 = 0
    public var unusedDatabases: UInt64 = 0
    public var unusedDatabaseCount = 0
    public var stoppedServers: UInt64 = 0
    public var sessionExtras: UInt64 = 0
    /// Titles of failed hardening checks, split by whether MacSweep can fix them itself.
    public var fixableSettings: [String] = []
    public var manualSettings: [String] = []
    public var suspiciousItems = 0
    public var securityUpdates: [String] = []
    public var otherUpdates = 0
    public var speedTips = 0
    public var leftovers = 0

    public init() {}
}

public enum SmartFindings {
    /// Below this, a space finding is noise.
    static let minimumBytes: UInt64 = 20_000_000

    public static func build(_ input: SmartScanInput) -> [SmartFinding] {
        var list: [SmartFinding] = []
        func space(_ id: String, _ title: String, _ detail: String, _ bytes: UInt64, _ level: SmartFinding.Level, _ step: OptimizeStep?, _ page: String) {
            if bytes >= minimumBytes { list.append(SmartFinding(id: id, title: title, detail: detail, bytes: bytes, level: level, step: step, page: page)) }
        }
        func issue(_ id: String, _ title: String, _ detail: String, _ level: SmartFinding.Level, _ step: OptimizeStep?, _ page: String) {
            list.append(SmartFinding(id: id, title: title, detail: detail, bytes: 0, level: level, step: step, page: page))
        }
        if !input.securityUpdates.isEmpty {
            issue("security-updates", plural(input.securityUpdates.count, "security update") + " waiting", input.securityUpdates.prefix(3).joined(separator: ", "),
                  .urgent, nil, "Security Patcher")
        }
        if input.suspiciousItems > 0 {
            issue("suspicious", plural(input.suspiciousItems, "suspicious startup item or program", "suspicious startup items or programs"),
                  "Unsigned or oddly placed software that starts by itself.", .urgent, nil, "Security Audit")
        }
        if !input.fixableSettings.isEmpty {
            issue("settings-fixable", plural(input.fixableSettings.count, "security setting") + " MacSweep can turn on",
                  input.fixableSettings.joined(separator: ", ") + ". Needs your password once.", .urgent, .hardening, "Hardening")
        }
        if !input.manualSettings.isEmpty {
            issue("settings-manual", plural(input.manualSettings.count, "security setting") + " to change yourself",
                  input.manualSettings.joined(separator: ", "), .urgent, nil, "Hardening")
        }
        space("junk", "System junk", "Caches, logs and build output that tools recreate. Moved to the Trash.", input.safeJunk, .safe, .systemJunk, "Space & Junk")
        space("app-caches", "Hidden app caches", "Caches inside your biggest app folders. Open apps are skipped. Moved to the Trash.", input.appCaches, .safe, .appCaches, "Hidden Space")
        space("browser-copies", "Leftover browser copies", "Copies of Chrome, Brave or Edge left behind after a crash. Deleted; open browsers are skipped.",
              input.browserCopies, .safe, .browserCopies, "Hidden Space")
        space("session-extras", "AI session extras", "Subagent logs, tool output and file backups. Conversations are kept. Moved to the Trash.",
              input.sessionExtras, .safe, .sessionExtras, "AI Sessions")
        space("trash", "Trash", "Emptying it is permanent, so it's off unless you tick it.", input.trash, .review, .trashBins, "Trash Bins")
        space("review-junk", "Large items to review", "Models, SDKs, installers and old projects. Real data, so you choose.", input.reviewJunk, .review, nil, "Space & Junk")
        space("databases", plural(input.unusedDatabaseCount, "database") + " no project uses", "Local Postgres databases no config file names. Back up, then drop.",
              input.unusedDatabases, .review, nil, "Hidden Space")
        space("sandboxes", "App sandboxes", "Rebuilt by the app, but files saved inside are lost.", input.sandboxes, .review, nil, "Hidden Space")
        space("stopped-servers", "Data of stopped database servers", "An old database version's data that nothing is running.", input.stoppedServers, .review, nil, "Hidden Space")
        if input.otherUpdates > 0 {
            issue("updates", plural(input.otherUpdates, "app or tool update"), "Outdated apps are a common way in.", .review, nil, "Security Patcher")
        }
        if input.speedTips > 0 { issue("speed", plural(input.speedTips, "speed tip"), "Things slowing this Mac down right now.", .review, nil, "Optimization") }
        if input.leftovers > 0 { issue("leftovers", plural(input.leftovers, "leftover") + " from deleted apps", "Files apps left behind when they were removed.", .review, nil, "Uninstaller") }
        return list.sorted { ($0.level.rawValue, $0.bytes) > ($1.level.rawValue, $1.bytes) }
    }

    /// Steps ticked by default: everything safe, and security settings. Never the permanent Trash emptying.
    public static func defaultSteps(_ findings: [SmartFinding]) -> Set<OptimizeStep> {
        Set(findings.filter { $0.level != .review }.compactMap(\.step))
    }

    /// Space the ticked steps would give back.
    public static func bytes(_ findings: [SmartFinding], steps: Set<OptimizeStep>) -> UInt64 {
        findings.filter { $0.step.map(steps.contains) ?? false }.reduce(0) { $0 + $1.bytes }
    }

    static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) " + (count == 1 ? singular : plural ?? singular + "s")
    }
}

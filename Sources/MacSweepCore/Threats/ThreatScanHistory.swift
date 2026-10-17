import Foundation

public enum ThreatScanKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case quick = "Quick Scan", full = "Full Scan", deep = "Deep Scan", custom = "Custom Scan", download = "Download Check"
    public var id: String { rawValue }

    /// Folders each kind looks at (custom scans pass their own).
    public func roots(home: String = NSHomeDirectory()) -> [String] {
        switch self {
        case .quick: [home + "/Downloads", home + "/Desktop"]
        case .full: ThreatScanner.defaultRoots(home: home)
        case .deep: [home, "/Applications", "/Library/LaunchAgents", "/Library/LaunchDaemons", home + "/Library/LaunchAgents",
                     "/Library/Application Support", home + "/Library/Application Support", "/Users/Shared", "/private/tmp", "/private/var/tmp"]
        case .custom, .download: []
        }
    }

    public var scopeTitle: String {
        switch self {
        case .quick: "Downloads & Desktop"
        case .full: "Common locations"
        case .deep: "Whole home folder, apps & startup folders"
        case .custom: "Chosen folder"
        case .download: "Downloads"
        }
    }
}

public struct ThreatScanRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: ThreatScanKind
    public let scope: String
    public let date: Date
    public let duration: TimeInterval
    public let filesChecked: Int
    public let threats: Int

    public init(id: UUID = UUID(), kind: ThreatScanKind, scope: String, date: Date, duration: TimeInterval, filesChecked: Int, threats: Int) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.date = date
        self.duration = duration
        self.filesChecked = filesChecked
        self.threats = threats
    }

    public var isClean: Bool { threats == 0 }
}

/// The last scans and download checks, newest first, kept small on disk.
public struct ThreatScanHistory: Sendable {
    public let url: URL
    public static let limit = 30

    public init(url: URL) { self.url = url }

    public static var standard: ThreatScanHistory {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return ThreatScanHistory(url: base.appendingPathComponent("MacSweep/threat-scans.json"))
    }

    public func load() -> [ThreatScanRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([ThreatScanRecord].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    @discardableResult
    public func append(_ record: ThreatScanRecord) throws -> [ThreatScanRecord] {
        let records = Array(([record] + load()).sorted { $0.date > $1.date }.prefix(Self.limit))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: url, options: .atomic)
        return records
    }
}

/// Apple's built-in malware definitions (XProtect): version and when they were last updated.
public struct XProtectInfo: Sendable, Equatable {
    public let version: String
    public let updated: Date?

    public static let bundlePath = "/Library/Apple/System/Library/CoreServices/XProtect.bundle"

    public static func read(bundle: String = bundlePath) -> XProtectInfo? {
        let plist = bundle + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = info["CFBundleShortVersionString"] as? String else { return nil }
        let updated = (try? FileManager.default.attributesOfItem(atPath: plist))?[.modificationDate] as? Date
        return XProtectInfo(version: version, updated: updated)
    }

    /// Apple updates XProtect every week or two; a month without updates is worth a look.
    public func isCurrent(now: Date = Date()) -> Bool {
        updated.map { now.timeIntervalSince($0) < 30 * 86_400 } ?? false
    }
}

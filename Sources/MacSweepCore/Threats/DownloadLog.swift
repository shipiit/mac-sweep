import Foundation

/// One download Download Protection looked at, with what it found and what it did.
public struct DownloadRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        /// Not something that can run code (documents, images, media).
        case safeType
        /// A program or installer whose checks all passed.
        case passed
        /// Suspicious: the user was notified and nothing was moved.
        case flagged
        /// A clear threat moved to quarantine.
        case quarantined
    }

    public let id: UUID
    public let name: String
    public let path: String
    public let size: UInt64
    public let date: Date
    public let origin: String?
    public let kind: String
    public let signer: String?
    public let outcome: Outcome
    public let reasons: [String]

    public init(id: UUID = UUID(), name: String, path: String, size: UInt64, date: Date, origin: String?, kind: String,
                signer: String?, outcome: Outcome, reasons: [String]) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.date = date
        self.origin = origin
        self.kind = kind
        self.signer = signer
        self.outcome = outcome
        self.reasons = reasons
    }

    /// Builds the record for a checked download from its facts and verdict.
    public static func make(path: String, size: UInt64, date: Date, facts: FileFacts?, verdict: ThreatVerdict?) -> DownloadRecord {
        let name = (path as NSString).lastPathComponent
        let kind = facts?.kind ?? FileKind.classify(name: name, isExecutable: false, isMachO: false)
        let outcome: Outcome
        if let verdict {
            outcome = verdict.isAutoQuarantine ? .quarantined : .flagged
        } else {
            outcome = facts == nil || [.document, .other, .archive].contains(kind) ? .safeType : .passed
        }
        return DownloadRecord(name: name, path: path, size: size, date: date, origin: facts?.origin, kind: kind.title,
                              signer: facts?.signature?.title, outcome: outcome, reasons: verdict?.reasons ?? [])
    }

    /// The website it came from, without the full URL.
    public var originHost: String? { origin.flatMap { URL(string: $0)?.host } ?? origin }
}

extension FileKind {
    public var title: String {
        switch self {
        case .app: "App"
        case .installerPackage: "Installer"
        case .diskImage: "Disk image"
        case .script: "Script"
        case .executable: "Program"
        case .archive: "Archive"
        case .document: "Document"
        case .other: "File"
        }
    }
}

/// The last downloads checked, newest first, saved so the history survives restarts.
public struct DownloadLog: Sendable {
    public let url: URL
    public static let limit = 20

    public init(url: URL) { self.url = url }

    public static var standard: DownloadLog {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return DownloadLog(url: base.appendingPathComponent("MacSweep/downloads.json"))
    }

    public func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([DownloadRecord].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    /// Adds records, replacing any earlier record for the same path, and keeps the newest `limit`.
    @discardableResult
    public func append(_ records: [DownloadRecord]) throws -> [DownloadRecord] {
        let paths = Set(records.map(\.path))
        let merged = Array((records + load().filter { !paths.contains($0.path) }).sorted { $0.date > $1.date }.prefix(Self.limit))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(merged).write(to: url, options: .atomic)
        return merged
    }
}

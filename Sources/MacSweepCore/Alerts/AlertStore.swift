import Foundation
import os

/// Engine state plus the recent alert list, saved together so relaunching neither re-fires old
/// conditions nor forgets the battery and startup-item baselines.
public struct AlertArchive: Codable, Sendable, Equatable {
    public var state: AlertEngineState
    public var recent: [SmartAlert]

    public static let recentLimit = 50

    public init(state: AlertEngineState = AlertEngineState(), recent: [SmartAlert] = []) {
        self.state = state
        self.recent = recent
    }

    /// Newest first, capped at `recentLimit`.
    public mutating func record(_ alerts: [SmartAlert]) {
        guard !alerts.isEmpty else { return }
        recent = Array((alerts.sorted { $0.date > $1.date } + recent).prefix(Self.recentLimit))
    }
}

public struct AlertStore: Sendable {
    public let url: URL
    private static let log = Logger(subsystem: Log.subsystem, category: "alerts")

    public init(url: URL) {
        self.url = url
    }

    public static var standard: AlertStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return AlertStore(url: base.appendingPathComponent("MacSweep/alerts.json"))
    }

    public func save(_ archive: AlertArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(archive).write(to: url, options: .atomic)
    }

    /// An empty archive when nothing is saved or the file is unreadable.
    public func load() -> AlertArchive {
        guard let data = try? Data(contentsOf: url) else { return AlertArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(AlertArchive.self, from: data)
        } catch {
            Self.log.warning("discarding unreadable alert state: \(error.localizedDescription, privacy: .public)")
            return AlertArchive()
        }
    }
}

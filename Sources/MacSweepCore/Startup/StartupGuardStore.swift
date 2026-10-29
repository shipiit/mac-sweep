import Foundation
import os

/// Everything the Startup Guard remembers between launches.
public struct StartupGuardArchive: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// Approved launch agents/daemons, keyed by plist path.
    public var baseline: [String: StartupFingerprint]
    public var held: [HeldStartupItem]
    /// Newest first, capped at `historyLimit`.
    public var history: [StartupGuardEvent]

    public static let historyLimit = 100

    public init(isEnabled: Bool = false, baseline: [String: StartupFingerprint] = [:], held: [HeldStartupItem] = [],
                history: [StartupGuardEvent] = []) {
        self.isEnabled = isEnabled
        self.baseline = baseline
        self.held = held
        self.history = history
    }

    public mutating func log(_ event: StartupGuardEvent) {
        history = Array(([event] + history).prefix(Self.historyLimit))
    }

    /// Turning the guard on accepts everything installed right now; only later additions are held.
    public mutating func enable(current: [LaunchItem], at now: Date) {
        isEnabled = true
        baseline = StartupGuardPolicy.baseline(from: current)
        held.removeAll()
        log(StartupGuardEvent(date: now, name: "Startup Guard", path: "", action: "Turned on with \(baseline.count) approved items"))
    }

    public mutating func disable(at now: Date) {
        isEnabled = false
        log(StartupGuardEvent(date: now, name: "Startup Guard", path: "", action: "Turned off"))
    }

    /// Approve or keep-blocked: either way the item is known now and leaves the held list.
    public mutating func resolve(_ id: String, action: String, at now: Date) {
        guard let index = held.firstIndex(where: { $0.id == id }) else { return }
        let entry = held.remove(at: index)
        baseline[id] = entry.fingerprint
        log(StartupGuardEvent(date: now, name: entry.fingerprint.name, path: id, action: action))
    }

    public mutating func markBlocked(_ id: String, at now: Date) {
        guard let index = held.firstIndex(where: { $0.id == id }) else { return }
        held[index].status = .blocked
        log(StartupGuardEvent(date: now, name: held[index].fingerprint.name, path: id, action: "Blocked"))
    }

    public mutating func forget(_ id: String, action: String, at now: Date) {
        guard let index = held.firstIndex(where: { $0.id == id }) else { return }
        let entry = held.remove(at: index)
        baseline[id] = nil
        log(StartupGuardEvent(date: now, name: entry.fingerprint.name, path: id, action: action))
    }
}

public struct StartupGuardStore: Sendable {
    public let url: URL
    private static let log = Logger(subsystem: Log.subsystem, category: "startup-guard")

    public init(url: URL) {
        self.url = url
    }

    public static var standard: StartupGuardStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return StartupGuardStore(url: base.appendingPathComponent("MacSweep/startup-guard.json"))
    }

    public func save(_ archive: StartupGuardArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(archive).write(to: url, options: .atomic)
    }

    /// An empty (guard off) archive when nothing is saved or the file is unreadable.
    public func load() -> StartupGuardArchive {
        guard let data = try? Data(contentsOf: url) else { return StartupGuardArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(StartupGuardArchive.self, from: data)
        } catch {
            Self.log.warning("discarding unreadable startup guard state: \(error.localizedDescription, privacy: .public)")
            return StartupGuardArchive()
        }
    }
}

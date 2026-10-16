import Foundation
import os

/// Persists the latest scan so the map is available instantly at launch.
public struct ScanStore: Sendable {
    public let url: URL
    private static let log = Logger(subsystem: Log.subsystem, category: "scan-store")

    public init(url: URL) {
        self.url = url
    }

    public static var standard: ScanStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return ScanStore(url: base.appendingPathComponent("MacSweep/last-scan.plist"))
    }

    public func save(_ result: ScanResult) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(result).write(to: url, options: .atomic)
        Self.log.info("saved scan of \(result.root.path, privacy: .public)")
    }

    /// Nil when there is no saved scan or it can't be read (e.g. written by an older format).
    public func load() -> ScanResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try PropertyListDecoder().decode(ScanResult.self, from: data)
        } catch {
            Self.log.warning("discarding unreadable saved scan: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

public enum ScanSchedule: String, CaseIterable, Sendable, Identifiable {
    case off = "Off"
    case nightly = "Every night (2 AM)"
    case morning = "Every morning (8 AM)"
    case sixHours = "Every 6 hours"

    public var id: String { rawValue }

    /// When the next automatic scan is due. A missed slot (Mac asleep) is due immediately.
    public func nextDue(after lastScan: Date?, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .off:
            return nil
        case .sixHours:
            guard let lastScan else { return now }
            return lastScan.addingTimeInterval(6 * 3_600)
        case .nightly, .morning:
            let hour = self == .nightly ? 2 : 8
            guard let lastScan else { return now }
            let slotToday = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
            let latestSlot = slotToday <= now ? slotToday : calendar.date(byAdding: .day, value: -1, to: slotToday) ?? slotToday
            if lastScan < latestSlot { return latestSlot }
            return calendar.date(byAdding: .day, value: 1, to: latestSlot) ?? latestSlot
        }
    }

    public func isDue(lastScan: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due = nextDue(after: lastScan, now: now, calendar: calendar) else { return false }
        return due <= now
    }
}

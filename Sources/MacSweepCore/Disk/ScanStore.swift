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

    /// The scan that the current one replaced, kept so "what grew" can compare the two.
    public var previousURL: URL { sibling("previous") }
    /// Holds the current scan's finish time so a save can tell a fresh scan from a re-save of the
    /// same one (e.g. after cleanup) without decoding the whole tree.
    var stampURL: URL { sibling("stamp") }

    private func sibling(_ suffix: String) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "plist" : url.pathExtension
        return url.deletingLastPathComponent().appendingPathComponent("\(base)-\(suffix).\(ext)")
    }

    /// Saves the scan. A different scan (new `finishedAt`) moves the one on disk to `previousURL`;
    /// re-saving the same scan just overwrites it so the previous scan stays a genuine earlier scan.
    public func save(_ result: ScanResult) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(result)
        if manager.fileExists(atPath: url.path), storedFinishedAt() != result.finishedAt {
            try? manager.removeItem(at: previousURL)
            try manager.moveItem(at: url, to: previousURL)
        }
        try data.write(to: url, options: .atomic)
        try encoder.encode(ScanStamp(finishedAt: result.finishedAt)).write(to: stampURL, options: .atomic)
        Self.log.info("saved scan of \(result.root.path, privacy: .public)")
    }

    /// Nil when there is no saved scan or it can't be read (e.g. written by an older format).
    public func load() -> ScanResult? {
        Self.decode(at: url)
    }

    /// The scan before the current one; nil when there is none or it can't be read.
    public func loadPrevious() -> ScanResult? {
        Self.decode(at: previousURL)
    }

    public func clear() {
        for file in [url, previousURL, stampURL] { try? FileManager.default.removeItem(at: file) }
    }

    /// Scans saved before the stamp existed fall back to decoding the stored scan once.
    private func storedFinishedAt() -> Date? {
        if let data = try? Data(contentsOf: stampURL),
           let stamp = try? PropertyListDecoder().decode(ScanStamp.self, from: data) {
            return stamp.finishedAt
        }
        return Self.decode(at: url)?.finishedAt
    }

    private static func decode(at url: URL) -> ScanResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try PropertyListDecoder().decode(ScanResult.self, from: data)
        } catch {
            log.warning("discarding unreadable saved scan: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private struct ScanStamp: Codable {
    let finishedAt: Date
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

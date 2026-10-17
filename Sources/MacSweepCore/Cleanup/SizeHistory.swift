import Foundation

/// Append-only CSV of recommendation sizes per scan (`date,bytes,path`), so the next scan can flag what grew.
public struct SizeHistory: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: SizeHistory {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return SizeHistory(url: base.appendingPathComponent("MacSweep/sizes.csv"))
    }

    /// Records one scan. Re-recording the same scan date is ignored so a re-evaluation doesn't duplicate rows.
    public func record(_ sizes: [String: UInt64], at date: Date) throws {
        let stamp = Self.stamp(date)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !existing.contains("\n" + stamp + ","), !existing.hasPrefix(stamp + ",") else { return }
        let rows = sizes.sorted { $0.key < $1.key }.map { "\(stamp),\($0.value),\($0.key.replacingOccurrences(of: "\n", with: " "))" }
        guard !rows.isEmpty else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = (existing.isEmpty || existing.hasSuffix("\n") ? existing : existing + "\n") + rows.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Latest size recorded for each path strictly before `date`.
    public func previous(before date: Date) -> [String: UInt64] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return Self.parse(text, before: Self.stamp(date))
    }

    static func parse(_ text: String, before stamp: String) -> [String: UInt64] {
        var latest: [String: (String, UInt64)] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let size = UInt64(parts[1]) else { continue }
            let date = String(parts[0])
            let path = String(parts[2])
            guard !date.isEmpty, !path.isEmpty, date < stamp, latest[path].map({ $0.0 < date }) ?? true else { continue }
            latest[path] = (date, size)
        }
        return latest.mapValues(\.1)
    }

    /// ISO-8601 in UTC sorts the same as time, so dates compare as strings.
    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

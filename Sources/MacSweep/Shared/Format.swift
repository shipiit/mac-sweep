import Foundation
import MacSweepCore

enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func bytes(_ value: UInt64?) -> String {
        value.map(bytes) ?? "—"
    }

    static func signedBytes(_ value: Int64) -> String {
        let magnitude = ByteCountFormatter.string(fromByteCount: abs(value), countStyle: .memory)
        return value >= 0 ? "+" + magnitude : "−" + magnitude
    }

    static func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }

    static func path(_ path: String) -> String {
        PathTools.abbreviate(path, home: NSHomeDirectory())
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    /// "42s", "3m 12s", "1h 32m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        if total < 60 { return "\(total)s" }
        if total < 3_600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3_600)h \((total % 3_600) / 60)m"
    }
}

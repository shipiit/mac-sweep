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
}

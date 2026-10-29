import Foundation

/// `git count-objects -v`. Sizes are reported by git in KiB and stored here in bytes.
public struct GitObjectStats: Sendable, Equatable {
    public var looseCount: Int = 0
    public var looseSize: UInt64 = 0
    public var packedCount: Int = 0
    public var packs: Int = 0
    public var packSize: UInt64 = 0
    public var garbageCount: Int = 0
    public var garbageSize: UInt64 = 0

    public init(looseCount: Int = 0, looseSize: UInt64 = 0, packedCount: Int = 0, packs: Int = 0,
                packSize: UInt64 = 0, garbageCount: Int = 0, garbageSize: UInt64 = 0) {
        self.looseCount = looseCount
        self.looseSize = looseSize
        self.packedCount = packedCount
        self.packs = packs
        self.packSize = packSize
        self.garbageCount = garbageCount
        self.garbageSize = garbageSize
    }

    /// Loose objects or many packs mean `git gc` will likely shrink the folder.
    public var wouldBenefitFromCompact: Bool { looseCount >= 100 || packs > 1 || garbageCount > 0 }
}

public enum GitOutputParser {
    /// Nil when the output has none of the expected keys (empty, garbage or an error message).
    public static func countObjects(_ output: String) -> GitObjectStats? {
        var stats = GitObjectStats()
        var recognised = 0
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let value = UInt64(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            let kib = value.multipliedReportingOverflow(by: 1024)
            let bytes = kib.overflow ? UInt64.max : kib.partialValue
            let count = Int(clamping: value)
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "count": stats.looseCount = count
            case "size": stats.looseSize = bytes
            case "in-pack": stats.packedCount = count
            case "packs": stats.packs = count
            case "size-pack": stats.packSize = bytes
            case "garbage": stats.garbageCount = count
            case "size-garbage": stats.garbageSize = bytes
            default: continue
            }
            recognised += 1
        }
        return recognised > 0 ? stats : nil
    }

    /// `git log -1 --format=%ct`: Unix seconds, or nil for an empty repository or unexpected output.
    public static func commitDate(_ output: String) -> Date? {
        guard let seconds = TimeInterval(output.trimmingCharacters(in: .whitespacesAndNewlines)), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// `git status --porcelain`: any non-blank line is a changed or untracked path.
    public static func hasUncommittedWork(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// What a compaction changed, measured on the `.git` folder before and after.
public struct GitCompactReport: Sendable, Equatable {
    public let before: UInt64
    public let after: UInt64

    public init(before: UInt64, after: UInt64) {
        self.before = before
        self.after = after
    }

    /// Never negative: gc can briefly grow a tiny repository, which is reported as nothing saved.
    public var saved: UInt64 { before > after ? before - after : 0 }

    public var savedFraction: Double { before == 0 ? 0 : Double(saved) / Double(before) }
}

import Foundation

public enum CleanupSafety: String, Sendable, CaseIterable {
    /// Regenerated automatically by the owning tool; removing it only costs a re-download or rebuild.
    case safe
    /// Real data the user may still want (models, SDKs, simulators, installers).
    case review
}

public enum CleanupTargetSpec: Sendable {
    /// Specific paths (may start with `~/`).
    case paths([String])
    /// Each child of a directory, minus excluded names.
    case contents(of: String, excluding: [String] = [])
    /// Directories with one of these names anywhere under home, optionally only if untouched for N days.
    case named([String], idleDays: Int?)
    /// For each child of a directory, these named grandchildren (e.g. Electron apps' `*/Cache`), but only
    /// in children that contain at least one `signature` entry on disk (proof it's the expected kind of app).
    case nested(in: String, names: [String], signature: [String])
    /// Files in a directory whose extension matches.
    case files(in: String, extensions: [String], olderThanDays: Int?)
}

public struct CleanupRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let safety: CleanupSafety
    public let category: StorageCategory
    public let target: CleanupTargetSpec

    public init(id: String, title: String, detail: String, safety: CleanupSafety, category: StorageCategory, target: CleanupTargetSpec) {
        self.id = id
        self.title = title
        self.detail = detail
        self.safety = safety
        self.category = category
        self.target = target
    }
}

public struct CleanupTarget: Identifiable, Hashable, Sendable {
    public let path: String
    public let size: UInt64
    public let modified: Date?

    public var id: String { path }

    public init(path: String, size: UInt64, modified: Date? = nil) {
        self.path = path
        self.size = size
        self.modified = modified
    }
}

public struct CleanupItem: Identifiable, Sendable {
    public let rule: CleanupRule
    public let targets: [CleanupTarget]

    public var id: String { rule.id }
    public var size: UInt64 { targets.reduce(0) { $0 + $1.size } }

    public init(rule: CleanupRule, targets: [CleanupTarget]) {
        self.rule = rule
        self.targets = targets
    }
}

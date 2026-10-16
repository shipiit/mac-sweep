import Foundation

/// Files with byte-identical content. Every member is a distinct inode, so trashing one really frees space.
public struct DuplicateGroup: Sendable, Identifiable, Equatable {
    /// SHA-256 of the content.
    public let id: String
    public let size: UInt64
    /// Ranked: the first file is the suggested one to keep.
    public let files: [FileStat]

    public init(id: String, size: UInt64, files: [FileStat]) {
        self.id = id
        self.size = size
        self.files = files
    }

    public var suggestedKeep: FileStat? { files.first }
    /// Space freed by keeping one copy and trashing the rest.
    public var reclaimable: UInt64 { size * UInt64(max(files.count - 1, 0)) }

    public func removing(_ paths: Set<String>) -> DuplicateGroup? {
        let left = files.filter { !paths.contains($0.path) }
        return left.count >= 2 ? DuplicateGroup(id: id, size: size, files: left) : nil
    }
}

public struct DuplicateScanResult: Sendable, Equatable {
    public var groups: [DuplicateGroup]
    public var filesScanned: Int
    /// Files that matched another's size but could not be opened.
    public var unreadable: Int
    public var skippedCloudOnly: Int
    /// Extra hard links to a file already counted; trashing them would free nothing.
    public var hardLinksSkipped: Int
    public var rejectedRoots: [ScanRoots.Rejection]

    public var reclaimable: UInt64 { groups.reduce(0) { $0 + $1.reclaimable } }
    public var duplicateCount: Int { groups.reduce(0) { $0 + $1.files.count - 1 } }
}

/// Which copy of a set of duplicates to keep: one in a preferred folder, then the oldest,
/// then the one with the shortest path (usually the "original" location), then by name.
public enum KeepSuggestion {
    public static func rank(_ files: [FileStat], preferredFolders: [String]) -> [FileStat] {
        files.sorted { lhs, rhs in
            let lhsPreferred = isPreferred(lhs.path, preferredFolders)
            let rhsPreferred = isPreferred(rhs.path, preferredFolders)
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            let lhsAge = min(lhs.created, lhs.modified)
            let rhsAge = min(rhs.created, rhs.modified)
            if lhsAge != rhsAge { return lhsAge < rhsAge }
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
    }

    /// Photos: keep the biggest file (usually the highest quality), then fall back to the duplicate rules.
    public static func rankPhotos(_ files: [FileStat], preferredFolders: [String]) -> [FileStat] {
        let ranked = rank(files, preferredFolders: preferredFolders)
        return ranked.enumerated().sorted { lhs, rhs in
            lhs.element.size != rhs.element.size ? lhs.element.size > rhs.element.size : lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func isPreferred(_ path: String, _ folders: [String]) -> Bool {
        folders.contains { PathTools.isDescendant(path, of: $0) }
    }
}

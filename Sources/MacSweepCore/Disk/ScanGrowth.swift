import Foundation

public struct GrowthEntry: Identifiable, Sendable, Equatable {
    public enum Change: Sendable, Equatable {
        case grew
        case shrank
        case added
        case removed
        case renamed(from: String)
    }

    public let path: String
    public let isDirectory: Bool
    public let oldSize: UInt64
    public let newSize: UInt64
    public let change: Change

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var delta: Int64 { Int64(clamping: newSize) - Int64(clamping: oldSize) }
}

public struct ScanGrowthReport: Sendable, Equatable {
    public let rootPath: String
    public let oldDate: Date
    public let newDate: Date
    public let oldSize: UInt64
    public let newSize: UInt64
    /// Largest growth first.
    public let grown: [GrowthEntry]
    /// Largest shrink first.
    public let shrunk: [GrowthEntry]
    /// Folders that moved to a new name with about the same contents.
    public let renamed: [GrowthEntry]

    public var totalDelta: Int64 { Int64(clamping: newSize) - Int64(clamping: oldSize) }
}

/// Compares two scans of the same folder and names the items that explain the change: a folder
/// is listed only when no reported descendant already accounts for most of its growth.
public enum ScanGrowth {
    /// Share of a folder's change its reported descendants must explain for it to be left out.
    static let explainedShare = 0.75
    /// Size tolerance when pairing a removed and an added sibling as a rename.
    static let renameTolerance = 0.01

    /// Nil when the scans don't cover the same folder.
    public static func compare(old: ScanResult, new: ScanResult, minimumDelta: UInt64 = 50_000_000,
                               limit: Int = 25) -> ScanGrowthReport? {
        guard let oldRoot = old.root.node(at: new.root.path), oldRoot.kind == .directory,
              new.root.kind == .directory else { return nil }
        var context = Context(minimum: Int64(clamping: minimumDelta), rootPath: new.root.path)
        _ = visit(oldRoot, new.root, &context)
        let grown = context.entries.filter { $0.delta > 0 && !$0.isRename }.sorted { $0.delta > $1.delta }
        let shrunk = context.entries.filter { $0.delta < 0 && !$0.isRename }.sorted { $0.delta < $1.delta }
        return ScanGrowthReport(
            rootPath: new.root.path, oldDate: old.finishedAt, newDate: new.finishedAt,
            oldSize: oldRoot.size, newSize: new.root.size,
            grown: Array(grown.prefix(limit)), shrunk: Array(shrunk.prefix(limit)),
            renamed: Array(context.entries.filter(\.isRename).prefix(limit))
        )
    }

    struct Context {
        let minimum: Int64
        let rootPath: String
        var entries: [GrowthEntry] = []
    }

    /// Change after excluding restricted folders, plus how much growth/shrink reported items explain.
    struct Outcome {
        var adjusted: Int64
        var grow: Int64
        var shrink: Int64
    }

    static func visit(_ old: FileNode, _ new: FileNode, _ context: inout Context) -> Outcome {
        let raw = Int64(clamping: new.size) - Int64(clamping: old.size)
        var excluded: Int64 = 0
        var grow: Int64 = 0
        var shrink: Int64 = 0
        if old.kind == .directory, new.kind == .directory {
            let oldChildren = Dictionary(old.children.filter { $0.kind != .aggregate }.map { ($0.path, $0) },
                                         uniquingKeysWith: { first, _ in first })
            let newChildren = new.children.filter { $0.kind != .aggregate }
            var added: [FileNode] = []
            for child in newChildren {
                guard let previous = oldChildren[child.path] else {
                    added.append(child)
                    continue
                }
                let childRaw = Int64(clamping: child.size) - Int64(clamping: previous.size)
                if child.kind == .restricted || previous.kind == .restricted {
                    excluded += childRaw
                    continue
                }
                let outcome = visit(previous, child, &context)
                excluded += childRaw - outcome.adjusted
                grow += outcome.grow
                shrink += outcome.shrink
            }
            let newPaths = Set(newChildren.map(\.path))
            let removed = old.children.filter { $0.kind != .aggregate && !newPaths.contains($0.path) }
            // Folding into "N smaller items" differs between scans, so an item appearing or
            // vanishing next to an aggregate tile may just have been folded: credit the parent.
            let hasAggregate = old.children.contains { $0.kind == .aggregate } || new.children.contains { $0.kind == .aggregate }
            if !hasAggregate {
                let unmatched = pairRenames(added: added, removed: removed, &context)
                for child in unmatched.added where Int64(clamping: child.size) >= context.minimum {
                    context.entries.append(entry(nil, child, .added))
                    grow += Int64(clamping: child.size)
                }
                for child in unmatched.removed where Int64(clamping: child.size) >= context.minimum {
                    context.entries.append(entry(child, nil, .removed))
                    shrink -= Int64(clamping: child.size)
                }
            }
        }
        let adjusted = raw - excluded
        if new.path != context.rootPath, abs(adjusted) >= context.minimum {
            if adjusted > 0, Double(grow) < explainedShare * Double(adjusted) {
                context.entries.append(entry(old, new, .grew, delta: adjusted))
                grow = max(grow, adjusted)
            } else if adjusted < 0, Double(-shrink) < explainedShare * Double(-adjusted) {
                context.entries.append(entry(old, new, .shrank, delta: adjusted))
                shrink = min(shrink, adjusted)
            }
        }
        return Outcome(adjusted: adjusted, grow: grow, shrink: shrink)
    }

    /// Pairs removed and added siblings of the same kind and item count whose sizes match within 1%.
    static func pairRenames(added: [FileNode], removed: [FileNode],
                            _ context: inout Context) -> (added: [FileNode], removed: [FileNode]) {
        var remaining = removed
        var unmatchedAdded: [FileNode] = []
        for child in added {
            let match = remaining.firstIndex { candidate in
                candidate.kind == child.kind && candidate.itemCount == child.itemCount
                    && Double(abs(Int64(clamping: candidate.size) - Int64(clamping: child.size)))
                    <= renameTolerance * Double(max(candidate.size, child.size, 1))
            }
            guard let match else {
                unmatchedAdded.append(child)
                continue
            }
            context.entries.append(entry(remaining[match], child, .renamed(from: remaining[match].path)))
            remaining.remove(at: match)
        }
        return (unmatchedAdded, remaining)
    }

    /// `delta` overrides the raw size change (used when restricted folders are excluded).
    private static func entry(_ old: FileNode?, _ new: FileNode?, _ change: GrowthEntry.Change, delta: Int64? = nil) -> GrowthEntry {
        let oldSize = old?.size ?? 0
        var newSize = new?.size ?? 0
        if let delta {
            newSize = UInt64(clamping: Int64(clamping: oldSize) + delta)
        }
        return GrowthEntry(path: new?.path ?? old?.path ?? "", isDirectory: (new ?? old)?.kind == .directory,
                           oldSize: oldSize, newSize: newSize, change: change)
    }
}

extension GrowthEntry {
    var isRename: Bool {
        if case .renamed = change { return true }
        return false
    }
}

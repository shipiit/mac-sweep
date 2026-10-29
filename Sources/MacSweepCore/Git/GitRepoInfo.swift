import Foundation

/// One repository's footprint: how much of it is `.git` history versus checked-out files.
public struct GitRepoInfo: Sendable, Equatable, Identifiable {
    public let path: String
    public var gitSize: UInt64?
    public var totalSize: UInt64?
    public var lfsSize: UInt64 = 0
    public var lastCommit: Date?
    /// Nil when git couldn't be asked (in use or failed).
    public var hasUncommittedWork: Bool?
    public var objects: GitObjectStats?
    public var isInUse = false

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public var workingTreeSize: UInt64? {
        guard let gitSize, let totalSize else { return nil }
        return totalSize > gitSize ? totalSize - gitSize : 0
    }

    /// Share of the whole folder taken by `.git`, 0...1.
    public var gitShare: Double? {
        guard let gitSize, let totalSize, totalSize > 0 else { return nil }
        return min(Double(gitSize) / Double(totalSize), 1)
    }

    public init(path: String, gitSize: UInt64? = nil, totalSize: UInt64? = nil) {
        self.path = path
        self.gitSize = gitSize
        self.totalSize = totalSize
    }
}

public enum GitRepoRanking {
    /// Biggest `.git` first; unmeasured repositories sink to the bottom, ties break by path.
    public static func sorted(_ repos: [GitRepoInfo]) -> [GitRepoInfo] {
        repos.sorted { lhs, rhs in
            switch (lhs.gitSize, rhs.gitSize) {
            case let (l?, r?) where l != r: l > r
            case (.some, .none): true
            case (.none, .some): false
            default: lhs.path < rhs.path
            }
        }
    }

    /// The `limit` biggest repositories.
    public static func top(_ repos: [GitRepoInfo], limit: Int) -> [GitRepoInfo] {
        Array(sorted(repos).prefix(max(limit, 0)))
    }

    public static func totalGitSize(_ repos: [GitRepoInfo]) -> UInt64 {
        repos.reduce(0) { $0 &+ ($1.gitSize ?? 0) }
    }
}

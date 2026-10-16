import Foundation

public struct FileNode: Identifiable, Sendable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case directory
        case file
        /// Many small entries folded into one tile to keep the tree compact.
        case aggregate
        /// A directory the scanner was not allowed to read.
        case restricted
    }

    public let path: String
    /// Only aggregate tiles ("12 smaller items") need a stored label; everything else derives its
    /// name from the path, which halves string memory for large scans.
    private let label: String?
    public let kind: Kind
    public let size: UInt64
    public let itemCount: Int
    public let modified: Date?
    public let isHidden: Bool
    public let isGitRepo: Bool
    public let children: [FileNode]

    public var name: String { label ?? (path == "/" ? "/" : (path as NSString).lastPathComponent) }
    public var id: String { kind == .aggregate ? path + "/\u{2026}" : path }
    public var isDirectory: Bool { kind == .directory }
    public var parentPath: String { (path as NSString).deletingLastPathComponent }

    public init(
        path: String,
        name: String,
        kind: Kind,
        size: UInt64,
        itemCount: Int = 1,
        modified: Date? = nil,
        isHidden: Bool = false,
        isGitRepo: Bool = false,
        children: [FileNode] = []
    ) {
        self.path = path
        let derived = (path as NSString).lastPathComponent
        self.label = kind == .aggregate || (!name.isEmpty && name != derived) ? name : nil
        self.kind = kind
        self.size = size
        self.itemCount = itemCount
        self.modified = modified
        self.isHidden = isHidden
        self.isGitRepo = isGitRepo
        self.children = children
    }

    public func node(at target: String) -> FileNode? {
        if target == path { return kind == .aggregate ? nil : self }
        let prefix = path == "/" ? "/" : path + "/"
        guard kind == .directory, target.hasPrefix(prefix) else { return nil }
        for child in children {
            if let found = child.node(at: target) { return found }
        }
        return nil
    }

    /// Returns a copy with the given paths removed and every ancestor's size reduced to match.
    public func removing(_ paths: Set<String>) -> FileNode {
        guard kind == .directory, !paths.isEmpty else { return self }
        let prefix = path == "/" ? "/" : path + "/"
        let relevant = paths.filter { $0.hasPrefix(prefix) }
        guard !relevant.isEmpty else { return self }

        var kept: [FileNode] = []
        var removedSize: UInt64 = 0
        var removedCount = 0
        for child in children {
            if child.kind != .aggregate, relevant.contains(child.path) {
                removedSize += child.size
                removedCount += child.itemCount
                continue
            }
            let updated = child.removing(relevant)
            removedSize += child.size - updated.size
            removedCount += child.itemCount - updated.itemCount
            kept.append(updated)
        }
        return FileNode(
            path: path, name: name, kind: kind,
            size: size - min(size, removedSize),
            itemCount: max(itemCount - removedCount, 0),
            modified: modified, isHidden: isHidden, isGitRepo: isGitRepo,
            children: kept.sorted { $0.size > $1.size }
        )
    }

    /// Depth-first walk; return false from `visit` to skip a node's descendants.
    public func walk(_ visit: (FileNode) -> Bool) {
        guard visit(self) else { return }
        for child in children { child.walk(visit) }
    }
}

extension FileNode {
    enum CodingKeys: String, CodingKey {
        case path, name, kind, size, itemCount, modified, isHidden, isGitRepo, children
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try c.decode(String.self, forKey: .path),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            kind: try c.decode(Kind.self, forKey: .kind),
            size: try c.decode(UInt64.self, forKey: .size),
            itemCount: try c.decode(Int.self, forKey: .itemCount),
            modified: try c.decodeIfPresent(Date.self, forKey: .modified),
            isHidden: try c.decode(Bool.self, forKey: .isHidden),
            isGitRepo: try c.decode(Bool.self, forKey: .isGitRepo),
            children: try c.decode([FileNode].self, forKey: .children)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(label, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(size, forKey: .size)
        try c.encode(itemCount, forKey: .itemCount)
        try c.encodeIfPresent(modified, forKey: .modified)
        try c.encode(isHidden, forKey: .isHidden)
        try c.encode(isGitRepo, forKey: .isGitRepo)
        try c.encode(children, forKey: .children)
    }
}

extension FileNode: Equatable {
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id && lhs.size == rhs.size && lhs.itemCount == rhs.itemCount
    }
}

extension FileNode: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(size)
    }
}

public enum PathTools {
    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
    }

    public static func hasHiddenComponent(_ path: String, below root: String) -> Bool {
        let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
        return relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}

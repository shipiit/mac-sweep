import Foundation
import os

/// Finds junk in seconds by measuring only the places the catalog points at, instead of scanning the whole disk.
/// The result is a small tree holding just those folders, so the same `CleanupEngine` rules and safety checks apply.
public enum QuickJunkScanner {
    private static let log = Logger(subsystem: Log.subsystem, category: "quick-junk")

    /// Folders that rules look into (or at), with descendants of other roots dropped.
    public static func roots(rules: [CleanupRule] = CleanupCatalog.rules, home: String) -> [String] {
        let raw = rules.flatMap { rule -> [String] in
            switch rule.target {
            case .paths(let paths): return paths
            case .contents(let dir, _), .files(let dir, _, _), .matching(let dir, _, _),
                 .olderVersions(let dir, _), .duplicateVersions(let dir): return [dir]
            // Only the named cache folders inside each app are measured, not the whole parent (often tens of GB).
            case .nested(let dir, let names, let signature): return nestedPaths(in: PathTools.expand(dir, home: home), names: names, signature: signature)
            case .named: return []
            }
        }
        let expanded = Set(raw.map { PathTools.expand($0, home: home) }).sorted()
        return expanded.filter { path in !expanded.contains { $0 != path && PathTools.isDescendant(path, of: $0) } }
    }

    static func nestedPaths(in dir: String, names: [String], signature: [String]) -> [String] {
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return apps.flatMap { app -> [String] in
            let base = dir + "/" + app
            guard signature.isEmpty || signature.contains(where: { FileManager.default.fileExists(atPath: base + "/" + $0) }) else { return [] }
            return names.map { base + "/" + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// Directory names that `.named` rules look for, found with a folder-only walk of home (no file sizes).
    public static func namedMatches(rules: [CleanupRule] = CleanupCatalog.rules, home: String, maxDepth: Int = 7) -> [String] {
        let patterns = rules.flatMap { rule -> [String] in
            if case .named(let names, _) = rule.target { return names }
            return []
        }
        guard !patterns.isEmpty else { return [] }
        let skipped: Set<String> = ["Library", ".Trash", ".git", "Pictures", "Music", "Movies"]
        var found: [String] = []
        func walk(_ dir: String, depth: Int) {
            guard depth <= maxDepth, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names where !skipped.contains(name) && !CleanupEngine.editorDirectories.contains(name) {
                let path = dir + "/" + name
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                      (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil else { continue }
                if patterns.contains(where: { path.hasSuffix("/" + $0) }) {
                    found.append(path)
                } else if name != "node_modules" {
                    autoreleasepool { walk(path, depth: depth + 1) }
                }
            }
        }
        walk(home, depth: 0)
        return found
    }

    /// Measures every root and match (a few at a time) and runs the catalog against the result.
    /// Project folders (node_modules, .venv, worktrees) are the slow part: ones changed recently can't match an
    /// idle-only rule so they're skipped, and unchanged ones reuse their size from the last scan.
    public static func scan(rules: [CleanupRule] = CleanupCatalog.rules, home: String = NSHomeDirectory(), now: Date = Date(),
                            cache: SizeCache? = .standard) async -> (items: [CleanupItem], tree: FileNode) {
        let started = Date()
        let roots = roots(rules: rules, home: home).filter { FileManager.default.fileExists(atPath: $0) }
        // Each match is skipped when it changed more recently than its own rule's idle period allows.
        let idleByPattern = rules.flatMap { rule -> [(String, Int?)] in
            if case .named(let names, let idle) = rule.target { return names.map { ($0, idle) } }
            return []
        }
        let named = namedMatches(rules: rules, home: home).filter { path in
            guard let days = idleByPattern.first(where: { path.hasSuffix("/" + $0.0) })?.1, days > 0 else { return true }
            return (modified(path).map { $0 < now.addingTimeInterval(-Double(days) * 86_400) }) ?? true
        }
        let stored = cache?.load() ?? [:]
        let rootNodes = await Concurrent.map(roots, limit: 4) { path -> FileNode? in
            autoreleasepool { DiskScanner.scanSubtree(path, options: ScanOptions(), progress: ScanProgress()).node }
        }
        let namedNodes = await Concurrent.map(named, limit: 8) { path -> FileNode? in
            let stamp = modified(path)
            if let stamp, let hit = stored[path], hit.modified == stamp {
                return FileNode(path: path, name: (path as NSString).lastPathComponent, kind: .directory, size: hit.size, modified: stamp)
            }
            return autoreleasepool { DiskScanner.scanSubtree(path, options: ScanOptions(), progress: ScanProgress()).node }
        }
        let measured = namedNodes.compactMap { $0 }
        try? cache?.save(Dictionary(measured.compactMap { node in modified(node.path).map { (node.path, SizeCache.Entry(size: node.size, modified: $0)) } },
                                    uniquingKeysWith: { first, _ in first }))
        let tree = assemble(at: home, nodes: rootNodes.compactMap { $0 } + measured)
        let items = CleanupEngine.evaluate(rules: rules, tree: tree, home: home, now: now, sizeOf: { _ in nil })
        log.info("Quick junk scan: \(roots.count) locations, \(named.count) project folders in \(Int(Date().timeIntervalSince(started)))s")
        return (items, tree)
    }

    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Joins scanned subtrees into one tree rooted at `path`, adding the folders between them.
    static func assemble(at path: String, nodes: [FileNode]) -> FileNode {
        if let exact = nodes.first(where: { $0.path == path }) { return exact }
        let prefix = path == "/" ? "/" : path + "/"
        var groups: [String: [FileNode]] = [:]
        for node in nodes where node.path.hasPrefix(prefix) {
            let first = node.path.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? ""
            groups[prefix + first, default: []].append(node)
        }
        let children = groups.map { assemble(at: $0.key, nodes: $0.value) }.sorted { $0.size > $1.size }
        return FileNode(path: path, name: (path as NSString).lastPathComponent, kind: .directory,
                        size: children.reduce(0) { $0 + $1.size }, itemCount: children.reduce(0) { $0 + $1.itemCount },
                        modified: children.compactMap(\.modified).max(), children: children)
    }
}

/// Sizes of project folders from the last quick scan, reused while a folder's modification date is unchanged.
public struct SizeCache: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let size: UInt64
        public let modified: Date
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: SizeCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return SizeCache(url: base.appendingPathComponent("MacSweep/folder-sizes.json"))
    }

    public func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    public func save(_ entries: [String: Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}

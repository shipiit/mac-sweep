import Foundation

public enum ProjectActivity: String, Sendable, CaseIterable {
    case active = "Active"
    case idle = "Idle"
    case stale = "Stale"

    /// Active within a month, idle within three, stale beyond that (or never dated).
    public static func classify(lastModified: Date?, now: Date) -> ProjectActivity {
        guard let lastModified else { return .stale }
        let days = now.timeIntervalSince(lastModified) / 86_400
        if days < 30 { return .active }
        if days < 90 { return .idle }
        return .stale
    }
}

public struct NodeModulesFolder: Sendable, Equatable, Identifiable {
    public let path: String
    public var size: UInt64?

    public var id: String { path }

    public init(path: String, size: UInt64? = nil) {
        self.path = path
        self.size = size
    }
}

public struct NodeProject: Sendable, Equatable, Identifiable {
    public let root: String
    public var folders: [NodeModulesFolder]
    public var lastModified: Date?

    public var id: String { root }
    public var name: String { (root as NSString).lastPathComponent }
    public var totalSize: UInt64 { folders.reduce(0) { $0 + ($1.size ?? 0) } }
    public var isMeasured: Bool { folders.allSatisfy { $0.size != nil } }

    public init(root: String, folders: [NodeModulesFolder], lastModified: Date? = nil) {
        self.root = root
        self.folders = folders
        self.lastModified = lastModified
    }
}

public enum NodeModulesFinder {
    /// The whole home folder: projects live anywhere. Media, Library and bundles are skipped during the walk.
    public static func defaultRoots(home: String) -> [String] { [home] }

    static let skippedNames: Set<String> = ["Library", "Applications", "Pods", "DerivedData", "build", "dist", "vendor", "target",
                                            "Pictures", "Music", "Movies", "Public", ".Trash"]
    static let skippedExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "bundle", "framework", "xcarchive"]

    /// Walks each root to `maxDepth`, never descending into hidden folders or into a node_modules it found.
    public static func find(roots: [String], maxDepth: Int = 6, fileManager: FileManager = .default) -> [String] {
        var found: [String] = []
        var visited = Set<String>()
        func walk(_ directory: String, depth: Int) {
            guard depth <= maxDepth, visited.insert(directory).inserted else { return }
            let names = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for name in names where !name.hasPrefix(".") && !skippedNames.contains(name)
                && !skippedExtensions.contains((name as NSString).pathExtension.lowercased()) {
                let path = directory + "/" + name
                guard isRealDirectory(path, fileManager: fileManager) else { continue }
                if name == "node_modules" {
                    found.append(path)
                } else {
                    walk(path, depth: depth + 1)
                }
            }
        }
        for root in roots where isRealDirectory(root, fileManager: fileManager) { walk(root, depth: 0) }
        return found.sorted()
    }

    /// Symlinked folders are skipped so pnpm/yarn links and loops aren't counted twice.
    static func isRealDirectory(_ path: String, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    /// Groups node_modules folders under the nearest enclosing git repository; folders outside
    /// any repository form a project of their own parent folder.
    public static func group(_ folders: [String], gitRoots: Set<String>) -> [NodeProject] {
        var projects: [String: [NodeModulesFolder]] = [:]
        for folder in folders {
            let parent = (folder as NSString).deletingLastPathComponent
            let root = nearestRoot(of: parent, in: gitRoots) ?? parent
            projects[root, default: []].append(NodeModulesFolder(path: folder))
        }
        return projects.map { NodeProject(root: $0.key, folders: $0.value.sorted { $0.path < $1.path }) }
            .sorted { $0.root < $1.root }
    }

    static func nearestRoot(of path: String, in roots: Set<String>) -> String? {
        var current = path
        while current.count > 1 {
            if roots.contains(current) { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Ancestors of each folder that contain a `.git` entry.
    public static func gitRoots(for folders: [String], fileManager: FileManager = .default) -> Set<String> {
        var roots = Set<String>()
        var checked = Set<String>()
        for folder in folders {
            var current = (folder as NSString).deletingLastPathComponent
            while current.count > 1, checked.insert(current).inserted {
                if fileManager.fileExists(atPath: current + "/.git") { roots.insert(current) }
                current = (current as NSString).deletingLastPathComponent
            }
        }
        return roots
    }

    /// Biggest first; unmeasured projects sink to the bottom.
    public static func sorted(_ projects: [NodeProject]) -> [NodeProject] {
        projects.sorted { lhs, rhs in
            lhs.totalSize != rhs.totalSize ? lhs.totalSize > rhs.totalSize : lhs.root < rhs.root
        }
    }

    /// When the project's own files last changed: the newest of package.json, lockfiles and the folder itself.
    public static func lastModified(project root: String, fileManager: FileManager = .default) -> Date? {
        let markers = ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", ".git/HEAD", ".git/index", ""]
        return markers.compactMap { marker -> Date? in
            let path = marker.isEmpty ? root : root + "/" + marker
            return (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }.max()
    }
}

import Foundation

/// Finds git repositories with a bounded, folder-only walk. Files are never opened; only directory listings are read.
public enum GitRepoFinder {
    public static let defaultMaxDepth = 7

    static let skippedNames: Set<String> = [
        "Library", "Applications", "Pictures", "Music", "Movies", "Public", ".Trash",
        "node_modules", "Pods", "DerivedData", ".build",
        ".vscode", ".vscode-insiders", ".cursor", ".windsurf", ".idea", ".zed",
        ".npm", ".pnpm-store", ".cache", ".cargo", ".rustup", ".gradle", ".m2", ".docker", ".Spotlight-V100",
    ]
    static let skippedExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "bundle", "framework", "xcarchive"]

    /// Folders that hold a `.git` directory, sorted by path. A repository is never descended into,
    /// so nested repositories and submodules are not reported separately.
    public static func find(roots: [String], maxDepth: Int = defaultMaxDepth, fileManager: FileManager = .default) -> [String] {
        var found: [String] = []
        var visited = Set<String>()
        func walk(_ directory: String, depth: Int) {
            guard depth <= maxDepth, visited.insert(directory).inserted else { return }
            if isRealDirectory(directory + "/.git", fileManager: fileManager) {
                found.append(directory)
                return
            }
            let names = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            for name in names where !isSkipped(name) {
                let path = directory + "/" + name
                if isRealDirectory(path, fileManager: fileManager) { walk(path, depth: depth + 1) }
            }
        }
        for root in roots where isRealDirectory(root, fileManager: fileManager) { walk(root, depth: 0) }
        return found.sorted()
    }

    static func isSkipped(_ name: String) -> Bool {
        name == ".git" || skippedNames.contains(name) || skippedExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Symlinked folders are skipped so links and loops aren't walked twice.
    static func isRealDirectory(_ path: String, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    /// Another git process holds the index; running git now could fail or contend with it.
    public static func isInUse(repo: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: repo + "/.git/index.lock")
    }
}

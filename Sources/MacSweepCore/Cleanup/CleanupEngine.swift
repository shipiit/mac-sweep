import Foundation

public enum CleanupEngine {
    static let editorDirectories = [".vscode", ".vscode-insiders", ".cursor", ".windsurf", ".trae", ".kiro", ".antigravity", ".vscode-oss"]

    /// Matches the catalog against a scanned tree. Each byte is claimed by at most one rule.
    /// `sizeOf` measures paths that are absent from the tree (outside the scan root or pruned).
    public static func evaluate(
        rules: [CleanupRule] = CleanupCatalog.rules,
        tree: FileNode,
        home: String,
        now: Date = Date(),
        sizeOf: (String) -> UInt64? = { _ in nil },
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [CleanupItem] {
        var claimed: [String] = []
        var items: [CleanupItem] = []

        func isClaimed(_ path: String) -> Bool {
            claimed.contains { path == $0 || PathTools.isDescendant(path, of: $0) || PathTools.isDescendant($0, of: path) }
        }

        for rule in rules {
            let candidates = targets(for: rule.target, tree: tree, home: home, now: now, sizeOf: sizeOf, pathExists: pathExists)
            let accepted = candidates.filter { $0.size > 0 && !isClaimed($0.path) }
            claimed.append(contentsOf: accepted.map(\.path))
            if !accepted.isEmpty {
                items.append(CleanupItem(rule: rule, targets: accepted.sorted { $0.size > $1.size }))
            }
        }
        return items
    }

    static func targets(
        for spec: CleanupTargetSpec, tree: FileNode, home: String, now: Date,
        sizeOf: (String) -> UInt64?, pathExists: (String) -> Bool
    ) -> [CleanupTarget] {
        switch spec {
        case .paths(let paths):
            return paths.compactMap { raw in
                let path = PathTools.expand(raw, home: home)
                if let node = tree.node(at: path) {
                    return CleanupTarget(path: path, size: node.size, modified: node.modified)
                }
                return sizeOf(path).map { CleanupTarget(path: path, size: $0) }
            }

        case .contents(let raw, let excluding):
            let path = PathTools.expand(raw, home: home)
            guard let node = tree.node(at: path) else { return [] }
            return node.children
                .filter { $0.kind == .directory || $0.kind == .file }
                .filter { !excluding.contains($0.name) }
                .map { CleanupTarget(path: $0.path, size: $0.size, modified: $0.modified) }

        case .named(let patterns, let idleDays):
            var found: [CleanupTarget] = []
            // Editors ship prebuilt build output inside their extensions; those can't be regenerated.
            let skipped = [home + "/Library", home + "/.Trash"] + editorDirectories.map { home + "/" + $0 }
            let cutoff = idleDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
            tree.walk { node in
                guard node.kind == .directory else { return false }
                let isSkipped = skipped.contains { node.path == $0 || PathTools.isDescendant(node.path, of: $0) }
                if isSkipped || node.name == ".git" || node.name == "extensions" || node.path.contains("/extensions/") || node.path.contains("/node_modules/") { return false }
                let matches = patterns.contains { node.path.hasSuffix("/" + $0) }
                guard matches else { return node.name != "node_modules" }
                if let cutoff, let modified = node.modified, modified > cutoff { return false }
                found.append(CleanupTarget(path: node.path, size: node.size, modified: node.modified))
                return false
            }
            return found

        case .nested(let raw, let names, let signature):
            let path = PathTools.expand(raw, home: home)
            guard let node = tree.node(at: path) else { return [] }
            return node.children
                .filter(\.isDirectory)
                .filter { app in signature.isEmpty || signature.contains { pathExists(app.path + "/" + $0) } }
                .flatMap { app in app.children.filter { $0.isDirectory && names.contains($0.name) } }
                .map { CleanupTarget(path: $0.path, size: $0.size, modified: $0.modified) }

        case .files(let raw, let extensions, let olderThanDays):
            let path = PathTools.expand(raw, home: home)
            guard let node = tree.node(at: path) else { return [] }
            let cutoff = olderThanDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
            return node.children
                .filter { $0.kind == .file }
                .filter { extensions.contains(($0.name as NSString).pathExtension.lowercased()) }
                .filter { file in
                    guard let cutoff, let modified = file.modified else { return true }
                    return modified < cutoff
                }
                .map { CleanupTarget(path: $0.path, size: $0.size, modified: $0.modified) }
        }
    }
}

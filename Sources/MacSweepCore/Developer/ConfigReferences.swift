import Foundation

/// Finds which names (database names, for instance) appear in your projects' config files,
/// so MacSweep can tell a database a project uses from a forgotten one.
public enum ConfigReferences {
    static let skippedFolders: Set<String> = ["Library", ".Trash", "node_modules", ".git", ".venv", "venv", "build", "dist",
                                              ".cache", ".npm", ".pnpm-store", ".nvm", ".pyenv", ".rustup", ".cargo", "Pods",
                                              "DerivedData", ".next", "__pycache__", "Movies", "Music", "Pictures"]
    static let maxFileSize = 256 * 1024

    /// Config-like files only: env files, settings modules, compose and other YAML/TOML/INI files.
    public static func isConfigFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix(".env") || lower == "database.yml" || lower == "alembic.ini" { return true }
        if lower.hasSuffix(".py") { return lower.hasPrefix("settings") || lower.hasPrefix("config") || lower == "base.py" || lower == "local.py" }
        return [".yml", ".yaml", ".toml", ".ini", ".properties", ".conf"].contains { lower.hasSuffix($0) }
    }

    /// Words made of letters, digits and underscores, the shape of a database name inside a URL or setting.
    public static func words(in text: String) -> Set<String> {
        var result = Set<String>()
        var current = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { result.insert(current) }
        return result
    }

    /// Maps each of `names` to the config files (relative to `home`) that mention it as a whole word.
    public static func find(_ names: Set<String>, home: String = NSHomeDirectory(), maxDepth: Int = 7) -> [String: [String]] {
        guard !names.isEmpty else { return [:] }
        var found: [String: [String]] = [:]
        func walk(_ directory: String, depth: Int) {
            guard depth <= maxDepth, let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
            for entry in entries {
                let path = directory + "/" + entry
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    if !skippedFolders.contains(entry), !(depth == 0 && entry.hasPrefix(".") && entry != ".config") {
                        autoreleasepool { walk(path, depth: depth + 1) }
                    }
                } else if isConfigFile(entry), let text = read(path) {
                    let relative = String(path.dropFirst(home.count + 1))
                    for name in names.intersection(words(in: text)) { found[name, default: []].append(relative) }
                }
            }
        }
        walk(home, depth: 0)
        return found.mapValues { $0.sorted() }
    }

    private static func read(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= maxFileSize,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

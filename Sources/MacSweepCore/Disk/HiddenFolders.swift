import Foundation

/// A folder most people never see: a dot-folder in home, or a big folder deep in ~/Library.
public struct HiddenFolder: Sendable, Equatable, Identifiable {
    public let path: String
    public let size: UInt64
    public let summary: String?
    public let ifDeleted: String?
    public let risk: DeletionRisk?
    public var id: String { path }
}

/// A database server's data folder under Homebrew, with whether its server is running.
public struct DatabaseDataFolder: Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public let size: UInt64
    public let isRunning: Bool
    public var id: String { path }
}

public enum HiddenFolders {
    /// Library folders whose children are listed one by one (the rest of Library is measured as a whole elsewhere).
    static let libraryParents = ["Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
                                 "Library/Developer", "Library/Logs"]

    /// Every hidden folder in home plus the children of the big Library folders.
    public static func candidates(home: String = NSHomeDirectory()) -> [String] {
        let fileManager = FileManager.default
        let dotFolders = ((try? fileManager.contentsOfDirectory(atPath: home)) ?? [])
            .filter { $0.hasPrefix(".") && $0 != ".Trash" && $0 != ".DS_Store" }
            .map { home + "/" + $0 }
        let libraryChildren = libraryParents.flatMap { parent -> [String] in
            let base = home + "/" + parent
            return ((try? fileManager.contentsOfDirectory(atPath: base)) ?? []).filter { $0 != ".DS_Store" }.map { base + "/" + $0 }
        }
        return (dotFolders + libraryChildren).filter { path in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Measures candidates a few at a time and keeps the biggest, each with what it is and what deleting it does.
    public static func largest(home: String = NSHomeDirectory(), limit: Int = 40, minimum: UInt64 = 50_000_000,
                               measure: @escaping @Sendable (String) -> UInt64? = { DiskScanner.measure($0) }) async -> [HiddenFolder] {
        let sized = await Concurrent.map(candidates(home: home), limit: 4) { path -> (String, UInt64) in
            autoreleasepool { (path, measure(path) ?? 0) }
        }
        return sized.filter { $0.1 >= minimum }.sorted { $0.1 > $1.1 }.prefix(limit).map { path, size in
            let explanation = ImpactKnowledge.explain(path: path, home: home)
            return HiddenFolder(path: path, size: size, summary: explanation?.summary ?? FolderKnowledge.describe(path: path, home: home),
                                ifDeleted: explanation?.ifDeleted, risk: explanation?.risk)
        }
    }

    /// Postgres, MySQL and Redis data folders under Homebrew's var/.
    public static func databaseFolders(brewPrefix: String?, running: [PostgresServer], measure: (String) -> UInt64? = { DiskScanner.measure($0) }) -> [DatabaseDataFolder] {
        guard let brewPrefix else { return [] }
        let base = brewPrefix + "/var"
        let runningDirectories = Set(running.map { ($0.dataDirectory as NSString).standardizingPath })
        return ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [])
            .filter(isDatabaseFolderName)
            .map { name in
                let path = base + "/" + name
                return DatabaseDataFolder(name: name, path: path, size: measure(path) ?? 0, isRunning: runningDirectories.contains(path))
            }
            .sorted { $0.size > $1.size }
    }

    static func isDatabaseFolderName(_ name: String) -> Bool {
        name.hasPrefix("postgres") || name.hasPrefix("mysql") || name == "redis" || name.hasPrefix("mongodb")
    }

    /// Why a data folder can't be moved to the Trash, or nil when it can: only a stopped server's own folder under Homebrew's var/.
    public static func trashRefusal(_ folder: DatabaseDataFolder, brewPrefix: String?) -> String? {
        guard let brewPrefix, (folder.path as NSString).standardizingPath == brewPrefix + "/var/" + folder.name,
              isDatabaseFolderName(folder.name), !folder.name.contains("/") else { return "Not a database data folder." }
        if folder.isRunning { return "Its server is running. Stop it first." }
        // Postgres leaves postmaster.pid behind only while running or after a crash; either way, don't touch it.
        if FileManager.default.fileExists(atPath: folder.path + "/postmaster.pid") { return "It looks like the server is running or didn't shut down cleanly." }
        return nil
    }

    /// Moves a stopped server's data folder to the Trash (recoverable until the Trash is emptied).
    public static func trash(_ folder: DatabaseDataFolder, brewPrefix: String?) throws {
        if let reason = trashRefusal(folder, brewPrefix: brewPrefix) { throw DevCommandError.failed(reason) }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: folder.path), resultingItemURL: nil)
    }
}

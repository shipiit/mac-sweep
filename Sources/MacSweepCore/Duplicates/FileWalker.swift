import Darwin
import Foundation

/// One regular file seen during a walk, described by lstat (symlinks are never followed).
public struct FileStat: Sendable, Equatable, Hashable {
    public let path: String
    /// Logical size in bytes (what hashing reads).
    public let size: UInt64
    public let device: Int32
    public let inode: UInt64
    public let modified: Date
    public let created: Date

    public init(path: String, size: UInt64, device: Int32, inode: UInt64, modified: Date, created: Date) {
        self.path = path
        self.size = size
        self.device = device
        self.inode = inode
        self.modified = modified
        self.created = created
    }

    /// Re-reads the file; nil when it is gone or no longer a plain file.
    public static func current(_ path: String) -> FileStat? {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileStat(path: path, info: info)
    }

    init(path: String, info: stat) {
        self.init(
            path: path, size: UInt64(max(info.st_size, 0)), device: info.st_dev, inode: UInt64(info.st_ino),
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
            created: Date(timeIntervalSince1970: TimeInterval(info.st_birthtimespec.tv_sec))
        )
    }

    /// True when the file on disk is still the exact one that was scanned.
    public func isUnchanged(comparedTo other: FileStat) -> Bool {
        size == other.size && device == other.device && inode == other.inode && modified == other.modified
    }
}

public struct WalkOptions: Sendable {
    public var skipsHidden = true
    /// Folders never descended into: regenerable build output and VCS internals.
    public var excludedDirectoryNames: Set<String> = ["node_modules", ".build", "DerivedData", "Pods", ".git"]
    /// Bundles treated as one opaque item (never descended into).
    public var packageExtensions: Set<String> = [
        "app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
        "logicx", "bundle", "framework", "plugin", "kext", "pkg", "xcarchive", "xcodeproj", "xcworkspace",
        "aplibrary", "migratedphotolibrary", "band", "rtfd", "pages", "numbers", "key",
    ]
    /// Files smaller than this are ignored. Always at least 1, so empty files never match.
    public var minimumSize: UInt64 = 1
    /// Lower-cased extensions to keep; nil keeps every file.
    public var allowedExtensions: Set<String>?

    public init() {}
}

public struct WalkStats: Sendable, Equatable {
    public var filesSeen = 0
    /// iCloud placeholders whose content is not on this Mac; reading them would download them.
    public var skippedCloudOnly = 0
    /// Folders or files the walk could not read.
    public var unreadable = 0

    public init() {}
}

/// Synchronous fts walk shared by the duplicate and photo finders.
enum FileWalker {
    static let datalessFlag = UInt32(SF_DATALESS)

    /// Calls `visit` for every eligible regular file; stops early when `visit` returns false or the task is cancelled.
    static func walk(
        roots: [String], options: WalkOptions, stats: inout WalkStats, progress: FinderProgress? = nil, visit: (FileStat) -> Bool
    ) {
        guard !roots.isEmpty else { return }
        let cRoots = roots.map { strdup($0) }
        defer { cRoots.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = cRoots + [nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
        defer { fts_close(fts) }
        let minimum = max(options.minimumSize, 1)

        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let name = (path as NSString).lastPathComponent
            let isRoot = entry.pointee.fts_level == FTS_ROOTLEVEL
            let flags = entry.pointee.fts_statp?.pointee.st_flags ?? 0
            let hidden = name.hasPrefix(".") || (flags & UInt32(UF_HIDDEN)) != 0

            switch info {
            case FTS_D:
                if !isRoot, shouldSkipDirectory(path: path, name: name, hidden: hidden, options: options) {
                    fts_set(fts, entry, FTS_SKIP)
                }
            case FTS_F:
                stats.filesSeen += 1
                if stats.filesSeen % 500 == 0 {
                    progress?.seen(stats.filesSeen)
                    if Task.isCancelled { return }
                }
                guard !(options.skipsHidden && hidden), let statInfo = entry.pointee.fts_statp?.pointee else { continue }
                if (statInfo.st_flags & datalessFlag) != 0 {
                    stats.skippedCloudOnly += 1
                    continue
                }
                let file = FileStat(path: path, info: statInfo)
                guard file.size >= minimum else { continue }
                if let allowed = options.allowedExtensions, !allowed.contains((name as NSString).pathExtension.lowercased()) { continue }
                if !visit(file) { return }
            case FTS_DNR, FTS_ERR, FTS_NS:
                stats.unreadable += 1
            default:
                continue
            }
        }
    }

    private static func shouldSkipDirectory(path: String, name: String, hidden: Bool, options: WalkOptions) -> Bool {
        if options.skipsHidden && hidden { return true }
        if options.excludedDirectoryNames.contains(name) { return true }
        if options.packageExtensions.contains((name as NSString).pathExtension.lowercased()) { return true }
        let values = try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.isPackageKey])
        return values?.isPackage ?? false
    }
}

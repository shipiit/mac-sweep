import Darwin
import Foundation
import os

/// Walks a directory tree with fts(3): physical (no symlink following), never crossing volumes,
/// measuring allocated blocks so sparse files and clones are not over-reported.
public enum DiskScanner {
    private static let log = Logger(subsystem: Log.subsystem, category: "scanner")

    public static func scan(root: String, options: ScanOptions? = nil, progress: ScanProgress = ScanProgress()) async -> ScanResult {
        let started = Date()
        let options = options ?? .forRoot(root)
        let rootName = root == "/" ? "Macintosh HD" : (root as NSString).lastPathComponent
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        let childPaths = entries
            .map { root == "/" ? "/" + $0 : root + "/" + $0 }
            .filter { !options.excludedPaths.contains($0) }

        let hardLinks = HardLinkRegistry()
        let limiter = AsyncLimiter(limit: options.maxConcurrentWalkers)
        let rootDevice = device(of: root)
        let parts = await withTaskGroup(of: SubtreeResult.self) { group in
            for path in childPaths {
                group.addTask {
                    await scanSplitting(path, depth: options.splitDepth, device: rootDevice, options: options, progress: progress, hardLinks: hardLinks, limiter: limiter)
                }
            }
            var collected: [SubtreeResult] = []
            for await part in group { collected.append(part) }
            return collected
        }

        let children = parts.compactMap(\.node).sorted { $0.size > $1.size }
        let rootNode = FileNode(
            path: root, name: rootName, kind: .directory,
            size: children.reduce(0) { $0 + $1.size },
            itemCount: children.reduce(0) { $0 + $1.itemCount },
            modified: modificationDate(root),
            children: children
        )
        let largeFiles = parts.flatMap(\.largeFiles).sorted { $0.size > $1.size }.prefix(options.maxLargeFiles)
        let restricted = parts.reduce(0) { $0 + $1.restricted }
        let duration = Date().timeIntervalSince(started)
        log.info("scan of \(root, privacy: .public) finished: \(rootNode.size) bytes, \(rootNode.itemCount) files, \(restricted) restricted, \(duration)s")
        return ScanResult(root: rootNode, largeFiles: Array(largeFiles), restrictedCount: restricted, duration: duration, finishedAt: Date())
    }

    /// Allocated size of a single path (file or directory), for measuring things outside a scan.
    public static func measure(_ path: String) -> UInt64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return scanSubtree(path, options: ScanOptions(), progress: ScanProgress()).node?.size
    }

    /// Shared across parallel jobs so a hard-linked file is counted once per scan.
    final class HardLinkRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<UInt64>()

        func insert(_ key: UInt64) -> Bool {
            lock.withLock { seen.insert(key).inserted }
        }
    }

    struct SubtreeResult: Sendable {
        var node: FileNode?
        var largeFiles: [FileNode] = []
        var restricted = 0
    }

    final class DirBuilder {
        let path: String
        let modified: Date?
        let isHidden: Bool
        var size: UInt64
        var count = 0
        var kids: [FileNode] = []
        var otherSize: UInt64 = 0
        var otherCount = 0
        var isGitRepo = false

        init(path: String, size: UInt64, modified: Date?, isHidden: Bool) {
            self.path = path
            self.size = size
            self.modified = modified
            self.isHidden = isHidden
        }

        func add(_ node: FileNode, minSize: UInt64) {
            size += node.size
            count += node.itemCount
            if node.size >= minSize || node.kind == .restricted {
                kids.append(node)
            } else {
                otherSize += node.size
                otherCount += node.itemCount
            }
        }

        func addSmallFile(size fileSize: UInt64) {
            size += fileSize
            count += 1
            otherSize += fileSize
            otherCount += 1
        }

        func build() -> FileNode {
            var children = kids
            if otherSize > 0 {
                children.append(FileNode(
                    path: path, name: "\(otherCount) smaller items", kind: .aggregate,
                    size: otherSize, itemCount: otherCount
                ))
            }
            children.sort { $0.size > $1.size }
            return FileNode(
                path: path, name: (path as NSString).lastPathComponent, kind: .directory,
                size: size, itemCount: count, modified: modified, isHidden: isHidden,
                isGitRepo: isGitRepo, children: children
            )
        }
    }

    static func scanSubtree(
        _ path: String, options: ScanOptions, progress: ScanProgress, hardLinks: HardLinkRegistry = HardLinkRegistry()
    ) -> SubtreeResult {
        var result = SubtreeResult()
        var stack: [DirBuilder] = []
        var pendingFiles = 0
        var pendingBytes: UInt64 = 0

        guard let cPath = strdup(path) else { return result }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return result }
        defer { fts_close(fts) }

        func attach(_ node: FileNode) {
            if let parent = stack.last {
                parent.add(node, minSize: options.minNodeSize)
            } else {
                result.node = node
            }
        }

        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            let entryPath = String(cString: entry.pointee.fts_path)
            let stat = entry.pointee.fts_statp?.pointee
            let name = (entryPath as NSString).lastPathComponent
            let hidden = name.hasPrefix(".") || ((stat?.st_flags ?? 0) & UInt32(UF_HIDDEN)) != 0
            let modified = stat.map { Date(timeIntervalSince1970: TimeInterval($0.st_mtimespec.tv_sec)) }
            let allocated = stat.map { UInt64(max($0.st_blocks, 0)) * 512 } ?? 0

            switch info {
            case FTS_D:
                if options.excludedPaths.contains(entryPath) {
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                if name == ".git", let parent = stack.last { parent.isGitRepo = true }
                stack.append(DirBuilder(path: entryPath, size: allocated, modified: modified, isHidden: hidden))
            case FTS_DP:
                guard let builder = stack.popLast() else { continue }
                attach(builder.build())
            case FTS_DNR, FTS_ERR:
                // fts reports the preorder FTS_D first, then DNR in place of the postorder visit.
                if stack.last?.path == entryPath { stack.removeLast() }
                result.restricted += 1
                attach(FileNode(path: entryPath, name: name, kind: .restricted, size: 0, itemCount: 0, modified: modified, isHidden: hidden))
            case FTS_DC:
                continue
            default:
                if let stat, stat.st_nlink > 1 {
                    let key = UInt64(UInt32(bitPattern: stat.st_dev)) << 40 ^ UInt64(stat.st_ino)
                    if !hardLinks.insert(key) { continue }
                }
                pendingFiles += 1
                pendingBytes += allocated
                let isLarge = allocated >= options.minNodeSize || stack.isEmpty
                if isLarge {
                    let node = FileNode(path: entryPath, name: name, kind: .file, size: allocated, modified: modified, isHidden: hidden)
                    if allocated >= options.largeFileThreshold { result.largeFiles.append(node) }
                    attach(node)
                } else if let parent = stack.last {
                    parent.addSmallFile(size: allocated)
                }
            }

            if pendingFiles >= 2_000 {
                progress.add(files: pendingFiles, bytes: pendingBytes, currentPath: entryPath)
                pendingFiles = 0
                pendingBytes = 0
                if Task.isCancelled { break }
            }
        }
        progress.add(files: pendingFiles, bytes: pendingBytes, currentPath: path)
        // On cancellation unwind any open directories so callers still get a consistent partial tree.
        while let builder = stack.popLast() { attach(builder.build()) }
        if result.largeFiles.count > options.maxLargeFiles {
            result.largeFiles = Array(result.largeFiles.sorted { $0.size > $1.size }.prefix(options.maxLargeFiles))
        }
        return result
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

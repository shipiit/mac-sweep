import Darwin
import Foundation

extension DiskScanner {
    /// Scans `path`, fanning its children out as concurrent jobs while `depth` > 0, then walking
    /// each job's subtree sequentially with fts. Results are identical to a single sequential walk.
    static func scanSplitting(
        _ path: String, depth: Int, device: dev_t?, options: ScanOptions, progress: ScanProgress,
        hardLinks: HardLinkRegistry, limiter: AsyncLimiter
    ) async -> SubtreeResult {
        guard depth > 0, !Task.isCancelled, let info = plainDirectoryStat(path),
              device == nil || info.st_dev == device,
              !options.excludedPaths.contains(path),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: path)
        else {
            await limiter.acquire()
            let result = scanSubtree(path, options: options, progress: progress, hardLinks: hardLinks)
            await limiter.release()
            return result
        }

        let parts = await withTaskGroup(of: SubtreeResult.self) { group in
            for entry in entries {
                let child = path + "/" + entry
                group.addTask { await scanSplitting(child, depth: depth - 1, device: info.st_dev, options: options, progress: progress, hardLinks: hardLinks, limiter: limiter) }
            }
            var collected: [SubtreeResult] = []
            for await part in group { collected.append(part) }
            return collected
        }

        let name = (path as NSString).lastPathComponent
        let builder = DirBuilder(
            path: path,
            size: UInt64(max(info.st_blocks, 0)) * 512,
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
            isHidden: name.hasPrefix(".") || (info.st_flags & UInt32(UF_HIDDEN)) != 0
        )
        var result = SubtreeResult()
        for part in parts {
            if let node = part.node {
                if node.name == ".git", node.kind == .directory { builder.isGitRepo = true }
                builder.add(node, minSize: options.minNodeSize)
            }
            result.largeFiles += part.largeFiles
            result.restricted += part.restricted
        }
        result.node = builder.build()
        return result
    }

    /// lstat that only succeeds for real directories (symlinks and files return nil).
    static func plainDirectoryStat(_ path: String) -> stat? {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return info
    }

    static func device(of path: String) -> dev_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_dev : nil
    }
}

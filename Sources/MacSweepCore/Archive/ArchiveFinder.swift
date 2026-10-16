import Darwin
import Foundation
import os

/// Finds idle project folders and big idle folders worth zipping onto another drive.
public enum ArchiveFinder {
    private static let log = Logger(subsystem: Log.subsystem, category: "archive")

    public struct Discovered: Sendable, Equatable {
        public let path: String
        public let markers: [String]
    }

    public static func defaultRoots(home: String) -> [String] {
        ["Documents", "Downloads", "Desktop", "Developer", "Projects", "Code", "src", "repos"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    public static func find(
        roots: [String], home: String = NSHomeDirectory(), criteria: ArchiveCriteria = ArchiveCriteria(),
        now: Date = Date(), progress: FinderProgress = FinderProgress()
    ) async throws -> [ArchiveCandidate] {
        progress.begin(.listing, total: 0)
        let found = discover(roots: ScanRoots.resolve(roots, home: home).accepted)
        try Task.checkCancellation()
        progress.begin(.measuring, total: found.count)
        let facts = await Concurrent.map(found, limit: 3) { folder -> FolderFacts? in
            defer { progress.step() }
            return Task.isCancelled ? nil : survey(folder.path, markers: folder.markers)
        }
        try Task.checkCancellation()
        let candidates = ArchivePolicy.select(facts.compactMap { $0 }, criteria: criteria, now: now)
        log.info("archive scan: \(found.count) folders measured, \(candidates.count) candidates")
        return candidates
    }

    /// Every project (stopping at the first marker on each branch) plus every top-level folder of each root.
    public static func discover(roots: [String], maxDepth: Int = 4) -> [Discovered] {
        var found: [Discovered] = []

        func visit(_ directory: String, depth: Int) {
            guard depth <= maxDepth, !Task.isCancelled else { return }
            for child in subdirectories(of: directory) {
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: child)) ?? []
                let markers = ProjectMarkers.detect(entries: entries)
                if !markers.isEmpty {
                    found.append(Discovered(path: child, markers: markers))
                    continue
                }
                if depth == 1 { found.append(Discovered(path: child, markers: [])) }
                visit(child, depth: depth + 1)
            }
        }

        for root in roots { visit(root, depth: 1) }
        return found
    }

    private static func subdirectories(of directory: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let skipped = WalkOptions().packageExtensions
        return names.sorted().compactMap { name in
            guard !name.hasPrefix("."), !ProjectMarkers.buildFolderNames.contains(name),
                  !skipped.contains((name as NSString).pathExtension.lowercased()) else { return nil }
            let path = directory + "/" + name
            return DiskScanner.plainDirectoryStat(path) == nil ? nil : path
        }
    }

    /// Walks one folder: size, file count, newest change, build folders and a compressed-size estimate.
    public static func survey(_ path: String, markers: [String]) -> FolderFacts? {
        guard let cPath = strdup(path) else { return nil }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }

        var size: UInt64 = 0
        var files = 0
        var newest: Date?
        var builds: [CleanupTarget] = []
        var buckets: [CompressionEstimate.Kind: UInt64] = [:]
        var cloudOnly = 0
        let gitPrefix = path + "/.git"

        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            guard info != FTS_DP, let stat = entry.pointee.fts_statp?.pointee else { continue }
            let entryPath = String(cString: entry.pointee.fts_path)
            let name = (entryPath as NSString).lastPathComponent
            if info == FTS_D, entry.pointee.fts_level > FTS_ROOTLEVEL, ProjectMarkers.buildFolderNames.contains(name) {
                fts_set(fts, entry, FTS_SKIP)
                let buildSize = DiskScanner.measure(entryPath) ?? 0
                builds.append(CleanupTarget(path: entryPath, size: buildSize))
                size += buildSize
                continue
            }
            size += UInt64(max(stat.st_blocks, 0)) * 512
            if entryPath != gitPrefix, !entryPath.hasPrefix(gitPrefix + "/") {
                let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec))
                newest = max(newest ?? modified, modified)
            }
            guard info != FTS_D else { continue }
            files += 1
            if (stat.st_flags & FileWalker.datalessFlag) != 0 { cloudOnly += 1 }
            let kind = CompressionEstimate.kind(forExtension: (name as NSString).pathExtension)
            buckets[kind, default: 0] += UInt64(max(stat.st_size, 0))
            if files % 5_000 == 0, Task.isCancelled { return nil }
        }
        let estimate = CompressionEstimate.estimate(compressed: buckets[.compressed] ?? 0, text: buckets[.text] ?? 0, other: buckets[.other] ?? 0)
        return FolderFacts(path: path, markers: markers, size: size, fileCount: files, newestModification: newest,
                           buildFolders: builds, estimatedArchiveSize: estimate, cloudOnlyFiles: cloudOnly)
    }
}

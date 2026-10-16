import Foundation
import os

public struct DuplicateOptions: Sendable {
    public var walk = WalkOptions()
    /// Folders whose copies should be kept first.
    public var preferredFolders: [String] = []
    /// Files hashed at once. Hashing is disk-bound; a few readers saturate an SSD without starving the UI.
    public var concurrency = 4

    public init(minimumSize: UInt64 = 1024) {
        walk.minimumSize = minimumSize
    }
}

/// Finds byte-identical files: same size, then same first 64 KB, then same full SHA-256.
/// Each stage only reads files still tied with another, so most files are never opened.
public enum DuplicateFinder {
    private static let log = Logger(subsystem: Log.subsystem, category: "duplicates")

    public static func find(
        roots: [String], home: String = NSHomeDirectory(), options: DuplicateOptions = DuplicateOptions(),
        progress: FinderProgress = FinderProgress()
    ) async throws -> DuplicateScanResult {
        let started = Date()
        let resolution = ScanRoots.resolve(roots, home: home)
        progress.begin(.listing, total: 0)

        var stats = WalkStats()
        var bySize: [UInt64: [FileStat]] = [:]
        var inodes = Set<InodeKey>()
        var hardLinksSkipped = 0
        FileWalker.walk(roots: resolution.accepted, options: options.walk, stats: &stats, progress: progress) { file in
            guard inodes.insert(InodeKey(file)).inserted else {
                hardLinksSkipped += 1
                return true
            }
            bySize[file.size, default: []].append(file)
            return true
        }
        progress.seen(stats.filesSeen)
        try Task.checkCancellation()

        let sizeTied = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        bySize = [:]
        var unreadable = 0

        progress.begin(.comparingStarts, total: sizeTied.count)
        let heads = await hashAll(sizeTied, limit: options.concurrency, progress: progress) { try FileHasher.headHash($0.path) }
        try Task.checkCancellation()
        unreadable += heads.failed

        var confirmed: [[Hashed]] = []
        var needFull: [FileStat] = []
        for tie in tiedGroups(heads.hashed) {
            if tie[0].file.size <= UInt64(FileHasher.headLength) {
                confirmed.append(tie)
            } else {
                needFull += tie.map(\.file)
            }
        }

        progress.begin(.hashing, total: needFull.count)
        let fulls = await hashAll(needFull, limit: options.concurrency, progress: progress) { file in
            try FileHasher.fullHash(file.path) { progress.add(bytes: $0) }
        }
        try Task.checkCancellation()
        unreadable += fulls.failed
        confirmed += tiedGroups(fulls.hashed)

        progress.begin(.grouping, total: confirmed.count)
        let groups = confirmed.map { tie in
            DuplicateGroup(id: tie[0].digest, size: tie[0].file.size,
                           files: KeepSuggestion.rank(tie.map(\.file), preferredFolders: options.preferredFolders))
        }
        .sorted { $0.reclaimable != $1.reclaimable ? $0.reclaimable > $1.reclaimable : $0.id < $1.id }

        let result = DuplicateScanResult(
            groups: groups, filesScanned: stats.filesSeen, unreadable: unreadable + stats.unreadable,
            skippedCloudOnly: stats.skippedCloudOnly, hardLinksSkipped: hardLinksSkipped, rejectedRoots: resolution.rejected
        )
        log.info("duplicate scan: \(stats.filesSeen) files, \(groups.count) groups, \(result.reclaimable) bytes reclaimable, \(Date().timeIntervalSince(started))s")
        return result
    }

    struct Hashed: Sendable {
        let file: FileStat
        let digest: String
    }

    private struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64

        init(_ file: FileStat) {
            device = file.device
            inode = file.inode
        }
    }

    private static func hashAll(
        _ files: [FileStat], limit: Int, progress: FinderProgress, _ hash: @escaping @Sendable (FileStat) throws -> String
    ) async -> (hashed: [Hashed], failed: Int) {
        let outcomes = await Concurrent.map(files, limit: limit) { file -> Hashed? in
            defer { progress.step() }
            guard !Task.isCancelled else { return nil }
            do {
                return Hashed(file: file, digest: try hash(file))
            } catch {
                if !(error is CancellationError) {
                    log.notice("could not hash \(file.path, privacy: .private): \(String(describing: error), privacy: .public)")
                }
                return nil
            }
        }
        let hashed = outcomes.compactMap { $0 }
        return (hashed, Task.isCancelled ? 0 : outcomes.count - hashed.count)
    }

    /// Groups of two or more files sharing size and digest.
    static func tiedGroups(_ hashed: [Hashed]) -> [[Hashed]] {
        Dictionary(grouping: hashed) { "\($0.file.size):\($0.digest)" }.values.filter { $0.count > 1 }.map { Array($0) }
    }
}

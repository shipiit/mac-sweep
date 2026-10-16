import Foundation
import Testing
@testable import MacSweepCore

@Suite struct DiskScannerTests {
    @Test func scansSizesHiddenFilesAndGitRepos() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/proj/big.bin", bytes: 3 << 20)
        try Fixtures.write(root + "/proj/.git/HEAD", bytes: 10)
        try Fixtures.write(root + "/.hidden/cache.bin", bytes: 2 << 20)
        for index in 0..<5 { try Fixtures.write(root + "/proj/small\(index).txt", bytes: 100) }

        var options = ScanOptions()
        options.largeFileThreshold = 1 << 20
        let result = await DiskScanner.scan(root: root, options: options)

        let proj = try #require(result.root.node(at: root + "/proj"))
        #expect(proj.isGitRepo)
        #expect(proj.size >= 3 << 20)
        #expect(proj.children.contains { $0.kind == .aggregate })
        #expect(result.root.node(at: root + "/.hidden")?.isHidden == true)
        #expect(result.largeFiles.map(\.name).sorted() == ["big.bin", "cache.bin"])
        #expect(result.root.size == result.root.children.reduce(0) { $0 + $1.size })
        #expect(result.restrictedCount == 0)
    }

    @Test func doesNotFollowSymlinks() async throws {
        let root = try Fixtures.makeTempDir()
        let outside = try Fixtures.makeTempDir()
        defer {
            try? FileManager.default.removeItem(atPath: root)
            try? FileManager.default.removeItem(atPath: outside)
        }
        try Fixtures.write(outside + "/huge.bin", bytes: 4 << 20)
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: outside)

        let result = await DiskScanner.scan(root: root, options: ScanOptions())
        #expect(result.root.size < 1 << 20)
    }

    @Test func countsHardLinksOnce() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/d/a.bin", bytes: 2 << 20)
        try FileManager.default.linkItem(atPath: root + "/d/a.bin", toPath: root + "/d/b.bin")

        let result = await DiskScanner.scan(root: root, options: ScanOptions())
        let size = try #require(result.root.node(at: root + "/d")?.size)
        #expect(size < 3 << 20)
    }

    @Test func emptyDirectoryScansToZero() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let result = await DiskScanner.scan(root: root, options: ScanOptions())
        #expect(result.root.children.isEmpty)
        #expect(result.root.size == 0)
    }

    @Test func excludedPathsAreSkipped() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/skip/x.bin", bytes: 2 << 20)
        try Fixtures.write(root + "/keep/x.bin", bytes: 2 << 20)
        var options = ScanOptions()
        options.excludedPaths = [root + "/skip"]
        let result = await DiskScanner.scan(root: root, options: options)
        #expect(result.root.node(at: root + "/skip") == nil)
        #expect(result.root.node(at: root + "/keep") != nil)
    }

    @Test func unreadableDirectoryIsReportedNotFatal() async throws {
        let root = try Fixtures.makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/locked")
            try? FileManager.default.removeItem(atPath: root)
        }
        try Fixtures.write(root + "/locked/x.bin", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root + "/locked")
        let result = await DiskScanner.scan(root: root, options: ScanOptions())
        #expect(result.restrictedCount == 1)
        #expect(result.root.node(at: root + "/locked")?.kind == .restricted)
    }

    @Test func measureReturnsNilForMissingPath() {
        #expect(DiskScanner.measure("/definitely/not/here") == nil)
    }

    @Test func rootOptionsExcludeFirmlinkedVolumes() {
        #expect(ScanOptions.forRoot("/").excludedPaths.contains("/System/Volumes"))
        #expect(ScanOptions.forRoot("/Users/x").excludedPaths.isEmpty)
    }

    @Test func scanResultRemovingDropsLargeFilesUnderRemovedPaths() {
        let tree = Fixtures.dir("/r", [Fixtures.dir("/r/a", [Fixtures.file("/r/a/f", size: 10)]), Fixtures.file("/r/g", size: 5)])
        let result = ScanResult(root: tree, largeFiles: [Fixtures.file("/r/a/f", size: 10), Fixtures.file("/r/g", size: 5)],
                                restrictedCount: 0, duration: 0, finishedAt: Date())
        let updated = result.removing(["/r/a"])
        #expect(updated.largeFiles.map(\.path) == ["/r/g"])
        #expect(updated.root.size == 5)
    }
}

@Suite struct ParallelScanTests {
    @Test func splitScanMatchesSequentialScan() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/a/b/c/big.bin", bytes: 3 << 20)
        try Fixtures.write(root + "/a/b/small.txt", bytes: 300)
        try Fixtures.write(root + "/a/repo/.git/HEAD", bytes: 10)
        try Fixtures.write(root + "/a/repo/src/x.bin", bytes: 2 << 20)
        try Fixtures.write(root + "/top.bin", bytes: 1 << 20)
        try FileManager.default.createSymbolicLink(atPath: root + "/a/link", withDestinationPath: root + "/a/b")

        var sequential = ScanOptions()
        sequential.splitDepth = 0
        var parallel = ScanOptions()
        parallel.splitDepth = 3
        let one = await DiskScanner.scan(root: root, options: sequential)
        let two = await DiskScanner.scan(root: root, options: parallel)

        #expect(one.root.size == two.root.size)
        #expect(one.root.itemCount == two.root.itemCount)
        #expect(two.root.node(at: root + "/a/repo")?.isGitRepo == true)
        #expect(one.largeFiles.map(\.path).sorted() == two.largeFiles.map(\.path).sorted())
        #expect(two.root.node(at: root + "/a/b")?.size == one.root.node(at: root + "/a/b")?.size)
    }

    @Test func splitScanReportsUnreadableDirectories() async throws {
        let root = try Fixtures.makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/a/locked")
            try? FileManager.default.removeItem(atPath: root)
        }
        try Fixtures.write(root + "/a/locked/x", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root + "/a/locked")
        var options = ScanOptions()
        options.splitDepth = 3
        let result = await DiskScanner.scan(root: root, options: options)
        #expect(result.restrictedCount == 1)
    }

    @Test func plainDirectoryStatRejectsFilesAndSymlinks() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/f", bytes: 1)
        try FileManager.default.createSymbolicLink(atPath: root + "/l", withDestinationPath: root)
        #expect(DiskScanner.plainDirectoryStat(root) != nil)
        #expect(DiskScanner.plainDirectoryStat(root + "/f") == nil)
        #expect(DiskScanner.plainDirectoryStat(root + "/l") == nil)
        #expect(DiskScanner.plainDirectoryStat(root + "/missing") == nil)
    }
}

@Suite struct AsyncLimiterTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0

        func enter() { lock.withLock { current += 1; peak = max(peak, current) } }
        func leave() { lock.withLock { current -= 1 } }
    }

    @Test func neverExceedsLimit() async {
        let limiter = AsyncLimiter(limit: 2)
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await limiter.acquire()
                    counter.enter()
                    try? await Task.sleep(for: .milliseconds(5))
                    counter.leave()
                    await limiter.release()
                }
            }
        }
        #expect(counter.peak <= 2)
        #expect(counter.peak >= 1)
    }

    @Test func zeroLimitIsTreatedAsOne() async {
        let limiter = AsyncLimiter(limit: 0)
        await limiter.acquire()
        await limiter.release()
    }
}

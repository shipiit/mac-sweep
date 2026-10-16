import Foundation
import Testing
@testable import MacSweepCore

@Suite struct DuplicateFinderTests {
    private func write(_ path: String, _ data: Data) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func bytes(_ count: Int, seed: UInt8) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    private func find(_ home: String, roots: [String]? = nil, minimumSize: UInt64 = 1) async throws -> DuplicateScanResult {
        try await DuplicateFinder.find(roots: roots ?? [home + "/Documents"], home: home, options: DuplicateOptions(minimumSize: minimumSize))
    }

    @Test func groupsIdenticalFilesOnly() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let docs = home + "/Documents"
        try write(docs + "/a.bin", bytes(5_000, seed: 1))
        try write(docs + "/sub/b.bin", bytes(5_000, seed: 1))
        try write(docs + "/c.bin", bytes(5_000, seed: 2))
        try write(docs + "/unique.bin", bytes(7_000, seed: 1))

        let result = try await find(home)
        #expect(result.groups.count == 1)
        let group = try #require(result.groups.first)
        #expect(Set(group.files.map(\.path)) == [docs + "/a.bin", docs + "/sub/b.bin"])
        #expect(group.reclaimable == 5_000)
        #expect(result.reclaimable == 5_000 && result.duplicateCount == 1)
    }

    @Test func sameHeadDifferentTailIsNotADuplicate() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let docs = home + "/Documents"
        let first = bytes(200_000, seed: 3)
        var second = first
        second[199_999] ^= 0xFF
        try write(docs + "/x.bin", first)
        try write(docs + "/y.bin", second)
        try write(docs + "/z.bin", bytes(200_000, seed: 3))

        let result = try await find(home)
        #expect(result.groups.count == 1)
        #expect(Set(result.groups[0].files.map(\.path)) == [docs + "/x.bin", docs + "/z.bin"])
        #expect(result.groups[0].reclaimable == 200_000)
    }

    @Test func hardLinksAndSymlinksAreNotExtraCopies() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let docs = home + "/Documents"
        try write(docs + "/original.bin", bytes(4_000, seed: 9))
        try FileManager.default.linkItem(atPath: docs + "/original.bin", toPath: docs + "/hardlink.bin")
        try FileManager.default.createSymbolicLink(atPath: docs + "/symlink.bin", withDestinationPath: docs + "/original.bin")

        let onlyLinks = try await find(home)
        #expect(onlyLinks.groups.isEmpty)
        #expect(onlyLinks.hardLinksSkipped == 1)

        try write(docs + "/copy.bin", bytes(4_000, seed: 9))
        let withCopy = try await find(home)
        #expect(withCopy.groups.count == 1)
        let paths = Set(try #require(withCopy.groups.first).files.map(\.path))
        #expect(paths.count == 2 && paths.contains(docs + "/copy.bin"))
        #expect(!paths.contains(docs + "/symlink.bin"))
    }

    @Test func emptyAndSmallFilesAreSkipped() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let docs = home + "/Documents"
        try write(docs + "/empty1", Data())
        try write(docs + "/empty2", Data())
        try write(docs + "/small1", bytes(500, seed: 1))
        try write(docs + "/small2", bytes(500, seed: 1))

        #expect(try await find(home, minimumSize: 1).groups.count == 1)
        #expect(try await find(home, minimumSize: 1024).groups.isEmpty)
        #expect(try await find(home, minimumSize: 0).groups.count == 1)
    }

    @Test func unreadableFilesAreCountedNotGrouped() async throws {
        let home = try Fixtures.makeTempDir()
        let docs = home + "/Documents"
        try write(docs + "/a.bin", bytes(3_000, seed: 4))
        try write(docs + "/b.bin", bytes(3_000, seed: 4))
        try write(docs + "/locked.bin", bytes(3_000, seed: 4))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: docs + "/locked.bin")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: docs + "/locked.bin")
            try? FileManager.default.removeItem(atPath: home)
        }

        let result = try await find(home)
        #expect(result.unreadable == 1)
        #expect(result.groups.count == 1 && result.groups[0].files.count == 2)
    }

    @Test func skipsPackagesHiddenAndBuildFolders() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let docs = home + "/Documents"
        let content = bytes(2_000, seed: 5)
        try write(docs + "/keep.bin", content)
        try write(docs + "/Tool.app/Contents/Resources/keep.bin", content)
        try write(docs + "/Library.photoslibrary/originals/keep.bin", content)
        try write(docs + "/.hidden/keep.bin", content)
        try write(docs + "/web/node_modules/pkg/keep.bin", content)

        #expect(try await find(home).groups.isEmpty)
        try write(docs + "/other/keep.bin", content)
        #expect(try await find(home).groups.count == 1)
    }

    @Test func overlappingRootsAreWalkedOnce() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try write(home + "/Documents/sub/a.bin", bytes(2_000, seed: 6))
        let result = try await find(home, roots: [home + "/Documents", home + "/Documents/sub"])
        #expect(result.groups.isEmpty)
    }

    @Test func rejectsSystemAndSensitiveRoots() {
        let home = NSHomeDirectory()
        let resolution = ScanRoots.resolve(["/System", "/", home, home + "/Library/Caches", home + "/.ssh", "/tmp/../etc"], home: home)
        #expect(resolution.accepted.isEmpty)
        #expect(resolution.rejected.count == 6)
    }

    @Test func cancellationStopsTheScan() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        for index in 0..<20 { try write(home + "/Documents/\(index).bin", bytes(300_000, seed: 7)) }
        let task = Task { try await find(home) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func keepSuggestionPrefersFolderThenOldestThenShortestPath() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        func file(_ path: String, _ date: Date) -> FileStat {
            FileStat(path: path, size: 10, device: 1, inode: UInt64(path.count), modified: date, created: date)
        }
        let files = [file("/h/Downloads/long/name/copy.jpg", new), file("/h/Pictures/a.jpg", new), file("/h/Downloads/b.jpg", old)]
        #expect(KeepSuggestion.rank(files, preferredFolders: []).map(\.path).first == "/h/Downloads/b.jpg")
        #expect(KeepSuggestion.rank(files, preferredFolders: ["/h/Pictures"]).first?.path == "/h/Pictures/a.jpg")
        let sameAge = [file("/h/x/longer.jpg", old), file("/h/x/a.jpg", old), file("/h/x/b.jpg", old)]
        #expect(KeepSuggestion.rank(sameAge, preferredFolders: []).map(\.path) == ["/h/x/a.jpg", "/h/x/b.jpg", "/h/x/longer.jpg"])
        #expect(KeepSuggestion.rank([], preferredFolders: []).isEmpty)
    }
}

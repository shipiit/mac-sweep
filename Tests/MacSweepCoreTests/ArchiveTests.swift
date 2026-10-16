import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ArchiveTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func facts(_ path: String, markers: [String] = [], size: UInt64, files: Int = 10, idleDays: Double?, cloud: Int = 0) -> FolderFacts {
        FolderFacts(path: path, markers: markers, size: size, fileCount: files,
                    newestModification: idleDays.map { now.addingTimeInterval(-$0 * 86_400) }, estimatedArchiveSize: size / 2, cloudOnlyFiles: cloud)
    }

    @Test func selectsIdleProjectsAndLargeFolders() {
        let criteria = ArchiveCriteria()
        let picked = ArchivePolicy.select([
            facts("/u/old-app", markers: ["Node"], size: 100 << 20, idleDays: 200),
            facts("/u/fresh-app", markers: ["Node"], size: 100 << 20, idleDays: 10),
            facts("/u/tiny-app", markers: ["Go"], size: 1 << 20, idleDays: 400),
            facts("/u/Downloads/old", size: 2 << 30, idleDays: 365),
            facts("/u/Downloads/small", size: 100 << 20, idleDays: 365),
            facts("/u/cloud", markers: ["Git"], size: 1 << 30, idleDays: 365, cloud: 3),
            facts("/u/empty", markers: ["Git"], size: 1 << 30, files: 0, idleDays: 365),
            facts("/u/undated", markers: ["Git"], size: 1 << 30, idleDays: nil),
        ], criteria: criteria, now: now)
        #expect(picked.map(\.id) == ["/u/Downloads/old", "/u/old-app"])
        #expect(picked[1].reason == .project(["Node"]) && picked[1].idleDays == 200)
        #expect(picked[0].reason == .largeFolder)
    }

    @Test func parentCandidateHidesItsChildren() {
        let picked = ArchivePolicy.select([facts("/u/work", size: 3 << 30, idleDays: 300),
                                           facts("/u/work/app", markers: ["Git"], size: 1 << 30, idleDays: 300)],
                                          criteria: ArchiveCriteria(), now: now)
        #expect(picked.map(\.id) == ["/u/work"])
        #expect(ArchivePolicy.select([], criteria: ArchiveCriteria(), now: now).isEmpty)
    }

    @Test func boundaryIdleDays() {
        var criteria = ArchiveCriteria()
        criteria.minimumIdleDays = 180
        #expect(ArchivePolicy.select([facts("/u/a", markers: ["Git"], size: 1 << 30, idleDays: 180)], criteria: criteria, now: now).count == 1)
        #expect(ArchivePolicy.select([facts("/u/a", markers: ["Git"], size: 1 << 30, idleDays: 179.9)], criteria: criteria, now: now).isEmpty)
    }

    @Test func detectsProjectMarkers() {
        #expect(ProjectMarkers.detect(entries: ["package.json", ".git", "README.md"]) == ["Git", "Node"])
        #expect(ProjectMarkers.detect(entries: ["App.xcodeproj", "requirements.txt", "setup.py"]) == ["Python", "Xcode"])
        #expect(ProjectMarkers.detect(entries: []).isEmpty)
    }

    @Test func compressionEstimates() {
        #expect(CompressionEstimate.kind(forExtension: "ZIP") == .compressed)
        #expect(CompressionEstimate.kind(forExtension: "swift") == .text || CompressionEstimate.kind(forExtension: "swift") == .other)
        #expect(CompressionEstimate.estimate(compressed: 0, text: 0, other: 0) == 0)
        let estimate = CompressionEstimate.estimate(compressed: 1_000, text: 1_000, other: 1_000)
        #expect(estimate > 0 && estimate < 3_000)
    }

    @Test func archivePathAvoidsCollisions() {
        let taken: Set<String> = ["/dest/app.zip", "/dest/app 2.zip"]
        #expect(Archiver.archivePath(for: "/u/app", in: "/dest") { taken.contains($0) } == "/dest/app 3.zip")
        #expect(Archiver.archivePath(for: "/u/app", in: "/dest") { _ in false } == "/dest/app.zip")
    }

    @Test func validationRefusesUnsafeTargets() {
        let home = "/Users/x"
        #expect(throws: ArchiveError.destinationInsideSource) {
            try Archiver.validate(source: "/Users/x/work/app", destination: "/Users/x/work/app/out", home: home, needed: 1, available: 10)
        }
        #expect(throws: ArchiveError.destinationMissing) {
            try Archiver.validate(source: "/Users/x/work/app", destination: "/Volumes/Ext", home: home, needed: 1, available: nil)
        }
        #expect(throws: ArchiveError.notEnoughSpace(needed: 10, available: 5)) {
            try Archiver.validate(source: "/Users/x/work/app", destination: "/Volumes/Ext", home: home, needed: 10, available: 5)
        }
        #expect(throws: (any Error).self) {
            try Archiver.validate(source: "/System/Library", destination: "/Volumes/Ext", home: home, needed: 1, available: 10)
        }
        #expect(throws: Never.self) {
            try Archiver.validate(source: "/Users/x/work/app", destination: "/Volumes/Ext", home: home, needed: 1, available: 10)
        }
    }

    @Test func archivesVerifiesAndDetectsChanges() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let source = root + "/project"
        try FileManager.default.createDirectory(atPath: source + "/src", withIntermediateDirectories: true)
        try "hello".write(toFile: source + "/src/a.txt", atomically: true, encoding: .utf8)
        try "world".write(toFile: source + "/b.txt", atomically: true, encoding: .utf8)
        let destination = root + "/dest"
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let verified = try await Archiver.archiveAndVerify(source: source, destination: destination, estimatedSize: 1_000, home: root)
        #expect(FileManager.default.fileExists(atPath: verified.archivePath) && verified.fileCount == 2 && verified.totalBytes == 10)
        try "changed!".write(toFile: source + "/b.txt", atomically: true, encoding: .utf8)
        let result = Archiver.trashOriginal(verified, home: root, extraProtected: [])
        #expect(!result.succeeded, "a source that changed after archiving is never trashed")
        #expect(FileManager.default.fileExists(atPath: source))
    }
}

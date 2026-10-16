import Foundation
import Testing
@testable import MacSweepCore

@Suite struct KeepOneTrashTests {
    private func stat(_ path: String) throws -> FileStat {
        try #require(FileStat.current(path))
    }

    private func makeGroup(_ home: String, names: [String]) throws -> [FileStat] {
        try names.map { name in
            let path = home + "/Documents/" + name
            try Fixtures.write(path, bytes: 2_048)
            return try stat(path)
        }
    }

    @Test func planNeverTakesEveryCopy() {
        func file(_ path: String) -> FileStat { FileStat(path: path, size: 100, device: 1, inode: UInt64(path.hashValue.magnitude), modified: .distantPast, created: .distantPast) }
        let groupA = [file("/a1"), file("/a2"), file("/a3")]
        let groupB = [file("/b1"), file("/b2")]

        let partial = KeepOneTrash.plan(groups: [groupA, groupB], selected: ["/a2", "/a3", "/b2"])
        #expect(Set(partial.targets.map(\.path)) == ["/a2", "/a3", "/b2"])
        #expect(partial.blockedGroups == 0 && partial.reclaimable == 300)

        let everything = KeepOneTrash.plan(groups: [groupA, groupB], selected: ["/a1", "/a2", "/a3", "/b2"])
        #expect(everything.targets.map(\.path) == ["/b2"])
        #expect(everything.blockedGroups == 1)

        #expect(KeepOneTrash.plan(groups: [], selected: ["/a1"]).targets.isEmpty)
        #expect(KeepOneTrash.plan(groups: [groupA], selected: []).targets.isEmpty)
        #expect(KeepOneTrash.plan(groups: [[file("/solo")]], selected: ["/solo"]).blockedGroups == 1)
    }

    @Test func trashesSelectedCopiesAndKeepsTheRest() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let group = try makeGroup(home, names: ["one.bin", "two.bin", "three.bin"])
        let outcome = KeepOneTrash.trash(groups: [group], selected: [group[1].path, group[2].path], home: home, extraProtected: [])
        #expect(outcome.removedPaths == [group[1].path, group[2].path])
        #expect(outcome.freed == group[1].size + group[2].size)
        #expect(FileManager.default.fileExists(atPath: group[0].path))
    }

    @Test func refusesToTrashWholeGroup() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let group = try makeGroup(home, names: ["one.bin", "two.bin"])
        let outcome = KeepOneTrash.trash(groups: [group], selected: Set(group.map(\.path)), home: home, extraProtected: [])
        #expect(outcome.results.isEmpty && outcome.blockedGroups == 1)
        #expect(group.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func refusesWhenKeptCopyIsGoneOrChanged() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let group = try makeGroup(home, names: ["keep.bin", "dupe.bin"])
        try FileManager.default.removeItem(atPath: group[0].path)
        let outcome = KeepOneTrash.trash(groups: [group], selected: [group[1].path], home: home, extraProtected: [])
        #expect(outcome.removedPaths.isEmpty)
        #expect(outcome.results.allSatisfy { if case .refused = $0.outcome { true } else { false } })
        #expect(FileManager.default.fileExists(atPath: group[1].path))
    }

    @Test func refusesTargetsChangedSinceScan() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let group = try makeGroup(home, names: ["keep.bin", "dupe.bin"])
        try Data(repeating: 1, count: 10).write(to: URL(fileURLWithPath: group[1].path))
        let outcome = KeepOneTrash.trash(groups: [group], selected: [group[1].path], home: home, extraProtected: [])
        #expect(outcome.removedPaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: group[1].path))
    }

    @Test func pathGuardStillApplies() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.ssh/key", bytes: 2_048)
        try Fixtures.write(home + "/Documents/key", bytes: 2_048)
        let group = [try stat(home + "/Documents/key"), try stat(home + "/.ssh/key")]
        let outcome = KeepOneTrash.trash(groups: [group], selected: [home + "/.ssh/key"], home: home, extraProtected: [])
        #expect(outcome.removedPaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: home + "/.ssh/key"))
    }

    @Test func groupsShrinkAfterRemoval() {
        let files = (1...3).map { FileStat(path: "/f\($0)", size: 10, device: 1, inode: UInt64($0), modified: .distantPast, created: .distantPast) }
        let group = DuplicateGroup(id: "x", size: 10, files: files)
        #expect(group.removing(["/f2"])?.files.count == 2)
        #expect(group.removing(["/f2", "/f3"]) == nil)
        #expect(group.suggestedKeep?.path == "/f1")
        let cluster = PhotoCluster(photos: files)
        #expect(cluster.reclaimable == 20)
        #expect(cluster.removing(["/f1", "/f3"]) == nil)
    }
}

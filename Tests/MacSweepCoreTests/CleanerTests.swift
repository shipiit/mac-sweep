import Foundation
import Testing
@testable import MacSweepCore

/// Exercises real removal against a throwaway fake home, never the user's files.
@Suite struct CleanerTests {
    @Test func deleteModeRemovesAllowedTargets() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.npm/_cacache/blob", bytes: 1000)

        let results = Cleaner.remove([CleanupTarget(path: home + "/.npm/_cacache", size: 1000)], mode: .delete, home: home)
        #expect(results.map(\.outcome) == [.removed])
        #expect(!FileManager.default.fileExists(atPath: home + "/.npm/_cacache"))
    }

    @Test func refusesProtectedTargetsAndLeavesThemInPlace() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.ssh/id_ed25519", bytes: 10)

        let results = Cleaner.remove([CleanupTarget(path: home + "/.ssh", size: 10)], mode: .delete, home: home)
        guard case .refused = results.first?.outcome else {
            Issue.record("expected refusal, got \(String(describing: results.first?.outcome))")
            return
        }
        #expect(FileManager.default.fileExists(atPath: home + "/.ssh/id_ed25519"))
    }

    @Test func missingTargetReportsFailure() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let results = Cleaner.remove([CleanupTarget(path: home + "/gone", size: 1)], mode: .delete, home: home)
        guard case .failed = results.first?.outcome else {
            Issue.record("expected failure")
            return
        }
    }

    @Test func itemsAlreadyInTrashAreDeletedEvenInTrashMode() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.Trash/old.dmg", bytes: 10)
        let results = Cleaner.remove([CleanupTarget(path: home + "/.Trash/old.dmg", size: 10)], mode: .trash, home: home)
        #expect(results.first?.succeeded == true)
        #expect(!FileManager.default.fileExists(atPath: home + "/.Trash/old.dmg"))
    }

    @Test func emptyTargetListIsNoOp() {
        #expect(Cleaner.remove([], mode: .delete, home: "/Users/test").isEmpty)
    }

    @Test func mixedBatchReportsEachOutcome() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.gradle/caches/x", bytes: 10)
        let results = Cleaner.remove([
            CleanupTarget(path: home + "/.gradle/caches", size: 10),
            CleanupTarget(path: "/System/Library", size: 10),
        ], mode: .delete, home: home)
        #expect(results.count == 2)
        #expect(results[0].succeeded)
        #expect(!results[1].succeeded)
    }
}

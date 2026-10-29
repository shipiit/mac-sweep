import Foundation
import Testing
@testable import MacSweepCore

@Suite struct PermissionsTests {
    let home = "/Users/test"

    @Test func readableSafariFolderMeansFullDiskAccess() {
        let readable: Set<String> = [home + "/Library/Safari"]
        #expect(Permissions.hasFullDiskAccess(home: home, canRead: { readable.contains($0) }))
    }

    @Test func anyProtectedLocationIsEnough() {
        for path in Permissions.protectedProbes(home: home) {
            #expect(Permissions.hasFullDiskAccess(home: home, canRead: { $0 == path }), "\(path)")
        }
    }

    @Test func nothingReadableMeansNoAccess() {
        #expect(!Permissions.hasFullDiskAccess(home: home, canRead: { _ in false }))
    }

    /// macOS 27 refuses TCC.db even with Full Disk Access, so it must not be the only probe.
    @Test func doesNotRelyOnTCCDatabaseAlone() {
        let probes = Permissions.protectedProbes(home: home)
        #expect(probes.count > 1)
        #expect(probes.contains(home + "/Library/Safari"))
        #expect(probes.contains(home + "/Library/Mail"))
    }

    @Test func realProbeOnTemporaryHomeWithoutProtectedFoldersIsFalse() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: temp) }
        #expect(!Permissions.hasFullDiskAccess(home: temp))
    }
}

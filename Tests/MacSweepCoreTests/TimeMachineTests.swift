import Foundation
import Testing
@testable import MacSweepCore

@Suite struct TimeMachineParserTests {
    static let utc = TimeZone(identifier: "UTC") ?? .gmt

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    }

    @Test(arguments: [
        "/Volumes/Backup/Backups.backupdb/Mac/2024-03-05-142233",
        "/Volumes/.timemachine/ABC/2024-03-05-142233.backup/2024-03-05-142233.backup\n",
    ])
    func parsesLatestBackupDate(output: String) {
        #expect(TimeMachineParser.latestBackupDate(output, timeZone: Self.utc) == Self.date(2024, 3, 5, 14, 22, 33))
    }

    @Test(arguments: [
        "",
        "Failed to mount backup destination, error: Error Domain=TMBackupDestinationErrorDomain Code=18",
        "/Volumes/Backup/2024-13-40-250000",
    ])
    func latestBackupDateRejectsGarbage(output: String) {
        #expect(TimeMachineParser.latestBackupDate(output, timeZone: Self.utc) == nil)
    }

    @Test func parsesDestinations() {
        let output = """
            ====================================================
            Name          : Backup Disk
            Kind          : Local
            Mount Point   : /Volumes/Backup Disk
            ID            : 1234-ABCD
            ====================================================
            Name          : NAS
            Kind          : Network
            URL           : smb://nas.local/tm
            ID            : 5678
            """
        let destinations = TimeMachineParser.destinations(output)
        #expect(destinations == [
            BackupDestination(name: "Backup Disk", kind: "Local", mountPoint: "/Volumes/Backup Disk", id: "1234-ABCD"),
            BackupDestination(name: "NAS", kind: "Network", mountPoint: nil, id: "5678"),
        ])
    }

    @Test func destinationWithoutIDFallsBackToName() {
        let destinations = TimeMachineParser.destinations("Name : Disk\nKind : Local")
        #expect(destinations.map(\.id) == ["Disk"])
    }

    @Test(arguments: ["", "tmutil: No destinations configured.", "garbage\nmore garbage", "Kind : Local\n===="])
    func noDestinations(output: String) {
        #expect(TimeMachineParser.destinations(output).isEmpty)
    }

    @Test func parsesExclusions() {
        let output = """
            [Included]    /Users/test/Documents
            [Excluded]    /Users/test/Projects
            [UNKNOWN]     /Users/test/Missing
            garbage line
            [Excluded]
            """
        #expect(TimeMachineParser.exclusions(output) == [
            "/Users/test/Documents": .included,
            "/Users/test/Projects": .excluded,
            "/Users/test/Missing": .unknown,
        ])
        #expect(TimeMachineParser.exclusions("").isEmpty)
    }

    @Test func detectsFullDiskAccessMessages() {
        #expect(TimeMachineParser.mentionsFullDiskAccess("tmutil requires Full Disk Access privileges."))
        #expect(TimeMachineParser.mentionsFullDiskAccess("Operation not permitted"))
        #expect(!TimeMachineParser.mentionsFullDiskAccess(""))
        #expect(!TimeMachineParser.mentionsFullDiskAccess("No machine directory found for host."))
    }
}

@Suite struct BackupAssessmentTests {
    static let disk = BackupDestination(name: "Disk", kind: "Local", mountPoint: nil, id: "1")
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func daysAgo(_ days: Double) -> BackupReport.Status { .backedUp(now.addingTimeInterval(-days * 86_400)) }

    @Test func statusFromLatestBackup() {
        let status = BackupAssessment.status(destinations: [Self.disk], latest: "/Volumes/D/2024-03-05-142233\n",
                                             timeZone: TimeMachineParserTests.utc)
        #expect(status == .backedUp(TimeMachineParserTests.date(2024, 3, 5, 14, 22, 33) ?? .distantPast))
    }

    @Test func statusWithoutBackup() {
        #expect(BackupAssessment.status(destinations: [], latest: "") == .notConfigured)
        #expect(BackupAssessment.status(destinations: [Self.disk], latest: "No machine directory found") == .neverCompleted)
        #expect(BackupAssessment.status(destinations: [Self.disk], latest: "\ntmutil requires Full Disk Access privileges.") == .needsFullDiskAccess)
        #expect(BackupAssessment.status(destinations: [], latest: "Operation not permitted") == .needsFullDiskAccess)
    }

    @Test(arguments: [
        (0.0, FindingSeverity.info),
        (1.0, .info),
        (1.1, .info),
        (2.0, .low),
        (7.0, .low),
        (7.5, .medium),
        (14.0, .medium),
        (15.0, .high),
        (400.0, .high),
    ])
    func ageSeverity(days: Double, expected: FindingSeverity) {
        #expect(BackupAssessment.ageSeverity(Self.daysAgo(days), now: Self.now) == expected)
    }

    @Test func ageSeverityWithoutBackup() {
        #expect(BackupAssessment.ageSeverity(.notConfigured) == .high)
        #expect(BackupAssessment.ageSeverity(.neverCompleted) == .high)
        #expect(BackupAssessment.ageSeverity(.needsFullDiskAccess) == .info)
    }

    @Test func importantFoldersKeepsExistingAndDedupesCase() {
        let existing: Set<String> = ["/Users/test/Documents", "/Users/test/Projects", "/Users/test/projects", "/Users/test/Sites"]
        let folders = BackupAssessment.importantFolders(home: Fixtures.home) { existing.contains($0) }
        #expect(folders == ["/Users/test/Documents", "/Users/test/Projects", "/Users/test/Sites"])
        #expect(BackupAssessment.importantFolders(home: Fixtures.home) { _ in false }.isEmpty)
    }

    @Test func excludedImportantIsSortedAndOnlyExcluded() {
        let folders: [String: ExclusionState] = ["/b": .excluded, "/a": .excluded, "/c": .included, "/d": .unknown]
        #expect(BackupAssessment.excludedImportant(folders) == ["/a", "/b"])
        #expect(BackupAssessment.excludedImportant([:]).isEmpty)
    }
}

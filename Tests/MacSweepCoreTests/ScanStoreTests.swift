import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ScanStoreTests {
    @Test func roundTripsAScan() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ScanStore(url: URL(fileURLWithPath: dir + "/sub/last.plist"))
        let tree = Fixtures.dir("/r", [Fixtures.dir("/r/a", [Fixtures.file("/r/a/f", size: 10)]),
                                       FileNode(path: "/r", name: "3 smaller items", kind: .aggregate, size: 3, itemCount: 3)])
        let result = ScanResult(root: tree, largeFiles: [Fixtures.file("/r/a/f", size: 10)], restrictedCount: 2,
                                duration: 12, finishedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(result)
        let loaded = try #require(store.load())
        #expect(loaded.root == result.root)
        #expect(loaded.root.node(at: "/r/a/f")?.size == 10)
        #expect(loaded.root.children.contains { $0.kind == .aggregate })
        #expect(loaded.restrictedCount == 2)
        #expect(loaded.finishedAt == result.finishedAt)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func missingOrCorruptFileLoadsNil() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ScanStore(url: URL(fileURLWithPath: dir + "/x.plist"))
        #expect(store.load() == nil)
        try Data("junk".utf8).write(to: store.url)
        #expect(store.load() == nil)
    }
}

@Suite struct ScanScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    @Test func offIsNeverDue() {
        #expect(ScanSchedule.off.nextDue(after: nil, now: date(16, 10), calendar: calendar) == nil)
        #expect(!ScanSchedule.off.isDue(lastScan: nil, now: date(16, 10), calendar: calendar))
    }

    @Test func neverScannedIsDueNow() {
        for schedule in [ScanSchedule.nightly, .morning, .sixHours] {
            #expect(schedule.isDue(lastScan: nil, now: date(16, 10), calendar: calendar))
        }
    }

    @Test func nightlyRunsOncePerNightAndCatchesUpAfterSleep() {
        let nightly = ScanSchedule.nightly
        #expect(!nightly.isDue(lastScan: date(16, 2, 5), now: date(16, 23), calendar: calendar))
        #expect(nightly.nextDue(after: date(16, 2, 5), now: date(16, 23), calendar: calendar) == date(17, 2))
        #expect(nightly.isDue(lastScan: date(16, 2, 5), now: date(17, 2, 1), calendar: calendar))
        // Mac was asleep at 2 AM; it catches up when it wakes at 9.
        #expect(nightly.isDue(lastScan: date(15, 23), now: date(16, 9), calendar: calendar))
    }

    @Test func morningUsesEightAM() {
        #expect(!ScanSchedule.morning.isDue(lastScan: date(16, 8, 30), now: date(16, 20), calendar: calendar))
        #expect(ScanSchedule.morning.isDue(lastScan: date(16, 7), now: date(16, 8, 1), calendar: calendar))
    }

    @Test func sixHourInterval() {
        #expect(!ScanSchedule.sixHours.isDue(lastScan: date(16, 4), now: date(16, 9, 59), calendar: calendar))
        #expect(ScanSchedule.sixHours.isDue(lastScan: date(16, 4), now: date(16, 10), calendar: calendar))
    }
}

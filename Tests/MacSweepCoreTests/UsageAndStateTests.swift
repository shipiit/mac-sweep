import Foundation
import Testing
@testable import MacSweepCore

@Suite struct UsageLogTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    @Test func recordsAndSummarises() {
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(16, 10), to: date(16, 11), calendar: calendar)
        log.record(bundleID: "com.b", name: "B", from: date(16, 11), to: date(16, 11, 30), calendar: calendar)
        log.recordActivation(bundleID: "com.a", name: "A", at: date(16, 10), calendar: calendar)
        let summary = log.summary(days: 1, now: date(16, 20), calendar: calendar)
        #expect(summary.map(\.bundleID) == ["com.a", "com.b"])
        #expect(summary[0].seconds == 3_600 && summary[0].activations == 1)
        #expect(summary[1].seconds == 1_800)
    }

    @Test func splitsAcrossMidnight() {
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(16, 23, 30), to: date(17, 0, 30), calendar: calendar)
        #expect(log.days["2026-10-16"]?.seconds["com.a"] == 1_800)
        #expect(log.days["2026-10-17"]?.seconds["com.a"] == 1_800)
        #expect(log.summary(days: 2, now: date(17, 12), calendar: calendar).first?.seconds == 3_600)
    }

    @Test func recordsHourlyTimeline() {
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(16, 9, 30), to: date(16, 11, 15), calendar: calendar)
        let hours = log.hourly(days: 1, now: date(16, 20), calendar: calendar)
        #expect(hours[9] == 1_800 && hours[10] == 3_600 && hours[11] == 900)
        #expect(hours.reduce(0, +) == 6_300)
        #expect(log.hourly(days: 2, now: date(16, 20), calendar: calendar)[10] == 1_800)
    }

    @Test func oldLogsWithoutHoursStillDecode() throws {
        let legacy = #"{"days":{"2026-10-16":{"seconds":{"com.a":60},"activations":{},"names":{}}}}"#
        let log = try JSONDecoder().decode(UsageLog.self, from: Data(legacy.utf8))
        #expect(log.days["2026-10-16"]?.seconds["com.a"] == 60)
        #expect(log.days["2026-10-16"]?.hours.isEmpty == true)
    }

    @Test func ignoresBackwardsOrEmptyIntervals() {
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(16, 10), to: date(16, 10), calendar: calendar)
        log.record(bundleID: "com.a", name: "A", from: date(16, 11), to: date(16, 10), calendar: calendar)
        #expect(log.days.isEmpty)
    }

    @Test func prunesOldDaysAndTotalsDaily() {
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(1, 10), to: date(1, 11), calendar: calendar)
        log.record(bundleID: "com.a", name: "A", from: date(16, 10), to: date(16, 12), calendar: calendar)
        log.prune(now: date(16 + 20, 12), calendar: calendar)
        #expect(log.days.keys.sorted() == ["2026-10-16"])
        let totals = log.dailyTotals(days: 3, now: date(17, 9), calendar: calendar)
        #expect(totals.map(\.seconds) == [0, 7_200, 0])
    }

    @Test func lastActiveSurvivesRoundTripAndOldFiles() throws {
        var log = UsageLog()
        log.lastActive["com.a"] = date(16, 10)
        let decoded = try JSONDecoder().decode(UsageLog.self, from: try JSONEncoder().encode(log))
        #expect(decoded.lastActive["com.a"] == date(16, 10))
        let legacy = try JSONDecoder().decode(UsageLog.self, from: Data(#"{"days":{}}"#.utf8))
        #expect(legacy.lastActive.isEmpty)
        log.prune(now: date(16, 10).addingTimeInterval(40 * 86_400), calendar: calendar)
        #expect(log.lastActive.isEmpty)
    }

    @Test func storeRoundTripsAndToleratesCorruption() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = UsageLogStore(url: URL(fileURLWithPath: dir + "/usage.json"))
        #expect(store.load() == UsageLog())
        var log = UsageLog()
        log.record(bundleID: "com.a", name: "A", from: date(16, 10), to: date(16, 11), calendar: calendar)
        try store.save(log)
        #expect(store.load() == log)
        try Data("nope".utf8).write(to: store.url)
        #expect(store.load() == UsageLog())
    }
}

@Suite struct ChromiumStateTests {
    @Test func parsesInstallTimesStateAndStoreStatus() throws {
        let json = """
        {"extensions":{"settings":{
          "aaa":{"first_install_time":"13347646250337949","last_update_time":"13429808273442850","disable_reasons":[],"cws-info":{"is-live":true,"violation-type":0}},
          "bbb":{"first_install_time":"13347646250337949","disable_reasons":[1],"cws-info":{"is-live":false,"violation-type":0}},
          "ccc":{"state":1,"cws-info":{"is-live":true,"violation-type":3}}
        }}}
        """
        let states = ChromiumExtensionState.parse(Data(json.utf8))
        let a = try #require(states["aaa"])
        #expect(a.enabled && a.storeStatus == .listed)
        let year = Calendar(identifier: .gregorian).component(.year, from: try #require(a.installed))
        #expect(year == 2023)
        #expect(states["bbb"]?.enabled == false && states["bbb"]?.storeStatus == .removedFromStore)
        #expect(states["ccc"]?.storeStatus == .policyViolation && states["ccc"]?.enabled == true)
        #expect(ChromiumExtensionState.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func storeVerdictRaisesRisk() {
        var ext = BrowserExtension(browser: "Chrome", profile: "Default", extensionID: "x", name: "X", version: "1", permissions: ["storage"], path: "/x")
        #expect(ext.risk == .low)
        ext.state.storeStatus = .removedFromStore
        #expect(ext.risk == .high)
        #expect(ext.managePage?.url == "chrome://extensions/?id=x")
    }
}

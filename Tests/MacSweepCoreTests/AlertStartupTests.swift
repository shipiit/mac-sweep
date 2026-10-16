import Foundation
import Testing
@testable import MacSweepCore

@Suite struct StartupItemAlertTests {
    typealias F = AlertFixtures

    func agent(_ name: String, program: String? = nil, kind: StartupFingerprint.Kind = .userAgent) -> StartupFingerprint {
        StartupFingerprint(id: "/Library/LaunchAgents/\(name).plist", kind: kind, name: name, executable: program ?? "/usr/local/bin/\(name)")
    }

    func run(_ engine: inout AlertEngine, _ items: [StartupFingerprint], at seconds: TimeInterval = 0) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), startupItems: items))
    }

    @Test func firstScanIsBaselineOnly() {
        var engine = AlertEngine()
        #expect(run(&engine, [agent("a"), agent("b")]).isEmpty)
        #expect(engine.state.startupBaseline?.count == 2)
    }

    @Test func newItemFiresCritical() {
        var engine = AlertEngine()
        _ = run(&engine, [agent("a")])
        let alerts = run(&engine, [agent("a"), agent("evil", kind: .daemon)], at: 60)
        #expect(alerts.count == 1)
        #expect(alerts.first?.severity == .critical)
        #expect(alerts.first?.title.contains("launch daemon") == true)
        #expect(alerts.first?.subjectPath == "/Library/LaunchAgents/evil.plist")
    }

    @Test func unchangedListAndRemovalsDoNotFire() {
        var engine = AlertEngine()
        _ = run(&engine, [agent("a"), agent("b")])
        #expect(run(&engine, [agent("a"), agent("b")], at: 60).isEmpty)
        #expect(run(&engine, [agent("a")], at: 120).isEmpty)
        #expect(run(&engine, [], at: 180).isEmpty)
    }

    @Test func newItemFiresOnlyOnce() {
        var engine = AlertEngine()
        _ = run(&engine, [])
        #expect(run(&engine, [agent("x")], at: 60).count == 1)
        #expect(run(&engine, [agent("x")], at: 120).isEmpty)
    }

    @Test func changedExecutableFires() {
        var engine = AlertEngine()
        _ = run(&engine, [agent("a", program: "/Applications/A.app/a")])
        let alerts = run(&engine, [agent("a", program: "/tmp/payload")], at: 60)
        #expect(alerts.count == 1)
        #expect(alerts.first?.message.contains("/tmp/payload") == true)
    }

    @Test func loginItemsAreTracked() {
        var engine = AlertEngine()
        _ = run(&engine, [])
        let login = StartupFingerprint(LoginItem(name: "Helper", path: "/Applications/Helper.app", hidden: false))
        let alerts = run(&engine, [login], at: 60)
        #expect(alerts.first?.title == "New login item: Helper")
        #expect(alerts.first?.subjectPath == "/Applications/Helper.app")
    }

    @Test func launchItemConversionKeepsScopeAndProgram() {
        let item = LaunchItem(label: "com.x", plistPath: "/Library/LaunchDaemons/com.x.plist", scope: .daemon, program: nil,
                              arguments: ["/usr/bin/x", "-d"], runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        let fingerprint = StartupFingerprint(item)
        #expect(fingerprint.kind == .daemon)
        #expect(fingerprint.executable == "/usr/bin/x")
        #expect(fingerprint.id == item.plistPath)
    }

    @Test func itemsAddedWhileDisabledAreAbsorbedIntoBaseline() {
        var engine = AlertEngine()
        _ = run(&engine, [])
        #expect(engine.evaluate(AlertSnapshot(date: F.at(60), startupItems: [agent("x")]), enabled: []).isEmpty)
        #expect(run(&engine, [agent("x")], at: 120).isEmpty)
    }

    @Test func missingScanKeepsBaseline() {
        var engine = AlertEngine()
        _ = run(&engine, [agent("a")])
        _ = engine.evaluate(AlertSnapshot(date: F.at(60)))
        #expect(engine.state.startupBaseline?.count == 1)
    }
}

@Suite struct AlertStoreTests {
    @Test func archiveRoundTripsAndStatePreventsRefiring() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = AlertStore(url: URL(fileURLWithPath: dir + "/nested/alerts.json"))
        var engine = AlertEngine()
        let snapshot = AlertSnapshot(date: AlertFixtures.start, volume: AlertFixtures.volume(free: 1 * AlertFixtures.gb),
                                     batteryHealth: 0.9, startupItems: [])
        var archive = AlertArchive()
        archive.record(engine.evaluate(snapshot))
        archive.state = engine.state
        try store.save(archive)

        let loaded = store.load()
        #expect(loaded == archive)
        var relaunched = AlertEngine(state: loaded.state)
        #expect(relaunched.evaluate(snapshot).isEmpty, "a relaunch must not re-fire the same condition")
        #expect(relaunched.state.batteryBaseline == 0.9)
    }

    @Test func missingOrCorruptFileGivesEmptyArchive() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = AlertStore(url: URL(fileURLWithPath: dir + "/alerts.json"))
        #expect(store.load() == AlertArchive())
        try Data("{not json".utf8).write(to: store.url)
        #expect(store.load() == AlertArchive())
    }

    @Test func recordKeepsNewestFirstAndCaps() {
        var archive = AlertArchive()
        archive.record([])
        #expect(archive.recent.isEmpty)
        for index in 0..<(AlertArchive.recentLimit + 5) {
            archive.record([SmartAlert(rule: .largeTrash, key: "k\(index)", severity: .info, title: "t", message: "m",
                                       date: AlertFixtures.at(TimeInterval(index)))])
        }
        #expect(archive.recent.count == AlertArchive.recentLimit)
        #expect(archive.recent.first?.key == "k\(AlertArchive.recentLimit + 4)")
    }

    @Test func oldFiredTimesArePruned() {
        var engine = AlertEngine()
        _ = engine.evaluate(AlertSnapshot(date: AlertFixtures.at(0), trashBytes: 9 * AlertFixtures.gb))
        #expect(engine.state.lastFired["trash"] != nil)
        _ = engine.evaluate(AlertSnapshot(date: AlertFixtures.at(4 * 86_400)))
        #expect(engine.state.lastFired.isEmpty)
    }
}

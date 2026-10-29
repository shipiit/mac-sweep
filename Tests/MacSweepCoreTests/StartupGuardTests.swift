import Foundation
import Testing
@testable import MacSweepCore

@Suite struct StartupGuardTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func item(_ label: String, scope: LaunchScope = .userAgent, program: String? = nil) -> LaunchItem {
        let dir = switch scope {
        case .userAgent: "/Users/test/Library/LaunchAgents"
        case .globalAgent: "/Library/LaunchAgents"
        case .daemon: "/Library/LaunchDaemons"
        }
        return LaunchItem(label: label, plistPath: "\(dir)/\(label).plist", scope: scope, program: program ?? "/opt/\(label)",
                          arguments: [], runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
    }

    @Test func enablingAcceptsEverythingCurrent() {
        let current = [Self.item("a"), Self.item("b", scope: .daemon)]
        var archive = StartupGuardArchive()
        archive.enable(current: current, at: Self.now)
        #expect(archive.isEnabled)
        #expect(archive.baseline.count == 2)
        #expect(StartupGuardPolicy.decide(baseline: archive.baseline, held: archive.held, current: current).isEmpty)
    }

    @Test func newUserAgentIsAutoBlockedOthersAsked() {
        let baseline = StartupGuardPolicy.baseline(from: [Self.item("a")])
        let current = [Self.item("a"), Self.item("evil"), Self.item("g", scope: .globalAgent), Self.item("d", scope: .daemon)]
        let decision = StartupGuardPolicy.decide(baseline: baseline, held: [], current: current)
        #expect(decision.autoBlock.map(\.label) == ["evil"])
        #expect(decision.askToBlock.map(\.label) == ["g", "d"])
        #expect(decision.vanished.isEmpty)
    }

    @Test func changedProgramIsTreatedAsNew() {
        let baseline = StartupGuardPolicy.baseline(from: [Self.item("a")])
        let decision = StartupGuardPolicy.decide(baseline: baseline, held: [], current: [Self.item("a", program: "/tmp/payload")])
        #expect(decision.autoBlock.map(\.label) == ["a"])
    }

    @Test func alreadyHeldIsNotHeldTwice() {
        var archive = StartupGuardArchive()
        archive.enable(current: [], at: Self.now)
        let current = [Self.item("evil"), Self.item("d", scope: .daemon)]
        let first = StartupGuardPolicy.decide(baseline: archive.baseline, held: archive.held, current: current)
        StartupGuardPolicy.apply(first, to: &archive, blockedIDs: [Self.item("evil").plistPath], at: Self.now)
        #expect(archive.held.map(\.status) == [.blocked, .awaitingBlock])
        #expect(StartupGuardPolicy.decide(baseline: archive.baseline, held: archive.held, current: current).isEmpty)
    }

    @Test func failedAutoBlockWaitsForUser() {
        var archive = StartupGuardArchive()
        let decision = StartupGuardPolicy.decide(baseline: [:], held: [], current: [Self.item("x")])
        StartupGuardPolicy.apply(decision, to: &archive, blockedIDs: [], at: Self.now)
        #expect(archive.held.first?.status == .awaitingBlock)
        #expect(archive.history.first?.action == "Couldn't block automatically")
    }

    @Test func vanishedHeldItemsAreDropped() {
        var archive = StartupGuardArchive()
        StartupGuardPolicy.apply(StartupGuardPolicy.decide(baseline: [:], held: [], current: [Self.item("x")]),
                                 to: &archive, blockedIDs: [], at: Self.now)
        let decision = StartupGuardPolicy.decide(baseline: [:], held: archive.held, current: [])
        #expect(decision.vanished == [Self.item("x").plistPath])
        StartupGuardPolicy.apply(decision, to: &archive, blockedIDs: [], at: Self.now)
        #expect(archive.held.isEmpty)
        #expect(archive.history.first?.action == "Removed from disk")
    }

    @Test func approveAndKeepBlockedAddToBaseline() {
        var archive = StartupGuardArchive()
        StartupGuardPolicy.apply(StartupGuardPolicy.decide(baseline: [:], held: [], current: [Self.item("x"), Self.item("y")]),
                                 to: &archive, blockedIDs: [], at: Self.now)
        archive.resolve(Self.item("x").plistPath, action: "Approved", at: Self.now)
        archive.markBlocked(Self.item("y").plistPath, at: Self.now)
        #expect(archive.held.map(\.status) == [.blocked])
        archive.resolve(Self.item("y").plistPath, action: "Kept blocked", at: Self.now)
        #expect(archive.held.isEmpty)
        #expect(archive.baseline.count == 2)
        #expect(StartupGuardPolicy.decide(baseline: archive.baseline, held: [], current: [Self.item("x"), Self.item("y")]).isEmpty)
        archive.resolve("/missing.plist", action: "Approved", at: Self.now)
        #expect(archive.history.first?.action == "Kept blocked")
    }

    @Test func forgetRemovesFromBaseline() {
        var archive = StartupGuardArchive()
        StartupGuardPolicy.apply(StartupGuardPolicy.decide(baseline: [:], held: [], current: [Self.item("x")]),
                                 to: &archive, blockedIDs: [], at: Self.now)
        archive.forget(Self.item("x").plistPath, action: "Moved to Trash", at: Self.now)
        #expect(archive.held.isEmpty)
        #expect(archive.baseline.isEmpty)
    }

    @Test func historyIsCapped() {
        var archive = StartupGuardArchive()
        for index in 0..<(StartupGuardArchive.historyLimit + 10) {
            archive.log(StartupGuardEvent(date: Self.now, name: "n\(index)", path: "", action: "a"))
        }
        #expect(archive.history.count == StartupGuardArchive.historyLimit)
        #expect(archive.history.first?.name == "n\(StartupGuardArchive.historyLimit + 9)")
    }

    @Test func storeRoundTripsAndToleratesCorruption() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = StartupGuardStore(url: URL(fileURLWithPath: dir + "/nested/guard.json"))
        #expect(store.load() == StartupGuardArchive())
        var archive = StartupGuardArchive()
        archive.enable(current: [Self.item("a")], at: Self.now)
        StartupGuardPolicy.apply(StartupGuardPolicy.decide(baseline: archive.baseline, held: [], current: [Self.item("a"), Self.item("b")]),
                                 to: &archive, blockedIDs: [], at: Self.now)
        try store.save(archive)
        #expect(store.load() == archive)
        try Data("{broken".utf8).write(to: store.url)
        #expect(store.load() == StartupGuardArchive())
        #expect(store.load().isEnabled == false)
    }
}

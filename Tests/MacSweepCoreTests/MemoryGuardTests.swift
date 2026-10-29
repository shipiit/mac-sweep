import Foundation
import Testing
@testable import MacSweepCore

@Suite struct MemoryGuardTests {
    func idle(_ pid: Int32, _ gb: Double) -> IdleApp {
        IdleApp(app: RunningAppSnapshot(pid: pid, bundleID: "b\(pid)", name: "App\(pid)", bundlePath: nil, launchDate: nil, lastActive: nil, isFrontmost: false),
                memory: UInt64(gb * Double(1 << 30)), processCount: 1, idleSince: Date(timeIntervalSince1970: 0), isAtLeast: false)
    }

    @Test func doesNothingWhenOffNormalOrBrief() {
        let apps = [idle(1, 3)]
        #expect(MemoryGuard.plan(pressure: .warning, sustainedFor: 120, idle: apps, mode: .off) == nil)
        #expect(MemoryGuard.plan(pressure: .normal, sustainedFor: 999, idle: apps, mode: .quitIdle) == nil)
        #expect(MemoryGuard.plan(pressure: .critical, sustainedFor: 30, idle: apps, mode: .quitIdle) == nil, "brief spikes are ignored")
        #expect(MemoryGuard.plan(pressure: .critical, sustainedFor: 120, idle: [], mode: .quitIdle) == nil)
    }

    @Test func notifyOnlySuggestsTopThree() throws {
        let plan = try #require(MemoryGuard.plan(pressure: .warning, sustainedFor: 61, idle: [idle(1, 0.5), idle(2, 3), idle(3, 1), idle(4, 2)], mode: .notify))
        #expect(plan.quit.isEmpty && plan.suggest.map(\.id) == [2, 4, 3])
    }

    @Test func quitsBiggestUntilTargetMetAtMostThree() throws {
        let warning = try #require(MemoryGuard.plan(pressure: .warning, sustainedFor: 61, idle: [idle(1, 0.5), idle(2, 1.5), idle(3, 1)], mode: .quitIdle))
        #expect(warning.quit.map(\.id) == [2, 3] && warning.suggest.map(\.id) == [1])
        #expect(warning.freesAtLeast == UInt64(2.5 * Double(1 << 30)))
        let critical = try #require(MemoryGuard.plan(pressure: .critical, sustainedFor: 61, idle: (1...6).map { idle(Int32($0), 0.5) }, mode: .quitIdle))
        #expect(critical.quit.count == 3, "never more than three apps at once")
        #expect(MemoryGuard.target(for: .critical) > MemoryGuard.target(for: .warning))
    }
}

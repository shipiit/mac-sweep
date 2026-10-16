import Foundation
import Testing
@testable import MacSweepCore

enum AlertFixtures {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let gb: UInt64 = 1_000_000_000

    static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    static func volume(free: UInt64, total: UInt64 = 1_000 * gb) -> VolumeStats {
        VolumeStats(total: total, available: free)
    }
}

@Suite struct LowDiskAlertTests {
    typealias F = AlertFixtures

    func run(_ engine: inout AlertEngine, free: UInt64, total: UInt64 = 1_000 * AlertFixtures.gb, at seconds: TimeInterval = 0) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), volume: F.volume(free: free, total: total)))
    }

    @Test func firesBelowTenPercent() {
        var engine = AlertEngine()
        let alerts = run(&engine, free: 99 * F.gb)
        #expect(alerts.count == 1)
        #expect(alerts.first?.rule == .lowDisk)
        #expect(alerts.first?.severity == .warning)
    }

    @Test func firesBelowFifteenGBEvenWhenPercentIsFine() {
        var engine = AlertEngine()
        // 14.9 GB of 100 GB is 14.9%: the absolute limit catches it.
        #expect(run(&engine, free: 14_900_000_000, total: 100 * F.gb).count == 1)
    }

    @Test func boundaryValuesDoNotFire() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 100 * F.gb).isEmpty, "exactly 10% is not below 10%")
        var small = AlertEngine()
        #expect(run(&small, free: 15 * F.gb, total: 100 * F.gb).isEmpty, "exactly 15 GB is not below 15 GB")
    }

    @Test func healthyDiskDoesNotFire() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 500 * F.gb).isEmpty)
    }

    @Test func zeroTotalIsIgnored() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 0, total: 0).isEmpty)
    }

    @Test func criticalWhenNearlyFull() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 4 * F.gb).first?.severity == .critical)
    }

    @Test func firesOncePerCondition() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 50 * F.gb, at: 0).count == 1)
        #expect(run(&engine, free: 40 * F.gb, at: 60).isEmpty)
        #expect(run(&engine, free: 40 * F.gb, at: 30 * 86_400).isEmpty, "still the same condition")
    }

    @Test func hoveringAroundTheLineDoesNotRearm() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 99 * F.gb, at: 0).count == 1)
        // 11% is above the alert line but below the 12% re-arm line.
        #expect(run(&engine, free: 110 * F.gb, at: 7 * 3_600).isEmpty)
        #expect(run(&engine, free: 99 * F.gb, at: 8 * 3_600).isEmpty)
    }

    @Test func rearmsAfterRecoveryButRespectsCooldown() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 99 * F.gb, at: 0).count == 1)
        #expect(run(&engine, free: 300 * F.gb, at: 60).isEmpty)
        #expect(run(&engine, free: 99 * F.gb, at: 3_600).isEmpty, "inside the 6 h cooldown")
        #expect(run(&engine, free: 300 * F.gb, at: 3 * 3_600).isEmpty)
        #expect(run(&engine, free: 99 * F.gb, at: 7 * 3_600).count == 1, "after the cooldown")
    }

    @Test func disabledRuleNeverFiresAndFiresOnceEnabled() {
        var engine = AlertEngine()
        let snapshot = AlertSnapshot(date: F.at(0), volume: F.volume(free: 10 * F.gb))
        #expect(engine.evaluate(snapshot, enabled: []).isEmpty)
        #expect(engine.evaluate(snapshot, enabled: [.lowDisk]).count == 1)
    }

    @Test func missingVolumeNeitherFiresNorRearms() {
        var engine = AlertEngine()
        #expect(run(&engine, free: 99 * F.gb, at: 0).count == 1)
        #expect(engine.evaluate(AlertSnapshot(date: F.at(7 * 3_600))).isEmpty)
        #expect(run(&engine, free: 99 * F.gb, at: 8 * 3_600).isEmpty)
    }
}

@Suite struct ThermalAlertTests {
    typealias F = AlertFixtures

    func run(_ engine: inout AlertEngine, _ level: ThermalLevel, at seconds: TimeInterval) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), thermal: level))
    }

    @Test func coolAndWarmDoNotFire() {
        var engine = AlertEngine()
        #expect(run(&engine, .nominal, at: 0).isEmpty)
        #expect(run(&engine, .fair, at: 1).isEmpty, "fair is the boundary below serious")
    }

    @Test func seriousFiresWarningCriticalFiresCritical() {
        var hot = AlertEngine()
        #expect(run(&hot, .serious, at: 0).first?.severity == .warning)
        var throttling = AlertEngine()
        #expect(run(&throttling, .critical, at: 0).first?.severity == .critical)
    }

    @Test func staysQuietWhileHotAndHonoursCooldown() {
        var engine = AlertEngine()
        #expect(run(&engine, .serious, at: 0).count == 1)
        #expect(run(&engine, .critical, at: 10).isEmpty)
        #expect(run(&engine, .nominal, at: 20).isEmpty)
        #expect(run(&engine, .serious, at: 29 * 60).isEmpty, "inside 30 min cooldown")
        #expect(run(&engine, .nominal, at: 29 * 60 + 1).isEmpty)
        #expect(run(&engine, .serious, at: 30 * 60).count == 1)
    }
}

@Suite struct TrashAlertTests {
    typealias F = AlertFixtures

    func run(_ engine: inout AlertEngine, _ bytes: UInt64, at seconds: TimeInterval) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), trashBytes: bytes))
    }

    @Test func firesAboveFiveGB() {
        var engine = AlertEngine()
        #expect(run(&engine, 5 * F.gb + 1, at: 0).first?.rule == .largeTrash)
    }

    @Test func exactlyFiveGBAndEmptyDoNotFire() {
        var engine = AlertEngine()
        #expect(run(&engine, 5 * F.gb, at: 0).isEmpty)
        #expect(run(&engine, 0, at: 1).isEmpty)
    }

    @Test func oncePerConditionWithDailyCooldown() {
        var engine = AlertEngine()
        #expect(run(&engine, 8 * F.gb, at: 0).count == 1)
        #expect(run(&engine, 9 * F.gb, at: 60).isEmpty)
        #expect(run(&engine, 0, at: 120).isEmpty)
        #expect(run(&engine, 8 * F.gb, at: 3_600).isEmpty)
        #expect(run(&engine, 0, at: 3_700).isEmpty)
        #expect(run(&engine, 8 * F.gb, at: 86_400).count == 1)
    }
}

@Suite struct BatteryAlertTests {
    typealias F = AlertFixtures

    func run(_ engine: inout AlertEngine, _ health: Double, at seconds: TimeInterval = 0) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), batteryHealth: health))
    }

    @Test func firstReadingOnlyRecordsBaseline() {
        var engine = AlertEngine()
        #expect(run(&engine, 0.9).isEmpty)
        #expect(engine.state.batteryBaseline == 0.9)
    }

    @Test func dropOfTwoPointsFiresAndMovesBaseline() {
        var engine = AlertEngine()
        _ = run(&engine, 0.90)
        let alerts = run(&engine, 0.88, at: 60)
        #expect(alerts.count == 1)
        #expect(alerts.first?.severity == .warning)
        #expect(engine.state.batteryBaseline == 0.88)
        #expect(run(&engine, 0.88, at: 120).isEmpty)
    }

    @Test func smallDropDoesNotFireButAccumulates() {
        var engine = AlertEngine()
        _ = run(&engine, 0.90)
        #expect(run(&engine, 0.89, at: 60).isEmpty)
        #expect(engine.state.batteryBaseline == 0.90, "slow drift is measured from the stored value")
        #expect(run(&engine, 0.875, at: 120).count == 1)
    }

    @Test func riseMovesBaselineUp() {
        var engine = AlertEngine()
        _ = run(&engine, 0.85)
        #expect(run(&engine, 0.87, at: 60).isEmpty)
        #expect(engine.state.batteryBaseline == 0.87)
    }

    @Test func belowEightyPercentIsCritical() {
        var engine = AlertEngine()
        _ = run(&engine, 0.81)
        #expect(run(&engine, 0.79, at: 60).first?.severity == .critical)
    }

    @Test func disabledKeepsBaselineForLater() {
        var engine = AlertEngine()
        _ = run(&engine, 0.90)
        #expect(engine.evaluate(AlertSnapshot(date: F.at(60), batteryHealth: 0.85), enabled: []).isEmpty)
        #expect(engine.state.batteryBaseline == 0.90)
        #expect(run(&engine, 0.85, at: 120).count == 1)
    }
}

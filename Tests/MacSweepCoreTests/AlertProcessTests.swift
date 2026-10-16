import Foundation
import Testing
@testable import MacSweepCore

@Suite struct SustainedCPUAlertTests {
    typealias F = AlertFixtures

    func process(_ cpu: Double, pid: Int32 = 42, name: String = "Spinner", started: Date? = AlertFixtures.start) -> ProcessLoad {
        ProcessLoad(pid: pid, started: started, name: name, path: "/Applications/\(name).app", cpuPercent: cpu)
    }

    /// Simulates the process sampler every `step` seconds from `from` to `to`.
    func feed(_ engine: inout AlertEngine, _ processes: [ProcessLoad], from: TimeInterval, to: TimeInterval,
              step: TimeInterval = 10) -> [SmartAlert] {
        stride(from: from, through: to, by: step).flatMap { second in
            engine.evaluate(AlertSnapshot(date: F.at(second), processes: processes, processesSampledAt: F.at(second)))
        }
    }

    @Test func firesAfterTwoMinutesAboveEightyPercent() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(95)], from: 0, to: 110).isEmpty)
        let alerts = feed(&engine, [process(95)], from: 120, to: 120)
        #expect(alerts.count == 1)
        #expect(alerts.first?.key == "cpu:Spinner")
        #expect(alerts.first?.subjectPath == "/Applications/Spinner.app")
    }

    @Test func exactlyEightyPercentNeverFires() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(80)], from: 0, to: 600).isEmpty)
    }

    @Test func dipResetsTheStreak() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(90)], from: 0, to: 100).isEmpty)
        #expect(feed(&engine, [process(20)], from: 110, to: 110).isEmpty)
        #expect(feed(&engine, [process(90)], from: 120, to: 230).isEmpty)
        #expect(feed(&engine, [process(90)], from: 240, to: 240).count == 1)
    }

    @Test func longSampleGapRestartsStreak() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(90)], from: 0, to: 60).isEmpty)
        // Asleep for an hour: the streak starts over instead of counting the gap.
        #expect(feed(&engine, [process(90)], from: 3_660, to: 3_770).isEmpty)
        #expect(feed(&engine, [process(90)], from: 3_780, to: 3_780).count == 1)
    }

    @Test func repeatedEvaluationsOfOneSampleDoNotAdvanceTime() {
        var engine = AlertEngine()
        for second in stride(from: 0.0, through: 600, by: 2) {
            let snapshot = AlertSnapshot(date: F.at(second), processes: [process(99)], processesSampledAt: F.at(0))
            #expect(engine.evaluate(snapshot).isEmpty)
        }
    }

    @Test func reusedPIDIsANewProcess() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(90)], from: 0, to: 100).isEmpty)
        let reborn = process(90, started: F.at(105))
        #expect(feed(&engine, [reborn], from: 110, to: 220).isEmpty)
    }

    @Test func firesOnceThenCooldownAfterRecovery() {
        var engine = AlertEngine()
        #expect(feed(&engine, [process(90)], from: 0, to: 600).count == 1)
        #expect(feed(&engine, [process(5)], from: 610, to: 610).isEmpty)
        #expect(feed(&engine, [process(90)], from: 620, to: 900).isEmpty, "30 min cooldown")
        #expect(feed(&engine, [process(5)], from: 910, to: 910).isEmpty)
        #expect(feed(&engine, [process(90)], from: 1_900, to: 2_020).count == 1)
    }

    @Test func eachProcessFiresSeparately() {
        var engine = AlertEngine()
        let alerts = feed(&engine, [process(90, pid: 1, name: "A"), process(90, pid: 2, name: "B"), process(10, pid: 3, name: "C")],
                          from: 0, to: 120)
        #expect(Set(alerts.map(\.key)) == ["cpu:A", "cpu:B"])
    }

    @Test func emptyProcessListClearsStreaks() {
        var engine = AlertEngine()
        _ = feed(&engine, [process(90)], from: 0, to: 60)
        _ = feed(&engine, [], from: 70, to: 70)
        #expect(engine.state.cpuStreaks.isEmpty)
    }
}

@Suite struct MemoryLeakAlertTests {
    typealias F = AlertFixtures

    func leaking(_ growth: Int64, growing: Bool = true, name: String = "Leaky") -> ProcessLoad {
        ProcessLoad(pid: 7, started: F.start, name: name, path: nil, cpuPercent: 1,
                    memoryTrend: MemoryTrendSummary(bytesPerMinute: 20_000_000, growth: growth, isSteadilyGrowing: growing))
    }

    func run(_ engine: inout AlertEngine, _ processes: [ProcessLoad], at seconds: TimeInterval) -> [SmartAlert] {
        engine.evaluate(AlertSnapshot(date: F.at(seconds), processes: processes))
    }

    @Test func steadyGrowthFires() {
        var engine = AlertEngine()
        let alerts = run(&engine, [leaking(300_000_000)], at: 0)
        #expect(alerts.count == 1)
        #expect(alerts.first?.rule == .memoryLeak)
        #expect(alerts.first?.key == "leak:Leaky")
    }

    @Test func notSteadyOrTooSmallDoesNotFire() {
        var engine = AlertEngine()
        #expect(run(&engine, [leaking(300_000_000, growing: false)], at: 0).isEmpty)
        #expect(run(&engine, [leaking(99_999_999)], at: 1).isEmpty)
    }

    @Test func minimumGrowthBoundaryFires() {
        var engine = AlertEngine()
        #expect(run(&engine, [leaking(100_000_000)], at: 0).count == 1)
    }

    @Test func firesOnceWhileGrowingAndCoolsDownAfterwards() {
        var engine = AlertEngine()
        #expect(run(&engine, [leaking(300_000_000)], at: 0).count == 1)
        #expect(run(&engine, [leaking(400_000_000)], at: 60).isEmpty)
        #expect(run(&engine, [], at: 120).isEmpty)
        #expect(run(&engine, [leaking(300_000_000)], at: 1_800).isEmpty, "inside the 1 h cooldown")
        #expect(run(&engine, [], at: 1_900).isEmpty)
        #expect(run(&engine, [leaking(300_000_000)], at: 3_700).count == 1)
    }

    @Test func disabledDoesNotFire() {
        var engine = AlertEngine()
        let snapshot = AlertSnapshot(date: F.at(0), processes: [leaking(300_000_000)])
        #expect(engine.evaluate(snapshot, enabled: [.sustainedCPU]).isEmpty)
    }
}

import Foundation
import Testing
@testable import MacSweepCore

@Suite struct TimelineAccumulatorTests {
    let start = TimelineFixtures.start

    func reading(_ seconds: TimeInterval, cpu: Double, process: String? = nil, memory: UInt64? = 4_000,
                 disk: UInt64? = nil, cost: Double? = nil) -> TimelineReading {
        TimelineReading(time: start.addingTimeInterval(seconds), cpu: cpu, memoryUsed: memory, diskFree: disk,
                        downloadRate: 100, uploadRate: 50, topProcess: process, topProcessCPU: cpu * 400, aiCost: cost)
    }

    @Test func slotsAlignToWallClock() {
        #expect(TimelineAccumulator.slotStart(for: start.addingTimeInterval(299)) == start)
        #expect(TimelineAccumulator.slotStart(for: start.addingTimeInterval(300)) == start.addingTimeInterval(300))
    }

    @Test func emitsMeanAndPeakWhenTheNextSlotStarts() throws {
        var accumulator = TimelineAccumulator()
        #expect(accumulator.pending() == nil)
        #expect(accumulator.add(reading(0, cpu: 0.2, process: "a", disk: 9)) == nil)
        #expect(accumulator.add(reading(100, cpu: 0.9, process: "spiky", memory: nil)) == nil)
        #expect(accumulator.add(reading(200, cpu: 0.1, process: "b", memory: 2_000, cost: 1.5)) == nil)
        let emitted = accumulator.add(reading(300, cpu: 0.5))
        let sample = try #require(emitted)
        #expect(sample.time == start)
        #expect(abs(sample.cpu - 0.4) < 1e-9)
        #expect(sample.cpuPeak == 0.9)
        #expect(sample.topProcess == "spiky")
        #expect(sample.topProcessCPU == 360)
        #expect(sample.memoryUsed == 3_000, "readings without memory are skipped, not counted as zero")
        #expect(sample.diskFree == 9)
        #expect(sample.aiCost == 1.5)
        #expect(sample.downloadRate == 100)
        #expect(accumulator.pending()?.time == start.addingTimeInterval(300))
    }

    @Test func gapEmitsOnlyTheLastSlot() throws {
        var accumulator = TimelineAccumulator()
        _ = accumulator.add(reading(0, cpu: 0.3))
        let emitted = accumulator.add(reading(7_200, cpu: 0.3))
        let sample = try #require(emitted)
        #expect(sample.time == start)
        #expect(accumulator.pending()?.time == start.addingTimeInterval(7_200))
    }

    @Test func clockGoingBackwardsDropsTheSlot() {
        var accumulator = TimelineAccumulator()
        _ = accumulator.add(reading(600, cpu: 0.3))
        #expect(accumulator.add(reading(0, cpu: 0.3)) == nil)
        #expect(accumulator.pending()?.time == start)
    }

    @Test func invalidCPUIsClamped() throws {
        var accumulator = TimelineAccumulator()
        _ = accumulator.add(reading(0, cpu: .nan))
        _ = accumulator.add(reading(1, cpu: 3))
        let sample = try #require(accumulator.pending())
        #expect(sample.cpuPeak == 1)
        #expect(sample.cpu == 0.5)
    }
}

@Suite struct TimelineAggregatorTests {
    typealias F = TimelineFixtures

    var now: Date { F.start.addingTimeInterval(86_400) }

    @Test func emptyInputGivesNothing() {
        #expect(TimelineAggregator.points([], range: .day, now: now).isEmpty)
        #expect(TimelineAggregator.spikes([]).isEmpty)
        #expect(TimelineAggregator.dailyCosts([]).isEmpty)
    }

    @Test func dayRangeKeepsFiveMinuteResolutionAndDropsOldSamples() {
        let samples = (0...288).map { F.sample($0) }
        let points = TimelineAggregator.points(samples, range: .day, now: now)
        #expect(points.count == 288, "the sample exactly 24 h ago is outside the window")
        #expect(Set(points.map(\.segment)) == [0])
    }

    @Test func weekRangeAveragesIntoHalfHours() throws {
        let samples = (0..<6).map { F.sample($0, cpu: Double($0) / 10, peak: $0 == 2 ? 0.95 : nil, process: "p\($0)") }
        let points = TimelineAggregator.points(samples, range: .week, now: now)
        let point = try #require(points.first)
        #expect(points.count == 1)
        #expect(abs(point.cpu - 0.25) < 1e-9)
        #expect(point.cpuPeak == 0.95)
        #expect(point.topProcess == "p2")
    }

    @Test func gapsStartANewSegment() {
        let samples = [F.sample(1), F.sample(2), F.sample(20), F.sample(21)]
        let points = TimelineAggregator.points(samples, range: .day, now: now)
        #expect(points.map(\.segment) == [0, 0, 1, 1])
    }

    @Test func fortnightUsesHourBuckets() {
        let samples = (0..<24).map { F.sample($0) }
        #expect(TimelineAggregator.points(samples, range: .fortnight, now: now).count == 2)
        #expect(TimelineRange.fortnight.title == "14d")
        #expect(TimelineRange.day.title == "24h")
    }

    @Test func spikesFindStandoutLocalPeaks() {
        var samples = (0..<50).map { F.sample($0, cpu: 0.1) }
        samples[10] = F.sample(10, cpu: 0.9, process: "Xcode")
        samples[30] = F.sample(30, cpu: 0.7, process: "Chrome")
        samples[31] = F.sample(31, cpu: 0.6, process: "Chrome")
        let points = TimelineAggregator.points(samples, range: .day, now: now)
        let spikes = TimelineAggregator.spikes(points)
        #expect(spikes.map(\.topProcess) == ["Xcode", "Chrome"])
        #expect(TimelineAggregator.spikes(points, limit: 1).map(\.topProcess) == ["Xcode"])
        #expect(TimelineAggregator.spikes(points, limit: 0).isEmpty)
    }

    @Test func flatOrQuietSeriesHasNoSpikes() {
        let flat = TimelineAggregator.points((0..<20).map { F.sample($0, cpu: 0.9) }, range: .day, now: now)
        #expect(TimelineAggregator.spikes(flat).isEmpty, "nothing stands out from a uniformly busy series")
        var quiet = (0..<20).map { F.sample($0, cpu: 0.01) }
        quiet[5] = F.sample(5, cpu: 0.3)
        let points = TimelineAggregator.points(quiet, range: .day, now: now)
        #expect(TimelineAggregator.spikes(points).isEmpty, "below the 50% minimum")
        #expect(TimelineAggregator.spikes(Array(points.prefix(2))).isEmpty)
    }

    @Test func dailyCostTakesEachDaysRunningMaximum() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let samples = [F.sample(0, cost: 1), F.sample(1, cost: 3), F.sample(2), F.sample(3, cost: .infinity),
                       F.sample(288, cost: 0.5)]
        let costs = TimelineAggregator.dailyCosts(samples, calendar: calendar)
        #expect(costs.map(\.cost) == [3, 0.5])
        #expect(costs.first?.day == calendar.startOfDay(for: F.start))
    }
}

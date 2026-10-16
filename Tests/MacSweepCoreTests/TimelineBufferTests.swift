import Foundation
import Testing
@testable import MacSweepCore

enum TimelineFixtures {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func sample(_ slot: Int, cpu: Double = 0.2, peak: Double? = nil, process: String = "proc",
                       cost: Double? = nil) -> TimelineSample {
        TimelineSample(time: start.addingTimeInterval(TimeInterval(slot) * 300), cpu: cpu, cpuPeak: peak ?? cpu,
                       memoryUsed: 8_000_000_000, diskFree: 100_000_000_000, downloadRate: 1_000, uploadRate: 500,
                       aiCost: cost, topProcess: process, topProcessCPU: 150)
    }
}

@Suite struct TimelineBufferTests {
    typealias F = TimelineFixtures

    @Test func emptyBuffer() {
        let buffer = TimelineBuffer(capacity: 4)
        #expect(buffer.isEmpty)
        #expect(buffer.samples.isEmpty)
        #expect(buffer.latest == nil)
        #expect(TimelineBuffer(data: buffer.encoded()) == buffer)
    }

    @Test func wrapsAroundKeepingNewestInOrder() {
        var buffer = TimelineBuffer(capacity: 3)
        for slot in 0..<5 { buffer.append(F.sample(slot)) }
        #expect(buffer.count == 3)
        #expect(buffer.samples.map(\.time) == [2, 3, 4].map { F.sample($0).time })
        #expect(buffer.latest?.time == F.sample(4).time)
    }

    @Test func ignoresDuplicateAndOlderSlots() {
        var buffer = TimelineBuffer(capacity: 5)
        buffer.append(F.sample(3))
        buffer.append(F.sample(3, cpu: 0.9))
        buffer.append(F.sample(1))
        #expect(buffer.count == 1)
        #expect(buffer.latest?.cpu == 0.2)
    }

    @Test func zeroCapacityIsClampedToOne() {
        var buffer = TimelineBuffer(capacity: 0)
        buffer.append(F.sample(0))
        buffer.append(F.sample(1))
        #expect(buffer.capacity == 1)
        #expect(buffer.samples.map(\.time) == [F.sample(1).time])
    }

    @Test func encodesAndDecodesAfterWraparound() throws {
        var buffer = TimelineBuffer(capacity: 4)
        for slot in 0..<7 { buffer.append(F.sample(slot, cost: slot.isMultiple(of: 2) ? Double(slot) : nil)) }
        let decoded = try #require(TimelineBuffer(data: buffer.encoded()))
        #expect(decoded == buffer)
        #expect(decoded.samples.map(\.aiCost) == [nil, 4, nil, 6])
        #expect(decoded.samples.first?.topProcess == "proc")
    }

    @Test func fullFourteenDaysStaysSmall() {
        var buffer = TimelineBuffer()
        for slot in 0..<(TimelineBuffer.defaultCapacity + 10) { buffer.append(F.sample(slot)) }
        #expect(buffer.count == TimelineBuffer.defaultCapacity)
        #expect(buffer.encoded().count < 2_000_000)
    }

    @Test func rejectsCorruptData() {
        var buffer = TimelineBuffer(capacity: 4)
        buffer.append(F.sample(0))
        let good = buffer.encoded()
        #expect(TimelineBuffer(data: Data()) == nil)
        #expect(TimelineBuffer(data: Data("junkjunkjunkjunkjunk".utf8)) == nil)
        #expect(TimelineBuffer(data: good.dropLast()) == nil, "truncated")
        #expect(TimelineBuffer(data: good + Data([0])) == nil, "trailing bytes")
        var badVersion = good
        badVersion[4] = 9
        #expect(TimelineBuffer(data: badVersion) == nil)
        var countOverCapacity = good
        countOverCapacity[12] = 9
        #expect(TimelineBuffer(data: countOverCapacity) == nil)
        var badFraction = good
        badFraction[TimelineBuffer.headerSize + 4] = 0xFF
        badFraction[TimelineBuffer.headerSize + 5] = 0xFF
        #expect(TimelineBuffer(data: badFraction) == nil)
    }

    @Test func clampsOutOfRangeValues() throws {
        var buffer = TimelineBuffer(capacity: 2)
        var sample = F.sample(0, cpu: 1.7)
        sample.cpuPeak = .nan
        buffer.append(sample)
        let decoded = try #require(TimelineBuffer(data: buffer.encoded()))
        #expect(decoded.latest?.cpu == 1)
        #expect(decoded.latest?.cpuPeak == 0)
    }

    @Test func longAndMultibyteNamesTruncateOnCharacterBoundaries() throws {
        #expect(TimelineRecord.truncated("") == "")
        let long = String(repeating: "a", count: 100)
        #expect(TimelineRecord.truncated(long).utf8.count == TimelineRecord.nameBytes)
        let emoji = String(repeating: "\u{1F600}", count: 10)
        let cut = TimelineRecord.truncated(emoji)
        #expect(cut.utf8.count <= TimelineRecord.nameBytes)
        #expect(cut.count == TimelineRecord.nameBytes / 4)

        var buffer = TimelineBuffer(capacity: 1)
        buffer.append(F.sample(0, process: emoji))
        let decoded = try #require(TimelineBuffer(data: buffer.encoded()))
        #expect(decoded.latest?.topProcess == cut)
    }
}

@Suite struct TimelineStoreTests {
    typealias F = TimelineFixtures

    @Test func roundTripsThroughFile() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = TimelineStore(url: URL(fileURLWithPath: dir + "/sub/timeline.bin"))
        var buffer = TimelineBuffer(capacity: 10)
        for slot in 0..<3 { buffer.append(F.sample(slot)) }
        try store.save(buffer)
        #expect(store.load(capacity: 10) == buffer)
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = TimelineStore(url: URL(fileURLWithPath: dir + "/timeline.bin"))
        #expect(store.load(capacity: 8) == TimelineBuffer(capacity: 8))
        try Data(repeating: 7, count: 99).write(to: store.url)
        let loaded = store.load(capacity: 8)
        #expect(loaded.isEmpty)
        #expect(loaded.capacity == 8)
    }

    @Test func loadResizesToRequestedCapacity() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = TimelineStore(url: URL(fileURLWithPath: dir + "/timeline.bin"))
        var buffer = TimelineBuffer(capacity: 10)
        for slot in 0..<6 { buffer.append(F.sample(slot)) }
        try store.save(buffer)
        let smaller = store.load(capacity: 4)
        #expect(smaller.capacity == 4)
        #expect(smaller.samples.map(\.time) == (2..<6).map { F.sample($0).time })
    }
}

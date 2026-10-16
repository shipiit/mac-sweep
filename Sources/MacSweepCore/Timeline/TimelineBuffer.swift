import Foundation
import os

/// Fixed-capacity ring of samples: once full, each new sample overwrites the oldest.
public struct TimelineBuffer: Sendable, Equatable {
    /// 14 days of 5-minute slots.
    public static let defaultCapacity = 14 * 288

    public let capacity: Int
    private var storage: [TimelineSample] = []
    /// Where the next sample goes once the buffer is full.
    private var head = 0

    public init(capacity: Int = TimelineBuffer.defaultCapacity) {
        self.capacity = max(capacity, 1)
        storage.reserveCapacity(min(self.capacity, 512))
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    /// Oldest first.
    public var samples: [TimelineSample] {
        Array(storage[head...] + storage[..<head])
    }

    public var latest: TimelineSample? {
        storage.isEmpty ? nil : storage[(head + storage.count - 1) % storage.count]
    }

    /// Samples must move forward in time; a duplicate or older slot (clock change) is ignored.
    public mutating func append(_ sample: TimelineSample) {
        if let latest, sample.time <= latest.time { return }
        if storage.count < capacity {
            storage.append(sample)
        } else {
            storage[head] = sample
            head = (head + 1) % capacity
        }
    }

    // MARK: File format: "MSTL", version, record size, capacity, count, then records oldest first.

    static let magic: [UInt8] = Array("MSTL".utf8)
    static let version: UInt16 = 1
    static let headerSize = 4 + 2 + 2 + 4 + 4
    static let maximumCapacity = 100_000

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerSize + count * TimelineRecord.size)
        data.append(contentsOf: Self.magic)
        TimelineRecord.put(Self.version, &data)
        TimelineRecord.put(UInt16(TimelineRecord.size), &data)
        TimelineRecord.put(UInt32(capacity), &data)
        TimelineRecord.put(UInt32(count), &data)
        for sample in samples { TimelineRecord.append(sample, to: &data) }
        return data
    }

    /// Nil when the data isn't a complete, valid timeline file.
    public init?(data: Data) {
        guard data.count >= Self.headerSize, Array(data.prefix(4)) == Self.magic else { return nil }
        let decoded: (capacity: Int, samples: [TimelineSample])? = data.withUnsafeBytes { bytes in
            let version = UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
            let recordSize = Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: 6, as: UInt16.self)))
            let capacity = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self)))
            let count = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 12, as: UInt32.self)))
            guard version == Self.version, recordSize == TimelineRecord.size,
                  capacity > 0, capacity <= Self.maximumCapacity, count <= capacity,
                  bytes.count == Self.headerSize + count * recordSize
            else { return nil }
            var samples: [TimelineSample] = []
            samples.reserveCapacity(count)
            for index in 0..<count {
                guard let sample = TimelineRecord.read(bytes, at: Self.headerSize + index * recordSize) else { return nil }
                samples.append(sample)
            }
            return (capacity, samples)
        }
        guard let decoded else { return nil }
        self.init(capacity: decoded.capacity)
        for sample in decoded.samples { append(sample) }
    }

    public static func == (lhs: TimelineBuffer, rhs: TimelineBuffer) -> Bool {
        lhs.capacity == rhs.capacity && lhs.samples == rhs.samples
    }

    /// A buffer with a different capacity keeping the newest samples.
    public func resized(to newCapacity: Int) -> TimelineBuffer {
        var copy = TimelineBuffer(capacity: newCapacity)
        for sample in samples.suffix(copy.capacity) { copy.append(sample) }
        return copy
    }
}

public struct TimelineStore: Sendable {
    public let url: URL
    private static let log = Logger(subsystem: Log.subsystem, category: "timeline")

    public init(url: URL) {
        self.url = url
    }

    public static var standard: TimelineStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return TimelineStore(url: base.appendingPathComponent("MacSweep/timeline.bin"))
    }

    public func save(_ buffer: TimelineBuffer) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try buffer.encoded().write(to: url, options: .atomic)
    }

    /// An empty buffer when there is no file or it is corrupt; always sized to `capacity`.
    public func load(capacity: Int = TimelineBuffer.defaultCapacity) -> TimelineBuffer {
        guard let data = try? Data(contentsOf: url) else { return TimelineBuffer(capacity: capacity) }
        guard let buffer = TimelineBuffer(data: data) else {
            Self.log.warning("discarding unreadable timeline file (\(data.count) bytes)")
            return TimelineBuffer(capacity: capacity)
        }
        return buffer.capacity == capacity ? buffer : buffer.resized(to: capacity)
    }
}

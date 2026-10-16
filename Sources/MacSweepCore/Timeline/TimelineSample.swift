import Foundation

/// One 5-minute slot of system history. Mean values smooth the slot; the peak and the process
/// using the most CPU at that peak explain spikes.
public struct TimelineSample: Sendable, Equatable {
    /// Start of the slot, whole seconds.
    public var time: Date
    /// Mean busy fraction 0...1 across the slot.
    public var cpu: Double
    /// Highest busy fraction 0...1 seen in the slot.
    public var cpuPeak: Double
    public var memoryUsed: UInt64
    public var diskFree: UInt64
    /// Mean bytes per second.
    public var downloadRate: Double
    public var uploadRate: Double
    /// AI spend so far that day in USD; nil when unknown.
    public var aiCost: Double?
    public var topProcess: String
    /// Percent of one core used by `topProcess` at the peak.
    public var topProcessCPU: Double

    public init(time: Date, cpu: Double, cpuPeak: Double, memoryUsed: UInt64, diskFree: UInt64, downloadRate: Double,
                uploadRate: Double, aiCost: Double? = nil, topProcess: String = "", topProcessCPU: Double = 0) {
        self.time = time
        self.cpu = cpu
        self.cpuPeak = cpuPeak
        self.memoryUsed = memoryUsed
        self.diskFree = diskFree
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.aiCost = aiCost
        self.topProcess = topProcess
        self.topProcessCPU = topProcessCPU
    }
}

/// Fixed-size little-endian record so 14 days of samples stay around 270 KB on disk.
enum TimelineRecord {
    static let nameBytes = 28
    static let size = 4 + 2 + 2 + 8 + 8 + 4 + 4 + 4 + 4 + nameBytes

    static func append(_ sample: TimelineSample, to data: inout Data) {
        put(UInt32(clamping: Int64(sample.time.timeIntervalSince1970.rounded(.down))), &data)
        put(fraction(sample.cpu), &data)
        put(fraction(sample.cpuPeak), &data)
        put(sample.memoryUsed, &data)
        put(sample.diskFree, &data)
        put(Float(sample.downloadRate).bitPattern, &data)
        put(Float(sample.uploadRate).bitPattern, &data)
        put(Float(sample.aiCost ?? .nan).bitPattern, &data)
        put(Float(sample.topProcessCPU).bitPattern, &data)
        var name = Array(truncated(sample.topProcess).utf8)
        name += Array(repeating: 0, count: nameBytes - name.count)
        data.append(contentsOf: name)
    }

    static func read(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> TimelineSample? {
        var cursor = offset
        func next<T: FixedWidthInteger>(_: T.Type) -> T {
            defer { cursor += MemoryLayout<T>.size }
            return T(littleEndian: bytes.loadUnaligned(fromByteOffset: cursor, as: T.self))
        }
        let time = next(UInt32.self)
        let cpu = Double(next(UInt16.self)) / 10_000
        let peak = Double(next(UInt16.self)) / 10_000
        let memory = next(UInt64.self)
        let disk = next(UInt64.self)
        let down = Float(bitPattern: next(UInt32.self))
        let up = Float(bitPattern: next(UInt32.self))
        let cost = Float(bitPattern: next(UInt32.self))
        let topCPU = Float(bitPattern: next(UInt32.self))
        let nameSlice = bytes[cursor..<(cursor + nameBytes)].prefix { $0 != 0 }
        guard cpu <= 1, peak <= 1, down.isFinite, up.isFinite, topCPU.isFinite,
              let name = String(bytes: nameSlice, encoding: .utf8)
        else { return nil }
        return TimelineSample(
            time: Date(timeIntervalSince1970: TimeInterval(time)), cpu: cpu, cpuPeak: peak, memoryUsed: memory,
            diskFree: disk, downloadRate: Double(down), uploadRate: Double(up),
            aiCost: cost.isNaN ? nil : Double(cost), topProcess: name, topProcessCPU: Double(topCPU)
        )
    }

    /// Longest prefix that fits the name field without splitting a character.
    static func truncated(_ name: String) -> String {
        var result = ""
        var used = 0
        for character in name {
            let length = String(character).utf8.count
            guard used + length <= nameBytes else { break }
            result.append(character)
            used += length
        }
        return result
    }

    private static func fraction(_ value: Double) -> UInt16 {
        guard value.isFinite else { return 0 }
        return UInt16((min(max(value, 0), 1) * 10_000).rounded())
    }

    static func put<T: FixedWidthInteger>(_ value: T, _ data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

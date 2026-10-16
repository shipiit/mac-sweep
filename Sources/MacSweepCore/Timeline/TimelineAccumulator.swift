import Foundation

/// One live reading from the monitor loop (every few seconds).
public struct TimelineReading: Sendable, Equatable {
    public var time: Date
    /// Busy fraction 0...1.
    public var cpu: Double
    public var memoryUsed: UInt64?
    public var diskFree: UInt64?
    public var downloadRate: Double
    public var uploadRate: Double
    public var topProcess: String?
    /// Percent of one core used by `topProcess`.
    public var topProcessCPU: Double
    public var aiCost: Double?

    public init(time: Date, cpu: Double, memoryUsed: UInt64? = nil, diskFree: UInt64? = nil, downloadRate: Double = 0,
                uploadRate: Double = 0, topProcess: String? = nil, topProcessCPU: Double = 0, aiCost: Double? = nil) {
        self.time = time
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.diskFree = diskFree
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.topProcess = topProcess
        self.topProcessCPU = topProcessCPU
        self.aiCost = aiCost
    }
}

/// Folds live readings into one sample per wall-clock 5-minute slot. A slot is emitted when the
/// first reading of a later slot arrives, so a sleeping Mac leaves a gap rather than a fake value.
public struct TimelineAccumulator: Sendable {
    public static let slot: TimeInterval = 300

    private var slotStart: Date?
    private var readings = 0
    private var cpuSum = 0.0
    private var memorySum = 0.0
    private var memoryReadings = 0
    private var downloadSum = 0.0
    private var uploadSum = 0.0
    private var diskFree: UInt64?
    private var aiCost: Double?
    private var peak: (cpu: Double, process: String, processCPU: Double) = (0, "", 0)

    public init() {}

    public static func slotStart(for time: Date) -> Date {
        Date(timeIntervalSince1970: (time.timeIntervalSince1970 / slot).rounded(.down) * slot)
    }

    /// Returns the finished sample of the previous slot when `reading` starts a new one.
    public mutating func add(_ reading: TimelineReading) -> TimelineSample? {
        let start = Self.slotStart(for: reading.time)
        var finished: TimelineSample?
        if let current = slotStart, start != current {
            finished = start > current ? flush() : nil
            reset()
        }
        slotStart = start
        absorb(reading)
        return finished
    }

    /// The slot in progress, for showing the newest point before it is stored.
    public func pending() -> TimelineSample? { flush() }

    private mutating func absorb(_ reading: TimelineReading) {
        let cpu = reading.cpu.isFinite ? min(max(reading.cpu, 0), 1) : 0
        readings += 1
        cpuSum += cpu
        if let memory = reading.memoryUsed {
            memorySum += Double(memory)
            memoryReadings += 1
        }
        downloadSum += max(reading.downloadRate, 0)
        uploadSum += max(reading.uploadRate, 0)
        if let disk = reading.diskFree { diskFree = disk }
        if let cost = reading.aiCost { aiCost = cost }
        if readings == 1 || cpu > peak.cpu {
            peak = (cpu, reading.topProcess ?? "", reading.topProcessCPU)
        }
    }

    private func flush() -> TimelineSample? {
        guard let slotStart, readings > 0 else { return nil }
        let count = Double(readings)
        return TimelineSample(
            time: slotStart,
            cpu: cpuSum / count,
            cpuPeak: peak.cpu,
            memoryUsed: memoryReadings > 0 ? UInt64(memorySum / Double(memoryReadings)) : 0,
            diskFree: diskFree ?? 0,
            downloadRate: downloadSum / count,
            uploadRate: uploadSum / count,
            aiCost: aiCost,
            topProcess: peak.process,
            topProcessCPU: peak.processCPU
        )
    }

    private mutating func reset() {
        self = TimelineAccumulator()
    }
}

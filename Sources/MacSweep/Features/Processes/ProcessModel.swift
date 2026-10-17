import AppKit
import Foundation
import MacSweepCore
import Observation

struct ProcessRow: Identifiable, Hashable {
    let snapshot: ProcessSnapshot
    let cpu: Double
    let trend: MemoryTrendSummary

    var id: Int32 { snapshot.pid }
    var pid: Int32 { snapshot.pid }
    var name: String { snapshot.name }
    var user: String { snapshot.user }
    /// Sort key: unreadable memory sorts as zero.
    var memory: UInt64 { snapshot.memory ?? 0 }
    var threads: Int { snapshot.threads ?? 0 }
    var growthPerMinute: Double { trend.bytesPerMinute }
    var started: Date { snapshot.started ?? .distantPast }

    static func == (lhs: ProcessRow, rhs: ProcessRow) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.cpu == rhs.cpu && lhs.trend == rhs.trend
    }

    func hash(into hasher: inout Hasher) { hasher.combine(snapshot) }
}

@MainActor
@Observable
final class ProcessModel {
    private(set) var rows: [ProcessRow] = []
    private(set) var memory: SystemMemoryStats?
    private(set) var lastUpdated: Date?
    var isPaused = false

    /// True while a page that shows live process data is open; otherwise sampling slows to save CPU.
    var isLive = true
    static let interval: Duration = .seconds(3)
    static let backgroundInterval: Duration = .seconds(10)
    static let historyLimit = 120

    @ObservationIgnored private var history: [Int32: (started: Date?, samples: [MemorySample])] = [:]
    @ObservationIgnored private var previousCPU: [Int32: UInt64] = [:]
    @ObservationIgnored private var previousTime: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let launchTime = Date()

    var growingCount: Int { rows.filter(\.trend.isSteadilyGrowing).count }
    var isWatchingLongEnough: Bool { Date().timeIntervalSince(launchTime) > 30 }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.isPaused { await self.refresh() }
                // Live updates while you're looking; a slower trickle in the background keeps
                // memory-trend history going without costing battery.
                try? await Task.sleep(for: NSApp.isActive && (self?.isLive ?? true) ? Self.interval : Self.backgroundInterval)
            }
        }
    }

    func refresh() async {
        async let snapshots = Task.detached(priority: .utility) { ProcessSampler.sample() }.value
        async let stats = Task.detached(priority: .utility) { SystemMemory.read() }.value
        let (current, memoryStats) = await (snapshots, stats)
        ingest(current, at: Date())
        memory = memoryStats
    }

    func samples(for pid: Int32) -> [MemorySample] {
        history[pid]?.samples ?? []
    }

    func row(pid: Int32) -> ProcessRow? {
        rows.first { $0.pid == pid }
    }

    private func ingest(_ snapshots: [ProcessSnapshot], at now: Date) {
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        let clock = now.timeIntervalSince(launchTime)
        var nextHistory: [Int32: (started: Date?, samples: [MemorySample])] = [:]
        var nextCPU: [Int32: UInt64] = [:]

        rows = snapshots.map { snapshot in
            var entry = history[snapshot.pid] ?? (snapshot.started, [])
            // A reused PID belongs to a different process; start its history fresh.
            if entry.started != snapshot.started { entry = (snapshot.started, []) }
            if let bytes = snapshot.memory {
                entry.samples.append(MemorySample(time: clock, bytes: bytes))
                if entry.samples.count > Self.historyLimit { entry.samples.removeFirst(entry.samples.count - Self.historyLimit) }
            }
            nextHistory[snapshot.pid] = entry
            if let cpu = snapshot.cpuTimeNanos { nextCPU[snapshot.pid] = cpu }

            let cpu = ProcessSampler.cpuPercent(previous: previousCPU[snapshot.pid], current: snapshot.cpuTimeNanos, elapsed: elapsed)
            return ProcessRow(snapshot: snapshot, cpu: cpu ?? 0, trend: MemoryTrend.summarize(entry.samples))
        }
        history = nextHistory
        previousCPU = nextCPU
        previousTime = now
        lastUpdated = now
    }
}

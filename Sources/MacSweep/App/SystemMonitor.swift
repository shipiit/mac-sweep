import Foundation
import MacSweepCore
import Observation

/// Lightweight live gauges shared by the overview, the menu bar and the notch.
@MainActor
@Observable
final class SystemMonitor {
    private(set) var cpu: Double = 0
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var downloadRate: Double = 0
    private(set) var uploadRate: Double = 0
    private(set) var volume: VolumeStats?
    private(set) var loadAverage: [Double] = []

    @ObservationIgnored private var previousTicks: CPUTicks?
    @ObservationIgnored private var previousNet: (NetworkCounters, Date)?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastVolumeCheck = Date.distantPast

    static let historyLength = 60

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }

    private func sample() {
        let now = Date()
        if let ticks = SystemLoad.cpuTicks() {
            if let previous = previousTicks {
                cpu = SystemLoad.usage(from: previous, to: ticks)
                Self.append(cpu, to: &cpuHistory)
            }
            previousTicks = ticks
        }
        if let counters = SystemLoad.networkCounters() {
            if let (previous, at) = previousNet {
                let elapsed = now.timeIntervalSince(at)
                downloadRate = SystemLoad.rate(from: previous.received, to: counters.received, elapsed: elapsed)
                uploadRate = SystemLoad.rate(from: previous.sent, to: counters.sent, elapsed: elapsed)
            }
            previousNet = (counters, now)
        }
        if let memory = SystemMemory.read() {
            Self.append(Double(memory.used) / Double(max(memory.total, 1)), to: &memoryHistory)
        }
        Self.append(downloadRate, to: &downloadHistory)
        Self.append(uploadRate, to: &uploadHistory)
        // Volume capacity queries are comparatively slow and change slowly: refresh every 30 s.
        if now.timeIntervalSince(lastVolumeCheck) > 30 {
            volume = VolumeStats.forPath(NSHomeDirectory())
            lastVolumeCheck = now
        }
        loadAverage = SystemLoad.loadAverage()
    }
}

import Foundation
import MacSweepCore
import Observation
import UserNotifications

/// Feeds live readings into the smart-alert rules and the 14-day timeline. Cheap: one tick every 30 s
/// built from values the monitors already sampled; the Trash is measured at most every 10 minutes.
@MainActor
@Observable
final class InsightsCenter {
    private(set) var recent: [SmartAlert] = []
    private(set) var timeline: TimelineBuffer
    private(set) var currentSlot: TimelineSample?
    var enabledRules: Set<AlertRule> {
        didSet { UserDefaults.standard.set(enabledRules.map(\.rawValue), forKey: Self.rulesKey) }
    }

    @ObservationIgnored private var engine: AlertEngine
    @ObservationIgnored private var accumulator = TimelineAccumulator()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var trashBytes: UInt64?
    @ObservationIgnored private var trashMeasuredAt: Date?
    @ObservationIgnored private let alertStore = AlertStore.standard
    @ObservationIgnored private let timelineStore = TimelineStore.standard
    private static let rulesKey = "alertRules"

    init() {
        let archive = AlertStore.standard.load()
        engine = AlertEngine(state: archive.state)
        recent = archive.recent
        timeline = TimelineStore.standard.load()
        let stored = UserDefaults.standard.stringArray(forKey: Self.rulesKey)
        enabledRules = stored.map { Set($0.compactMap(AlertRule.init(rawValue:))) } ?? Set(AlertRule.allCases)
    }

    func start(app: AppModel) {
        guard loop == nil else { return }
        loop = Task { [weak self, weak app] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                guard let self, let app else { return }
                await self.tick(app)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Saved samples plus the 5-minute slot being filled, so the chart has data right away.
    var samplesIncludingCurrent: [TimelineSample] {
        timeline.samples + (currentSlot.map { [$0] } ?? [])
    }

    func recordNow(_ app: AppModel) {
        Task { await tick(app) }
    }

    func clearRecent() {
        recent = []
        persistAlerts()
    }

    private func tick(_ app: AppModel) async {
        let now = Date()
        if trashMeasuredAt.map({ now.timeIntervalSince($0) > 600 }) ?? true {
            trashMeasuredAt = now
            trashBytes = await Task.detached(priority: .utility) { TrashBins.list().reduce(0) { $0 + $1.size } }.value
        }
        let rows = app.processes.rows
        let top = rows.max { $0.cpu < $1.cpu }
        let snapshot = AlertSnapshot(
            date: now, volume: app.monitor.volume,
            processes: rows.isEmpty ? nil : rows.map {
                ProcessLoad(pid: $0.pid, started: $0.snapshot.started, name: $0.name, path: $0.snapshot.path, cpuPercent: $0.cpu, memoryTrend: $0.trend)
            },
            processesSampledAt: app.processes.lastUpdated, thermal: app.system.thermal,
            batteryHealth: app.system.battery?.health,
            startupItems: app.startup.items.isEmpty ? nil : app.startup.items.map(StartupFingerprint.init),
            trashBytes: trashBytes)
        let fired = engine.evaluate(snapshot, enabled: enabledRules)
        if !fired.isEmpty {
            recent = Array((fired + recent).prefix(AlertArchive.recentLimit))
            AlertNotifier.post(fired)
        }
        persistAlerts()

        let reading = TimelineReading(time: now, cpu: app.monitor.cpu, memoryUsed: app.processes.memory?.used,
                                      diskFree: app.monitor.volume?.available, downloadRate: app.monitor.downloadRate,
                                      uploadRate: app.monitor.uploadRate, topProcess: top?.name, topProcessCPU: top?.cpu ?? 0,
                                      aiCost: app.ai.todayCost)
        if let sample = accumulator.add(reading) {
            timeline.append(sample)
            let buffer = timeline
            let store = timelineStore
            Task.detached(priority: .utility) { try? store.save(buffer) }
        }
        currentSlot = accumulator.pending()
    }

    private func persistAlerts() {
        let archive = AlertArchive(state: engine.state, recent: recent)
        let store = alertStore
        Task.detached(priority: .utility) { try? store.save(archive) }
    }
}

enum AlertNotifier {
    /// Asks for permission the first time an alert actually fires, not at launch.
    static func post(_ alerts: [SmartAlert]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.message
                if alert.severity == .critical { content.sound = .default }
                center.add(UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil))
            }
        }
    }
}

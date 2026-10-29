import AppKit
import MacSweepCore
import Observation
import UserNotifications

/// Watches memory pressure and, when it stays high, notifies about or politely quits idle apps (never the one
/// you're using). Costs nothing extra: it reads numbers the process sampler already collected.
@MainActor
@Observable
final class MemoryGuardCenter {
    struct Event: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let text: String
    }

    var mode: MemoryGuardMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var idleMinutes: Int {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: Self.idleKey) }
    }
    private(set) var events: [Event] = []
    private(set) var pressureSince: Date?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastAction: Date?
    static let modeKey = "memoryGuardMode"
    static let idleKey = "memoryGuardIdleMinutes"

    init() {
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(MemoryGuardMode.init(rawValue:)) ?? .notify
        idleMinutes = UserDefaults.standard.object(forKey: Self.idleKey) as? Int ?? 30
    }

    func start(app: AppModel) {
        guard loop == nil else { return }
        loop = Task { [weak self, weak app] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, let app else { return }
                self.check(app)
            }
        }
    }

    /// Idle apps right now, biggest first, with all their helper processes counted.
    func idleApps(_ app: AppModel, minutes: Int? = nil) -> [IdleApp] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map {
            RunningAppSnapshot(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "",
                               bundlePath: $0.bundleURL?.path, launchDate: $0.launchDate,
                               lastActive: app.usage.lastActive[$0.bundleIdentifier ?? ""], isFrontmost: $0.processIdentifier == front)
        }
        return IdleApps.find(apps: apps, processes: app.processes.rows.map(\.snapshot), watchingSince: app.usage.watchingSince,
                             threshold: TimeInterval((minutes ?? idleMinutes) * 60), minimumMemory: 200 << 20)
            .sorted { $0.memory > $1.memory }
    }

    private func check(_ app: AppModel) {
        guard let pressure = app.processes.memory?.pressure else { return }
        guard pressure != .normal else {
            pressureSince = nil
            return
        }
        let since = pressureSince ?? Date()
        pressureSince = since
        // One action per 15 minutes, so a busy Mac isn't nagged or emptied of apps.
        if let lastAction, Date().timeIntervalSince(lastAction) < 900 { return }
        guard let plan = MemoryGuard.plan(pressure: pressure, sustainedFor: Date().timeIntervalSince(since), idle: idleApps(app), mode: mode) else { return }
        lastAction = Date()
        for item in plan.quit { NSRunningApplication(processIdentifier: item.app.pid)?.terminate() }
        let text: String
        if plan.quit.isEmpty {
            text = "Memory is \(pressure.rawValue.lowercased()). Idle apps using the most: " + plan.suggest.map { "\($0.app.name) (\(Format.bytes($0.memory)))" }.joined(separator: ", ")
        } else {
            text = "Memory was \(pressure.rawValue.lowercased()), so MacSweep quit " + plan.quit.map { "\($0.app.name) (\(Format.bytes($0.memory)))" }.joined(separator: ", ")
                + ". They can be reopened any time."
        }
        events.insert(Event(date: Date(), text: text), at: 0)
        events = Array(events.prefix(30))
        AlertNotifier.post([SmartAlert(rule: .memoryLeak, key: "memory-guard", severity: pressure == .critical ? .critical : .warning,
                                       title: plan.quit.isEmpty ? "Memory is running low" : "Freed memory", message: text, date: Date())])
    }
}

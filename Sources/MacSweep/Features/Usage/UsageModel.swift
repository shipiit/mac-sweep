import AppKit
import MacSweepCore
import Observation

/// Records which app is in front and for how long, using workspace activation notifications.
/// Nothing leaves the Mac; the log lives in Application Support and keeps 30 days.
@MainActor
@Observable
final class UsageModel {
    private(set) var log: UsageLog
    /// Last time each app was in front (or stopped being in front); persisted with the usage log.
    var lastActive: [String: Date] { log.lastActive }
    let watchingSince = Date()
    @ObservationIgnored private let store = UsageLogStore.standard
    @ObservationIgnored private var current: (bundleID: String, name: String, since: Date)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var flushLoop: Task<Void, Never>?

    init() {
        log = UsageLogStore.standard.load()
    }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKeys.trackUsage) as? Bool ?? true }

    func start() {
        guard observers.isEmpty, isEnabled else { return }
        if let app = NSWorkspace.shared.frontmostApplication { begin(app, at: Date()) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self.switchTo(app) } }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.close(at: Date()) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { if let app = NSWorkspace.shared.frontmostApplication { self.begin(app, at: Date()) } }
            })
        }
        flushLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.flush()
            }
        }
    }

    func stop() {
        close(at: Date())
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        flushLoop?.cancel()
        flushLoop = nil
        persist()
    }

    func clear() {
        log = UsageLog()
        store.clear()
    }

    private func switchTo(_ app: NSRunningApplication) {
        let now = Date()
        if let previous = current?.bundleID { log.lastActive[previous] = now }
        if let id = app.bundleIdentifier { log.lastActive[id] = now }
        close(at: now)
        begin(app, at: now)
        if let id = app.bundleIdentifier { log.recordActivation(bundleID: id, name: app.localizedName ?? id, at: now) }
    }

    private func begin(_ app: NSRunningApplication, at date: Date) {
        guard let id = app.bundleIdentifier else { return }
        current = (id, app.localizedName ?? id, date)
    }

    private func close(at date: Date) {
        guard let current else { return }
        log.record(bundleID: current.bundleID, name: current.name, from: current.since, to: date)
        self.current = nil
    }

    /// Credits the app in front so far without ending its session, then saves.
    private func flush() {
        guard let running = current else { return }
        let now = Date()
        log.record(bundleID: running.bundleID, name: running.name, from: running.since, to: now)
        log.lastActive[running.bundleID] = now
        current = (running.bundleID, running.name, now)
        log.prune()
        persist()
    }

    private func persist() {
        let snapshot = log
        let store = store
        Task.detached(priority: .background) { try? store.save(snapshot) }
    }
}

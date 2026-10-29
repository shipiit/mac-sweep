import Foundation
import MacSweepCore
import Observation
import os
import UserNotifications

/// Holds new launch agents/daemons until you approve them. Call `start()` once at launch.
@MainActor
@Observable
final class StartupGuard {
    private(set) var archive: StartupGuardArchive
    private(set) var busy: Set<String> = []
    private(set) var isChecking = false
    var message: String?

    @ObservationIgnored private let store: StartupGuardStore
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var recheck = false
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "startup-guard")

    init(store: StartupGuardStore = .standard) {
        self.store = store
        archive = store.load()
    }

    var isEnabled: Bool { archive.isEnabled }
    var held: [HeldStartupItem] { archive.held }
    var history: [StartupGuardEvent] { archive.history }

    /// Idempotent. Resumes watching if the guard was on, and catches anything added while MacSweep was closed.
    func start() {
        guard !started else { return }
        started = true
        guard archive.isEnabled else { return }
        startWatching()
        Task { await check() }
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != archive.isEnabled else { return }
        if enabled {
            let current = await Self.scan()
            archive.enable(current: current, at: Date())
            started = true
            startWatching()
        } else {
            archive.disable(at: Date())
            watcher = nil
        }
        save()
    }

    func check() async {
        guard archive.isEnabled else { return }
        guard !isChecking else { recheck = true; return }
        isChecking = true
        defer { isChecking = false }
        repeat {
            recheck = false
            await checkOnce()
        } while recheck
    }

    func approve(_ entry: HeldStartupItem) async {
        await run(entry) { item in
            if entry.status == .blocked { try await LaunchControl.perform(.enable, on: item) }
            self.archive.resolve(entry.id, action: "Approved", at: Date())
        }
    }

    func keepBlocked(_ entry: HeldStartupItem) {
        archive.resolve(entry.id, action: "Kept blocked", at: Date())
        save()
    }

    func block(_ entry: HeldStartupItem) async {
        await run(entry) { item in
            try await LaunchControl.perform(.disable, on: item)
            self.archive.markBlocked(entry.id, at: Date())
        }
    }

    func remove(_ entry: HeldStartupItem) async {
        await run(entry) { item in
            try await LaunchItemRemover.execute(LaunchItemRemover.plan(for: item))
            self.archive.forget(entry.id, action: "Moved to Trash", at: Date())
        }
    }

    private func checkOnce() async {
        let current = await Self.scan()
        let decision = StartupGuardPolicy.decide(baseline: archive.baseline, held: archive.held, current: current)
        guard !decision.isEmpty else { return }
        var blocked = Set<String>()
        for item in decision.autoBlock {
            do {
                try await LaunchControl.perform(.disable, on: item)
                blocked.insert(item.plistPath)
            } catch {
                log.error("auto-block failed for \(item.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        StartupGuardPolicy.apply(decision, to: &archive, blockedIDs: blocked, at: Date())
        save()
        for item in decision.autoBlock {
            notify(title: blocked.contains(item.plistPath) ? "Blocked new startup item: \(item.label)" : "New startup item: \(item.label)",
                   body: "It tried to start automatically. Review it in Startup Items › Guard.")
        }
        for item in decision.askToBlock {
            notify(title: "New startup item needs review: \(item.label)",
                   body: "Installed for all users. Open Startup Items › Guard to block or approve it.")
        }
    }

    private func run(_ entry: HeldStartupItem, _ action: @escaping (LaunchItem) async throws -> Void) async {
        guard let item = Self.launchItem(for: entry) else {
            archive.forget(entry.id, action: "Already gone from disk", at: Date())
            save()
            return
        }
        busy.insert(entry.id)
        defer { busy.remove(entry.id) }
        do {
            try await action(item)
        } catch {
            message = "\(entry.fingerprint.name): \(error.localizedDescription)"
        }
        save()
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let paths = LaunchItemScanner.directories(home: NSHomeDirectory()).map(\.0)
        watcher = DirectoryWatcher(paths: paths) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.check() }
            }
        }
    }

    private func save() {
        do {
            try store.save(archive)
        } catch {
            log.error("couldn't save startup guard state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func notify(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private static func scan() async -> [LaunchItem] {
        await Task.detached(priority: .utility) { LaunchItemScanner.scan() }.value
    }

    private static func launchItem(for entry: HeldStartupItem) -> LaunchItem? {
        let scope: LaunchScope = switch entry.fingerprint.kind {
        case .daemon: .daemon
        case .globalAgent: .globalAgent
        case .userAgent, .loginItem: .userAgent
        }
        guard let data = FileManager.default.contents(atPath: entry.plistPath) else { return nil }
        return LaunchItemScanner.parse(data, path: entry.plistPath, scope: scope)
    }
}

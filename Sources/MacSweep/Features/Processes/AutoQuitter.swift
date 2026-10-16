import AppKit
import MacSweepCore
import os

/// Opt-in, per app: quits apps the user chose once they've been idle past the threshold.
/// Uses the normal quit (like ⌘Q), so apps with unsaved work still ask to save.
@MainActor
final class AutoQuitter {
    static let listKey = "autoQuitBundles"
    private let app: AppModel
    private var loop: Task<Void, Never>?
    private let log = Logger(subsystem: Log.subsystem, category: "auto-quit")

    init(app: AppModel) {
        self.app = app
    }

    static func enabled() -> Set<String> {
        Set((UserDefaults.standard.string(forKey: listKey) ?? "").split(separator: ",").map(String.init))
    }

    static func setEnabled(_ bundleID: String, _ on: Bool) {
        var list = enabled()
        if on { list.insert(bundleID) } else { list.remove(bundleID) }
        UserDefaults.standard.set(list.sorted().joined(separator: ","), forKey: listKey)
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.run()
            }
        }
    }

    private func run() {
        let list = Self.enabled()
        guard !list.isEmpty else { return }
        let minutes = UserDefaults.standard.object(forKey: "idleThresholdMinutes") as? Int ?? 120
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && list.contains($0.bundleIdentifier ?? "") }
            .map { RunningAppSnapshot(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "",
                                      bundlePath: $0.bundleURL?.path, launchDate: $0.launchDate,
                                      lastActive: app.usage.lastActive[$0.bundleIdentifier ?? ""], isFrontmost: $0.processIdentifier == front) }
        let idle = IdleApps.find(apps: apps, processes: app.processes.rows.map(\.snapshot), watchingSince: app.usage.watchingSince,
                                 threshold: TimeInterval(minutes * 60), minimumMemory: 0)
        for item in idle {
            NSRunningApplication(processIdentifier: item.app.pid)?.terminate()
            log.info("auto-quit \(item.app.bundleID, privacy: .public) after \(minutes) idle minutes")
        }
    }
}

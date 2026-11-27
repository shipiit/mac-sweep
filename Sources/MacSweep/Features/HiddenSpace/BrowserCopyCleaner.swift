import AppKit
import MacSweepCore
import os

/// Deletes a Chromium browser's leftover code-sign copies right after it quits, when the setting is on.
@MainActor
final class BrowserCopyCleaner {
    private let log = Logger(subsystem: Log.subsystem, category: "browser-copy-cleaner")
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.appQuit(bundleID) }
        }
    }

    private func appQuit(_ bundleID: String?) {
        guard let bundleID, UserDefaults.standard.bool(forKey: SettingsKeys.autoRemoveBrowserCopies) else { return }
        Task {
            // Give the browser a moment to finish shutting down (and to come straight back, if it's restarting).
            try? await Task.sleep(for: .seconds(5))
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let freed = await Task.detached(priority: .utility) {
                CodeSignClones.removeLeftBehind(by: bundleID, isRunning: running.contains)
            }.value
            if freed > 0 { log.info("removed leftover browser copies after quit (\(freed) bytes)") }
        }
    }
}

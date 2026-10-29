import AppKit
import MacSweepCore
import Observation

@MainActor
@Observable
final class BrowserProfilesModel {
    private(set) var groups: [BrowserProfileGroup] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var cleaning: String?
    var message: String?

    var totalSize: UInt64 { groups.reduce(0) { $0 + $1.totalSize } }
    var profileCount: Int { groups.reduce(0) { $0 + $1.profiles.count } }
    var cleanableSize: UInt64 { groups.flatMap(\.profiles).reduce(0) { $0 + $1.size(of: .safe) } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        groups = await Task.detached(priority: .userInitiated) { BrowserProfilesScanner.scan() }.value
        isLoading = false
        hasLoaded = true
    }

    func blockedReason(for browser: ChromiumBrowser) -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return BrowserProfilesScanner.blockedReason(for: browser, runningBundleIDs: running)
    }

    /// Moves only the profile's caches to the Trash; site data, history and extensions stay.
    func cleanCaches(_ profile: BrowserProfile) async {
        if let reason = blockedReason(for: profile.browser) {
            message = reason
            return
        }
        let targets = profile.cleanTargets
        guard !targets.isEmpty else {
            message = "Nothing to clean in \(profile.displayName)."
            return
        }
        cleaning = profile.id
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        cleaning = nil
        let failed = results.filter { !$0.succeeded }.count
        message = failed == 0
            ? "Moved \(Format.bytes(profile.size(of: .safe))) of \(profile.browser.name) caches (\(profile.displayName)) to the Trash."
            : "Cleaned \(profile.displayName) with \(failed) folders skipped."
        await refresh()
    }
}

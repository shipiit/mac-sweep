import AppKit
import MacSweepCore
import Observation

@MainActor
@Observable
final class PrivacyModel {
    private(set) var items: [PrivacyItem] = []
    private(set) var isLoading = false
    var selected: Set<String> = []
    var message: String?

    func refresh() async {
        isLoading = true
        items = await Task.detached(priority: .userInitiated) { PrivacyScanner.scan() }.value
        selected.formIntersection(Set(items.map(\.id)))
        isLoading = false
    }

    func runningApps(for items: [PrivacyItem]) -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Array(Set(items.compactMap { item in item.bundleID.flatMap { running.contains($0) ? item.app : nil } })).sorted()
    }

    /// Deletes permanently: moving history or cookies to the Trash would defeat the purpose.
    func clearSelected() async {
        let chosen = items.filter { selected.contains($0.id) }
        let blocked = runningApps(for: chosen)
        guard blocked.isEmpty else {
            message = "Quit \(blocked.joined(separator: ", ")) first. Browsers rewrite these files while open."
            return
        }
        let targets = chosen.flatMap { item in item.paths.map { CleanupTarget(path: $0, size: 0) } }
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .delete) }.value
        let failed = results.filter { !$0.succeeded }.count
        message = failed == 0 ? "Cleared \(chosen.count) items." : "Cleared with \(failed) files skipped (missing access?)."
        selected.removeAll()
        await refresh()
    }
}

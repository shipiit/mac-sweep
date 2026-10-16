import AppKit
import MacSweepCore
import Observation

@MainActor
@Observable
final class AppsModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var orphans: [CleanupTarget] = []
    private(set) var isLoading = false
    private(set) var leftovers: [String: [CleanupTarget]] = [:]
    var message: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let quick = await Task.detached(priority: .userInitiated) { AppInventory.scan(measure: false) }.value
        if apps.isEmpty { apps = quick }
        let measured = await Task.detached(priority: .utility) { AppInventory.scan(measure: true) }.value
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let known = await AppInventory.knownBundleIDs(scanned: measured, running: running)
        apps = measured
        orphans = await Task.detached(priority: .utility) { Leftovers.orphans(installedBundleIDs: known) }.value
    }

    func loadLeftovers(for app: InstalledApp) async {
        guard leftovers[app.id] == nil else { return }
        leftovers[app.id] = await Task.detached(priority: .userInitiated) { Leftovers.find(for: app) }.value
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
    }

    /// Moves the app and its leftovers to the Trash. Refuses while the app is running.
    func uninstall(_ app: InstalledApp, includeLeftovers: Set<String>) async {
        if isRunning(app) {
            message = "Quit \(app.name) first, then uninstall it."
            return
        }
        let extras = (leftovers[app.id] ?? []).filter { includeLeftovers.contains($0.path) }
        let targets = [CleanupTarget(path: app.path, size: app.size ?? 0)] + extras
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        let failed = results.filter { !$0.succeeded }
        if results.first?.succeeded == true {
            apps.removeAll { $0.id == app.id }
            let freed = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
            message = "\(app.name) moved to the Trash with \(results.count - 1 - failed.count) leftovers (\(Format.bytes(freed)))."
        } else {
            message = "Couldn't remove \(app.name). It may be owned by the system; drag it to the Trash in Finder to authenticate."
        }
    }

    func removeOrphans(_ paths: Set<String>) async {
        let targets = orphans.filter { paths.contains($0.path) }
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        let removed = Set(results.filter(\.succeeded).map(\.path))
        orphans.removeAll { removed.contains($0.path) }
        message = "Moved \(removed.count) leftover folders to the Trash."
    }
}

@MainActor
@Observable
final class UpdaterModel {
    private(set) var updates: [AvailableUpdate] = []
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    private(set) var upgrading: Set<String> = []
    var message: String?

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        updates = await Updater.check()
        lastChecked = Date()
        isChecking = false
    }

    func upgrade(_ update: AvailableUpdate) async {
        upgrading.insert(update.id)
        defer { upgrading.remove(update.id) }
        do {
            _ = try await Updater.upgrade(update)
            updates.removeAll { $0.id == update.id }
            message = "\(update.name) updated to \(update.available)."
        } catch {
            message = "\(update.name): \(error.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class ExtensionsModel {
    private(set) var items: [SystemExtensionItem] = []

    func refresh() async {
        items = await Task.detached { ExtensionsHub.scan() }.value
    }

    func remove(_ item: SystemExtensionItem) {
        let result = Cleaner.remove([CleanupTarget(path: item.path, size: 0)], mode: .trash)
        if result.first?.succeeded == true { items.removeAll { $0.id == item.id } }
    }
}

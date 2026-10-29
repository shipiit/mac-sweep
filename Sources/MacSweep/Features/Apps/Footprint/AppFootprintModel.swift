import AppKit
import MacSweepCore
import Observation

/// Per-app disk footprint and the "Clear cache" / "Reset app" actions for the Uninstaller's footprint tab.
@MainActor
@Observable
final class AppFootprintModel {
    private(set) var footprints: [AppFootprint] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Apps with an action in flight, by footprint id.
    private(set) var working: Set<String> = []
    /// The reset waiting for confirmation in the sheet.
    var pendingReset: AppFootprintPlan?
    var message: String?

    private let home = NSHomeDirectory()

    /// MacSweep's own bundle ID; never measured, cleared or reset.
    private var excluded: Set<String> {
        Set([Bundle.main.bundleIdentifier].compactMap { $0 })
    }

    var totalFootprint: UInt64 { footprints.reduce(0) { $0 + $1.total } }
    var totalData: UInt64 { footprints.reduce(0) { $0 + $1.dataSize } }
    var totalCache: UInt64 { footprints.reduce(0) { $0 + $1.cacheSize } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let home = home
        let excluded = excluded
        let selfPath = Bundle.main.bundlePath
        footprints = await Task.detached(priority: .utility) {
            let apps = AppInventory.scan(home: home, measure: true).filter { $0.path != selfPath }
            return AppFootprintScanner.scan(apps: apps, home: home, excludedBundleIDs: excluded)
        }.value
    }

    func isRunning(_ footprint: AppFootprint) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == footprint.app.bundleID }
    }

    func clearCache(_ footprint: AppFootprint) async {
        guard let plan = plan(footprint, action: .clearCache) else { return }
        if plan.isEmpty {
            message = "\(footprint.app.name) has no cache to clear."
            return
        }
        await run(plan)
    }

    /// Builds the reset plan and opens the confirmation sheet.
    func prepareReset(_ footprint: AppFootprint) {
        guard let plan = plan(footprint, action: .reset) else { return }
        if plan.isEmpty && plan.refused.isEmpty {
            message = "\(footprint.app.name) has no settings or data to reset."
            return
        }
        pendingReset = plan
    }

    func confirmReset() async {
        guard let plan = pendingReset else { return }
        pendingReset = nil
        await run(plan)
    }

    /// Returns nil (with a message) when the app is running or refused.
    private func plan(_ footprint: AppFootprint, action: FootprintAction) -> AppFootprintPlan? {
        if isRunning(footprint) {
            message = "Quit \(footprint.app.name) first. Its data can't be moved while it's running."
            return nil
        }
        switch AppFootprintPlanner.plan(footprint, action: action, home: home, excludedBundleIDs: excluded,
                                        extraProtected: [Bundle.main.bundlePath]) {
        case .success(let plan): return plan
        case .failure(let refusal):
            message = refusal.message
            return nil
        }
    }

    private func run(_ plan: AppFootprintPlan) async {
        let footprint = footprints.first { $0.app.id == plan.app.id }
        if let footprint, isRunning(footprint) {
            message = "Quit \(plan.app.name) first. Its data can't be moved while it's running."
            return
        }
        working.insert(plan.app.id)
        defer { working.remove(plan.app.id) }
        let home = home
        let targets = plan.targets
        let results = await Task.detached(priority: .userInitiated) {
            Cleaner.remove(targets, mode: .trash, home: home)
        }.value
        let freed = results.filter(\.succeeded).reduce(UInt64(0)) { $0 + $1.size }
        let failed = results.filter { !$0.succeeded }.count
        let verb = plan.action == .reset ? "Reset \(plan.app.name)" : "Cleared \(plan.app.name)'s cache"
        message = failed == 0
            ? "\(verb): moved \(Format.bytes(freed)) to the Trash."
            : "\(verb): moved \(Format.bytes(freed)) to the Trash; \(failed) item(s) couldn't be moved."
        await remeasure(plan.app)
    }

    private func remeasure(_ app: InstalledApp) async {
        let home = home
        let updated = await Task.detached(priority: .utility) { AppFootprintScanner.footprint(for: app, home: home) }.value
        guard let index = footprints.firstIndex(where: { $0.id == updated.id }) else { return }
        footprints[index] = updated
        footprints.sort { $0.total > $1.total }
    }
}

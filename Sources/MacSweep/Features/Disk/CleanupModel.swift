import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class CleanupModel {
    enum SelectionState {
        case none
        case partial
        case all
    }

    struct Report: Identifiable {
        let id = UUID()
        let mode: RemovalMode
        let freed: UInt64
        let removedCount: Int
        let failures: [RemovalResult]
    }

    let home: String
    private(set) var items: [CleanupItem] = []
    private(set) var isEvaluating = false
    private(set) var isCleaning = false
    var selected: Set<String> = []
    var mode: RemovalMode = .trash
    var report: Report?

    /// Folders and files ticked by hand in the treemap's folder panel, cleaned together with recommendations.
    private(set) var picked: [String: CleanupTarget] = [:]
    /// Bytes each target grew (or shrank) since the previous scan, from `SizeHistory`.
    private(set) var growth: [String: Int64] = [:]

    /// Path → safety, used by the treemap to hatch cleanable tiles.
    private(set) var cleanableIndex: [String: CleanupSafety] = [:]

    @ObservationIgnored var onRemoved: ((Set<String>) -> Void)?
    @ObservationIgnored private var evaluation: Task<Void, Never>?

    init(home: String) {
        self.home = home
    }

    func items(_ safety: CleanupSafety) -> [CleanupItem] { items.filter { $0.rule.safety == safety } }
    func total(_ safety: CleanupSafety) -> UInt64 { items(safety).reduce(0) { $0 + $1.size } }
    func count(_ safety: CleanupSafety) -> Int { items(safety).count }

    var selectedTargets: [CleanupTarget] {
        let fromRules = items.flatMap(\.targets).filter { selected.contains($0.path) }
        let ruled = Set(fromRules.map(\.path))
        return fromRules + picked.values.filter { !ruled.contains($0.path) }.sorted { $0.size > $1.size }
    }

    /// Review-first locations; the generated script leaves these commented out.
    var reviewPaths: Set<String> { Set(items(.review).flatMap(\.targets).map(\.path)) }

    var hasSelection: Bool { !selected.isEmpty || !picked.isEmpty }

    func isPicked(_ path: String) -> Bool { picked[path] != nil || selected.contains(path) }

    /// Ticks a folder from the treemap. Protected paths are refused, the same as everywhere else.
    func togglePick(_ node: FileNode) {
        if picked[node.path] != nil {
            picked[node.path] = nil
        } else if selected.contains(node.path) {
            selected.remove(node.path)
        } else if PathGuard.canRemove(node.path, home: home, extraProtected: [Bundle.main.bundlePath]) {
            picked[node.path] = CleanupTarget(path: node.path, size: node.size, modified: node.modified)
        }
    }

    func growth(of item: CleanupItem) -> Int64? {
        let deltas = item.targets.compactMap { growth[$0.path] }
        return deltas.isEmpty ? nil : deltas.reduce(0, +)
    }

    var selectedSize: UInt64 { selectedTargets.reduce(0) { $0 + $1.size } }
    var selectedItemCount: Int { items.filter { selectionState($0) != .none }.count + picked.count }
    var selectionIncludesReview: Bool { items(.review).contains { selectionState($0) != .none } }

    private(set) var isQuickScanning = false
    private(set) var lastQuickScan: Date?

    /// Finds junk in about a minute by measuring only known locations, no full disk scan needed.
    func quickScan() async {
        guard !isQuickScanning else { return }
        isQuickScanning = true
        isEvaluating = true
        let home = home
        let found = await Task.detached(priority: .userInitiated) { await QuickJunkScanner.scan(home: home) }.value
        apply(found.items)
        isEvaluating = false
        isQuickScanning = false
        lastQuickScan = Date()
        await updateGrowth(scannedAt: Date())
        MemoryRelief.release()
    }

    private func apply(_ items: [CleanupItem]) {
        self.items = items
        let valid = Set(items.flatMap(\.targets).map(\.path))
        selected.formIntersection(valid)
        cleanableIndex = Dictionary(items.flatMap { item in item.targets.map { ($0.path, item.rule.safety) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Weekly, opt-in: moves safe junk (never review-first items, never anything in use) to the Trash and notifies.
    func autoCleanIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.autoCleanWeekly), !isCleaning,
              AutoClean.isDue(lastRun: defaults.object(forKey: SettingsKeys.autoCleanLastRun) as? Date) else { return }
        await quickScan()
        let safe = items.filter { $0.rule.safety == .safe }.flatMap(\.targets)
        let conflicts = await InUseCheck.run(targets: safe.map(\.path), home: home)
        let targets = AutoClean.targets(items, inUse: Set(conflicts.map(\.targetPath)))
        defaults.set(Date(), forKey: SettingsKeys.autoCleanLastRun)
        guard !targets.isEmpty else { return }
        let results = await removeNow(targets, mode: .trash)
        let freed = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
        AlertNotifier.post([SmartAlert(rule: .largeTrash, key: "auto-clean", severity: .info, title: "Weekly cleanup done",
                                       message: "Moved \(Format.bytes(freed)) of safe junk to the Trash. Empty the Trash to get the space back.", date: Date())])
    }

    func evaluate(_ result: ScanResult?) {
        evaluation?.cancel()
        guard let result else {
            items = []
            cleanableIndex = [:]
            return
        }
        isEvaluating = true
        let home = home
        evaluation = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                CleanupEngine.evaluate(tree: result.root, home: home, sizeOf: DiskScanner.measure)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.items = items
            let valid = Set(items.flatMap(\.targets).map(\.path))
            self.selected.formIntersection(valid)
            self.cleanableIndex = Dictionary(
                items.flatMap { item in item.targets.map { ($0.path, item.rule.safety) } },
                uniquingKeysWith: { first, _ in first }
            )
            self.isEvaluating = false
            await self.updateGrowth(scannedAt: result.finishedAt)
        }
    }

    /// Compares each target with the last scan in the size history, then records this scan.
    private func updateGrowth(scannedAt: Date) async {
        let sizes = Dictionary(items.flatMap(\.targets).map { ($0.path, $0.size) }, uniquingKeysWith: { first, _ in first })
        let previous = await Task.detached(priority: .utility) { () -> [String: UInt64] in
            let history = SizeHistory.standard
            let before = history.previous(before: scannedAt)
            try? history.record(sizes, at: scannedAt)
            return before
        }.value
        growth = Dictionary(uniqueKeysWithValues: sizes.compactMap { path, size in
            previous[path].map { (path, Int64(clamping: size) - Int64(clamping: $0)) }
        })
    }

    func safety(forPath path: String) -> CleanupSafety? {
        var current = path
        while current.count > home.count {
            if let safety = cleanableIndex[current] { return safety }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    func selectionState(_ item: CleanupItem) -> SelectionState {
        let count = item.targets.filter { selected.contains($0.path) }.count
        if count == 0 { return .none }
        return count == item.targets.count ? .all : .partial
    }

    func toggle(_ item: CleanupItem) {
        let paths = item.targets.map(\.path)
        if selectionState(item) == .all {
            selected.subtract(paths)
        } else {
            selected.formUnion(paths)
        }
    }

    func toggle(_ target: CleanupTarget) {
        if selected.contains(target.path) {
            selected.remove(target.path)
        } else {
            selected.insert(target.path)
        }
    }

    func selectSafe() {
        selected.formUnion(items(.safe).flatMap(\.targets).map(\.path))
    }

    func clearSelection() {
        selected.removeAll()
        picked.removeAll()
    }

    func cleanSelected(skipping skipped: Set<String> = []) {
        remove(selectedTargets.filter { !skipped.contains($0.path) }, mode: mode)
    }

    func remove(_ targets: [CleanupTarget], mode: RemovalMode) {
        Task { await removeNow(targets, mode: mode) }
    }

    /// Removes targets and waits for the result (used by Smart Scan's Run step).
    @discardableResult
    func removeNow(_ targets: [CleanupTarget], mode: RemovalMode) async -> [RemovalResult] {
        guard !targets.isEmpty, !isCleaning else { return [] }
        isCleaning = true
        let home = home
        do {
            let results = await Task.detached(priority: .userInitiated) {
                Cleaner.remove(targets, mode: mode, home: home)
            }.value
            let removed = results.filter(\.succeeded)
            let removedPaths = Set(removed.map(\.path))
            self.selected.subtract(removedPaths)
            for path in removedPaths { self.picked[path] = nil }
            self.items = self.items.compactMap { item in
                let remaining = item.targets.filter { !removedPaths.contains($0.path) }
                return remaining.isEmpty ? nil : CleanupItem(rule: item.rule, targets: remaining)
            }
            for path in removedPaths { self.cleanableIndex[path] = nil }
            self.report = Report(
                mode: mode,
                freed: removed.reduce(0) { $0 + $1.size },
                removedCount: removed.count,
                failures: results.filter { !$0.succeeded }
            )
            self.isCleaning = false
            self.onRemoved?(removedPaths)
            return results
        }
    }
}

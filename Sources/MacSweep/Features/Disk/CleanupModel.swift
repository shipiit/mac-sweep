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
        items.flatMap(\.targets).filter { selected.contains($0.path) }
    }

    var selectedSize: UInt64 { selectedTargets.reduce(0) { $0 + $1.size } }
    var selectedItemCount: Int { items.filter { selectionState($0) != .none }.count }
    var selectionIncludesReview: Bool { items(.review).contains { selectionState($0) != .none } }

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
        }
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

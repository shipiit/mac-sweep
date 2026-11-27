import Foundation
import MacSweepCore
import Observation

/// Every Claude Code and Codex session on disk, with selection and removal to the Trash.
@MainActor @Observable
final class AISessionsModel {
    static let shared = AISessionsModel()

    private(set) var sessions: [AISessionRecord] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isRemoving = false
    var selected = Set<String>()
    var report: String?

    var names: [String: String] { SessionNames.all() }
    var totalSize: UInt64 { sessions.reduce(0) { $0 + $1.size } }
    var selectedSize: UInt64 { sessions.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        sessions = await Task.detached(priority: .utility) { SessionInventory.all() }.value
        selected.formIntersection(Set(sessions.map(\.id)))
        isLoading = false
        hasLoaded = true
    }

    func isNamed(_ session: AISessionRecord) -> Bool { SessionInventory.isKept(session.id, keeping: Set(names.keys)) }

    func name(of session: AISessionRecord) -> String? {
        names.first { session.id == $0.key || session.id.hasSuffix("-" + $0.key) }?.value
    }

    /// Selects sessions untouched for `days`, never named ones or anything from today.
    func selectOlder(than days: Int) {
        selected = Set(SessionInventory.old(sessions, olderThanDays: max(days, 1), keeping: Set(names.keys)).map(\.id))
    }

    func moveSelectedToTrash() async {
        let chosen = sessions.filter { selected.contains($0.id) && !$0.isActive() }
        guard !chosen.isEmpty, !isRemoving else { return }
        isRemoving = true
        let targets = chosen.flatMap { session in session.paths.map { CleanupTarget(path: $0, size: 0, modified: session.modified) } }
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        let failed = Set(results.filter { !$0.succeeded }.map(\.path))
        let removed = chosen.filter { session in !session.paths.contains(where: failed.contains) }
        let freed = removed.reduce(0) { $0 + $1.size }
        report = "Moved \(removed.count) session\(removed.count == 1 ? "" : "s") (\(Format.bytes(freed))) to the Trash."
            + (failed.isEmpty ? " Empty the Trash to free the space." : " \(failed.count) file\(failed.count == 1 ? "" : "s") couldn't be moved.")
        selected.removeAll()
        isRemoving = false
        await refresh()
    }
}

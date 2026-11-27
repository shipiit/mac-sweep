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
    /// Sessions compressed into MacSweep's archive, restorable to where they were.
    private(set) var archived: [ArchivedSession] = []
    /// "3 of 12" while a compression run is in progress.
    private(set) var progress: String?
    var selected = Set<String>()
    var report: String?

    var names: [String: String] { SessionNames.all() }
    var totalSize: UInt64 { sessions.reduce(0) { $0 + $1.size } }
    var selectedSize: UInt64 { sessions.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }
    var extrasSize: UInt64 { sessions.reduce(0) { $0 + $1.extrasSize } }
    var selectedExtrasSize: UInt64 { sessions.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.extrasSize } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        sessions = await Task.detached(priority: .utility) { SessionInventory.all() }.value
        archived = await Task.detached(priority: .utility) { SessionArchive.list() }.value
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

    /// Ticks the sessions whose extras (subagent logs, tool output, file backups) take at least `minimum` bytes.
    func selectSlimmable(minimum: UInt64 = 10_000_000) {
        selected = Set(sessions.filter { $0.extrasSize >= minimum && !$0.isActive() }.map(\.id))
    }

    /// Keeps each ticked session's conversation and moves only its extras to the Trash.
    func slimSelected() async {
        let chosen = sessions.filter { selected.contains($0.id) && !$0.isActive() && !$0.extras.isEmpty }
        guard !chosen.isEmpty, !isRemoving else { return }
        isRemoving = true
        let targets = chosen.flatMap { session in session.extras.map { CleanupTarget(path: $0, size: 0, modified: session.modified) } }
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        let failed = Set(results.filter { !$0.succeeded }.map(\.path))
        let slimmed = chosen.filter { session in !session.extras.contains(where: failed.contains) }
        report = "Slimmed \(slimmed.count) session\(slimmed.count == 1 ? "" : "s"): \(Format.bytes(slimmed.reduce(0) { $0 + $1.extrasSize })) of subagent logs, tool output and file backups moved to the Trash. The conversations are untouched."
            + (failed.isEmpty ? " Empty the Trash to free the space." : " \(failed.count) item\(failed.count == 1 ? "" : "s") couldn't be moved.")
        selected.removeAll()
        isRemoving = false
        await refresh()
    }

    var archivedSaved: UInt64 { archived.reduce(0) { $0 + $1.saved } }

    /// Compresses each ticked session's transcript into the archive. The original goes only after the copy is proven identical.
    func compressSelected() async {
        let chosen = sessions.filter { selected.contains($0.id) && !$0.isActive() && !isNamed($0) }
        guard !chosen.isEmpty, !isRemoving else { return }
        isRemoving = true
        var saved: UInt64 = 0, failures: [String] = []
        for (index, session) in chosen.enumerated() {
            progress = "\(index + 1) of \(chosen.count)"
            do { saved += try await SessionArchive.archive(session).saved } catch { failures.append(error.localizedDescription) }
        }
        progress = nil
        report = "Compressed \(chosen.count - failures.count) session\(chosen.count - failures.count == 1 ? "" : "s") and freed \(Format.bytes(saved)). Restore one from the Archived list to /resume it."
            + (failures.isEmpty ? "" : " \(failures.count) couldn't be compressed: \(failures.prefix(2).joined(separator: "; "))")
        selected.removeAll()
        isRemoving = false
        await refresh()
    }

    func restore(_ record: ArchivedSession) async {
        guard !isRemoving else { return }
        isRemoving = true
        do {
            try await SessionArchive.restore(record)
            report = "Restored \(record.title ?? record.project). You can /resume it again."
        } catch {
            report = "Couldn't restore: \(error.localizedDescription)"
        }
        isRemoving = false
        await refresh()
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

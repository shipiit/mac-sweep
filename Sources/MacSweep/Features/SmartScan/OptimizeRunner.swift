import Foundation
import MacSweepCore
import Observation

/// Runs Smart Scan's clean-up steps one after another. Stop takes effect between steps, never mid-removal.
@MainActor
@Observable
final class OptimizeRunner {
    private(set) var steps: [OptimizeStep] = []
    private(set) var states: [OptimizeStep: OptimizeStepState] = [:]
    private(set) var isRunning = false
    private(set) var isStopping = false
    private(set) var finishedAt: Date?

    var progress: Double { OptimizePlan.progress(states, steps: steps) }
    var freed: UInt64 { OptimizePlan.freed(states) }

    static let maintenanceTasks: [MaintenanceTask] = [.rebuildLaunchServices, .clearFontCaches]

    func stop() {
        guard isRunning else { return }
        isStopping = true
    }

    func reset() {
        steps = []
        states = [:]
        finishedAt = nil
    }

    func run(_ enabled: Set<OptimizeStep>, app: AppModel) async {
        guard !isRunning else { return }
        steps = OptimizePlan.steps(enabled: enabled)
        states = Dictionary(uniqueKeysWithValues: steps.map { ($0, .pending) })
        finishedAt = nil
        isRunning = true
        isStopping = false
        for step in steps {
            if isStopping {
                states[step] = .skipped("Stopped")
                continue
            }
            states[step] = .running
            states[step] = await perform(step, app: app)
        }
        isRunning = false
        isStopping = false
        finishedAt = Date()
        MemoryRelief.release()
        // The pages these steps changed show fresh numbers the next time they're opened.
        if steps.contains(.sessionExtras) { await AISessionsModel.shared.refresh() }
        if steps.contains(.hardening) { await HardeningModel.shared.refresh() }
        if steps.contains(.appCaches) || steps.contains(.browserCopies) { await HiddenSpaceModel.shared.refresh() }
    }

    private func perform(_ step: OptimizeStep, app: AppModel) async -> OptimizeStepState {
        switch step {
        case .systemJunk: return await cleanJunk(app)
        case .trashBins: return await emptyTrash()
        case .maintenance: return await runMaintenance()
        case .appCaches:
            let hidden = HiddenSpaceModel.shared
            let parts = hidden.appData.filter { !hidden.isAppRunning($0.app) }.flatMap(\.removable).filter { $0.kind == .cache }
            return await trash(parts.map { CleanupTarget(path: $0.path, size: $0.size) }, empty: "No app caches to clear")
        case .sessionExtras:
            let sessions = AISessionsModel.shared.sessions.filter { !$0.isActive() && !$0.extras.isEmpty }
            // Sizes are per session, so each session's total rides on its first path.
            let targets = sessions.flatMap { session in
                session.extras.enumerated().map { CleanupTarget(path: $1, size: $0 == 0 ? session.extrasSize : 0, modified: session.modified) }
            }
            return await trash(targets, empty: "No session extras to remove")
        case .browserCopies:
            let hidden = HiddenSpaceModel.shared
            let clones = hidden.clones, running = hidden.runningBrowsers()
            guard !clones.isEmpty else { return .done(freed: 0, note: "No leftover copies") }
            let results = await Task.detached { CodeSignClones.remove(clones, isRunning: running.contains) }.value
            let freed = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
            let skipped = results.filter { !$0.succeeded }.count
            return skipped > 0 && freed == 0 ? .skipped("Quit the browser first") : .done(freed: freed, note: skipped > 0 ? "\(skipped) skipped: browser is open" : nil)
        case .hardening:
            let ids = HardeningModel.shared.oneClickFixes
            guard !ids.isEmpty else { return .done(freed: 0, note: "Nothing to change") }
            do {
                try await Hardening.applyFixes(ids)
                return .done(freed: 0, note: "\(ids.count) setting\(ids.count == 1 ? "" : "s") turned on")
            } catch AdminRunner.AdminError.cancelled {
                return .skipped("Password not entered")
            } catch {
                return .warning("Couldn't apply: \(error.localizedDescription)")
            }
        case .flushDNSAndRAM:
            do {
                try await AdminRunner.flushDNSAndPurgeMemory()
                return .done(freed: 0, note: "DNS flushed · inactive memory released")
            } catch AdminRunner.AdminError.cancelled {
                return .skipped("Password not entered")
            } catch {
                return .warning("Couldn't run: \(error.localizedDescription)")
            }
        }
    }

    /// Moves targets to the Trash and reports what went.
    private func trash(_ targets: [CleanupTarget], empty: String) async -> OptimizeStepState {
        guard !targets.isEmpty else { return .done(freed: 0, note: empty) }
        let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash) }.value
        let moved = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
        let failed = results.filter { !$0.succeeded }.count
        return failed > 0 && moved == 0 ? .warning("\(failed) couldn't be moved")
            : .done(freed: moved, note: failed > 0 ? "In the Trash · \(failed) couldn't be moved" : "In the Trash")
    }

    private func cleanJunk(_ app: AppModel) async -> OptimizeStepState {
        let safe = app.cleanup.items(.safe).flatMap(\.targets)
        guard !safe.isEmpty else { return .done(freed: 0, note: "Nothing to clean") }
        let conflicts = await InUseCheck.run(targets: safe.map(\.path), home: app.home)
        let targets = OptimizePlan.junkTargets(safe, inUse: Set(conflicts.map(\.targetPath)))
        let results = await app.cleanup.removeNow(targets, mode: .trash)
        let freed = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
        let failed = results.filter { !$0.succeeded }.count
        let skipped = safe.count - targets.count
        if results.isEmpty && !targets.isEmpty { return .warning("Another clean-up is already running") }
        let notes = [skipped > 0 ? "\(skipped) in use, skipped" : nil, failed > 0 ? "\(failed) couldn't be removed" : nil].compactMap { $0 }
        return failed > 0 && freed == 0 ? .warning(notes.joined(separator: " · ")) : .done(freed: freed, note: notes.isEmpty ? nil : notes.joined(separator: " · "))
    }

    private func emptyTrash() async -> OptimizeStepState {
        let outcome = await Task.detached(priority: .userInitiated) { () -> (UInt64, Int) in
            let bins = TrashBins.list()
            var freed: UInt64 = 0
            var failed = 0
            for bin in bins {
                let result = TrashBins.empty(bin)
                failed += result.failed.count
                if result.failed.isEmpty { freed += bin.size }
            }
            return (freed, failed)
        }.value
        return outcome.1 > 0 && outcome.0 == 0
            ? .warning("\(outcome.1) items couldn't be removed")
            : .done(freed: outcome.0, note: outcome.1 > 0 ? "\(outcome.1) items couldn't be removed" : nil)
    }

    private func runMaintenance() async -> OptimizeStepState {
        var failures: [String] = []
        for task in Self.maintenanceTasks {
            do { _ = try await task.run() } catch { failures.append(task.title) }
        }
        return failures.isEmpty ? .done(freed: 0, note: Self.maintenanceTasks.map(\.title).joined(separator: " · "))
            : .warning("Failed: \(failures.joined(separator: ", "))")
    }
}

import Foundation
import MacSweepCore
import Observation

/// Smart Scan's progress and results. Shared, so a scan keeps going and its results stay when you look at another page.
@MainActor @Observable
final class SmartScanModel {
    static let shared = SmartScanModel()

    private(set) var isRunning = false
    private(set) var step = ""
    private(set) var finishedAt: Date?
    private(set) var states: [SmartScanStep: StepState] = [:]
    private(set) var trashSize: UInt64 = 0
    let runner = OptimizeRunner()
    var enabledSteps: Set<OptimizeStep> = []

    /// Everything the scan measured, from each feature's own model.
    func input(app: AppModel) -> SmartScanInput {
        let hidden = HiddenSpaceModel.shared, hardening = HardeningModel.shared
        let patches = SecurityPatches.ranked(app.updates.updates)
        var input = SmartScanInput()
        input.safeJunk = app.cleanup.total(.safe)
        input.reviewJunk = app.cleanup.total(.review)
        input.trash = trashSize
        let closedAppParts = hidden.appData.filter { !hidden.isAppRunning($0.app) }.flatMap(\.removable)
        input.appCaches = closedAppParts.filter { $0.kind == .cache }.reduce(0) { $0 + $1.size }
        input.sandboxes = hidden.removableParts.filter { $0.kind == .rebuildable }.reduce(0) { $0 + $1.size }
        input.browserCopies = hidden.clonesSize
        let unused = hidden.databases.filter { $0.kind == .unreferenced || $0.kind == .test }
        input.unusedDatabases = unused.reduce(0) { $0 + $1.size }
        input.unusedDatabaseCount = unused.count
        input.stoppedServers = hidden.dataFolders.filter { !$0.isRunning }.reduce(0) { $0 + $1.size }
        input.sessionExtras = AISessionsModel.shared.sessions.filter { !$0.isActive() }.reduce(0) { $0 + $1.extrasSize }
        input.fixableSettings = hardening.failing.filter { if case .admin = $0.fix { true } else { false } }.map(\.title)
        input.manualSettings = hardening.failing.filter { if case .admin = $0.fix { false } else { true } }.map(\.title)
        input.suspiciousItems = app.security.highFindings
        input.securityUpdates = patches.filter { $0.severity == .high }.map(\.update.name)
        input.otherUpdates = patches.filter { $0.severity != .high }.count
        input.speedTips = Advisor.advise(app.advisorInput).count
        input.leftovers = app.apps.orphans.count
        return input
    }

    func run(app: AppModel) {
        guard !isRunning else { return }
        isRunning = true
        states = Dictionary(uniqueKeysWithValues: SmartScanStep.allCases.map { ($0, StepState.waiting) })
        Task {
            step = "Looking for junk…"
            states[.junk] = .running("Measuring caches, build output, old versions and leftovers…")
            // A targeted scan of known junk locations takes about a minute; the full disk map isn't needed here.
            await app.cleanup.quickScan()
            states[.junk] = .done("\(Format.bytes(app.cleanup.total(.safe))) safe to remove")

            step = "Looking outside your home folder…"
            states[.hidden] = .running("Apps' hidden data, databases, browser copies and AI sessions…")
            async let hidden: Void = HiddenSpaceModel.shared.refresh()
            async let sessions: Void = AISessionsModel.shared.refresh()
            _ = await (hidden, sessions)
            states[.hidden] = .done("\(Format.bytes(HiddenSpaceModel.shared.reclaimableAppData)) of app data · \(Format.bytes(AISessionsModel.shared.extrasSize)) of session extras")

            step = "Checking security…"
            states[.security] = .running("Startup items, running programs, extensions and security settings…")
            async let audit: Void = app.security.run()
            async let hardening: Void = HardeningModel.shared.refresh()
            _ = await (audit, hardening)
            states[.security] = .done("\(app.security.checkedItems) items checked · hardening \(HardeningModel.shared.score)/100")

            step = "Checking speed…"
            states[.speed] = .running("Memory, CPU, login items…")
            await app.startup.refresh()
            states[.speed] = .done("\(Advisor.advise(app.advisorInput).count) tips · \(app.startup.items.count) startup items")

            step = "Checking apps…"
            states[.apps] = .running("Measuring apps, checking Homebrew and macOS updates…")
            async let updates: Void = app.updates.check()
            async let apps: Void = app.apps.refresh()
            _ = await (updates, apps)
            states[.apps] = .done("\(app.apps.apps.count) apps · \(app.updates.updates.count) updates · \(app.apps.orphans.count) leftovers")
            trashSize = await Task.detached(priority: .utility) { TrashBins.list().reduce(0) { $0 + $1.size } }.value
            enabledSteps = SmartFindings.defaultSteps(SmartFindings.build(input(app: app))).union([.maintenance])
            finishedAt = Date()
            isRunning = false
        }
    }
}

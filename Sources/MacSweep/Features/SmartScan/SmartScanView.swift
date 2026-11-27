import MacSweepCore
import SwiftUI

struct SmartScanView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app
    @State private var isRunning = false
    @State private var step = ""
    @State private var finishedAt: Date?
    @State private var states: [SmartScanStep: StepState] = [:]
    @State private var runner = OptimizeRunner()
    @State private var enabledSteps: Set<OptimizeStep> = []
    @State private var trashSize: UInt64 = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if !runner.steps.isEmpty {
                    OptimizeRunView(runner: runner) {
                        runner.reset()
                        run()
                    }
                } else if isRunning {
                    hero
                    SmartScanChecklist(states: states)
                } else if finishedAt == nil {
                    SmartScanHome(onScan: run)
                } else {
                    SmartFindingsCard(findings: SmartFindings.build(scanInput), steps: $enabledSteps,
                                      onFix: { Task { await runner.run(enabledSteps, app: app) } }, onScanAgain: run)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Smart Scan")
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 150, height: 150)
                    .shadow(color: accent.opacity(isRunning ? 0.7 : 0.4), radius: isRunning ? 45 : 30, y: 10)
                    .scaleEffect(isRunning ? 1.04 : 1)
                    .animation(isRunning ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: isRunning)
                SpinningRing(isActive: isRunning, lineWidth: 7).frame(width: 176, height: 176)
                Image(systemName: isRunning ? "magnifyingglass" : "sparkles")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: isRunning)
            }
            .accessibilityHidden(true)
            Text(isRunning ? step : finishedAt == nil ? "Check your whole Mac in one go" : "Scan complete")
                .font(.largeTitle.weight(.semibold))
            Text("Junk and caches, malware and security, speed tips and app updates.")
                .foregroundStyle(.secondary)
            Button(action: run) {
                Text(isRunning ? "Scanning…" : finishedAt == nil ? "Scan" : "Scan Again")
                    .font(.title3.weight(.semibold))
                    .frame(width: 150, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isRunning)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Everything the scan measured, from each feature's own model.
    private var scanInput: SmartScanInput {
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

    private func run() {
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
            enabledSteps = SmartFindings.defaultSteps(SmartFindings.build(scanInput)).union([.maintenance])
            finishedAt = Date()
            isRunning = false
        }
    }
}

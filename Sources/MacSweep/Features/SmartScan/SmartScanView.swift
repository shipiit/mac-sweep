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
    @State private var enabledSteps: Set<OptimizeStep> = [.systemJunk, .maintenance]
    @State private var trashSize: UInt64 = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if !runner.steps.isEmpty {
                    OptimizeRunView(runner: runner) {
                        runner.reset()
                        run()
                    }
                } else if !isRunning && finishedAt == nil {
                    SmartScanHome(onScan: run)
                } else {
                    hero
                    if isRunning || finishedAt != nil { SmartScanChecklist(states: states) }
                    if finishedAt != nil && !isRunning {
                        OptimizeReviewCard(enabled: $enabledSteps, junkSize: app.cleanup.total(.safe), trashSize: trashSize) {
                            Task { await runner.run(enabledSteps, app: app) }
                        }
                    }
                    if isRunning || finishedAt != nil || app.disk.result != nil { results }
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

    private var results: some View {
        let advice = Advisor.advise(app.advisorInput)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
            if isPending(.junk) { SkeletonResultCard(tint: .green) } else {
            ResultCard(title: "Cleanup", symbol: "trash", tint: .green,
                       headline: Format.bytes(app.cleanup.total(.safe)),
                       detail: "safe to remove · \(Format.bytes(app.cleanup.total(.review))) to review",
                       action: ("Review & Clean", {
                           app.cleanup.selectSafe()
                           app.section = .storage
                       }))
            }
            if isPending(.security) { SkeletonResultCard(tint: .indigo) } else {
            ResultCard(title: "Protection", symbol: "checkmark.shield", tint: .indigo,
                       headline: "\(app.security.score)%",
                       detail: app.security.highFindings == 0 && app.security.protectionsOff == 0
                           ? "No threats found" : "\(app.security.highFindings) to review · \(app.security.protectionsOff) protections off",
                       action: ("Review", { app.section = .security }))
            }
            if isPending(.speed) { SkeletonResultCard(tint: .orange) } else {
            ResultCard(title: "Speed", symbol: "hare", tint: .orange,
                       headline: advice.isEmpty ? "All good" : "\(advice.count) tips",
                       detail: advice.first?.title ?? "Nothing slowing your Mac down",
                       action: ("Optimize", { app.section = .optimization }))
            }
            if isPending(.apps) { SkeletonResultCard(tint: .blue) } else {
            ResultCard(title: "Applications", symbol: "arrow.down.app", tint: .blue,
                       headline: app.updates.lastChecked == nil ? "Not checked" : app.updates.updates.count == 1 ? "1 update" : "\(app.updates.updates.count) updates",
                       detail: app.apps.orphans.isEmpty ? "No leftovers from deleted apps"
                           : "\(app.apps.orphans.count) leftovers from deleted apps",
                       action: ("Manage", { app.section = app.updates.updates.isEmpty ? .uninstaller : .updater }))
            }
        }
        .frame(maxWidth: 1100)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: states)
    }

    private func isPending(_ step: SmartScanStep) -> Bool {
        guard isRunning else { return false }
        if case .done = states[step] { return false }
        return true
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

            step = "Checking security…"
            states[.security] = .running("Startup items, running programs, browser extensions…")
            await app.security.run()
            states[.security] = .done("\(app.security.checkedItems) items checked · score \(app.security.score)%")

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
            finishedAt = Date()
            isRunning = false
        }
    }
}

private struct ResultCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    let action: (title: String, run: () -> Void)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
            Text(headline).font(.system(size: 30, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Button(action.title, action: action.run).buttonStyle(.borderedProminent).tint(tint)
        }
        .padding(18)
        .frame(height: 210)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.25)))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

import MacSweepCore
import SwiftUI

struct SmartScanView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app
    @State private var scan = SmartScanModel.shared

    var body: some View {
        @Bindable var scan = scan
        ScrollView {
            VStack(spacing: 26) {
                if !scan.runner.steps.isEmpty {
                    OptimizeRunView(runner: scan.runner) {
                        scan.runner.reset()
                        scan.run(app: app)
                    }
                } else if scan.isRunning {
                    hero
                    SmartScanChecklist(states: scan.states)
                } else if scan.finishedAt == nil {
                    SmartScanHome(onScan: { scan.run(app: app) })
                } else {
                    SmartFindingsCard(findings: SmartFindings.build(scan.input(app: app)), steps: $scan.enabledSteps,
                                      onFix: { Task { await scan.runner.run(scan.enabledSteps, app: app) } }, onScanAgain: { scan.run(app: app) })
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
                    .shadow(color: accent.opacity(scan.isRunning ? 0.7 : 0.4), radius: scan.isRunning ? 45 : 30, y: 10)
                    .scaleEffect(scan.isRunning ? 1.04 : 1)
                    .animation(scan.isRunning ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: scan.isRunning)
                SpinningRing(isActive: scan.isRunning, lineWidth: 7).frame(width: 176, height: 176)
                Image(systemName: scan.isRunning ? "magnifyingglass" : "sparkles")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: scan.isRunning)
            }
            .accessibilityHidden(true)
            Text(scan.isRunning ? scan.step : scan.finishedAt == nil ? "Check your whole Mac in one go" : "Scan complete")
                .font(.largeTitle.weight(.semibold))
            Text("Junk and caches, malware and security, speed tips and app updates.")
                .foregroundStyle(.secondary)
            Button(action: { scan.run(app: app) }) {
                Text(scan.isRunning ? "Scanning…" : scan.finishedAt == nil ? "Scan" : "Scan Again")
                    .font(.title3.weight(.semibold))
                    .frame(width: 150, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(scan.isRunning)
            .keyboardShortcut(.defaultAction)
        }
    }
}

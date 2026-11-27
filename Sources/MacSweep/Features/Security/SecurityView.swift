import MacSweepCore
import SwiftUI

struct SecurityView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let security = app.security
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 14) {
                    SecurityHero(security: security) { withAnimation { proxy.scrollTo("recommendations", anchor: .top) } }
                    ProtectionCards(checks: security.protections)
                    FindingsCard(findings: security.findings, isRunning: security.isRunning)
                    ExtensionsCard(extensions: security.extensions)
                    HStack(alignment: .top, spacing: 14) {
                        SecurityActivityCard()
                        SecurityRecommendationsCard().id("recommendations")
                        PrivacyAccessCard()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Label("MacSweep audits persistence, unsigned code and browser extensions using heuristics. It isn't a signature-based antivirus; Apple's XProtect handles known-malware signatures automatically.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .navigationTitle("Security Audit")
        .navigationSubtitle(security.lastRun.map { "Checked \(Format.relative($0))" } ?? "Not checked yet")
        .toolbar {
            Button("Check Now", systemImage: "arrow.clockwise") { Task { await security.run() } }
                .disabled(security.isRunning)
                .keyboardShortcut("r", modifiers: .command)
        }
        .task { if security.lastRun == nil && !security.isRunning { await security.run() } }
    }
}

/// Score, verdict, what was checked and the main actions.
private struct SecurityHero: View {
    let security: SecurityModel
    let showRecommendations: () -> Void
    @Environment(AppModel.self) private var app
    @State private var hardening = HardeningModel.shared

    var body: some View {
        let toHarden = hardening.failing.count
        let issues = security.protectionsOff + security.highFindings
        let on = security.protections.filter { $0.state == .on }.count
        VStack(alignment: .leading, spacing: 10) {
            SummaryHero(
                symbol: issues > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill", eyebrow: "Protection score",
                value: "\(security.score) / 100",
                caption: (issues > 0 ? "Your Mac needs attention" : toHarden > 0 ? "Protected, with settings to tighten" : "Your Mac is well protected")
                    + " · \(security.checkedItems) startup items and processes checked · \(security.uniqueExtensionCount) browser extensions",
                tint: security.score >= 85 ? .green : security.score >= 60 ? .orange : .red, isLoading: security.lastRun == nil,
                segments: [
                    BarSegment(label: "Protections on", value: Double(on), color: .green, detail: "\(on)"),
                    BarSegment(label: "Protections off", value: Double(security.protectionsOff), color: .red, detail: "\(security.protectionsOff)"),
                    BarSegment(label: "Findings to review", value: Double(security.highFindings), color: .orange, detail: "\(security.highFindings)"),
                    BarSegment(label: "Settings to harden", value: Double(toHarden), color: .yellow, detail: "\(toHarden)"),
                ]
            ) {
                Button { Task { await security.run() } } label: {
                    Label(security.isRunning ? "Checking…" : "Run Security Audit", systemImage: "magnifyingglass").frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent).disabled(security.isRunning)
                Button(action: showRecommendations) { Label("Review Recommendations", systemImage: "list.bullet.clipboard").frame(minWidth: 190) }
            }
            HStack(spacing: 8) {
                chip("\(security.protectionsOff) protection\(security.protectionsOff == 1 ? "" : "s") off", isGood: security.protectionsOff == 0)
                chip("\(security.highFindings) finding\(security.highFindings == 1 ? "" : "s") to review", isGood: security.highFindings == 0)
                chip("\(security.highAccessExtensions) high-risk extension\(security.highAccessExtensions == 1 ? "" : "s")", isGood: security.highAccessExtensions == 0)
                if hardening.hasLoaded {
                    Button { app.section = .hardening } label: {
                        chip(toHarden == 0 ? "All settings hardened" : "\(toHarden) setting\(toHarden == 1 ? "" : "s") to harden ›", isGood: toHarden == 0)
                    }
                    .buttonStyle(.plain).help("Open Hardening")
                }
            }
            .task { await hardening.refresh() }
        }
    }

    private func chip(_ text: String, isGood: Bool) -> some View {
        Label(text, systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.callout.weight(.medium)).foregroundStyle(isGood ? .green : .red)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((isGood ? Color.green : .red).opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

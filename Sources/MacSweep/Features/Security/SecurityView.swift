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

/// Score ring, verdict, three counters and the main actions.
private struct SecurityHero: View {
    let security: SecurityModel
    let showRecommendations: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        let issues = security.protectionsOff + security.highFindings
        let tint: Color = security.score >= 85 ? .green : security.score >= 60 ? .orange : .red
        Panel(padding: 24) {
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 12)
                    Circle().trim(from: 0, to: Double(security.score) / 100).stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(security.score)%").font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Protection Score").font(.caption).foregroundStyle(.secondary)
                    }
                    if security.isRunning { SpinningRing(isActive: true, lineWidth: 3).frame(width: 150, height: 150) }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 10) {
                    Text(security.lastRun == nil ? "Checking your Mac…" : issues == 0 ? "Your Mac is well protected" : "Your Mac needs attention")
                        .font(.system(size: 30, weight: .bold))
                    Text("\(security.checkedItems) startup items and processes checked · \(security.uniqueExtensionCount) browser extensions")
                        .font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        chip("\(security.protectionsOff) protection\(security.protectionsOff == 1 ? "" : "s") off", isGood: security.protectionsOff == 0)
                        chip("\(security.highFindings) finding\(security.highFindings == 1 ? "" : "s") to review", isGood: security.highFindings == 0)
                        chip("\(security.highAccessExtensions) high-risk extension\(security.highAccessExtensions == 1 ? "" : "s")", isGood: security.highAccessExtensions == 0)
                    }
                }
                Spacer()
                VStack(spacing: 10) {
                    Button { Task { await security.run() } } label: {
                        Label(security.isRunning ? "Checking…" : "Run Security Audit", systemImage: "magnifyingglass")
                            .font(.headline).foregroundStyle(.white).frame(width: 230).padding(.vertical, 12)
                            .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(security.isRunning)
                    Button(action: showRecommendations) {
                        Label("Review Recommendations", systemImage: "list.bullet.clipboard")
                            .font(.headline).frame(width: 230).padding(.vertical, 11)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ text: String, isGood: Bool) -> some View {
        Label(text, systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.callout.weight(.medium)).foregroundStyle(isGood ? .green : .red)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((isGood ? Color.green : .red).opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

import MacSweepCore
import SwiftUI

/// Every setting that makes this Mac harder to break into: what's on, what's off, and a fix for each gap.
struct HardeningView: View {
    @State private var model = HardeningModel.shared
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let error = model.error {
                    NoticeBanner(symbol: "exclamationmark.triangle", title: "A fix didn't apply", message: error, actionTitle: "Dismiss") { model.error = nil }
                }
                if !model.hasLoaded {
                    ForEach(0..<2, id: \.self) { _ in
                        Card { VStack(alignment: .leading, spacing: 12) { SkeletonBar(width: 220, height: 16); SkeletonBar(); SkeletonBar(width: 420) }.shimmering() }
                    }
                } else {
                    if !model.failing.isEmpty { section("To fix", subtitle: "Most important first.", checks: model.failing) }
                    section(model.failing.isEmpty ? "Everything is locked down" : "Already protecting you",
                            subtitle: "These are set the safe way. MacSweep rechecks them every time you open this page.", checks: model.passing)
                }
            }
            .padding(20)
        }
        .task { await model.refresh() }
    }

    private var hero: some View {
        let failed = model.failing.count, unknown = model.checks.filter { $0.state == .unknown }.count
        let passed = model.checks.count - failed - unknown
        return SummaryHero(
            symbol: "lock.shield", eyebrow: "Hardening score", value: "\(model.score) / 100",
            caption: failed == 0 ? "\(passed) protections on. Nothing to fix." : "\(passed) protections on · \(failed) to fix" + (unknown > 0 ? " · \(unknown) couldn't be checked" : ""),
            tint: model.score >= 90 ? .green : model.score >= 70 ? .orange : .red, isLoading: !model.hasLoaded,
            segments: [
                BarSegment(label: "On", value: Double(passed), color: .green, detail: "\(passed)"),
                BarSegment(label: "To fix", value: Double(failed), color: .orange, detail: "\(failed)"),
                BarSegment(label: "Couldn't check", value: Double(unknown), color: .gray.opacity(0.4), detail: "\(unknown)"),
            ]
        ) {
            if !model.oneClickFixes.isEmpty {
                Button { Task { await model.fix(model.oneClickFixes) } } label: {
                    Label("Fix \(model.oneClickFixes.count) Now", systemImage: "wand.and.stars").frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent).disabled(model.isFixing)
                .help("Applies every fix MacSweep can make itself. macOS asks for your password once.")
            }
            Button { Task { await model.refresh() } } label: { Label("Recheck", systemImage: "arrow.clockwise").frame(minWidth: 130) }
                .disabled(model.isLoading)
        }
    }

    private func section(_ title: String, subtitle: String, checks: [HardeningCheck]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, subtitle: subtitle)
                ForEach(checks) { check in
                    HardeningRow(check: check, isFixing: model.isFixing) { run(check) }
                    if check.id != checks.last?.id { Divider() }
                }
            }
        }
    }

    private func run(_ check: HardeningCheck) {
        switch check.fix {
        case .admin(let id): Task { await model.fix([id]) }
        case .openSettings(let url): FileActions.open(url: URL(string: url))
        case .openDNSShield: app.section = .dnsShield
        case nil: break
        }
    }
}

private struct HardeningRow: View {
    let check: HardeningCheck
    let isFixing: Bool
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(check.title).font(.callout.weight(.semibold))
                    if check.state == .fail { SeverityPill(severity: check.severity) }
                }
                Text(check.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(check.status).font(.callout.monospacedDigit()).foregroundStyle(check.state == .fail ? color : .secondary)
            if let title = buttonTitle { Button(title, action: fix).disabled(isFixing).frame(minWidth: 110, alignment: .trailing) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var buttonTitle: String? {
        switch check.fix {
        case .admin: "Fix Now"
        case .openSettings: "Open Settings"
        case .openDNSShield: "Open DNS Shield"
        case nil: nil
        }
    }

    private var symbol: String {
        switch check.state {
        case .pass: "checkmark.shield.fill"
        case .fail: "exclamationmark.shield.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch check.state {
        case .pass: .green
        case .fail: check.severity == .high ? .red : .orange
        case .unknown: .secondary
        }
    }
}

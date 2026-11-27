import MacSweepCore
import SwiftUI

/// Pending updates ranked by how much they matter for security, with the fastest way to install each.
struct PatcherView: View {
    @Environment(AppModel.self) private var app
    @State private var hardening = HardeningModel.shared
    @State private var definitions = SecurityPatches.malwareDefinitions()
    @State private var showsRoutine = false
    private static let softwareUpdate = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")

    var body: some View {
        let model = app.updates
        let patches = SecurityPatches.ranked(model.updates)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero(patches)
                if let message = model.message {
                    NoticeBanner(symbol: "info.circle", title: "Update", message: message, tint: .blue, actionTitle: "Dismiss") { app.updates.message = nil }
                }
                automatic
                if model.lastChecked == nil {
                    Card { Label(model.isChecking ? "Checking Apple and Homebrew for updates…" : "Not checked yet. Press Check Now.", systemImage: "arrow.down.circle").foregroundStyle(.secondary) }
                } else if patches.isEmpty {
                    Card { Label("Everything is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                } else {
                    let important = patches.filter { $0.severity != .low }, routine = patches.filter { $0.severity == .low }
                    if !important.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Install these first", subtitle: "Apple's security fixes, then apps and the tools that handle network traffic or keys.")
                                ForEach(important) { patch in
                                    PatchRow(patch: patch, isUpgrading: model.upgrading.contains(patch.id)) { install(patch) }
                                    if patch.id != important.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    if !routine.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    SectionHeader(title: "\(routine.count) other developer tools", subtitle: "Behind their latest version, with no special security weight.")
                                    Spacer()
                                    Button(showsRoutine ? "Hide" : "Show") { showsRoutine.toggle() }
                                    Button("Update All") { Task { for patch in routine { await app.updates.upgrade(patch.update) } } }
                                        .disabled(!model.upgrading.isEmpty).help("Upgrades them one after another with Homebrew")
                                }
                                if showsRoutine {
                                    ForEach(routine) { patch in
                                        PatchRow(patch: patch, isUpgrading: model.upgrading.contains(patch.id)) { install(patch) }
                                        if patch.id != routine.last?.id { Divider() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            if model.lastChecked == nil { await model.check() }
            await hardening.refresh()
        }
    }

    private func hero(_ patches: [SecurityPatch]) -> some View {
        let model = app.updates
        let urgent = patches.filter { $0.severity == .high }.count
        let count = { (severity: FindingSeverity) in Double(patches.filter { $0.severity == severity }.count) }
        return SummaryHero(
            symbol: "bandage", eyebrow: "Updates that matter for security",
            value: patches.isEmpty ? "Up to date" : "\(patches.filter { $0.severity != .low }.count) to install",
            caption: [urgent > 0 ? "\(urgent) from Apple with security fixes" : nil,
                      definitions.map { "malware definitions \($0.version), updated \(Format.relative($0.updated))" },
                      model.lastChecked.map { "checked \(Format.relative($0))" }].compactMap { $0 }.joined(separator: " · "),
            tint: urgent > 0 ? .red : patches.isEmpty ? .green : .orange, isLoading: model.lastChecked == nil && model.isChecking,
            segments: [
                BarSegment(label: "Security fixes", value: count(.high), color: .red, detail: "\(Int(count(.high)))"),
                BarSegment(label: "Apps & network tools", value: count(.medium), color: .orange, detail: "\(Int(count(.medium)))"),
                BarSegment(label: "Other tools", value: count(.low), color: .blue, detail: "\(Int(count(.low)))"),
            ]
        ) {
            if urgent > 0 {
                Button { FileActions.open(url: Self.softwareUpdate) } label: { Label("Install macOS Update", systemImage: "arrow.down.circle").frame(minWidth: 150) }
                    .buttonStyle(.borderedProminent)
            }
            Button { Task { await app.updates.check(); definitions = SecurityPatches.malwareDefinitions() } } label: {
                Label("Check Now", systemImage: "arrow.clockwise").frame(minWidth: 150)
            }
            .disabled(model.isChecking)
        }
    }

    @ViewBuilder private var automatic: some View {
        if let check = hardening.checks.first(where: { $0.id == "auto-updates" }) {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: check.state == .fail ? "exclamationmark.shield.fill" : "checkmark.shield.fill").font(.title2)
                        .foregroundStyle(check.state == .fail ? .red : .green).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic security updates: \(check.status)").font(.callout.weight(.semibold))
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if check.state == .fail { Button("Turn On") { Task { await hardening.fix(["auto-updates"]) } }.disabled(hardening.isFixing) }
                }
            }
        }
    }

    private func install(_ patch: SecurityPatch) {
        if patch.update.source == .macOS { FileActions.open(url: Self.softwareUpdate) } else { Task { await app.updates.upgrade(patch.update) } }
    }
}

private struct PatchRow: View {
    let patch: SecurityPatch
    let isUpgrading: Bool
    let install: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(patch.update.name).font(.callout.weight(.semibold)).lineLimit(1)
                    SeverityPill(severity: patch.severity)
                    if patch.update.needsRestart { Pill(text: "Restart needed") }
                }
                Text(patch.reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text([patch.update.installed, patch.update.available].filter { !$0.isEmpty }.joined(separator: " → "))
                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            Text(patch.update.source.rawValue).font(.caption).foregroundStyle(.tertiary).frame(width: 96, alignment: .trailing)
            if isUpgrading {
                ProgressView().controlSize(.small).frame(minWidth: 150)
            } else {
                Button(patch.update.source == .macOS ? "Open Software Update" : "Update", action: install).frame(minWidth: 150, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

import MacSweepCore
import SwiftUI

extension FindingSeverity {
    var color: Color {
        switch self {
        case .info: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

struct SecurityView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let security = app.security
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SecurityHeader(security: security)
                ProtectionGrid(checks: security.protections)
                FindingsCard(findings: security.findings, isRunning: security.isRunning)
                ExtensionsCard(extensions: security.extensions)
                Text("MacSweep audits persistence, unsigned code and browser extensions using heuristics. It isn't a signature-based antivirus; Apple's XProtect (above) handles known-malware signatures automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Security")
        .navigationSubtitle(security.lastRun.map { "Checked \(Format.relative($0))" } ?? "Not checked yet")
        .toolbar {
            Button("Run Check", systemImage: "arrow.clockwise") { Task { await security.run() } }
                .disabled(security.isRunning)
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}

private struct SecurityHeader: View {
    let security: SecurityModel

    var body: some View {
        Card {
            HStack(spacing: 20) {
                RingGauge(value: Double(security.score) / 100, label: "Score", size: 86, lineWidth: 9, invertColors: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline).font(.title2.weight(.semibold))
                    Text("\(security.checkedItems) startup items and processes checked · \(security.uniqueExtensionCount) browser extensions")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Pill(text: "\(security.protectionsOff) protections off", color: security.protectionsOff > 0 ? .red : .green)
                        Pill(text: "\(security.highFindings) findings to review", color: security.highFindings > 0 ? .orange : .green)
                        Pill(text: "\(security.highAccessExtensions) high-risk extensions", color: security.highAccessExtensions > 0 ? .red : .green)
                    }
                }
                Spacer()
                if security.isRunning { ProgressView().controlSize(.small) }
            }
        }
    }

    private var headline: String {
        if security.lastRun == nil { return "Checking your Mac…" }
        switch security.score {
        case 90...: return "Your Mac looks well protected"
        case 70..<90: return "A few things are worth a look"
        default: return "Your Mac needs attention"
        }
    }
}

private struct ProtectionGrid: View {
    let checks: [ProtectionCheck]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(checks) { check in
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: symbol(check.state)).foregroundStyle(color(check.state))
                            Text(check.title).fontWeight(.semibold).lineLimit(1)
                        }
                        Text(check.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(label(check.state)).font(.caption.weight(.semibold)).foregroundStyle(color(check.state))
                            Spacer()
                            if check.state != .on, let url = check.settingsURL {
                                Button("Turn On…") { FileActions.open(url: URL(string: url)) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ state: ProtectionCheck.State) -> String {
        switch state {
        case .on: "checkmark.shield.fill"
        case .off: "xmark.shield.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func color(_ state: ProtectionCheck.State) -> Color {
        switch state {
        case .on: .green
        case .off: .red
        case .unknown: .secondary
        }
    }

    private func label(_ state: ProtectionCheck.State) -> String {
        switch state {
        case .on: "On"
        case .off: "Off"
        case .unknown: "Unknown"
        }
    }
}

private struct FindingsCard: View {
    @Environment(AppModel.self) private var app
    let findings: [SecurityFinding]
    let isRunning: Bool
    @State private var removal: LaunchItemRemover.Plan?
    @State private var error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Startup items & running programs", subtitle: "Unsigned code, temp-folder launchers, Apple impersonators and known adware")
                if findings.isEmpty {
                    Label(isRunning ? "Checking…" : "Nothing suspicious found.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Pill(text: finding.severity.title, color: finding.severity.color).frame(width: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title).fontWeight(.medium)
                            Text(finding.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if let path = finding.path {
                                Text(Format.path(path)).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer()
                        actions(for: finding)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder private func actions(for finding: SecurityFinding) -> some View {
        HStack {
            if let path = finding.path { Button("Reveal") { FileActions.reveal(path) } }
            switch finding.subject {
            case .launchItem(let plistPath, _):
                if let item = app.startup.items.first(where: { $0.plistPath == plistPath }) {
                    Button("Disable") { Task { await app.startup.perform(.disable, on: item); await app.security.run() } }
                    Button("Remove…", role: .destructive) { removal = LaunchItemRemover.plan(for: item) }
                } else {
                    Button("Startup Items") { app.section = .startup }
                }
            case .process:
                Button("Processes") { app.section = .processes }
            case .file:
                EmptyView()
            }
        }
        .controlSize(.small)
        .task { if app.startup.items.isEmpty { await app.startup.refresh() } }
        .confirmationDialog("Remove \(removal?.item.label ?? "")?", isPresented: isPresented($removal), titleVisibility: .visible,
                            presenting: removal) { plan in
            Button(plan.needsAdmin ? "Remove as Administrator" : "Remove", role: .destructive) {
                Task {
                    do {
                        try await LaunchItemRemover.execute(plan)
                    } catch AdminRunner.AdminError.cancelled {
                        return
                    } catch {
                        self.error = error.localizedDescription
                    }
                    await app.startup.refresh()
                    await app.security.run()
                }
            }
        } message: { plan in
            Text("Stops it now and moves these to the Trash:\n" + plan.filesToTrash.map(Format.path).joined(separator: "\n"))
        }
        .alert("Couldn't remove", isPresented: isPresented($error), presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }
}

private struct ExtensionsCard: View {
    @Environment(AppModel.self) private var app
    let extensions: [BrowserExtension]

    var body: some View {
        let groups = ExtensionGroup.group(extensions)
        let risky = groups.filter { $0.risk == .high }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Browser extensions",
                                  subtitle: "\(groups.count) extensions · \(risky.count) high risk · \(groups.filter { $0.risk == .medium }.count) can read all sites")
                    Spacer()
                    Button("All Extensions") { app.section = .extensions }
                }
                if risky.isEmpty {
                    Label("No high-risk extensions.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(risky) { ExtensionGroupRow(group: $0) }
            }
        }
    }
}

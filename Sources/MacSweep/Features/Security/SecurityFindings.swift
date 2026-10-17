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

struct FindingsCard: View {
    @Environment(AppModel.self) private var app
    let findings: [SecurityFinding]
    let isRunning: Bool
    @State private var removal: LaunchItemRemover.Plan?
    @State private var error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    IconBadge(symbol: "square.stack.3d.up.fill", tint: .blue, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Startup items & background processes").font(.headline)
                        Text("\(app.security.checkedItems) items scanned · login items, launch agents, daemons and running processes")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if findings.isEmpty {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(isRunning ? "Checking…" : "Nothing suspicious found").fontWeight(.semibold).foregroundStyle(.green)
                                Text("All startup items look safe.").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.green) }
                    }
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

struct ExtensionsCard: View {
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

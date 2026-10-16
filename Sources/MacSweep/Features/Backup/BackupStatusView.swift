import MacSweepCore
import SwiftUI

/// Time Machine at a glance: how old the latest backup is, where it goes, and what it leaves out.
struct BackupStatusView: View {
    @State private var model = BackupStatusModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if model.report != nil, model.severity >= .medium {
                    NoticeBanner(symbol: model.severity.symbol, title: "Your files aren't protected by a recent backup",
                                 message: "If this Mac's drive fails or the Mac is lost, recent work is gone. Connect your backup disk or set one up.",
                                 tint: model.severity.color,
                                 actionTitle: "Open Time Machine Settings") { FileActions.open(url: URL(string: SettingsLinks.timeMachine)) }
                }
                if model.report?.status == .needsFullDiskAccess {
                    NoticeBanner(symbol: "lock.shield", title: "Full Disk Access is needed",
                                 message: "Grant MacSweep Full Disk Access to see when your last backup finished.",
                                 actionTitle: "Open Full Disk Access") { FileActions.open(url: Permissions.fullDiskAccessSettingsURL) }
                }
                if let report = model.report {
                    BackupDestinationsCard(destinations: report.destinations)
                    BackupFoldersCard(checked: model.checkedFolders, excluded: model.excluded)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Backups")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.load() } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading)
            }
        }
        .task { if model.report == nil { await model.load() } }
    }

    private var hero: some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 18) {
                SymbolBadge(symbol: "clock.arrow.circlepath", size: 60)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(model.headline).font(.title2.weight(.semibold))
                        if model.report != nil { SeverityPill(severity: model.severity) }
                    }
                    Text(model.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if case .backedUp(let date)? = model.report?.status {
                        Text(date.formatted(date: .complete, time: .shortened))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                if model.isLoading { ProgressView().controlSize(.small) }
                Button("Open Time Machine Settings") { FileActions.open(url: URL(string: SettingsLinks.timeMachine)) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct BackupDestinationsCard: View {
    let destinations: [BackupDestination]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Destinations", subtitle: "Where Time Machine saves your backups")
                if destinations.isEmpty {
                    Label("No backup disk is set up.", systemImage: "externaldrive.badge.xmark").foregroundStyle(.secondary)
                }
                ForEach(destinations) { destination in
                    HStack(spacing: 12) {
                        SymbolBadge(symbol: destination.kind == "Network" ? "externaldrive.connected.to.line.below" : "externaldrive")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name).fontWeight(.medium)
                            Text(destination.kind ?? "Backup disk").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(destination.mountPoint == nil ? "Not connected" : "Connected",
                              systemImage: destination.mountPoint == nil ? "bolt.horizontal.circle" : "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct BackupFoldersCard: View {
    let checked: [String]
    let excluded: [String]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Important folders", subtitle: "Folders that hurt most to lose, checked against Time Machine's exclusions")
                if checked.isEmpty {
                    Label("Couldn't check folder exclusions.", systemImage: "questionmark.folder").foregroundStyle(.secondary)
                } else if excluded.isEmpty {
                    Label("All \(checked.count) important folders are included in backups.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(excluded, id: \.self) { path in
                        HStack(spacing: 12) {
                            FileIcon(path: path, size: 24)
                            Text(Format.path(path)).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            SeverityPill(severity: .medium, text: "Excluded")
                            Button("Show in Finder") { FileActions.reveal(path) }
                        }
                    }
                }
            }
        }
    }
}

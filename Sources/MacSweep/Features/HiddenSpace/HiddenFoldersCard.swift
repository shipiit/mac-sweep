import MacSweepCore
import SwiftUI

/// Database data folders under Homebrew, including servers that aren't running (their data still takes space).
struct DataFoldersCard: View {
    let model: HiddenSpaceModel
    @State private var pending: DatabaseDataFolder?

    var body: some View {
        let folders = model.dataFolders
        if !folders.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Database data folders",
                                  subtitle: "A stopped server's data still takes space. If you no longer use an old version, you can move its data to the Trash here.")
                    ForEach(folders) { folder in
                        HStack {
                            Image(systemName: "cylinder.split.1x2").foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.name).font(.callout.weight(.semibold))
                                Text(Format.path(folder.path)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(folder.isRunning ? "Running" : "Stopped", systemImage: folder.isRunning ? "circle.fill" : "circle")
                                .font(.caption).foregroundStyle(folder.isRunning ? .green : .secondary)
                            Text(Format.bytes(folder.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                            if !folder.isRunning { Button("Move to Trash…") { pending = folder }.disabled(model.busy != nil) }
                            Button("Reveal", systemImage: "folder") { FileActions.reveal(folder.path) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                }
            }
            .confirmationDialog("Move \(pending?.name ?? "this folder") to the Trash?",
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { folder in
                Button("Move \(Format.bytes(folder.size)) to Trash") { Task { await model.trashDataFolder(folder) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Every database stored by this server version goes with it. MacSweep can't list them while the server is stopped, so start it first if you're not sure what's inside. You can put the folder back until you empty the Trash.")
            }
        }
    }
}

/// The biggest hidden folders in home and inside ~/Library, each explained.
struct HiddenFoldersCard: View {
    let model: HiddenSpaceModel
    @State private var expanded: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Hidden folders",
                                  subtitle: "Dot-folders in your home and the biggest folders inside ~/Library: app data, caches, containers and developer files you can't see in Finder.")
                    Spacer()
                    if model.isMeasuringFolders { ProgressView().controlSize(.small) }
                }
                if model.hiddenFolders.isEmpty {
                    Text(model.isMeasuringFolders ? "Measuring ~/Library and hidden folders…" : "Nothing over 50 MB.").foregroundStyle(.secondary)
                }
                let largest = max(model.hiddenFolders.first?.size ?? 1, 1)
                ForEach(model.hiddenFolders) { folder in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Button {
                                expanded = expanded == folder.path ? nil : folder.path
                            } label: {
                                Image(systemName: expanded == folder.path ? "chevron.down" : "chevron.right").frame(width: 12)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(expanded == folder.path ? "Hide details" : "Show details")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.path(folder.path)).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                                ProgressView(value: Double(folder.size) / Double(largest)).accessibilityHidden(true)
                            }
                            if let risk = folder.risk { RiskTag(risk: risk) }
                            Text(Format.bytes(folder.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                            Button("Reveal", systemImage: "folder") { FileActions.reveal(folder.path) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        if expanded == folder.path {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.summary ?? "No description for this folder yet.")
                                if let ifDeleted = folder.ifDeleted { Text("If deleted: " + ifDeleted).foregroundStyle(.secondary) }
                                FolderDrillDown(path: folder.path, model: model).padding(.top, 4)
                            }
                            .font(.caption).padding(.leading, 22)
                        }
                    }
                }
            }
        }
    }
}

private struct RiskTag: View {
    let risk: DeletionRisk

    var body: some View {
        let color: Color = switch risk {
        case .safe: .green
        case .caution: .orange
        case .keep: .blue
        }
        Text(risk.rawValue).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }
}

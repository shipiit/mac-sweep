import MacSweepCore
import SwiftUI

struct CleanConfirmSheet: View {
    @Environment(\.appAccent) private var accent
    @Bindable var cleanup: CleanupModel
    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [InUseConflict]?
    @State private var skipInUse = true

    private var skipped: Set<String> {
        skipInUse ? Set((conflicts ?? []).map(\.targetPath)) : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: cleanup.mode == .trash ? "trash" : "flame")
                    .font(.largeTitle)
                    .foregroundStyle(cleanup.mode == .trash ? accent : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Clean \(Format.bytes(cleanup.selectedTargets.filter { !skipped.contains($0.path) }.reduce(0) { $0 + $1.size }))?")
                        .font(.title2.bold())
                    Text("\(cleanup.selectedTargets.count) locations in \(cleanup.selectedItemCount) groups")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Method", selection: $cleanup.mode) {
                Text("Move to Trash").tag(RemovalMode.trash)
                Text("Delete immediately").tag(RemovalMode.delete)
            }
            .pickerStyle(.radioGroup)

            if cleanup.mode == .delete {
                warning("Deleting skips the Trash and can't be undone.", color: .red)
            } else {
                warning("Moving to the Trash is reversible, but the space only frees up once you empty the Trash.", color: .secondary)
            }
            if cleanup.selectionIncludesReview {
                warning("Your selection includes “Review first” items such as models, SDKs or installers.", color: .orange)
            }

            inUseSection

            List(cleanup.selectedTargets.sorted { $0.size > $1.size }) { target in
                HStack {
                    Text(Format.path(target.path)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Format.bytes(target.size)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .frame(height: 180)
            .listStyle(.bordered)

            HStack {
                if cleanup.isCleaning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(cleanup.mode == .trash ? "Move to Trash" : "Delete", role: .destructive) {
                    cleanup.cleanSelected(skipping: skipped)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(cleanup.mode == .delete ? .red : accent)
                .keyboardShortcut(.defaultAction)
                .disabled(cleanup.isCleaning || conflicts == nil)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task { conflicts = await InUseCheck.run(targets: cleanup.selectedTargets.map(\.path), home: cleanup.home) }
    }

    @ViewBuilder private var inUseSection: some View {
        if let conflicts {
            if conflicts.isEmpty {
                Label("Nothing running is using these locations.", systemImage: "checkmark.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(conflicts.count) locations are in use right now", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(conflicts.prefix(4)) { conflict in
                        Text("• \(Format.path(conflict.targetPath)): \(conflict.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Toggle("Skip items that are in use (recommended)", isOn: $skipInUse)
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking running apps…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func warning(_ text: String, color: Color) -> some View {
        Label(text, systemImage: color == .secondary ? "info.circle" : "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Confirmation for trashing a single item picked from the map or the file list.
struct TrashConfirmation: ViewModifier {
    @Binding var nodes: [FileNode]?
    let onConfirm: ([FileNode]) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: isPresented($nodes),
            titleVisibility: .visible,
            presenting: nodes
        ) { nodes in
            Button("Move to Trash", role: .destructive) { onConfirm(nodes) }
            Button("Cancel", role: .cancel) {}
        } message: { nodes in
            Text(nodes.count == 1 ? Format.path(nodes[0].path) : "\(nodes.count) items. You can restore them from the Trash.")
        }
    }

    private var title: String {
        guard let nodes else { return "" }
        let size = Format.bytes(nodes.reduce(0) { $0 + $1.size })
        return nodes.count == 1 ? "Move “\(nodes[0].name)” (\(size)) to the Trash?" : "Move \(nodes.count) items (\(size)) to the Trash?"
    }
}

extension View {
    func trashConfirmation(_ nodes: Binding<[FileNode]?>, onConfirm: @escaping ([FileNode]) -> Void) -> some View {
        modifier(TrashConfirmation(nodes: nodes, onConfirm: onConfirm))
    }
}

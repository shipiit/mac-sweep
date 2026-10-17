import MacSweepCore
import SwiftUI

/// Contents of the folder selected in the treemap, biggest first, each with a tick box and what deleting it means.
struct FolderPicker: View {
    let folder: FileNode?
    let cleanup: CleanupModel
    @Environment(\.appAccent) private var accent

    var body: some View {
        if let folder, !folder.children.isEmpty {
            let largest = max(folder.children.first?.size ?? 1, 1)
            List {
                Section {
                    ForEach(folder.children.prefix(200)) { child in row(child, largest: largest) }
                } header: {
                    HStack {
                        FileIcon(path: folder.path, size: 16)
                        Text(Format.path(folder.path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(folder.size)).monospacedDigit()
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("Pick a folder", systemImage: "square.grid.3x3.square",
                                   description: Text("Click a folder in the map to list what's inside and tick what to remove."))
                .frame(minHeight: 220)
        }
    }

    private func row(_ node: FileNode, largest: UInt64) -> some View {
        let canRemove = PathGuard.canRemove(node.path, home: cleanup.home, extraProtected: [Bundle.main.bundlePath])
        let safety = cleanup.safety(forPath: node.path)
        let explanation = ImpactKnowledge.explain(path: node.path, home: cleanup.home)
        return HStack(alignment: .top, spacing: 10) {
            Toggle(node.name, isOn: Binding(get: { cleanup.isPicked(node.path) }, set: { _ in cleanup.togglePick(node) }))
                .toggleStyle(.checkbox).labelsHidden().disabled(!canRemove)
                .help(canRemove ? "Add to the selection" : "Protected: MacSweep never removes this")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name).lineLimit(1)
                    if let safety { Pill(text: safety.title, color: safety.color) }
                    if !canRemove { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Protected") }
                }
                Text(explanation.map { "If deleted: \($0.ifDeleted)" } ?? "\(Format.count(node.itemCount)) files · modified \(Format.relative(node.modified))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                GeometryReader { proxy in
                    Capsule().fill(accent.opacity(0.6)).frame(width: max(proxy.size.width * Double(node.size) / Double(largest), 2))
                }
                .frame(height: 3)
            }
            Spacer(minLength: 6)
            Text(Format.bytes(node.size)).monospacedDigit().font(.callout)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") { FileActions.reveal(node.path) }
            Button("Copy Path") { FileActions.copy(node.path) }
        }
    }
}

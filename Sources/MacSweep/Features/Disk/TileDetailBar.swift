import MacSweepCore
import SwiftUI

/// Footer under the map describing the hovered or selected item, with what it is and quick actions.
struct TileDetailBar: View {
    let tile: TreemapTile
    let home: String
    let safety: CleanupSafety?
    let onTrash: (FileNode) -> Void

    var body: some View {
        let node = tile.node
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FileIcon(path: node.path, size: 18)
                Text(node.name).fontWeight(.semibold).lineLimit(1)
                Text(Format.path(node.path)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let safety { Pill(text: safety.title, color: safety.color) }
                if node.isHidden { Pill(text: "Hidden") }
                Pill(text: tile.category.rawValue, color: tile.category.color)
                Text(Format.bytes(node.size)).font(.system(.body, design: .monospaced).weight(.semibold))
            }
            HStack(spacing: 10) {
                if let explanation = ImpactKnowledge.explain(path: node.path, home: home) {
                    Label("\(explanation.summary) If deleted: \(explanation.ifDeleted)", systemImage: explanation.risk.symbol)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(explanation.ifDeleted)
                } else {
                    Text("\(Format.count(node.itemCount)) files · modified \(Format.relative(node.modified))").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal") { FileActions.reveal(node.path) }
                Button("Copy Path") { FileActions.copy(node.path) }
                Button("Trash…", role: .destructive) { onTrash(node) }
                    .disabled(!PathGuard.canRemove(node.path, home: home, extraProtected: [Bundle.main.bundlePath]))
            }
            .controlSize(.small)
        }
        .font(.callout)
    }
}

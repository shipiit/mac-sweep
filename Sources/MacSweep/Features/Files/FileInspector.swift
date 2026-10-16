import MacSweepCore
import SwiftUI

extension DeletionRisk {
    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .keep: .red
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .keep: "hand.raised.fill"
        }
    }
}

struct RiskLabel: View {
    let explanation: Explanation?

    var body: some View {
        if let explanation {
            HStack(spacing: 6) {
                Image(systemName: explanation.risk.symbol).foregroundStyle(explanation.risk.color)
                    .accessibilityLabel(explanation.risk.rawValue)
                Text(explanation.summary).foregroundStyle(.secondary).lineLimit(1)
            }
            .help("\(explanation.risk.rawValue): \(explanation.ifDeleted)")
        } else {
            Text("Unknown").foregroundStyle(.tertiary)
        }
    }
}

/// Explains the selected file or folder: what it is, what deleting it would do, and quick actions.
struct FileInspector: View {
    let node: FileNode?
    let home: String
    let onTrash: (FileNode) -> Void

    var body: some View {
        if let node {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        FileIcon(path: node.path, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name).font(.headline).lineLimit(2)
                            Text(Format.bytes(node.size)).font(.system(.title3, design: .monospaced).weight(.semibold))
                        }
                    }
                    explanationView(ImpactKnowledge.explain(path: node.path, home: home))
                    InfoGrid(rows: [
                        ("Modified", node.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—"),
                        ("Kind", node.isDirectory ? "Folder · \(Format.count(node.itemCount)) files" : (node.name as NSString).pathExtension.uppercased()),
                        ("Hidden", node.isHidden || PathTools.hasHiddenComponent(node.path, below: home) ? "Yes" : "No"),
                    ])
                    PathField(title: "Location", path: node.path)
                    HStack {
                        Button("Reveal in Finder") { FileActions.reveal(node.path) }
                        Button("Move to Trash…", role: .destructive) { onTrash(node) }
                            .disabled(!PathGuard.canRemove(node.path, home: home, extraProtected: [Bundle.main.bundlePath]))
                    }
                    if let reason = PathGuard.reason(node.path, home: home, extraProtected: [Bundle.main.bundlePath]) {
                        Label("MacSweep won't remove this: \(reason)", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Select a file", systemImage: "questionmark.folder",
                                   description: Text("See what it is and what would happen if you deleted it."))
        }
    }

    @ViewBuilder private func explanationView(_ explanation: Explanation?) -> some View {
        if let explanation {
            VStack(alignment: .leading, spacing: 8) {
                Label(explanation.risk.rawValue, systemImage: explanation.risk.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(explanation.risk.color)
                Text(explanation.summary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("If you delete it").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(explanation.ifDeleted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(explanation.risk.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text("MacSweep doesn't recognise this item. It goes to the Trash, so you can put it back if something breaks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

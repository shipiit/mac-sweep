import MacSweepCore
import SwiftUI

/// Large files grouped by what they are, each row saying plainly what deleting it would cause.
struct LargeFilesGroupedList: View {
    let rows: [FileRow]
    let home: String
    @Binding var selection: Set<String>
    /// The row clicked last, shown in the inspector.
    @Binding var inspected: String?
    @State private var collapsed: Set<FileGroup> = []

    var body: some View {
        let groups = Dictionary(grouping: rows) { FileGroup.of(path: $0.node.path, home: home) }
        List {
            ForEach(FileGroup.allCases.filter { groups[$0] != nil }) { group in
                let items = groups[group] ?? []
                Section(isExpanded: Binding(get: { !collapsed.contains(group) }, set: { isOpen in
                    if isOpen { collapsed.remove(group) } else { collapsed.insert(group) }
                })) {
                    ForEach(items) { row in
                        LargeFileRow(row: row, home: home, isSelected: selection.contains(row.id), isInspected: inspected == row.id,
                                     toggle: { toggle(row) }, inspect: { inspected = row.id })
                    }
                } header: {
                    header(group, items)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func header(_ group: FileGroup, _ items: [FileRow]) -> some View {
        let safe = items.filter { ImpactKnowledge.explain(path: $0.node.path, home: home)?.risk == .safe && canRemove($0) }
        return HStack(spacing: 8) {
            Image(systemName: group.symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(group.rawValue).font(.headline)
            Text("\(items.count) · \(Format.bytes(items.reduce(0) { $0 + $1.size }))").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if !safe.isEmpty {
                Button("Select \(safe.count) safe (\(Format.bytes(safe.reduce(0) { $0 + $1.size })))") {
                    selection.formUnion(safe.map(\.id))
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func canRemove(_ row: FileRow) -> Bool {
        PathGuard.canRemove(row.node.path, home: home, extraProtected: [Bundle.main.bundlePath])
    }

    private func toggle(_ row: FileRow) {
        if selection.contains(row.id) { selection.remove(row.id) } else if canRemove(row) { selection.insert(row.id) }
    }
}

private struct LargeFileRow: View {
    let row: FileRow
    let home: String
    let isSelected: Bool
    let isInspected: Bool
    let toggle: () -> Void
    let inspect: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        let explanation = ImpactKnowledge.explain(path: row.node.path, home: home)
        let canRemove = PathGuard.canRemove(row.node.path, home: home, extraProtected: [Bundle.main.bundlePath])
        HStack(alignment: .top, spacing: 10) {
            Toggle(row.name, isOn: Binding(get: { isSelected }, set: { _ in toggle() })).toggleStyle(.checkbox).labelsHidden()
                .disabled(!canRemove).help(canRemove ? "Select" : "Protected: MacSweep never removes this")
            FileIcon(path: row.node.path, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    if row.isHiddenPath { Pill(text: "Hidden") }
                    RiskPill(risk: explanation?.risk)
                }
                Text(explanation.map { "\($0.summary) If deleted: \($0.ifDeleted)" } ?? "Not something MacSweep recognises. Open its folder to check before deleting.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(Format.path(row.location)) · modified \(Format.relative(row.node.modified))")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Format.bytes(row.size)).font(.callout.weight(.semibold)).monospacedDigit()
            Button { FileActions.reveal(row.node.path) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Reveal in Finder").accessibilityLabel("Reveal \(row.name)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isInspected ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileActions.reveal(row.node.path) }
        .onTapGesture { inspect() }
    }
}

struct RiskPill: View {
    let risk: DeletionRisk?

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch risk {
        case .safe?: ("Safe to delete", "checkmark.circle.fill", .green)
        case .caution?: ("Think first", "exclamationmark.triangle.fill", .orange)
        case .keep?: ("Keep", "hand.raised.fill", .red)
        case nil: ("Unknown", "questionmark.circle", .secondary)
        }
        Label(text, systemImage: symbol).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1).background(color.opacity(0.12), in: Capsule())
    }
}

/// Lists exactly what each selected item is and what deleting it causes, before anything moves to the Trash.
struct TrashReviewSheet: View {
    let nodes: [FileNode]
    let home: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let risks = nodes.map { ImpactKnowledge.explain(path: $0.path, home: home)?.risk }
        let risky = risks.filter { $0 == .keep || $0 == nil }.count
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(nodes.count) item\(nodes.count == 1 ? "" : "s") to the Trash?").font(.title2.weight(.semibold))
            Text("\(Format.bytes(nodes.reduce(0) { $0 + $1.size })) · \(risks.filter { $0 == .safe }.count) safe · \(risks.filter { $0 == .caution }.count) think first · \(risky) keep or unknown. Everything goes to the Trash, so you can put it back until you empty it.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(nodes, id: \.path) { node in
                let explanation = ImpactKnowledge.explain(path: node.path, home: home)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(node.name).fontWeight(.medium).lineLimit(1)
                        RiskPill(risk: explanation?.risk)
                        Spacer()
                        Text(Format.bytes(node.size)).monospacedDigit()
                    }
                    Text("If deleted: " + (explanation?.ifDeleted ?? "Unknown. Check what uses it first."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 240)
            if risky > 0 {
                Label("\(risky) item\(risky == 1 ? " is" : "s are") marked Keep or Unknown. Deleting them may break an app or lose data.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
    }
}

import MacSweepCore
import SwiftUI

enum FileListKind: String, CaseIterable, Identifiable {
    case files = "Files"
    case folders = "Folders"

    var id: String { rawValue }
}

struct FileRow: Identifiable, Hashable {
    let node: FileNode
    let isHiddenPath: Bool

    var id: String { node.path }
    var name: String { node.name }
    var size: UInt64 { node.size }
    var modified: Date { node.modified ?? .distantPast }
    var location: String { node.parentPath }
    var kind: String { node.isDirectory ? "Folder" : (node.name as NSString).pathExtension.lowercased() }
}

struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var kind: FileListKind = .files
    @State private var hiddenOnly = false
    @State private var olderThanYear = false
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\FileRow.size, order: .reverse)]
    @State private var trashNodes: [FileNode]?
    /// Hidden until a file is clicked, so the list gets the full width.
    @State private var showsInspector = false
    @State private var inspectedPath: String?
    @State private var grouped = true
    @State private var reviewing: [FileNode]?

    private var inspected: FileNode? {
        guard let path = inspectedPath ?? (selection.count == 1 ? selection.first : nil) else { return nil }
        return app.disk.result?.root.node(at: path) ?? app.disk.result?.largeFiles.first { $0.path == path }
    }

    var body: some View {
        Group {
            if let result = app.disk.result {
                let rows = visibleRows(result)
                VStack(spacing: 0) {
                    summary(rows)
                    if rows.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else if grouped {
                        LargeFilesGroupedList(rows: rows, home: app.home, selection: $selection, inspected: $inspectedPath)
                    } else {
                        table(rows)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No scan yet", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Scan your disk to list the biggest files and folders, hidden ones included.")
                } actions: {
                    Button("Scan Home Folder") { app.disk.scan(root: app.disk.home); app.section = .storage }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Large & Hidden Files")
        .onChange(of: inspectedPath) { _, path in if path != nil { showsInspector = true } }
        .onChange(of: selection) { _, paths in if grouped == false, paths.count == 1 { showsInspector = true } }
        .searchable(text: $search, prompt: "Name or path")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $kind) {
                    ForEach(FileListKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Hidden only", systemImage: "eye.slash", isOn: $hiddenOnly)
                    .help("Only items inside dot-folders or flagged hidden")
                Toggle("Older than 1 year", systemImage: "clock.arrow.circlepath", isOn: $olderThanYear)
                Toggle("Group by kind", systemImage: "square.grid.3x1.below.line.grid.1x2", isOn: $grouped)
                    .help("Group files by what they are, or show one sortable table")
                Button("Move to Trash", systemImage: "trash") { reviewing = selectedNodes }
                    .disabled(selectedNodes.isEmpty)
                Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .inspector(isPresented: $showsInspector) {
            FileInspector(node: inspected, home: app.home) { trashNodes = [$0] }
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(item: Binding(get: { reviewing.map(ReviewBatch.init) }, set: { reviewing = $0?.nodes })) { batch in
            TrashReviewSheet(nodes: batch.nodes, home: app.home) {
                app.cleanup.remove(batch.nodes.map { CleanupTarget(path: $0.path, size: $0.size) }, mode: .trash)
                selection.removeAll()
            }
        }
        .trashConfirmation($trashNodes) { nodes in
            app.cleanup.remove(nodes.map { CleanupTarget(path: $0.path, size: $0.size) }, mode: .trash)
            selection.removeAll()
        }
    }

    private var selectedNodes: [FileNode] { selectedNodes(for: selection) }

    private func summary(_ rows: [FileRow]) -> some View {
        HStack {
            Text("\(rows.count) items · \(Format.bytes(rows.reduce(0) { $0 + $1.size }))")
            if !selection.isEmpty {
                let chosen = selectedNodes
                Text("· \(chosen.count) selected (\(Format.bytes(chosen.reduce(0) { $0 + $1.size })))").foregroundStyle(.secondary)
                Button("Review & Move to Trash…") { reviewing = chosen }.controlSize(.small).disabled(chosen.isEmpty)
                Button("Clear") { selection.removeAll() }.controlSize(.small)
            }
            Spacer()
            Text(kind == .files ? "Files over 10 MB" : "Folders over 1 MB").foregroundStyle(.secondary)
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func table(_ rows: [FileRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    FileIcon(path: row.node.path)
                    Text(row.name).lineLimit(1)
                    if row.isHiddenPath { Pill(text: "Hidden") }
                }
            }
            .width(min: 200, ideal: 300)
            TableColumn("If deleted") { row in
                RiskLabel(explanation: ImpactKnowledge.explain(path: row.node.path, home: app.home))
            }
            .width(min: 160, ideal: 280)
            TableColumn("Size", value: \.size) { row in
                Text(Format.bytes(row.size)).monospacedDigit().fontWeight(.medium)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Kind", value: \.kind) { row in Text(row.kind).foregroundStyle(.secondary) }
                .width(min: 50, ideal: 70)
            TableColumn("Modified", value: \.modified) { row in
                Text(Format.relative(row.node.modified)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Location", value: \.location) { row in
                Text(Format.path(row.location))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first {
                Button("Reveal in Finder") { FileActions.reveal(path) }
                Button("Open") { FileActions.open(path) }
                Button("Copy Path") { FileActions.copy(path) }
                Divider()
                Button("Move to Trash…") { trashNodes = selectedNodes(for: paths) }
                    .disabled(selectedNodes(for: paths).isEmpty)
            }
        } primaryAction: { paths in
            paths.first.map(FileActions.reveal)
        }
        .onDeleteCommand { trashNodes = selectedNodes }
    }

    private func selectedNodes(for paths: Set<String>) -> [FileNode] {
        visibleRows(app.disk.result).filter { paths.contains($0.id) }.map(\.node)
            .filter { PathGuard.canRemove($0.path, home: app.home, extraProtected: [Bundle.main.bundlePath]) }
    }

    private func visibleRows(_ result: ScanResult?) -> [FileRow] {
        guard let result else { return [] }
        let root = result.root.path
        let nodes: [FileNode]
        switch kind {
        case .files:
            nodes = result.largeFiles
        case .folders:
            var folders: [FileNode] = []
            result.root.walk { node in
                guard node.isDirectory else { return false }
                if node.path != root { folders.append(node) }
                return true
            }
            nodes = Array(folders.sorted { $0.size > $1.size }.prefix(1_000))
        }
        let cutoff = Date().addingTimeInterval(-365 * 86_400)
        let query = search.lowercased()
        return nodes
            .map { FileRow(node: $0, isHiddenPath: $0.isHidden || PathTools.hasHiddenComponent($0.path, below: root)) }
            .filter { !hiddenOnly || $0.isHiddenPath }
            .filter { !olderThanYear || ($0.node.modified.map { $0 < cutoff } ?? false) }
            .filter { query.isEmpty || $0.node.path.lowercased().contains(query) }
            .sorted(using: sortOrder)
    }
}

/// Wraps the nodes waiting for review so the sheet can be driven by an optional item.
private struct ReviewBatch: Identifiable {
    let nodes: [FileNode]
    var id: String { nodes.map(\.path).joined(separator: "|") }
}

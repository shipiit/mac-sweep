import MacSweepCore
import SwiftUI

/// The contents of a folder, biggest first. Every folder row opens the same list one level deeper,
/// so you can follow the space all the way down without leaving the page.
struct FolderDrillDown: View {
    let path: String
    let model: HiddenSpaceModel
    var depth = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let parts = model.folderParts[path] {
                if parts.isEmpty {
                    Text(depth == 0 ? "Nothing inside is over 10 MB, or macOS doesn't let apps read it." : "Nothing bigger than 10 MB inside.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let largest = max(parts.first?.size ?? 1, 1)
                ForEach(parts.prefix(25)) { part in DrillRow(part: part, fraction: Double(part.size) / Double(largest), model: model, depth: depth) }
                if parts.count > 25 { Text("…and \(parts.count - 25) smaller items").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Measuring \(Format.path(path))…").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .task { await model.loadParts(of: path) }
    }
}

private struct DrillRow: View {
    let part: FolderPart
    let fraction: Double
    let model: HiddenSpaceModel
    let depth: Int
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button { isOpen.toggle() } label: {
                    Image(systemName: part.isFolder ? (isOpen ? "chevron.down" : "chevron.right") : "doc").frame(width: 12)
                }
                .buttonStyle(.borderless).disabled(!part.isFolder)
                .accessibilityLabel(part.isFolder ? (isOpen ? "Close \(part.name)" : "Open \(part.name)") : "File")
                Text(part.name).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).frame(maxWidth: 320, alignment: .leading)
                if part.isRemovable { Pill(text: part.kind.rawValue, color: part.kind == .cache ? .green : .orange) }
                ProgressView(value: min(max(fraction, 0), 1)).frame(maxWidth: 140).accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(Format.bytes(part.size)).font(.caption.monospacedDigit())
                Button("Reveal", systemImage: "folder") { FileActions.reveal(part.path) }.labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
            }
            .contentShape(Rectangle())
            .onTapGesture { if part.isFolder { isOpen.toggle() } }
            // Five levels reach any file worth finding; deeper than that, Finder is the better tool.
            if isOpen && depth < 5 {
                FolderDrillDown(path: part.path, model: model, depth: depth + 1).padding(.leading, 20)
            } else if isOpen {
                Button("Open in Finder to go deeper") { FileActions.reveal(part.path) }.buttonStyle(.link).font(.caption).padding(.leading, 20)
            }
        }
    }
}

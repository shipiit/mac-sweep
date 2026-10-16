import MacSweepCore
import SwiftUI

struct DuplicateResults: View {
    let result: DuplicateScanResult
    let model: DuplicatesModel

    var body: some View {
        let chosen = result.groups.flatMap(\.files).filter { model.selected.contains($0.path) }
        VStack(alignment: .leading, spacing: 14) {
            StatStrip {
                StatTile(title: "Reclaimable", value: Format.bytes(result.reclaimable), detail: "if you keep one of each")
                StatTile(title: "Duplicates", value: "\(result.duplicateCount)", detail: "in \(result.groups.count) groups")
                StatTile(title: "Files checked", value: Format.count(result.filesScanned), detail: "\(result.hardLinksSkipped) hard links skipped")
            }
            if result.groups.isEmpty {
                Label("No duplicates found in these folders.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            } else {
                TrashBar(count: chosen.count, size: chosen.reduce(0) { $0 + $1.size }) { model.trashSelected() }
                ForEach(result.groups.prefix(200)) { group in
                    FileGroupCard(title: group.files.first.map { ($0.path as NSString).lastPathComponent } ?? "",
                                  subtitle: "\(group.files.count) copies · \(Format.bytes(group.size)) each",
                                  files: group.files, model: model)
                }
            }
        }
    }
}

struct PhotoResults: View {
    let result: SimilarPhotoResult
    let model: DuplicatesModel

    var body: some View {
        let chosen = result.clusters.flatMap(\.photos).filter { model.selected.contains($0.path) }
        VStack(alignment: .leading, spacing: 14) {
            StatStrip {
                StatTile(title: "Reclaimable", value: Format.bytes(result.clusters.reduce(0) { $0 + $1.reclaimable }), detail: "keeping the best of each")
                StatTile(title: "Similar sets", value: "\(result.clusters.count)", detail: "groups of look-alikes")
                StatTile(title: "Photos analysed", value: Format.count(result.imagesAnalysed), detail: result.wasCapped ? "capped at 5,000" : "all found")
            }
            if result.clusters.isEmpty {
                Label("No similar photos found.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            } else {
                TrashBar(count: chosen.count, size: chosen.reduce(0) { $0 + $1.size }) { model.trashSelected() }
                ForEach(result.clusters.prefix(150)) { cluster in
                    FileGroupCard(title: "\(cluster.photos.count) similar photos", subtitle: Format.bytes(cluster.reclaimable) + " reclaimable",
                                  files: cluster.photos, model: model, showsThumbnails: true)
                }
            }
        }
    }
}

/// One group: first file is the suggested keeper; checkboxes pick what goes to the Trash.
private struct FileGroupCard: View {
    let title: String
    let subtitle: String
    let files: [FileStat]
    let model: DuplicatesModel
    var showsThumbnails = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                ForEach(Array(files.enumerated()), id: \.element.path) { index, file in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(get: { model.selected.contains(file.path) }, set: { isOn in
                            if isOn { model.selected.insert(file.path) } else { model.selected.remove(file.path) }
                        })) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Remove \(file.path)")
                        if showsThumbnails { FileIcon(path: file.path, size: 40) } else { FileIcon(path: file.path) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Format.path(file.path)).lineLimit(1).truncationMode(.middle)
                            Text("Modified \(Format.relative(file.modified))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if index == 0 { Pill(text: "Suggested keep", color: .green) }
                        Button { FileActions.reveal(file.path) } label: { Image(systemName: "folder") }
                            .buttonStyle(.borderless).accessibilityLabel("Reveal in Finder")
                    }
                }
            }
        }
    }
}

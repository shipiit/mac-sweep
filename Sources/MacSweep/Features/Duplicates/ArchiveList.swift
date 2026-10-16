import MacSweepCore
import SwiftUI

struct ArchiveList: View {
    let candidates: [ArchiveCandidate]
    let model: DuplicatesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatStrip {
                StatTile(title: "Could free", value: Format.bytes(candidates.reduce(0) { $0 + $1.facts.size }), detail: "by offloading")
                StatTile(title: "Candidates", value: "\(candidates.count)", detail: "untouched for 6+ months")
                StatTile(title: "Build folders", value: Format.bytes(candidates.reduce(0) { $0 + $1.facts.buildFolderSize }), detail: "regenerable, inside them")
            }
            if candidates.isEmpty {
                Label("Nothing old and large enough to offload.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            }
            EqualHeightGrid(items: candidates, columns: 2) { candidate in ArchiveCard(candidate: candidate, model: model) }
        }
    }
}

private struct ArchiveCard: View {
    let candidate: ArchiveCandidate
    let model: DuplicatesModel
    @State private var confirmingTrash = false

    var body: some View {
        let facts = candidate.facts
        let verified = model.archived[candidate.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FileIcon(path: facts.path, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(facts.name).font(.headline).lineLimit(1)
                    Text(Format.path(facts.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Format.bytes(facts.size)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Text("Untouched for \(candidate.idleDays) days · \(Format.count(facts.fileCount)) files · zip ≈ \(Format.bytes(facts.estimatedArchiveSize))"
                 + (facts.markers.isEmpty ? "" : " · \(facts.markers.joined(separator: ", "))"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                if let verified {
                    Label("Verified at \(Format.path(verified.archivePath))", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green).lineLimit(1)
                    Spacer()
                    Button("Move Original to Trash") { confirmingTrash = true }
                } else if model.archivingPath == candidate.id {
                    ProgressView().controlSize(.small)
                    Text("Archiving and verifying…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Reveal") { FileActions.reveal(facts.path) }
                    Spacer()
                    Button("Archive to…") { model.archive(candidate) }.buttonStyle(.borderedProminent).disabled(model.archivingPath != nil)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .alert("Move \(facts.name) to the Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive) { model.trashOriginal(candidate) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The archive was verified. MacSweep re-checks that nothing changed since archiving before moving it.") }
    }
}

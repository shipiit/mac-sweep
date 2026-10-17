import MacSweepCore
import SwiftUI

struct QuarantineSection: View {
    let threats: ThreatCenter
    @State private var discarding: QuarantinedItem?
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel(padding: 22) {
                HStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 66, height: 66).background(accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(threats.quarantined.isEmpty ? "Quarantine is empty" : "\(threats.quarantined.count) item\(threats.quarantined.count == 1 ? "" : "s") in quarantine")
                            .font(.system(size: 26, weight: .bold))
                        Text("Files MacSweep isolates are moved out of your folders into a private quarantine and can't run. Nothing is deleted: restore anything you trust, or move it to the Trash.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { FileActions.reveal(QuarantineStore.standard.root) } label: { Label("Show in Finder", systemImage: "folder") }
                }
            }
            Text("How quarantine works").font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                HowItWorksStep(number: 1, symbol: "arrow.right.square", title: "Moved out of reach",
                               detail: "The file leaves Downloads (or wherever it was) for MacSweep's own folder in Application Support.")
                HowItWorksStep(number: 2, symbol: "hand.raised.slash", title: "Can't run",
                               detail: "Its permission to run as a program is removed, so double-clicking it does nothing.")
                HowItWorksStep(number: 3, symbol: "doc.text.magnifyingglass", title: "Everything is recorded",
                               detail: "Where it came from, where it was, why it was flagged and when.")
                HowItWorksStep(number: 4, symbol: "arrow.uturn.backward", title: "Your call",
                               detail: "Restore puts it back exactly where it was, with its permissions. Delete moves it to the Trash.")
            }
            .fixedSize(horizontal: false, vertical: true)
            if threats.quarantined.isEmpty {
                Panel {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(.green)
                        Text("Nothing has needed isolating").font(.headline)
                        Text("Quarantined files from scans and Download Protection will be listed here.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
            }
            ForEach(threats.quarantined) { item in row(item) }
        }
        .alert("Move \(discarding?.name ?? "") to the Trash?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
               presenting: discarding) { item in
            Button("Move to Trash", role: .destructive) { threats.discard(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("You can still recover it from the Trash until you empty it.") }
    }

    private func row(_ item: QuarantinedItem) -> some View {
        Panel(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.doc.fill").font(.title2).foregroundStyle(.red).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).fontWeight(.semibold)
                    ForEach(item.reasons, id: \.self) { Text("• \($0)").font(.callout).foregroundStyle(.secondary) }
                    Text("Was at \(Format.path(item.originalPath)) · quarantined \(Format.relative(item.date))" + (item.origin.map { " · from \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Restore") { threats.restore(item) }
                Button("Delete…") { discarding = item }.tint(.red)
            }
        }
    }
}

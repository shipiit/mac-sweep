import MacSweepCore
import SwiftUI

struct DuplicatesView: View {
    @State private var model = DuplicatesModel()
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Mode", selection: $model.mode) { ForEach(DuplicatesModel.Mode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 420)
                        .disabled(model.isWorking)
                    Spacer()
                    if hasResult {
                        Button(model.isWorking ? "Stop" : "Scan Again") { model.isWorking ? model.cancel() : model.scan() }
                    }
                }
                if let message = model.message {
                    Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                if model.isWorking { ScanProgressCard(progress: model.progress) { model.cancel() } }
                switch model.mode {
                case .exact:
                    if let result = model.duplicates { DuplicateResults(result: result, model: model) } else if !model.isWorking { intro }
                case .photos:
                    if let result = model.photos { PhotoResults(result: result, model: model) } else if !model.isWorking { intro }
                case .archive:
                    if let candidates = model.candidates { ArchiveList(candidates: candidates, model: model) } else if !model.isWorking { intro }
                }
            }
            .padding(20)
        }
        .navigationTitle("Duplicates & Archive")
    }

    private var hasResult: Bool {
        switch model.mode {
        case .exact: model.duplicates != nil
        case .photos: model.photos != nil
        case .archive: model.candidates != nil
        }
    }

    private var intro: some View {
        let (title, subtitle, symbol, bullets): (String, String, String, [(String, String, String)]) = switch model.mode {
        case .exact: ("Duplicate Finder", "Find identical files wasting space, then keep one copy of each.", "doc.on.doc",
                      [("number", "Byte-for-byte matches", "Size, then a quick fingerprint, then a full SHA-256: never a guess."),
                       ("lock.shield", "One copy always stays", "MacSweep refuses to remove every copy, and everything goes to the Trash.")])
        case .photos: ("Similar Photos", "Spot burst shots, edits and near-identical pictures.", "photo.on.rectangle.angled",
                       [("eye", "On-device image analysis", "Apple's Vision compares what photos look like; nothing leaves your Mac."),
                        ("hand.tap", "You choose", "The sharpest-looking original is suggested; you decide what goes.")])
        case .archive: ("Archive & Offload", "Move old projects to an external drive or iCloud and free the space.", "archivebox",
                        [("clock", "Untouched for 6 months", "Projects and big folders you haven't changed in a long time."),
                         ("checkmark.seal", "Verified before removal", "The zip is fully checked; only then can the original go to the Trash.")])
        }
        return ModuleIntro(title: title, subtitle: subtitle, symbol: symbol, tint: accent,
                           bullets: bullets.map { (symbol: $0.0, title: $0.1, detail: $0.2) },
                           actionTitle: "Scan", isWorking: model.isWorking) { model.scan() }
            .frame(minHeight: 460)
    }
}

private struct ScanProgressCard: View {
    let progress: FinderProgress.Snapshot?
    let onStop: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                if let fraction = progress?.fraction { ProgressView(value: fraction).frame(width: 220) } else { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress?.phase.rawValue ?? "Starting…").fontWeight(.medium)
                    Text("\(Format.count(progress?.filesSeen ?? 0)) files looked at").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop", action: onStop)
            }
        }
    }
}

/// Shared "N selected · size · Move to Trash" bar with the round action button.
struct TrashBar: View {
    let count: Int
    let size: UInt64
    let action: () -> Void
    @Environment(\.appAccent) private var accent
    @State private var confirming = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) selected").font(.headline)
                Text("\(Format.bytes(size)) will move to the Trash").foregroundStyle(.secondary)
            }
            Spacer()
            Button { confirming = true } label: {
                Text("Remove").font(.headline).foregroundStyle(.white).frame(width: 84, height: 84).background(accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .opacity(count == 0 ? 0.4 : 1)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .alert("Move \(count) files to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: { Text("At least one copy of every file is always kept. You can restore from the Trash.") }
    }
}

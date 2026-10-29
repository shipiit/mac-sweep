import MacSweepCore
import SwiftUI

struct TranscriptStorageCard: View {
    @Environment(AppModel.self) private var app
    @State private var days = 90
    @State private var targets: [CleanupTarget]?
    @State private var confirm = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Transcript storage", subtitle: "Old conversation logs from Claude Code and Codex")
                    Spacer()
                    Picker("Older than", selection: $days) {
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                    }
                    .fixedSize()
                }
                if let targets {
                    let size = targets.reduce(0) { $0 + $1.size }
                    HStack {
                        Text("\(targets.count) transcripts · \(Format.bytes(size))").font(.title3.weight(.semibold))
                        Text("Sessions you've named in AI Usage are always kept.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Move to Trash…") { confirm = true }.disabled(targets.isEmpty)
                    }
                    Label("You can no longer /resume these conversations or search their history. Usage totals already counted stay in MacSweep.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: days) {
            let days = days
            targets = await Task.detached(priority: .utility) { TranscriptCleanup.old(olderThanDays: days, keeping: Set(SessionNames.all().keys)) }.value
        }
        .confirmationDialog("Move \(targets?.count ?? 0) old transcripts to the Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let chosen = targets ?? []
                _ = Cleaner.remove(chosen, mode: .trash)
                targets = nil
                Task { await app.ai.refresh() }
                let days = days
                Task { targets = await Task.detached { TranscriptCleanup.old(olderThanDays: days, keeping: Set(SessionNames.all().keys)) }.value }
            }
        }
    }
}

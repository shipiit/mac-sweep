import MacSweepCore
import SwiftUI

/// What changed between the last two disk scans.
struct GrowthView: View {
    @Environment(AppModel.self) private var app
    @State private var report: ScanGrowthReport?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    ProgressView("Comparing scans…").frame(maxWidth: .infinity, minHeight: 300)
                } else if let report {
                    StatStrip {
                        StatTile(title: "Change", value: signed(report.totalDelta), detail: "since \(Format.relative(report.oldDate))",
                                 dot: report.totalDelta > 0 ? .orange : .green)
                        StatTile(title: "Grew", value: "\(report.grown.count)", detail: "folders and files")
                        StatTile(title: "Shrank", value: "\(report.shrunk.count)", detail: "folders and files")
                    }
                    list("Grew", report.grown)
                    list("Shrank", report.shrunk)
                    if !report.renamed.isEmpty { list("Moved or renamed", report.renamed) }
                } else {
                    ModuleIntro(title: "What Grew", subtitle: "Find out exactly which folders ate your space since the last scan.",
                                symbol: "chart.bar.doc.horizontal", tint: .orange,
                                bullets: [("arrow.up.right", "Biggest growers first", "Folders and files that changed by more than 50 MB."),
                                          ("clock.arrow.circlepath", "Compares two scans", app.disk.result == nil
                                              ? "Scan once now, and again later (nightly scans do this for you)."
                                              : "Your last scan was \(Format.relative(app.disk.result?.finishedAt)). Scan again to compare.")],
                                actionTitle: app.disk.isScanning ? "Scanning…" : "Scan Disk Now", isWorking: app.disk.isScanning) {
                        app.disk.scan()
                    }
                    .frame(minHeight: 460)
                }
            }
            .padding(20)
        }
        .navigationTitle("What Grew")
        .task(id: app.disk.result?.finishedAt) { await load() }
    }

    private func load() async {
        isLoading = true
        report = await Task.detached(priority: .utility) { () -> ScanGrowthReport? in
            let store = ScanStore.standard
            guard let new = store.load(), let old = store.loadPrevious() else { return nil }
            return ScanGrowth.compare(old: old, new: new)
        }.value
        isLoading = false
        MemoryRelief.release()
    }

    private func list(_ title: String, _ entries: [GrowthEntry]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if entries.isEmpty { Text("Nothing changed by more than 50 MB.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).lineLimit(1)
                            Text(Format.path(entry.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(signed(entry.delta)).monospacedDigit().fontWeight(.semibold)
                        Button { FileActions.reveal(entry.path) } label: { Image(systemName: "folder") }
                            .buttonStyle(.borderless).accessibilityLabel("Reveal \(entry.name)")
                    }
                }
            }
        }
    }

    private func signed(_ delta: Int64) -> String {
        (delta >= 0 ? "+" : "−") + Format.bytes(UInt64(delta.magnitude))
    }
}

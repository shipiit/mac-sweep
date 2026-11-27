import MacSweepCore
import SwiftUI

/// The space a home-folder scan can't see: apps, Homebrew, databases, simulators, temp files, swap and snapshots.
struct HiddenSpaceView: View {
    @State private var model = HiddenSpaceModel.shared
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatStrip {
                    StatTile(title: "Outside your home folder", value: Format.bytes(model.outsideHomeTotal), detail: "measured below")
                    StatTile(title: "Browser copies", value: Format.bytes(model.clonesSize), detail: "\(model.clones.count) leftover copies",
                             dot: model.clones.isEmpty ? nil : .orange)
                    StatTile(title: "Test databases", value: Format.bytes(model.testLeftovers.reduce(0) { $0 + $1.size }),
                             detail: "\(model.testLeftovers.count) not used by any project", dot: model.testLeftovers.isEmpty ? nil : .orange)
                    StatTile(title: "Free now", value: Format.bytes(UInt64(max(HiddenSpaceModel.freeBytes(), 0))))
                }
                if let result = model.result { ResultBanner(result: result) { model.result = nil } }
                if model.isLoading && !model.hasLoaded {
                    Card { HStack { ProgressView().controlSize(.small); Text("Measuring apps, Homebrew, databases and system files…").foregroundStyle(.secondary) } }
                } else {
                    breakdown
                    BrowserCopiesCard(model: model)
                    RuntimesCard(model: model)
                    DatabasesCard(model: model)
                    DataFoldersCard(folders: model.dataFolders)
                    HiddenFoldersCard(model: model)
                }
            }
            .padding(20)
        }
        .task { if !model.hasLoaded { await model.refresh() } }
        .toolbar {
            ToolbarItem {
                Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.disabled(model.isLoading)
            }
        }
    }

    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Where the rest of your disk goes",
                              subtitle: "Space & Junk scans your home folder. These live outside it, so they're measured here.")
                let largest = max(model.buckets.map(\.size).max() ?? 1, 1)
                ForEach(model.buckets.sorted { $0.size > $1.size }) { bucket in
                    BucketRow(bucket: bucket, fraction: Double(bucket.size) / Double(largest), tint: accent) { open(bucket.kind) }
                }
            }
        }
    }

    private func open(_ kind: SystemSpaceBucket.Kind) {
        switch kind {
        case .applications: app.section = .appFootprint
        case .homebrew: app.section = .developer
        case .updateSnapshots: FileActions.open(url: URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"))
        default: break
        }
    }
}

private struct BucketRow: View {
    let bucket: SystemSpaceBucket
    let fraction: Double
    let tint: Color
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bucket.kind.symbol).frame(width: 22).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bucket.kind.title).font(.callout.weight(.semibold))
                    Spacer()
                    Text(value).font(.callout.weight(.semibold).monospacedDigit())
                }
                ProgressView(value: min(max(fraction, 0), 1)).tint(tint).accessibilityHidden(true)
                Text(bucket.kind.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let link { Button(link, action: open).buttonStyle(.link).font(.caption) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var value: String {
        if bucket.kind == .updateSnapshots { return bucket.count == 0 ? "None" : "\(bucket.count ?? 0) snapshot\(bucket.count == 1 ? "" : "s")" }
        return Format.bytes(bucket.size)
    }

    private var link: String? {
        switch bucket.kind {
        case .applications: "Open App Footprint"
        case .homebrew: "Open Developer → Homebrew"
        case .updateSnapshots: (bucket.count ?? 0) > 0 ? "Open Software Update" : nil
        default: nil
        }
    }
}

private struct ResultBanner: View {
    let result: HiddenSpaceModel.ActionResult
    let dismiss: () -> Void

    var body: some View {
        let freed = result.freed > 0 ? "Free space went up by \(Format.bytes(UInt64(result.freed)))." : "Free space didn't change measurably yet."
        let problems = result.failures.isEmpty ? "" : " \(result.failures.count) couldn't be removed: " + result.failures.prefix(3).joined(separator: "; ")
        NoticeBanner(symbol: result.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                     title: result.title, message: freed + problems, tint: result.failures.isEmpty ? .green : .orange,
                     actionTitle: "Dismiss", action: dismiss)
    }
}

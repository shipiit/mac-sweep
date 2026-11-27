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
                hero
                StatStrip {
                    StatTile(title: "Reclaimable app data", value: Format.bytes(model.reclaimableAppData), detail: "caches & sandboxes",
                             dot: model.reclaimableAppData > 0 ? .green : nil, isLoading: !model.hasLoaded || model.isMeasuringFolders)
                    StatTile(title: "Unused databases", value: Format.bytes(unusedDatabases.reduce(0) { $0 + $1.size }),
                             detail: "\(unusedDatabases.count) no project names", dot: unusedDatabases.isEmpty ? nil : .orange, isLoading: !model.hasLoaded)
                    StatTile(title: "Stopped database servers", value: Format.bytes(stoppedFolders.reduce(0) { $0 + $1.size }),
                             detail: "\(stoppedFolders.count) data folder\(stoppedFolders.count == 1 ? "" : "s")", dot: stoppedFolders.isEmpty ? nil : .orange,
                             isLoading: !model.hasLoaded)
                    StatTile(title: "Browser copies", value: Format.bytes(model.clonesSize), detail: "\(model.clones.count) leftover",
                             dot: model.clones.isEmpty ? nil : .orange, isLoading: !model.hasLoaded)
                }
                if let result = model.result { ResultBanner(result: result) { model.result = nil } }
                if model.isLoading && !model.hasLoaded {
                    ForEach(0..<3, id: \.self) { _ in
                        Card { VStack(alignment: .leading, spacing: 12) { SkeletonBar(width: 220, height: 16); SkeletonBar(); SkeletonBar(width: 420) }.shimmering() }
                    }
                } else {
                    AppDataCard(model: model)
                    DatabasesCard(model: model)
                    DataFoldersCard(model: model)
                    if !model.clones.isEmpty { BrowserCopiesCard(model: model) }
                    if !model.runtimes.isEmpty { RuntimesCard(model: model) }
                    if model.clones.isEmpty && model.runtimes.isEmpty {
                        Card { Label("No leftover browser copies or simulator runtimes.", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                    }
                    breakdown
                    HiddenFoldersCard(model: model)
                }
            }
            .padding(20)
        }
        .task { if !model.hasLoaded { await model.refresh() } }
    }

    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Where the rest of your disk goes",
                              subtitle: "Space & Junk scans your home folder. These live outside it. Click any row to see what's inside, as deep as you like.")
                let largest = max(model.buckets.map(\.size).max() ?? 1, 1)
                ForEach(model.buckets.sorted { $0.size > $1.size }) { bucket in
                    BucketRow(bucket: bucket, fraction: Double(bucket.size) / Double(largest), tint: accent, model: model) { open(bucket.kind) }
                }
            }
        }
    }

    private var stoppedFolders: [DatabaseDataFolder] { model.dataFolders.filter { !$0.isRunning } }

    /// Everything on this page that can be removed, with the still-measuring parts counted as they arrive.
    private var reclaimable: UInt64 {
        model.reclaimableAppData + unusedDatabases.reduce(0) { $0 + $1.size } + stoppedFolders.reduce(0) { $0 + $1.size } + model.clonesSize
            + model.runtimes.reduce(0) { $0 + $1.size }
    }

    private var hero: some View {
        let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint]
        let buckets = model.buckets.filter { $0.kind != .updateSnapshots && $0.size > 0 }.sorted { $0.size > $1.size }
        return SummaryHero(
            symbol: "externaldrive.badge.questionmark", eyebrow: "You can get back up to", value: Format.bytes(reclaimable),
            caption: model.hasLoaded
                ? "of the \(Format.bytes(model.outsideHomeTotal)) outside your home folder and in hidden app data · \(Format.bytes(UInt64(max(HiddenSpaceModel.freeBytes(), 0)))) free now"
                : "Measuring apps, Homebrew, databases and system files…",
            isLoading: !model.hasLoaded,
            segments: buckets.enumerated().map { index, bucket in
                BarSegment(label: bucket.kind.title, value: Double(bucket.size), color: palette[index % palette.count], detail: Format.bytes(bucket.size))
            }
        ) {
            Button { Task { await model.refresh() } } label: { Label("Rescan", systemImage: "arrow.clockwise").frame(minWidth: 110) }
                .disabled(model.isLoading || model.isMeasuringFolders)
        }
    }

    private var unusedDatabases: [PostgresDatabase] { model.databases.filter { $0.kind == .unreferenced || $0.kind == .test } }

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
    let model: HiddenSpaceModel
    let open: () -> Void
    @State private var isOpen = false

    var body: some View {
        let roots = SystemSpace.roots(for: bucket.kind).filter { FileManager.default.fileExists(atPath: $0) }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bucket.kind.symbol).frame(width: 22).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Button { isOpen.toggle() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bucket.kind.title).font(.callout.weight(.semibold))
                            if !roots.isEmpty { Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(value).font(.callout.weight(.semibold).monospacedDigit())
                        }
                        ProgressView(value: min(max(fraction, 0), 1)).tint(tint).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(roots.isEmpty)
                .accessibilityLabel("\(bucket.kind.title), \(value)").accessibilityHint(roots.isEmpty ? "" : "Shows what's inside")
                Text(bucket.kind.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let link { Button(link, action: open).buttonStyle(.link).font(.caption) }
                if isOpen {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(roots, id: \.self) { root in
                            VStack(alignment: .leading, spacing: 2) {
                                if roots.count > 1 { Text(root).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                FolderDrillDown(path: root, model: model)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
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
        let problems = result.failures.isEmpty ? "" : "\(result.failures.count) couldn't be removed: " + result.failures.prefix(3).joined(separator: "; ")
        VStack(alignment: .trailing, spacing: 6) {
            NoticeBanner(symbol: result.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                         title: result.title, message: [result.freed > 0 || result.note == nil ? freed : "", result.note ?? "", problems].filter { !$0.isEmpty }.joined(separator: " "),
                         tint: result.failures.isEmpty ? .green : .orange, actionTitle: "Dismiss", action: dismiss)
            if let path = result.revealPath, result.note != nil { Button("Show Backups in Finder") { FileActions.reveal(path) }.buttonStyle(.link) }
        }
    }
}

import MacSweepCore
import SwiftUI

struct StorageView: View {
    @Environment(AppModel.self) private var app
    @State private var trashNodes: [FileNode]?
    @State private var selectedTile: TreemapTile?

    var body: some View {
        let disk = app.disk
        Group {
            if let result = disk.result {
                GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if !app.hasFullDiskAccess { FullDiskAccessBanner(onRecheck: app.refreshPermissions) }
                        if disk.isScanning { ScanProgressBar(disk: disk) }
                        StorageStats(disk: disk, cleanup: app.cleanup, result: result)
                        HStack(alignment: .top, spacing: 14) {
                            ExplorerCard(disk: disk, cleanup: app.cleanup, onTrash: { trashNodes = [$0] }, selected: $selectedTile)
                                .frame(minWidth: 520)
                            RecommendationsPanel(cleanup: app.cleanup, folder: selectedTile?.node ?? disk.focusNode)
                                .frame(width: 380)
                        }
                        // Map and panel fill whatever height the window has left below the stats.
                        .frame(height: max(600, proxy.size.height - (disk.isScanning ? 300 : 250)))
                    }
                    .padding(20)
                }
                }
            } else {
                ScanPlaceholder(disk: disk, hasFullDiskAccess: app.hasFullDiskAccess, onRecheck: app.refreshPermissions)
            }
        }
        .navigationTitle("Storage")
        .navigationSubtitle(subtitle)
        .toolbar { ScanToolbar(disk: disk) }
        .trashConfirmation($trashNodes) { nodes in
            app.cleanup.remove(nodes.map { CleanupTarget(path: $0.path, size: $0.size) }, mode: .trash)
        }
    }

    private var subtitle: String {
        guard let result = app.disk.result else { return "Not scanned yet" }
        return "\(Format.path(result.root.path)) · scanned \(Format.relative(result.finishedAt)) in \(Format.duration(result.duration))"
    }
}

/// The page's headline: what can go right now, the button that does it, and where the whole disk went.
struct StorageStats: View {
    @Environment(AppModel.self) private var app
    let disk: DiskModel
    let cleanup: CleanupModel
    let result: ScanResult
    @State private var showsConfirm = false

    var body: some View {
        // The live figure: the one saved with the scan goes stale within hours.
        let volume = app.monitor.volume ?? disk.volume
        let available = volume?.available ?? 0
        let used = volume?.used ?? 0
        let safe = cleanup.total(.safe), review = cleanup.total(.review)
        let unscanned = used > result.root.size ? used - result.root.size : 0
        let kept = result.root.size > safe + review ? result.root.size - safe - review : 0
        SummaryHero(
            symbol: "sparkles", eyebrow: safe > 0 ? "Safe to remove right now" : "Nothing safe to remove right now",
            value: Format.bytes(safe),
            caption: caption(available: available, total: volume?.total ?? 0), tint: .green,
            segments: [
                BarSegment(label: "Your files", value: Double(kept), color: .blue, detail: Format.bytes(kept)),
                BarSegment(label: "Safe to remove", value: Double(safe), color: .green, detail: Format.bytes(safe)),
                BarSegment(label: "Needs review", value: Double(review), color: .orange, detail: Format.bytes(review)),
                BarSegment(label: result.root.path == "/" ? "Purgeable & snapshots" : "System & apps", value: Double(unscanned), color: .purple, detail: Format.bytes(unscanned)),
                BarSegment(label: "Free", value: Double(available), color: .gray.opacity(0.35), detail: Format.bytes(available)),
            ]
        ) {
            Button {
                if !cleanup.hasSelection { cleanup.selectSafe() }
                showsConfirm = true
            } label: {
                Label(cleanup.hasSelection ? "Clean \(Format.bytes(cleanup.selectedSize))…" : "Clean Safe Items…", systemImage: "trash").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            .disabled((safe == 0 && !cleanup.hasSelection) || cleanup.isCleaning)
            .help("Review the list, then remove it. Nothing is deleted until you confirm.")
            Button { app.section = .hiddenSpace } label: {
                Label("What's in the other \(Format.bytes(unscanned))?", systemImage: "externaldrive.badge.questionmark").frame(minWidth: 150)
            }
            .help("Open Hidden Space: apps, databases, caches and system files outside your home folder")
        }
        .sheet(isPresented: $showsConfirm) { CleanConfirmSheet(cleanup: cleanup) }
    }

    private func caption(available: UInt64, total: UInt64) -> String {
        var parts = ["\(Format.bytes(available)) free of \(Format.bytes(total))"]
        if cleanup.selectedSize > 0 { parts.append("\(Format.bytes(available + cleanup.selectedSize)) after cleaning what's selected") }
        if result.restrictedCount > 0 { parts.append("\(result.restrictedCount) locked folders not scanned") }
        if let forecastText { parts.append(forecastText) }
        return parts.joined(separator: " · ")
    }
}

struct ScanToolbar: ToolbarContent {
    let disk: DiskModel
    @AppStorage("scanSchedule") private var schedule: ScanSchedule = .nightly

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if disk.isScanning {
                Button("Stop", systemImage: "stop.fill") { disk.cancel() }
                    .help("Stop scanning")
            } else {
                Menu {
                    Button("Home Folder") { disk.scan(root: disk.home) }
                    Button("Entire Disk (Macintosh HD)") { disk.scan(root: "/") }
                    Divider()
                    Button("Choose Folder…") { chooseFolder() }
                    Divider()
                    Picker("Automatic Scan", selection: $schedule) {
                        ForEach(ScanSchedule.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                } primaryAction: {
                    disk.scan()
                }
                .help("Rescan \(Format.path(disk.rootPath)) (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { disk.scan(root: url.path) }
    }
}

extension StorageStats {
    /// "Full in about 6 weeks at this rate", when free space has been shrinking.
    fileprivate var forecastText: String? {
        app.insights.storageForecast?.daysUntilFull.map { "Full \(StorageForecast.phrase(days: $0).replacingOccurrences(of: "in about ", with: "in ~"))" }
    }
}

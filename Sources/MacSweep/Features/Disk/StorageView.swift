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
                        .frame(height: max(600, proxy.size.height - (disk.isScanning ? 250 : 200)))
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

struct StorageStats: View {
    let disk: DiskModel
    let cleanup: CleanupModel
    let result: ScanResult

    var body: some View {
        let available = disk.volume?.available ?? 0
        let used = disk.volume?.used ?? 0
        let unscanned = used > result.root.size ? used - result.root.size : 0
        StatStrip {
            StatTile(title: "Free now", value: Format.bytes(available), detail: "of \(Format.bytes(disk.volume?.total ?? 0))")
            StatTile(
                title: "Free after cleanup",
                value: Format.bytes(available + cleanup.selectedSize),
                detail: cleanup.selectedSize > 0 ? "+" + Format.bytes(cleanup.selectedSize) : nil,
                detailColor: .green
            )
            StatTile(title: "Safe to remove", value: Format.bytes(cleanup.total(.safe)), detail: "\(cleanup.count(.safe)) groups", dot: .green)
            StatTile(title: "Needs review", value: Format.bytes(cleanup.total(.review)), detail: "\(cleanup.count(.review)) groups", dot: .orange)
            StatTile(
                title: result.restrictedCount > 0 ? "Not scanned · \(result.restrictedCount) locked" : "Not scanned",
                value: Format.bytes(unscanned),
                detail: result.root.path == "/" ? "purgeable & snapshots" : "system & apps"
            )
        }
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

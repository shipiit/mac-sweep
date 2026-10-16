import Foundation
import MacSweepCore
import Observation
import os

@MainActor
@Observable
final class DiskModel {
    enum Status: Equatable {
        case idle
        case scanning
        case finished
        case cancelled
    }

    let home: String
    private(set) var rootPath: String
    private(set) var status: Status = .idle
    private(set) var result: ScanResult? {
        didSet { onResultChange?(result) }
    }
    private(set) var progress: ScanProgress.Snapshot?
    private(set) var volume: VolumeStats?
    private(set) var scanStartedAt: Date?
    /// True while the running scan is a low-priority scheduled one.
    private(set) var isBackgroundScan = false
    var focusPath: String

    @ObservationIgnored var onResultChange: ((ScanResult?) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the latest scan; results or cancellations from older scans are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "disk")
    @ObservationIgnored private let store = ScanStore.standard

    init(home: String) {
        self.home = home
        self.rootPath = home
        self.focusPath = home
        refreshVolume()
        loadSaved()
    }

    /// Shows the previous scan immediately; a fresh scan replaces it when it finishes.
    private func loadSaved() {
        let store = store
        Task { [weak self] in
            let saved = await Task.detached(priority: .userInitiated) { store.load() }.value
            guard let self, let saved, self.result == nil, self.status != .scanning else { return }
            self.rootPath = saved.root.path
            self.focusPath = saved.root.path
            self.result = saved
            self.status = .finished
            MemoryRelief.release()
        }
    }

    private func persist() {
        guard let result else { return }
        let store = store
        Task.detached(priority: .background) {
            try? store.save(result)
        }
    }

    var isScanning: Bool { status == .scanning }

    /// Rough rescan progress, using the previous scan's size as the expected total.
    var estimatedFraction: Double? {
        guard let expected = result?.root.size, expected > 0, let bytes = progress?.bytes else { return nil }
        return min(Double(bytes) / Double(expected), 0.99)
    }

    var focusNode: FileNode? {
        result.flatMap { $0.root.node(at: focusPath) ?? $0.root }
    }

    /// Path components from the scan root down to the focused directory.
    var breadcrumbs: [(name: String, path: String)] {
        guard let root = result?.root else { return [] }
        var crumbs = [(name: root.path == home ? "~ Home" : root.name, path: root.path)]
        guard focusPath != root.path, PathTools.isDescendant(focusPath, of: root.path) else { return crumbs }
        var current = root.path
        for component in focusPath.dropFirst(root.path == "/" ? 1 : root.path.count + 1).split(separator: "/") {
            current = current == "/" ? "/" + component : current + "/" + component
            crumbs.append((String(component), current))
        }
        return crumbs
    }

    /// - Parameter isBackground: scheduled scans run at the lowest priority so they're never noticed.
    func scan(root: String? = nil, isBackground: Bool = false) {
        task?.cancel()
        let target = root ?? rootPath
        rootPath = target
        status = .scanning
        isBackgroundScan = isBackground
        scanStartedAt = Date()
        let progress = ScanProgress()
        self.progress = progress.snapshot()
        generation += 1
        let current = generation
        log.info("scan requested for \(target, privacy: .public)")

        // Below user-initiated so the UI and other apps stay responsive, but not so low that a busy
        // Mac starves the scan entirely.
        task = Task(priority: isBackground ? .background : .medium) { [weak self] in
            let poller = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.progress = progress.snapshot()
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            var options = ScanOptions.forRoot(target)
            if isBackground { options.maxConcurrentWalkers = 2 }
            let result = await DiskScanner.scan(root: target, options: options, progress: progress)
            poller.cancel()
            guard let self, self.generation == current else { return }
            if Task.isCancelled {
                self.status = .cancelled
                return
            }
            self.result = result
            self.focusPath = target
            self.status = .finished
            self.refreshVolume()
            self.persist()
            MemoryRelief.release()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        status = result == nil ? .idle : .cancelled
    }

    func open(_ path: String) {
        guard let node = result?.root.node(at: path), node.isDirectory else { return }
        focusPath = path
    }

    func goUp() {
        guard let root = result?.root, focusPath != root.path else { return }
        focusPath = (focusPath as NSString).deletingLastPathComponent
    }

    /// Reflects removals in the tree without rescanning the whole disk.
    func apply(removed paths: Set<String>) {
        guard let current = result, !paths.isEmpty else { return }
        result = current.removing(paths)
        if result?.root.node(at: focusPath) == nil { focusPath = current.root.path }
        refreshVolume()
        persist()
    }

    func refreshVolume() {
        volume = VolumeStats.forPath(home)
    }
}

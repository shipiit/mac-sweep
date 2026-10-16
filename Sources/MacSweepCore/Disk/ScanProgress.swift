import Foundation

/// Thread-safe progress counters shared by the scanner's parallel workers and polled by the UI.
public final class ScanProgress: @unchecked Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var files: Int
        public var bytes: UInt64
        public var currentPath: String
    }

    private let lock = NSLock()
    private var snapshotValue = Snapshot(files: 0, bytes: 0, currentPath: "")

    public init() {}

    public func snapshot() -> Snapshot {
        lock.withLock { snapshotValue }
    }

    func add(files: Int, bytes: UInt64, currentPath: String) {
        lock.withLock {
            snapshotValue.files += files
            snapshotValue.bytes += bytes
            snapshotValue.currentPath = currentPath
        }
    }
}

public struct ScanOptions: Sendable {
    /// Entries smaller than this are folded into an aggregate tile instead of getting their own node.
    public var minNodeSize: UInt64 = 1 << 20
    /// Files at least this big are collected for the Large Files list.
    public var largeFileThreshold: UInt64 = 10 << 20
    public var maxLargeFiles = 5_000
    /// Absolute paths never descended into (e.g. firmlinked volumes that would double-count).
    public var excludedPaths: Set<String> = []
    /// How many directory levels below each top-level entry are fanned out as separate parallel jobs.
    /// One giant folder (usually ~/Library) otherwise pins the whole scan to a single core.
    public var splitDepth = 2
    /// Directory walkers allowed to run at once. Half the cores keeps the Mac smooth during a scan.
    public var maxConcurrentWalkers = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

    public init() {}

    public static func forRoot(_ root: String) -> ScanOptions {
        var options = ScanOptions()
        if root == "/" {
            options.excludedPaths = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/cores"]
        }
        return options
    }
}

public struct ScanResult: Sendable, Codable {
    public let root: FileNode
    public let largeFiles: [FileNode]
    public let restrictedCount: Int
    public let duration: TimeInterval
    public let finishedAt: Date

    public init(root: FileNode, largeFiles: [FileNode], restrictedCount: Int, duration: TimeInterval, finishedAt: Date) {
        self.root = root
        self.largeFiles = largeFiles
        self.restrictedCount = restrictedCount
        self.duration = duration
        self.finishedAt = finishedAt
    }

    public func removing(_ paths: Set<String>) -> ScanResult {
        ScanResult(
            root: root.removing(paths),
            largeFiles: largeFiles.filter { file in
                !paths.contains(file.path) && !paths.contains { PathTools.isDescendant(file.path, of: $0) }
            },
            restrictedCount: restrictedCount,
            duration: duration,
            finishedAt: finishedAt
        )
    }
}

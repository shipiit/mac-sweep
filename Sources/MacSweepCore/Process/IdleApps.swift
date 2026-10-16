import Foundation

public struct RunningAppSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let bundlePath: String?
    public let launchDate: Date?
    /// Last time this app was in front, if seen while MacSweep was running.
    public let lastActive: Date?
    public let isFrontmost: Bool

    public init(pid: Int32, bundleID: String, name: String, bundlePath: String?, launchDate: Date?, lastActive: Date?, isFrontmost: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.bundlePath = bundlePath
        self.launchDate = launchDate
        self.lastActive = lastActive
        self.isFrontmost = isFrontmost
    }
}

public struct IdleApp: Identifiable, Sendable, Equatable {
    public let app: RunningAppSnapshot
    /// Memory of the app plus all its helper processes (renderers, GPU, plug-ins).
    public let memory: UInt64
    public let processCount: Int
    public let idleSince: Date
    /// True when idleness is a lower bound: the app hasn't been used since MacSweep started watching.
    public let isAtLeast: Bool

    public var id: Int32 { app.pid }
}

public enum IdleApps {
    /// Apps that must never be suggested: quitting them breaks the desktop or MacSweep itself.
    public static let neverSuggest: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.loginwindow", "com.apple.notificationcenterui", "com.rahulraj.macsweep",
    ]

    /// - Parameters:
    ///   - watchingSince: when MacSweep started observing app switches; apps unseen since then are idle at least that long.
    ///   - threshold: how long an app must be unused to be suggested.
    ///   - minimumMemory: ignore apps too small to be worth quitting.
    public static func find(
        apps: [RunningAppSnapshot],
        processes: [ProcessSnapshot],
        watchingSince: Date,
        now: Date = Date(),
        threshold: TimeInterval = 2 * 3_600,
        minimumMemory: UInt64 = 100 << 20,
        excluded: Set<String> = []
    ) -> [IdleApp] {
        apps.compactMap { app -> IdleApp? in
            guard !app.isFrontmost, !neverSuggest.contains(app.bundleID), !excluded.contains(app.bundleID) else { return nil }
            let idleSince: Date
            let isAtLeast: Bool
            if let last = app.lastActive {
                idleSince = last
                isAtLeast = false
            } else {
                idleSince = max(app.launchDate ?? watchingSince, watchingSince)
                isAtLeast = (app.launchDate ?? .distantPast) < watchingSince
            }
            guard now.timeIntervalSince(idleSince) >= threshold else { return nil }
            let family = processesBelonging(to: app, in: processes)
            let memory = family.reduce(0) { $0 + ($1.memory ?? 0) }
            guard memory >= minimumMemory else { return nil }
            return IdleApp(app: app, memory: memory, processCount: family.count, idleSince: idleSince, isAtLeast: isAtLeast)
        }
        .sorted { $0.memory > $1.memory }
    }

    /// The app's own process plus helpers that live inside its bundle or descend from it.
    public static func processesBelonging(to app: RunningAppSnapshot, in processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
        let bundlePrefix = app.bundlePath.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var family = Set<Int32>([app.pid])
        var changed = true
        while changed {
            changed = false
            for process in processes where !family.contains(process.pid) {
                let insideBundle = bundlePrefix.map { process.path?.hasPrefix($0) == true } ?? false
                if insideBundle || (process.ppid > 1 && family.contains(process.ppid)) {
                    family.insert(process.pid)
                    changed = true
                }
            }
        }
        return processes.filter { family.contains($0.pid) }
    }
}

import Foundation

public struct ProcessGroup: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A regular app plus its helpers (renderers, GPU, plug-ins).
        case app(bundleID: String, pid: Int32)
        /// Background processes sharing an executable name ("Python × 8").
        case named
    }

    public let name: String
    public let kind: Kind
    public let iconPath: String?
    public let processes: [ProcessSnapshot]

    public var id: String {
        switch kind {
        case .app(let bundleID, _): "app:" + bundleID
        case .named: "name:" + name
        }
    }

    public var memory: UInt64 { processes.reduce(0) { $0 + ($1.memory ?? 0) } }
    public var threads: Int { processes.reduce(0) { $0 + ($1.threads ?? 0) } }
}

public enum ProcessGroups {
    /// Every process lands in exactly one group: first the app families (largest apps claim first),
    /// then remaining processes grouped by name. Sorted by memory.
    public static func group(processes: [ProcessSnapshot], apps: [RunningAppSnapshot]) -> [ProcessGroup] {
        var claimed = Set<Int32>()
        var groups: [ProcessGroup] = []
        for app in apps {
            let family = IdleApps.processesBelonging(to: app, in: processes).filter { !claimed.contains($0.pid) }
            guard !family.isEmpty else { continue }
            family.forEach { claimed.insert($0.pid) }
            groups.append(ProcessGroup(name: app.name, kind: .app(bundleID: app.bundleID, pid: app.pid),
                                       iconPath: app.bundlePath, processes: family.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }))
        }
        let rest = Dictionary(grouping: processes.filter { !claimed.contains($0.pid) }, by: \.name)
        for (name, members) in rest {
            groups.append(ProcessGroup(name: name, kind: .named, iconPath: members.first?.path,
                                       processes: members.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }))
        }
        return groups.sorted { $0.memory > $1.memory }
    }
}

import Foundation
import os

/// Moves selected copies to the Trash while guaranteeing that every group keeps at least one file.
/// The invariant lives here, not in the UI: a selection covering a whole group is refused for that group.
public enum KeepOneTrash {
    private static let log = Logger(subsystem: Log.subsystem, category: "duplicates")

    public struct Plan: Sendable, Equatable {
        public let targets: [FileStat]
        /// Groups where every copy was selected; nothing in them is touched.
        public let blockedGroups: Int

        public var reclaimable: UInt64 { targets.reduce(0) { $0 + $1.size } }
    }

    public struct Outcome: Sendable, Equatable {
        public let results: [RemovalResult]
        public let blockedGroups: Int

        public var removedPaths: Set<String> { Set(results.filter(\.succeeded).map(\.path)) }
        public var freed: UInt64 { results.filter(\.succeeded).reduce(0) { $0 + $1.size } }
    }

    public static func plan(groups: [[FileStat]], selected: Set<String>) -> Plan {
        var targets: [FileStat] = []
        var blocked = 0
        for group in groups {
            let chosen = group.filter { selected.contains($0.path) }
            guard !chosen.isEmpty else { continue }
            if chosen.count >= group.count {
                blocked += 1
            } else {
                targets += chosen
            }
        }
        return Plan(targets: targets, blockedGroups: blocked)
    }

    /// Re-plans from scratch (a caller cannot pass a plan that breaks the invariant), re-checks each
    /// file against the scan, then trashes through `Cleaner`, which applies `PathGuard`.
    public static func trash(
        groups: [[FileStat]], selected: Set<String>, home: String = NSHomeDirectory(),
        extraProtected: [String] = [Bundle.main.bundlePath]
    ) -> Outcome {
        var results: [RemovalResult] = []
        var blocked = 0
        for group in groups {
            let plan = plan(groups: [group], selected: selected)
            blocked += plan.blockedGroups
            guard !plan.targets.isEmpty else { continue }
            let kept = group.filter { !selected.contains($0.path) }
            guard kept.contains(where: { isStillThere($0) }) else {
                log.warning("refused trashing duplicates: no kept copy is still intact")
                results += plan.targets.map { RemovalResult(path: $0.path, size: $0.size, outcome: .refused("The copy you're keeping has changed or moved. Scan again.")) }
                continue
            }
            for target in plan.targets {
                guard isStillThere(target) else {
                    results.append(RemovalResult(path: target.path, size: target.size, outcome: .refused("Changed since the scan.")))
                    continue
                }
                results += Cleaner.remove([CleanupTarget(path: target.path, size: target.size)], mode: .trash,
                                          home: home, extraProtected: extraProtected)
            }
        }
        return Outcome(results: results, blockedGroups: blocked)
    }

    private static func isStillThere(_ file: FileStat) -> Bool {
        FileStat.current(file.path).map { file.isUnchanged(comparedTo: $0) } ?? false
    }
}

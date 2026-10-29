import Foundation

/// What a footprint action removes. The app bundle is never part of either.
public enum FootprintAction: String, Sendable, Hashable {
    /// Cache locations only; settings, sign-ins and documents stay.
    case clearCache
    /// Everything except the app bundle, as if the app was freshly installed.
    case reset
}

public struct FootprintPlanRefusal: Sendable, Equatable {
    public let path: String
    public let reason: String
}

public struct AppFootprintPlan: Sendable, Equatable, Identifiable {
    public let app: InstalledApp
    public let action: FootprintAction
    /// Paths to move to the Trash. Nested items are folded into their ancestor so nothing is trashed twice.
    public let targets: [CleanupTarget]
    /// Categories each target belongs to, for the confirmation sheet.
    public let categories: [String: FootprintCategory]
    /// Paths PathGuard refused; listed so the user sees they stay.
    public let refused: [FootprintPlanRefusal]

    public var id: String { app.id + "|" + action.rawValue }
    public var total: UInt64 { targets.reduce(0) { $0 + $1.size } }
    public var isEmpty: Bool { targets.isEmpty }
}

public enum AppFootprintPlanner {
    /// Builds the removal plan for an action. Refuses Apple apps and the excluded IDs (MacSweep itself).
    /// Whether the app is running is checked by the caller, which owns NSWorkspace.
    public static func plan(
        _ footprint: AppFootprint,
        action: FootprintAction,
        home: String,
        excludedBundleIDs: Set<String> = [],
        extraProtected: [String] = []
    ) -> Result<AppFootprintPlan, FootprintRefusal> {
        if let refusal = AppFootprintLocator.refusal(bundleID: footprint.app.bundleID, excluded: excludedBundleIDs) {
            return .failure(refusal)
        }
        let selected = footprint.items.filter { item in
            guard item.category != .bundle, item.path != footprint.app.path,
                  !PathTools.isDescendant(item.path, of: footprint.app.path) else { return false }
            return action == .reset || item.category.isCache
        }
        var allowed: [FootprintItem] = []
        var refused: [FootprintPlanRefusal] = []
        for item in selected {
            if let reason = PathGuard.reason(item.path, home: home, extraProtected: extraProtected) {
                refused.append(FootprintPlanRefusal(path: item.path, reason: reason))
            } else {
                allowed.append(item)
            }
        }
        let folded = fold(allowed)
        return .success(AppFootprintPlan(
            app: footprint.app,
            action: action,
            targets: folded.map { CleanupTarget(path: $0.path, size: $0.size) },
            categories: Dictionary(folded.map { ($0.path, $0.category) }, uniquingKeysWith: { first, _ in first }),
            refused: refused.sorted { $0.path < $1.path }
        ))
    }

    /// Drops items nested inside another selected item and adds their size to the ancestor,
    /// since trashing the ancestor already removes them. Largest first.
    static func fold(_ items: [FootprintItem]) -> [FootprintItem] {
        let roots = items.filter { item in
            !items.contains { $0.path != item.path && PathTools.isDescendant(item.path, of: $0.path) }
        }
        return roots.map { root in
            let nested = items.filter { $0.path == root.path || PathTools.isDescendant($0.path, of: root.path) }
            let size = nested.reduce(UInt64(0)) { $0 + $1.size }
            return FootprintItem(path: root.path, category: root.category, size: size)
        }
        .sorted { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }
    }
}

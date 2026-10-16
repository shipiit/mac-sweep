import Foundation
import os

public enum RemovalMode: String, Sendable, CaseIterable {
    /// Recoverable from the Trash. Space is freed only once the Trash is emptied.
    case trash
    /// Frees space immediately. Not recoverable.
    case delete
}

public struct RemovalResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case removed
        case refused(String)
        case failed(String)
    }

    public let path: String
    public let size: UInt64
    public let outcome: Outcome

    public var succeeded: Bool { outcome == .removed }
}

public enum Cleaner {
    private static let log = Logger(subsystem: Log.subsystem, category: "cleaner")

    public static func remove(
        _ targets: [CleanupTarget],
        mode: RemovalMode,
        home: String = NSHomeDirectory(),
        extraProtected: [String] = [Bundle.main.bundlePath]
    ) -> [RemovalResult] {
        let fileManager = FileManager.default
        let trash = home + "/.Trash"
        return targets.map { target in
            if let reason = PathGuard.reason(target.path, home: home, extraProtected: extraProtected) {
                log.warning("refused removal of \(target.path, privacy: .private): \(reason, privacy: .public)")
                return RemovalResult(path: target.path, size: target.size, outcome: .refused(reason))
            }
            let url = URL(fileURLWithPath: target.path)
            do {
                // Anything already in the Trash can only be removed for real.
                if mode == .delete || PathTools.isDescendant(target.path, of: trash) {
                    try fileManager.removeItem(at: url)
                } else {
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                }
                log.info("removed \(target.path, privacy: .private) (\(target.size) bytes, mode \(mode.rawValue, privacy: .public))")
                return RemovalResult(path: target.path, size: target.size, outcome: .removed)
            } catch {
                log.error("failed to remove \(target.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return RemovalResult(path: target.path, size: target.size, outcome: .failed(error.localizedDescription))
            }
        }
    }
}

import Foundation

/// Decides which user-picked folders a duplicate, photo or archive scan may look inside.
/// Only folders in the home folder qualify, never the home folder itself, ~/Library, or
/// anything PathGuard protects (keys, credentials, mail).
public enum ScanRoots {
    public struct Resolution: Sendable, Equatable {
        public let accepted: [String]
        public let rejected: [Rejection]
    }

    public struct Rejection: Sendable, Equatable {
        public let path: String
        public let reason: String
    }

    public static func defaults(home: String) -> [String] {
        ["Downloads", "Documents", "Desktop", "Pictures"].map { home + "/" + $0 }
    }

    public static func resolve(_ paths: [String], home: String) -> Resolution {
        var accepted: [String] = []
        var rejected: [Rejection] = []
        for raw in paths {
            let path = URL(fileURLWithPath: PathTools.expand(raw, home: home)).resolvingSymlinksInPath().path
            if let reason = reason(path, home: home) {
                rejected.append(Rejection(path: raw, reason: reason))
            } else if !accepted.contains(path) {
                accepted.append(path)
            }
        }
        // A folder inside another chosen folder would be walked twice.
        let outermost = accepted.filter { path in !accepted.contains { PathTools.isDescendant(path, of: $0) } }
        return Resolution(accepted: outermost, rejected: rejected)
    }

    static func reason(_ path: String, home: String) -> String? {
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return "Not an absolute path." }
        guard PathTools.isDescendant(path, of: home) else { return "Only folders inside your home folder can be scanned." }
        if path == home + "/Library" || PathTools.isDescendant(path, of: home + "/Library") {
            return "The Library folder holds app data, not your files."
        }
        if PathGuard.protectedSubtrees(home: home).contains(where: { path == $0 || PathTools.isDescendant(path, of: $0) }) {
            return "Contains keys, credentials or system state."
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Folder not found."
        }
        return nil
    }
}

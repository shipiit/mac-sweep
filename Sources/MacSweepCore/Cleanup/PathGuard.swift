import Foundation

/// Last line of defence before anything is trashed or deleted. Default-deny: only paths inside
/// home, /Applications or /Users/Shared are eligible, and well-known roots are never touched.
public enum PathGuard {
    public static func canRemove(_ rawPath: String, home: String, extraProtected: [String] = []) -> Bool {
        reason(rawPath, home: home, extraProtected: extraProtected) == nil
    }

    /// Returns why a path is refused, or nil when it may be removed.
    public static func reason(_ rawPath: String, home: String, extraProtected: [String] = []) -> String? {
        guard rawPath.hasPrefix("/") else { return "Not an absolute path." }
        let path = (rawPath as NSString).standardizingPath
        guard !path.split(separator: "/").contains("..") else { return "Path contains '..'." }

        let allowedRoots = [home, "/Applications", "/Users/Shared"]
        guard allowedRoots.contains(where: { PathTools.isDescendant(path, of: $0) }) else {
            return "Outside your home folder and Applications."
        }

        let exact = Set(protectedExact(home: home))
        if exact.contains(path) { return "This is a system or standard folder." }

        let subtrees = protectedSubtrees(home: home) + extraProtected
        if subtrees.contains(where: { path == $0 || PathTools.isDescendant(path, of: $0) }) {
            return "Contains keys, credentials or system state."
        }
        // An uninstalled app's own preferences file may go; Apple's never.
        if path.hasPrefix(home + "/Library/Preferences/com.apple.") || path.hasPrefix(home + "/Library/Preferences/.") {
            return "macOS system preferences."
        }
        return nil
    }

    static func protectedExact(home: String) -> [String] {
        let homeChildren = [
            "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications",
            "Library", ".Trash", ".config", ".local", ".cache",
            "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Containers",
            "Library/Group Containers", "Library/Mobile Documents", "Library/CloudStorage", "Library/Developer",
            "Library/Android", "Library/LaunchAgents", "Library/Fonts", "Library/Preferences",
        ].map { home + "/" + $0 }
        return [home, "/Applications", "/Users/Shared"] + homeChildren
    }

    static func protectedSubtrees(home: String) -> [String] {
        [
            ".ssh", ".gnupg", ".aws", ".kube", ".docker/config.json", ".netrc", ".config/gh",
            "Library/Keychains", "Library/Preferences/ByHost", "Library/Mail", "Library/Messages",
            "Library/Application Support/com.apple.TCC", "Library/Application Support/AddressBook",
            "Library/Application Support/MobileSync", "Library/Accounts", "Library/Cookies",
        ].map { home + "/" + $0 } + ["/Applications/Utilities", "/Applications/Safari.app"]
    }
}

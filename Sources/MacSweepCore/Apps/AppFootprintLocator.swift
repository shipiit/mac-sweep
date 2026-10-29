import Foundation

/// A per-app location under ~/Library that exists on disk.
public struct FootprintLocation: Sendable, Hashable {
    public let path: String
    public let category: FootprintCategory

    public init(path: String, category: FootprintCategory) {
        self.path = path
        self.category = category
    }
}

public enum FootprintRefusal: Error, Sendable, Equatable {
    case appleApp
    case macSweepItself
    case invalidBundleID

    public var message: String {
        switch self {
        case .appleApp: "Apple apps are part of macOS and can't be reset here."
        case .macSweepItself: "MacSweep can't reset itself."
        case .invalidBundleID: "This app has no usable bundle identifier."
        }
    }
}

/// Matches an app's bundle ID and name to the folders it keeps under ~/Library.
public enum AppFootprintLocator {
    /// Apple apps and the running MacSweep are never measured for reset or touched.
    public static func refusal(bundleID: String, excluded: Set<String> = []) -> FootprintRefusal? {
        let lower = bundleID.lowercased()
        guard isSafeComponent(bundleID), lower.contains(".") else { return .invalidBundleID }
        if lower.hasPrefix("com.apple.") { return .appleApp }
        if excluded.contains(where: { $0.lowercased() == lower }) { return .macSweepItself }
        return nil
    }

    /// Every candidate path for the app, existing or not. Name-based paths need a name of 3+ characters.
    public static func candidates(bundleID: String, name: String, home: String) -> [FootprintLocation] {
        guard refusal(bundleID: bundleID) == nil else { return [] }
        let library = home + "/Library"
        let container = "\(library)/Containers/\(bundleID)"
        var byID: [(String, FootprintCategory)] = [
            ("\(library)/Caches/\(bundleID)", .caches),
            ("\(container)/Data/Library/Caches", .caches),
            ("\(library)/HTTPStorages/\(bundleID)", .caches),
            ("\(library)/HTTPStorages/\(bundleID).binarycookies", .caches),
            ("\(library)/Application Support/\(bundleID)", .applicationSupport),
            (container, .containers),
            ("\(library)/Preferences/\(bundleID).plist", .preferences),
            ("\(library)/Logs/\(bundleID)", .logs),
            ("\(library)/Saved Application State/\(bundleID).savedState", .savedState),
            ("\(library)/WebKit/\(bundleID)", .webKit),
        ]
        if usableName(name) {
            byID += [
                ("\(library)/Caches/\(name)", .caches),
                ("\(library)/Application Support/\(name)", .applicationSupport),
                ("\(library)/Logs/\(name)", .logs),
            ]
        }
        return byID.map { FootprintLocation(path: $0.0, category: $0.1) }
    }

    /// Group containers shared by the app: `<TEAMID>.<bundleID>[.suffix]` or `group.<bundleID>[.suffix]`.
    /// A bare team prefix alone never matches, so sibling apps from the same vendor are left alone.
    public static func isGroupContainer(_ entry: String, of bundleID: String) -> Bool {
        let lowerEntry = entry.lowercased()
        let id = bundleID.lowercased()
        var remainder = lowerEntry
        if remainder.hasPrefix("group.") {
            remainder = String(remainder.dropFirst("group.".count))
        } else if let dot = remainder.firstIndex(of: "."), isTeamPrefix(entry[entry.startIndex..<dot]) {
            remainder = String(remainder[remainder.index(after: dot)...])
        }
        return remainder == id || remainder.hasPrefix(id + ".")
    }

    /// Existing locations for the app, including matching group containers.
    public static func locate(bundleID: String, name: String, home: String) -> [FootprintLocation] {
        guard refusal(bundleID: bundleID) == nil else { return [] }
        let fm = FileManager.default
        var found = candidates(bundleID: bundleID, name: name, home: home).filter { fm.fileExists(atPath: $0.path) }
        let groups = home + "/Library/Group Containers"
        for entry in (try? fm.contentsOfDirectory(atPath: groups)) ?? [] where isGroupContainer(entry, of: bundleID) {
            found.append(FootprintLocation(path: groups + "/" + entry, category: .containers))
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.path).inserted }
    }

    /// Apple team IDs are 10 upper-case letters or digits, e.g. `UBF8T346G9`.
    static func isTeamPrefix(_ text: Substring) -> Bool {
        text.count == 10 && text.allSatisfy { ($0.isUppercase && $0.isASCII) || $0.isASCII && $0.isNumber }
    }

    static func usableName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 3 && isSafeComponent(name)
    }

    /// A single path component: no separators, no traversal.
    static func isSafeComponent(_ text: String) -> Bool {
        !text.isEmpty && !text.contains("/") && text != "." && text != ".." && !text.hasPrefix(".")
    }
}

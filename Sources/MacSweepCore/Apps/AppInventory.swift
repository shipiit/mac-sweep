import Foundation

public struct InstalledApp: Identifiable, Sendable, Equatable {
    public let name: String
    public let bundleID: String
    public let version: String
    public let path: String
    public let isAppStore: Bool
    public var size: UInt64?
    public var lastUsed: Date?

    public var id: String { path }

    public init(name: String, bundleID: String, version: String, path: String, isAppStore: Bool, size: UInt64? = nil, lastUsed: Date? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.path = path
        self.isAppStore = isAppStore
        self.size = size
        self.lastUsed = lastUsed
    }
}

/// Lists user-removable applications. System apps live in /System/Applications and are never listed.
public enum AppInventory {
    public static func roots(home: String) -> [String] {
        ["/Applications", home + "/Applications"]
    }

    public static func scan(home: String = NSHomeDirectory(), measure: Bool = true) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in roots(home: home) {
            for path in appBundles(in: root) {
                // Skips Safari and other system apps that only appear in /Applications.
                guard PathGuard.canRemove(path, home: home), let app = describe(path: path) else { continue }
                var entry = app
                if measure { entry.size = DiskScanner.measure(path) }
                entry.lastUsed = lastUsedDate(path)
                apps.append(entry)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles at the top level and one folder deep (e.g. /Applications/Utilities-style vendor folders).
    static func appBundles(in root: String) -> [String] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        var result: [String] = []
        for entry in entries {
            let path = root + "/" + entry
            if entry.hasSuffix(".app") {
                result.append(path)
            } else if DiskScanner.plainDirectoryStat(path) != nil {
                let nested = (try? fm.contentsOfDirectory(atPath: path)) ?? []
                result += nested.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
            }
        }
        return result
    }

    /// Every bundle ID that counts as "installed" for leftover detection: scanned apps, apps Spotlight
    /// knows about anywhere on disk, and anything running right now. Over-inclusive on purpose.
    public static func knownBundleIDs(scanned: [InstalledApp], running: [String]) async -> Set<String> {
        var ids = Set(scanned.map(\.bundleID)).union(running)
        if let result = try? await Shell.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"]) {
            for path in result.stdout.split(whereSeparator: \.isNewline) {
                if let info = NSDictionary(contentsOfFile: String(path) + "/Contents/Info.plist"),
                   let id = info["CFBundleIdentifier"] as? String {
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    public static func describe(path: String) -> InstalledApp? {
        guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return InstalledApp(
            name: name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            path: path,
            isAppStore: FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt")
        )
    }

    static func lastUsedDate(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

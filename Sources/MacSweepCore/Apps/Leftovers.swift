import Foundation

/// Finds the files an app scatters around ~/Library, so uninstalling removes everything.
public enum Leftovers {
    /// Candidate locations for an app's support files. Only existing ones are returned by `find`.
    public static func candidates(bundleID: String, name: String, home: String) -> [String] {
        let library = home + "/Library"
        var paths = [
            "\(library)/Application Support/\(bundleID)",
            "\(library)/Application Support/\(name)",
            "\(library)/Caches/\(bundleID)",
            "\(library)/Caches/\(name)",
            "\(library)/Preferences/\(bundleID).plist",
            "\(library)/Containers/\(bundleID)",
            "\(library)/Saved Application State/\(bundleID).savedState",
            "\(library)/HTTPStorages/\(bundleID)",
            "\(library)/HTTPStorages/\(bundleID).binarycookies",
            "\(library)/WebKit/\(bundleID)",
            "\(library)/Logs/\(name)",
            "\(library)/Logs/\(bundleID)",
            "\(library)/Application Scripts/\(bundleID)",
        ]
        if name.count < 3 { paths.removeAll { $0.hasSuffix("/" + name) } }
        return paths
    }

    public static func find(for app: InstalledApp, home: String = NSHomeDirectory()) -> [CleanupTarget] {
        let fm = FileManager.default
        var found = candidates(bundleID: app.bundleID, name: app.name, home: home).filter { fm.fileExists(atPath: $0) }
        found += matching(in: home + "/Library/Group Containers") { $0.hasSuffix("." + app.bundleID) || $0 == app.bundleID }
        found += matching(in: home + "/Library/LaunchAgents") { $0.hasPrefix(app.bundleID) && $0.hasSuffix(".plist") }
        return Array(Set(found)).sorted().map { CleanupTarget(path: $0, size: DiskScanner.measure($0) ?? 0) }
    }

    /// Support folders named after a bundle ID that no installed app owns (app already deleted).
    public static func orphans(installedBundleIDs: Set<String>, home: String = NSHomeDirectory(), now: Date = Date()) -> [CleanupTarget] {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 86_400)
        let library = home + "/Library"
        let folders = ["Application Support", "Caches", "Containers", "Saved Application State", "HTTPStorages", "WebKit"]
        var results: [CleanupTarget] = []
        for folder in folders {
            let dir = library + "/" + folder
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let id = entry.replacingOccurrences(of: ".savedState", with: "").replacingOccurrences(of: ".binarycookies", with: "")
                guard isOrphan(id, installed: installedBundleIDs) else { continue }
                let path = dir + "/" + entry
                // Recently touched means something (often a CLI tool with no .app) still uses it.
                let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                guard let modified, modified < cutoff else { continue }
                results.append(CleanupTarget(path: path, size: DiskScanner.measure(path) ?? 0, modified: modified))
            }
        }
        return results.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    /// Conservative: only reverse-DNS IDs, never Apple's, and never anything sharing a vendor
    /// prefix with an installed app (helpers and agents often use sibling IDs).
    static let idleDays = 30

    /// Command-line tools and frameworks keep data under bundle-style IDs without having an .app.
    static let toolMarkers = [".cli", "swiftpm", "python", "playwright", "turborepo", "wasilibs", "nodejs", "homebrew", "docker", "xcode"]

    static func isOrphan(_ id: String, installed: Set<String>) -> Bool {
        if toolMarkers.contains(where: { id.lowercased().contains($0) }) { return false }
        let parts = id.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "net", "io", "app", "dev", "co"].contains(parts[0].lowercased()) else { return false }
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple") { return false }
        let vendor = parts.prefix(2).joined(separator: ".").lowercased()
        return !installed.contains { $0.lowercased() == lower || $0.lowercased().hasPrefix(vendor + ".") }
    }

    private static func matching(in dir: String, _ predicate: (String) -> Bool) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter(predicate).map { dir + "/" + $0 }
    }
}

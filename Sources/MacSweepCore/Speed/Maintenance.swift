import Foundation

/// One-click upkeep jobs. Every command is a fixed constant: no user input is ever interpolated.
public enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case flushDNS
    case rebuildLaunchServices
    case reindexSpotlight
    case thinSnapshots
    case verifyDisk
    case clearFontCaches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flushDNS: "Flush DNS cache"
        case .rebuildLaunchServices: "Rebuild Launch Services"
        case .reindexSpotlight: "Reindex Spotlight"
        case .thinSnapshots: "Thin Time Machine snapshots"
        case .verifyDisk: "Verify startup disk"
        case .clearFontCaches: "Clear font caches"
        }
    }

    public var detail: String {
        switch self {
        case .flushDNS: "Fixes websites that won't load or point to an old address."
        case .rebuildLaunchServices: "Fixes duplicate apps in “Open With” and wrong default apps."
        case .reindexSpotlight: "Fixes search that misses files. Re-indexing runs in the background for a while."
        case .thinSnapshots: "Deletes local Time Machine restore points stored on this Mac to free “purgeable” space. Backups on your Time Machine drive are not affected."
        case .verifyDisk: "Checks the file system for errors (read-only)."
        case .clearFontCaches: "Fixes garbled or missing fonts. Takes effect after you log out."
        }
    }

    public var symbol: String {
        switch self {
        case .flushDNS: "network"
        case .rebuildLaunchServices: "square.grid.3x3"
        case .reindexSpotlight: "magnifyingglass"
        case .thinSnapshots: "clock.arrow.circlepath"
        case .verifyDisk: "internaldrive"
        case .clearFontCaches: "textformat"
        }
    }

    public var requiresAdmin: Bool {
        switch self {
        case .flushDNS, .reindexSpotlight, .thinSnapshots: true
        case .rebuildLaunchServices, .verifyDisk, .clearFontCaches: false
        }
    }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Shell command for admin tasks (run through the macOS password prompt).
    public var adminCommand: String? {
        switch self {
        case .flushDNS: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        case .reindexSpotlight: "/usr/bin/mdutil -E /"
        case .thinSnapshots: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
        default: nil
        }
    }

    /// Executable and arguments for tasks that run as you.
    public var userCommand: (String, [String])? {
        switch self {
        case .rebuildLaunchServices: (Self.lsregister, ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
        case .verifyDisk: ("/usr/sbin/diskutil", ["verifyVolume", "/"])
        case .clearFontCaches: ("/usr/bin/atsutil", ["databases", "-removeUser"])
        default: nil
        }
    }

    public func run() async throws -> String {
        if let command = adminCommand {
            return try await AdminRunner.runFixed(command)
        }
        guard let (executable, arguments) = userCommand else { return "" }
        let result = try await Shell.run(executable, arguments)
        if result.status != 0 {
            throw AdminRunner.AdminError.failed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }
}

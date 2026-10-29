import Foundation

public enum Permissions {
    public static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )

    public static let loginItemsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )

    /// Locations macOS only lets apps with Full Disk Access read. TCC.db alone is not enough:
    /// macOS 27 refuses it even with Full Disk Access granted.
    public static func protectedProbes(home: String) -> [String] {
        ["/Library/Safari", "/Library/Mail", "/Library/Messages", "/Library/Containers/com.apple.Safari",
         "/Library/Application Support/com.apple.TCC/TCC.db"].map { home + $0 }
    }

    public static func hasFullDiskAccess(home: String = NSHomeDirectory(), canRead: (String) -> Bool = isReadable) -> Bool {
        protectedProbes(home: home).contains(where: canRead)
    }

    public static func isReadable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue { return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }
}

public struct VolumeStats: Sendable, Equatable {
    public let total: UInt64
    public let available: UInt64

    public var used: UInt64 { total > available ? total - available : 0 }

    public init(total: UInt64, available: UInt64) {
        self.total = total
        self.available = available
    }

    /// Uses the "important usage" figure, which counts purgeable space the way Finder does.
    public static func forPath(_ path: String) -> VolumeStats? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeStats(total: UInt64(max(total, 0)), available: UInt64(max(available, 0)))
    }
}

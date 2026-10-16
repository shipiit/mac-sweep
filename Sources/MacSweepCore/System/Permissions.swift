import Foundation

public enum Permissions {
    public static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )

    public static let loginItemsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )

    /// TCC.db is only openable with Full Disk Access, so a successful open is a reliable probe.
    public static func hasFullDiskAccess(home: String = NSHomeDirectory()) -> Bool {
        let probe = home + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: probe) else { return false }
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

import Foundation

public enum StoreStatus: Sendable, Equatable {
    case listed
    /// Google took it down from the Chrome Web Store (frequently for malware or policy abuse).
    case removedFromStore
    case policyViolation
    case unknown
}

public struct ExtensionState: Sendable, Equatable {
    public var installed: Date?
    public var updated: Date?
    public var enabled = true
    public var storeStatus: StoreStatus = .unknown
    public var lastActivity: Date?

    public init(installed: Date? = nil, updated: Date? = nil, enabled: Bool = true, storeStatus: StoreStatus = .unknown, lastActivity: Date? = nil) {
        self.installed = installed
        self.updated = updated
        self.enabled = enabled
        self.storeStatus = storeStatus
        self.lastActivity = lastActivity
    }
}

/// Reads Chromium's per-profile extension records (Preferences / Secure Preferences). Read-only:
/// MacSweep never writes these files, because they're integrity-protected and tampering resets them.
public enum ChromiumExtensionState {
    public static func read(profileDir: String) -> [String: ExtensionState] {
        var states: [String: ExtensionState] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = FileManager.default.contents(atPath: profileDir + "/" + file) else { continue }
            states.merge(parse(data)) { _, new in new }
        }
        for id in states.keys { states[id]?.lastActivity = lastActivity(id: id, profileDir: profileDir) }
        return states
    }

    public static func parse(_ data: Data) -> [String: ExtensionState] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = (json["extensions"] as? [String: Any])?["settings"] as? [String: [String: Any]]
        else { return [:] }
        var result: [String: ExtensionState] = [:]
        for (id, entry) in settings {
            var state = ExtensionState()
            state.installed = chromeTime(entry["first_install_time"] ?? entry["install_time"])
            state.updated = chromeTime(entry["last_update_time"])
            if let reasons = entry["disable_reasons"] as? [Any] {
                state.enabled = reasons.isEmpty
            } else if let reasons = entry["disable_reasons"] as? Int {
                state.enabled = reasons == 0
            } else if let flag = entry["state"] as? Int {
                state.enabled = flag == 1
            }
            if let info = entry["cws-info"] as? [String: Any] {
                if (info["violation-type"] as? Int ?? 0) != 0 {
                    state.storeStatus = .policyViolation
                } else if info["is-live"] as? Bool == false {
                    state.storeStatus = .removedFromStore
                } else {
                    state.storeStatus = .listed
                }
            }
            result[id] = state
        }
        return result
    }

    /// Chromium stores times as microseconds since 1601-01-01 (Windows epoch), as strings or numbers.
    static func chromeTime(_ value: Any?) -> Date? {
        let micros: Double?
        switch value {
        case let string as String: micros = Double(string)
        case let number as NSNumber: micros = number.doubleValue
        default: micros = nil
        }
        guard let micros, micros > 0 else { return nil }
        return Date(timeIntervalSince1970: micros / 1_000_000 - 11_644_473_600)
    }

    /// The last time the extension wrote its own storage: a good proxy for "last used".
    static func lastActivity(id: String, profileDir: String) -> Date? {
        let candidates = [
            "Local Extension Settings/\(id)", "Sync Extension Settings/\(id)",
            "IndexedDB/chrome-extension_\(id)_0.indexeddb.leveldb", "Storage/ext/\(id)",
        ]
        return candidates.compactMap { relative in
            (try? FileManager.default.attributesOfItem(atPath: profileDir + "/" + relative))?[.modificationDate] as? Date
        }.max()
    }
}

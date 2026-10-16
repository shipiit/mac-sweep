import Foundation

public enum AppCategory: Hashable, Sendable {
    case all
    /// Not opened for 90+ days, or never recorded by Spotlight.
    case unused
    /// 500 MB or more.
    case large
    case appStore
    case other
    case vendor(String)
}

public enum AppCategories {
    public static let unusedDays = 90
    public static let largeBytes: UInt64 = 500 << 20

    static let knownVendors: [String: String] = [
        "apple": "Apple", "google": "Google", "microsoft": "Microsoft", "adobe": "Adobe", "jetbrains": "JetBrains",
        "anthropic": "Anthropic", "openai": "OpenAI", "macpaw": "MacPaw", "tinyspeck": "Slack", "spotify": "Spotify",
        "mozilla": "Mozilla", "brave": "Brave", "whatsapp": "WhatsApp", "signal": "Signal", "zoom": "Zoom",
        "docker": "Docker", "figma": "Figma", "notion": "Notion", "electron": "Electron apps", "todesktop": "ToDesktop",
    ]

    /// Vendor name from a reverse-DNS bundle ID (`com.google.Chrome` → "Google").
    public static func vendor(for bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return "Other" }
        let key = parts[1].lowercased()
        if let known = knownVendors[key] { return known }
        return key.count <= 2 ? "Other" : key.prefix(1).uppercased() + key.dropFirst()
    }

    public static func matches(_ app: InstalledApp, _ category: AppCategory, now: Date = Date()) -> Bool {
        switch category {
        case .all: return true
        case .unused:
            guard let last = app.lastUsed else { return true }
            return now.timeIntervalSince(last) >= Double(unusedDays) * 86_400
        case .large: return (app.size ?? 0) >= largeBytes
        case .appStore: return app.isAppStore
        case .other: return !app.isAppStore
        case .vendor(let name): return vendor(for: app.bundleID) == name
        }
    }

    /// Vendors with at least one app, most apps first.
    public static func vendors(_ apps: [InstalledApp]) -> [(name: String, count: Int)] {
        Dictionary(grouping: apps) { vendor(for: $0.bundleID) }
            .map { ($0.key, $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
}

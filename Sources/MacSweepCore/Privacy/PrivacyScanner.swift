import Foundation

public struct PrivacyItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case history = "Browsing history"
        case cookies = "Cookies"
        case cache = "Cache"
        case sessions = "Open tabs & sessions"
        case recents = "Recent items"
    }

    public let app: String
    public let kind: Kind
    public let paths: [String]
    public let size: UInt64
    /// Bundle ID that must not be running while the item is cleared.
    public let bundleID: String?

    public var id: String { app + "/" + kind.rawValue }

    public var consequence: String {
        switch kind {
        case .history: "Visited sites disappear from history and address-bar suggestions."
        case .cookies: "You'll be signed out of websites."
        case .cache: "Pages load a little slower the first time."
        case .sessions: "Open tabs from the last session can't be restored."
        case .recents: "Recent files and apps lists are emptied."
        }
    }
}

/// Finds privacy-sensitive traces. Passwords, autofill and bookmarks are never offered for removal.
public enum PrivacyScanner {
    struct Browser {
        let name: String
        let bundleID: String
        let root: String
        let cache: String
    }

    static let chromium: [Browser] = [
        Browser(name: "Chrome", bundleID: "com.google.Chrome", root: "Library/Application Support/Google/Chrome", cache: "Library/Caches/Google/Chrome"),
        Browser(name: "Brave", bundleID: "com.brave.Browser", root: "Library/Application Support/BraveSoftware/Brave-Browser", cache: "Library/Caches/BraveSoftware/Brave-Browser"),
        Browser(name: "Edge", bundleID: "com.microsoft.edgemac", root: "Library/Application Support/Microsoft Edge", cache: "Library/Caches/Microsoft Edge"),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", root: "Library/Application Support/Arc/User Data", cache: "Library/Caches/Arc"),
    ]

    static let historyFiles = ["History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts"]
    static let cookieFiles = ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"]
    static let sessionFiles = ["Sessions", "Current Session", "Current Tabs", "Last Session", "Last Tabs"]

    public static func scan(home: String = NSHomeDirectory()) -> [PrivacyItem] {
        let fm = FileManager.default
        var items: [PrivacyItem] = []
        func add(_ app: String, _ kind: PrivacyItem.Kind, _ paths: [String], _ bundleID: String?) {
            let existing = paths.filter { fm.fileExists(atPath: $0) }
            guard !existing.isEmpty else { return }
            let size = existing.reduce(UInt64(0)) { $0 + (DiskScanner.measure($1) ?? 0) }
            items.append(PrivacyItem(app: app, kind: kind, paths: existing, size: size, bundleID: bundleID))
        }

        for browser in chromium {
            let root = home + "/" + browser.root
            let profiles = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            guard !profiles.isEmpty else { continue }
            let inProfiles = { (files: [String]) in profiles.flatMap { profile in files.map { root + "/" + profile + "/" + $0 } } }
            add(browser.name, .history, inProfiles(historyFiles), browser.bundleID)
            add(browser.name, .cookies, inProfiles(cookieFiles), browser.bundleID)
            add(browser.name, .sessions, inProfiles(sessionFiles), browser.bundleID)
            add(browser.name, .cache, [home + "/" + browser.cache], browser.bundleID)
        }

        let firefoxRoot = home + "/Library/Application Support/Firefox/Profiles"
        let firefoxProfiles = ((try? fm.contentsOfDirectory(atPath: firefoxRoot)) ?? []).map { firefoxRoot + "/" + $0 }
        if !firefoxProfiles.isEmpty {
            // places.sqlite also holds bookmarks, so Firefox history is left to Firefox itself.
            add("Firefox", .cookies, firefoxProfiles.flatMap { [$0 + "/cookies.sqlite", $0 + "/cookies.sqlite-wal"] }, "org.mozilla.firefox")
            add("Firefox", .sessions, firefoxProfiles.map { $0 + "/sessionstore-backups" }, "org.mozilla.firefox")
            add("Firefox", .cache, [home + "/Library/Caches/Firefox"], "org.mozilla.firefox")
        }

        add("Safari", .history, [home + "/Library/Safari/History.db", home + "/Library/Safari/History.db-wal", home + "/Library/Safari/History.db-shm"], "com.apple.Safari")
        add("Safari", .cache, [home + "/Library/Caches/com.apple.Safari"], "com.apple.Safari")
        add("macOS", .recents, recentItemFiles(home: home), nil)
        return items
    }

    static func recentItemFiles(home: String) -> [String] {
        let dir = home + "/Library/Application Support/com.apple.sharedfilelist"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return entries.filter { $0.hasPrefix("com.apple.LSSharedFileList.Recent") }.map { dir + "/" + $0 }
    }
}

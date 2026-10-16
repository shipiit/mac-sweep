import Foundation

public enum ExtensionCapability: String, Sendable, CaseIterable {
    case allSites = "All websites"
    case cookies = "Cookies"
    case network = "Network requests"
    case proxy = "Routes your traffic"
    case debugger = "Debugger"
    case manageExtensions = "Other extensions"
    case nativeApp = "Apps on your Mac"
    case history = "History"
    case downloads = "Downloads"
    case clipboard = "Clipboard"
    case tabs = "Tabs"

    public var explanation: String {
        switch self {
        case .allSites: "Can read and change everything on every website you visit, including what you type."
        case .cookies: "Can read the cookies that keep you signed in."
        case .network: "Can see (and possibly block or change) network requests."
        case .proxy: "Can send all your browsing through its own servers."
        case .debugger: "Full control of pages through the browser debugger."
        case .manageExtensions: "Can install, disable or uninstall other extensions."
        case .nativeApp: "Can talk to a program installed on your Mac."
        case .history: "Can read your browsing history."
        case .downloads: "Can start and manage downloads."
        case .clipboard: "Can read what you copy."
        case .tabs: "Can see the titles and addresses of your open tabs."
        }
    }

    static func from(_ permissions: [String]) -> [ExtensionCapability] {
        let set = Set(permissions)
        var result: [ExtensionCapability] = []
        let broad = permissions.contains { $0 == "<all_urls>" || $0.hasPrefix("*://*/") || $0 == "http://*/*" || $0 == "https://*/*" }
        if broad { result.append(.allSites) }
        if set.contains("cookies") { result.append(.cookies) }
        if !set.isDisjoint(with: ["webRequest", "webRequestBlocking", "declarativeNetRequest", "declarativeNetRequestWithHostAccess"]) { result.append(.network) }
        if set.contains("proxy") { result.append(.proxy) }
        if set.contains("debugger") { result.append(.debugger) }
        if set.contains("management") { result.append(.manageExtensions) }
        if set.contains("nativeMessaging") { result.append(.nativeApp) }
        if set.contains("history") { result.append(.history) }
        if set.contains("downloads") { result.append(.downloads) }
        if set.contains("clipboardRead") { result.append(.clipboard) }
        if set.contains("tabs") { result.append(.tabs) }
        return result
    }
}

public enum ExtensionRisk: Int, Sendable, Comparable, CaseIterable {
    case low = 0, medium = 1, high = 2

    public var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct BrowserExtension: Identifiable, Sendable, Equatable {
    public let browser: String
    public let profile: String
    public let extensionID: String
    public let name: String
    public let version: String
    public let permissions: [String]
    public let path: String
    public let iconPath: String?
    /// Installed from the browser's official store (vs. sideloaded / developer mode).
    public let fromStore: Bool
    public var state = ExtensionState()

    public var id: String { browser + "/" + profile + "/" + extensionID }

    public init(browser: String, profile: String, extensionID: String, name: String, version: String, permissions: [String],
                path: String, iconPath: String? = nil, fromStore: Bool = true) {
        self.browser = browser
        self.profile = profile
        self.extensionID = extensionID
        self.name = name
        self.version = version
        self.permissions = permissions
        self.path = path
        self.iconPath = iconPath
        self.fromStore = fromStore
    }

    public var capabilities: [ExtensionCapability] { ExtensionCapability.from(permissions) }

    public var risk: ExtensionRisk { riskAssessment.risk }
    public var riskReasons: [String] { riskAssessment.reasons }

    /// High: can reroute traffic, debug pages, control other extensions, or is sideloaded with full site access.
    /// Medium: can read every site or your cookies. Low: everything narrower.
    var riskAssessment: (risk: ExtensionRisk, reasons: [String]) {
        let caps = Set(capabilities)
        var reasons: [String] = []
        if caps.contains(.proxy) { reasons.append("Can route all your traffic through its servers") }
        if caps.contains(.debugger) { reasons.append("Has debugger access to every page") }
        if caps.contains(.manageExtensions) { reasons.append("Can control other extensions") }
        if !fromStore, caps.contains(.allSites) { reasons.append("Not installed from the official store") }
        if state.storeStatus == .removedFromStore { reasons.append("Removed from the Chrome Web Store (often for malware or abuse)") }
        if state.storeStatus == .policyViolation { reasons.append("Flagged by Google for a policy violation") }
        if !reasons.isEmpty { return (.high, reasons) }
        if caps.contains(.allSites) { reasons.append("Can read and change all websites") }
        if caps.contains(.cookies) { reasons.append("Can read sign-in cookies") }
        return (reasons.isEmpty ? .low : .medium, reasons)
    }

    /// The browser's own extensions page at this extension, where it can be removed safely.
    public var managePage: (bundleID: String, url: String)? {
        switch browser {
        case "Chrome": ("com.google.Chrome", "chrome://extensions/?id=\(extensionID)")
        case "Brave": ("com.brave.Browser", "brave://extensions/?id=\(extensionID)")
        case "Edge": ("com.microsoft.edgemac", "edge://extensions/?id=\(extensionID)")
        case "Arc": ("company.thebrowser.Browser", "arc://extensions/?id=\(extensionID)")
        case "Vivaldi": ("com.vivaldi.Vivaldi", "vivaldi://extensions/?id=\(extensionID)")
        case "Firefox": ("org.mozilla.firefox", "about:addons")
        default: nil
        }
    }

    /// Kept for score/summary counts.
    public var isHighAccess: Bool { risk == .high }

    public var storeURL: URL? {
        switch browser {
        case "Chrome", "Brave", "Arc", "Vivaldi": URL(string: "https://chromewebstore.google.com/detail/\(extensionID)")
        case "Edge": URL(string: "https://microsoftedge.microsoft.com/addons/detail/\(extensionID)")
        case "Firefox": URL(string: "https://addons.mozilla.org/firefox/addon/\(extensionID)")
        default: nil
        }
    }
}

public enum BrowserExtensions {
    static let chromiumBrowsers: [(name: String, path: String)] = [
        ("Chrome", "Library/Application Support/Google/Chrome"),
        ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
        ("Edge", "Library/Application Support/Microsoft Edge"),
        ("Arc", "Library/Application Support/Arc/User Data"),
        ("Vivaldi", "Library/Application Support/Vivaldi"),
    ]

    static let storeUpdateHosts = ["clients2.google.com", "edge.microsoft.com"]

    public static func scan(home: String = NSHomeDirectory()) -> [BrowserExtension] {
        let fm = FileManager.default
        var found: [BrowserExtension] = []
        for browser in chromiumBrowsers {
            let root = home + "/" + browser.path
            let profiles = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            for profile in profiles {
                let states = ChromiumExtensionState.read(profileDir: root + "/" + profile)
                let extensionsDir = root + "/" + profile + "/Extensions"
                for id in (try? fm.contentsOfDirectory(atPath: extensionsDir)) ?? [] where id.count == 32 {
                    let versions = ((try? fm.contentsOfDirectory(atPath: extensionsDir + "/" + id)) ?? []).sorted()
                    guard let version = versions.last else { continue }
                    let dir = extensionsDir + "/" + id + "/" + version
                    guard let data = fm.contents(atPath: dir + "/manifest.json"),
                          let parsed = parseManifest(data, localeLookup: { localized(key: $0, in: dir) })
                    else { continue }
                    var item = BrowserExtension(browser: browser.name, profile: profile, extensionID: id, name: parsed.name,
                                                version: parsed.version, permissions: parsed.permissions, path: dir,
                                                iconPath: parsed.icon.map { dir + "/" + $0 }, fromStore: parsed.fromStore)
                    item.state = states[id] ?? ExtensionState()
                    found.append(item)
                }
            }
        }
        found += FirefoxExtensions.scan(home: home)
        return found.sorted { ($0.risk, $1.name) > ($1.risk, $0.name) }
    }

    public struct Manifest: Equatable {
        public let name: String
        public let version: String
        public let permissions: [String]
        public let icon: String?
        public let fromStore: Bool
    }

    public static func parseManifest(_ data: Data, localeLookup: (String) -> String? = { _ in nil }) -> Manifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var name = json["name"] as? String
        else { return nil }
        if name.hasPrefix("__MSG_"), name.hasSuffix("__") {
            let key = String(name.dropFirst(6).dropLast(2))
            name = localeLookup(key) ?? key
        }
        let permissions = (json["permissions"] as? [Any] ?? []) + (json["host_permissions"] as? [Any] ?? [])
            + ((json["content_scripts"] as? [[String: Any]])?.flatMap { $0["matches"] as? [Any] ?? [] } ?? [])
        let strings = Array(Set(permissions.compactMap { $0 as? String })).sorted()
        let icons = json["icons"] as? [String: String] ?? [:]
        let icon = icons.max { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }?.value
        let update = json["update_url"] as? String ?? ""
        return Manifest(name: name, version: json["version"] as? String ?? "", permissions: strings, icon: icon,
                        fromStore: storeUpdateHosts.contains { update.contains($0) })
    }

    static func localized(key: String, in dir: String) -> String? {
        for locale in ["en", "en_US", "en_GB"] {
            guard let data = FileManager.default.contents(atPath: "\(dir)/_locales/\(locale)/messages.json"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let entry = json[key] as? [String: Any] ?? json.first { $0.key.lowercased() == key.lowercased() }?.value as? [String: Any]
            if let message = entry?["message"] as? String { return message }
        }
        return nil
    }
}

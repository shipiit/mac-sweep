import Foundation

/// How safe it is to clear one part of a browser profile.
public enum ProfileDataSafety: String, Sendable, CaseIterable {
    /// Rebuilt automatically; clearing only makes the first page loads slower.
    case safe = "Safe to clean"
    /// Site data: clearing signs you out of sites or loses offline data.
    case review = "Review first"
    /// Shown for size only; MacSweep never clears it here.
    case keep = "Kept"
}

public enum ProfileComponentKind: String, Sendable, CaseIterable {
    case cache = "Cache"
    case codeCache = "Code Cache"
    case gpuCache = "GPU Cache"
    case cacheStorage = "Service Worker caches"
    case scriptCache = "Service Worker scripts"
    case fileSystem = "File System"
    case indexedDB = "IndexedDB"
    case localStorage = "Local Storage"
    case webStorage = "Web Storage"
    case extensions = "Extensions"
    case history = "History & Favicons"

    public var safety: ProfileDataSafety {
        switch self {
        case .cache, .codeCache, .gpuCache, .cacheStorage, .scriptCache: .safe
        case .fileSystem, .indexedDB, .localStorage, .webStorage: .review
        case .extensions, .history: .keep
        }
    }

    /// Paths relative to the profile directory.
    var relativePaths: [String] {
        switch self {
        case .cache: ["Cache"]
        case .codeCache: ["Code Cache"]
        case .gpuCache: ["GPUCache"]
        case .cacheStorage: ["Service Worker/CacheStorage"]
        case .scriptCache: ["Service Worker/ScriptCache"]
        case .fileSystem: ["File System"]
        case .indexedDB: ["IndexedDB"]
        case .localStorage: ["Local Storage"]
        case .webStorage: ["WebStorage"]
        case .extensions: ["Extensions"]
        case .history: ["History", "History-journal", "Favicons", "Favicons-journal"]
        }
    }

    public var consequence: String {
        switch safety {
        case .safe: "Rebuilt automatically. Sites load a little slower the first time."
        case .review: "Clearing signs you out of sites and removes data saved for offline use."
        case .keep: "Not cleaned here."
        }
    }
}

public struct ProfileComponent: Identifiable, Sendable, Equatable {
    public let kind: ProfileComponentKind
    public let paths: [String]
    public let size: UInt64
    /// Per-site breakdown (Service Worker caches only), largest first.
    public let sites: [SiteCache]

    public var id: String { kind.rawValue }
    public var safety: ProfileDataSafety { kind.safety }

    public init(kind: ProfileComponentKind, paths: [String], size: UInt64, sites: [SiteCache] = []) {
        self.kind = kind
        self.paths = paths
        self.size = size
        self.sites = sites
    }
}

/// One site's Service Worker cache folder. `origin` is nil when the folder's index couldn't be read.
public struct SiteCache: Identifiable, Sendable, Equatable {
    public let origin: String?
    public let path: String
    public let size: UInt64

    public var id: String { path }

    public init(origin: String?, path: String, size: UInt64) {
        self.origin = origin
        self.path = path
        self.size = size
    }
}

public struct ChromiumBrowser: Sendable, Equatable {
    public let name: String
    public let bundleID: String
    /// Relative to the home folder.
    public let root: String

    /// Chromium mirrors the profile layout under ~/Library/Caches for the HTTP cache.
    public var cacheRoot: String {
        root.replacingOccurrences(of: "Library/Application Support/", with: "Library/Caches/")
    }

    public static let all: [ChromiumBrowser] = [
        ChromiumBrowser(name: "Chrome", bundleID: "com.google.Chrome", root: "Library/Application Support/Google/Chrome"),
        ChromiumBrowser(name: "Brave", bundleID: "com.brave.Browser", root: "Library/Application Support/BraveSoftware/Brave-Browser"),
        ChromiumBrowser(name: "Edge", bundleID: "com.microsoft.edgemac", root: "Library/Application Support/Microsoft Edge"),
        ChromiumBrowser(name: "Arc", bundleID: "company.thebrowser.Browser", root: "Library/Application Support/Arc/User Data"),
        ChromiumBrowser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", root: "Library/Application Support/Vivaldi"),
    ]
}

public struct BrowserProfile: Identifiable, Sendable, Equatable {
    public let browser: ChromiumBrowser
    /// Folder name, e.g. "Default" or "Profile 2".
    public let directory: String
    /// Name the user gave the profile in the browser.
    public let displayName: String
    public let path: String
    public let components: [ProfileComponent]

    public var id: String { browser.name + "/" + directory }
    public var totalSize: UInt64 { components.reduce(0) { $0 + $1.size } }

    public func size(of safety: ProfileDataSafety) -> UInt64 {
        components.filter { $0.safety == safety }.reduce(0) { $0 + $1.size }
    }

    /// Only the caches: site data, history and extensions are never included.
    public var cleanTargets: [CleanupTarget] {
        components.filter { $0.safety == .safe }.flatMap { component in
            component.paths.map { CleanupTarget(path: $0, size: component.paths.count == 1 ? component.size : 0) }
        }
    }
}

/// Browser-wide data that isn't tied to one profile.
public struct BrowserProfileGroup: Identifiable, Sendable, Equatable {
    public let browser: ChromiumBrowser
    public let profiles: [BrowserProfile]
    /// On-device AI models (OptGuideOnDeviceModel); downloaded again if removed.
    public let modelsPath: String?
    public let modelsSize: UInt64

    public var id: String { browser.name }
    public var totalSize: UInt64 { profiles.reduce(modelsSize) { $0 + $1.totalSize } }
}

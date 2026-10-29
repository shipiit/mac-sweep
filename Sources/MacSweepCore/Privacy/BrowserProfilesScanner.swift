import Foundation

/// Lists every Chromium profile with a per-category size breakdown. Read-only: Login Data,
/// Cookies, Bookmarks and Preferences are never measured or offered here.
public enum BrowserProfilesScanner {
    public static func scan(home: String = NSHomeDirectory(), browsers: [ChromiumBrowser] = ChromiumBrowser.all) -> [BrowserProfileGroup] {
        browsers.compactMap { browser in
            let root = home + "/" + browser.root
            let directories = profileDirectories(in: root)
            guard !directories.isEmpty else { return nil }
            let names = FileManager.default.contents(atPath: root + "/Local State").map(profileNames) ?? [:]
            let profiles = directories.map { directory in
                BrowserProfile(browser: browser, directory: directory, displayName: names[directory] ?? directory,
                               path: root + "/" + directory,
                               components: components(profileDir: root + "/" + directory,
                                                      cacheDir: home + "/" + browser.cacheRoot + "/" + directory))
            }
            let modelsPath = root + "/OptGuideOnDeviceModel"
            let modelsSize = DiskScanner.measure(modelsPath)
            return BrowserProfileGroup(browser: browser, profiles: profiles,
                                       modelsPath: modelsSize == nil ? nil : modelsPath, modelsSize: modelsSize ?? 0)
        }
    }

    static func profileDirectories(in root: String) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return entries.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted { lhs, rhs in
            if lhs == "Default" { return rhs != "Default" }
            if rhs == "Default" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// "Local State" → profile.info_cache.<dir>.name.
    public static func profileNames(_ data: Data) -> [String: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any]
        else { return [:] }
        var names: [String: String] = [:]
        for (directory, value) in cache {
            guard let name = (value as? [String: Any])?["name"] as? String, !name.isEmpty else { continue }
            names[directory] = name
        }
        return names
    }

    static func components(profileDir: String, cacheDir: String) -> [ProfileComponent] {
        let fm = FileManager.default
        return ProfileComponentKind.allCases.compactMap { kind in
            var paths = kind.relativePaths.map { profileDir + "/" + $0 }
            if kind == .cache { paths.append(cacheDir) }
            let existing = paths.filter { fm.fileExists(atPath: $0) }
            guard !existing.isEmpty else { return nil }
            let size = existing.reduce(UInt64(0)) { $0 + (DiskScanner.measure($1) ?? 0) }
            let sites = kind == .cacheStorage ? siteCaches(in: existing[0]) : []
            return ProfileComponent(kind: kind, paths: existing, size: size, sites: sites)
        }
    }

    /// Each hashed folder under CacheStorage belongs to one site; its `index.txt` names the origin.
    static func siteCaches(in directory: String) -> [SiteCache] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return entries.compactMap { name -> SiteCache? in
            let path = directory + "/" + name
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            let origin = FileManager.default.contents(atPath: path + "/index.txt").flatMap(origin(inIndex:))
            return SiteCache(origin: origin, path: path, size: DiskScanner.measure(path) ?? 0)
        }
        .sorted { $0.size > $1.size }
    }

    /// The index is a protobuf; the origin is stored as a plain ASCII string inside it.
    public static func origin(inIndex data: Data) -> String? {
        let bytes = [UInt8](data.prefix(65_536))
        for scheme in ["https://", "http://", "chrome-extension://"] {
            let needle = Array(scheme.utf8)
            guard bytes.count >= needle.count else { continue }
            for start in 0...(bytes.count - needle.count) where Array(bytes[start..<(start + needle.count)]) == needle {
                var end = start + needle.count
                while end < bytes.count, bytes[end] > 0x20, bytes[end] < 0x7F { end += 1 }
                guard let text = String(bytes: bytes[start..<end], encoding: .ascii), text.count > needle.count else { continue }
                return trimmedOrigin(text)
            }
        }
        return nil
    }

    /// Keeps scheme://host[:port], dropping any path a cache URL may carry.
    static func trimmedOrigin(_ text: String) -> String {
        guard let url = URL(string: text), let scheme = url.scheme, let host = url.host else { return text }
        return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// Non-nil when the browser must be quit first: it rewrites its caches while open.
    public static func blockedReason(for browser: ChromiumBrowser, runningBundleIDs: Set<String>) -> String? {
        runningBundleIDs.contains(browser.bundleID) ? "Quit \(browser.name) first. It rewrites these files while it's open." : nil
    }
}

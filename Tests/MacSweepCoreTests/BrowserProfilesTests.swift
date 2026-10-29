import Foundation
import Testing
@testable import MacSweepCore

@Suite struct BrowserProfilesTests {
    static let chrome = ChromiumBrowser.all[0]

    static func localState(_ names: [String: String]) -> Data {
        let cache = names.mapValues { ["name": $0] }
        return (try? JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]])) ?? Data()
    }

    /// A Chrome layout with a named Default profile and an unnamed Profile 2.
    static func makeLayout() throws -> String {
        let home = try Fixtures.makeTempDir()
        let root = home + "/" + chrome.root
        let profile = root + "/Default"
        try Fixtures.write(root + "/Local State", bytes: 0)
        try localState(["Default": "Work"]).write(to: URL(fileURLWithPath: root + "/Local State"))
        for file in ["Cache/data_0", "Code Cache/js/a", "GPUCache/data_1", "Service Worker/ScriptCache/s",
                     "IndexedDB/https_site/db", "Local Storage/leveldb/000003.log", "Extensions/abc/1.0/manifest.json",
                     "History", "Favicons", "Cookies", "Login Data", "Bookmarks", "Preferences"] {
            try Fixtures.write(profile + "/" + file, bytes: 8_192)
        }
        try Fixtures.write(profile + "/Service Worker/CacheStorage/abc123/data", bytes: 40_000)
        let index = Data([0x0A, 0x14] + Array("https://example.com/".utf8) + [0x12, 0x00])
        try index.write(to: URL(fileURLWithPath: profile + "/Service Worker/CacheStorage/abc123/index.txt"))
        try Fixtures.write(profile + "/Service Worker/CacheStorage/def456/data", bytes: 4_096)
        try Fixtures.write(home + "/" + chrome.cacheRoot + "/Default/Cache/Cache_Data/f_0001", bytes: 100_000)
        try Fixtures.write(root + "/Profile 2/Cache/data_0", bytes: 4_096)
        try Fixtures.write(root + "/OptGuideOnDeviceModel/2025/weights.bin", bytes: 50_000)
        try Fixtures.write(root + "/System Profile/Cache/data", bytes: 4_096)
        return home
    }

    @Test func parsesProfileNamesFromLocalState() {
        let names = BrowserProfilesScanner.profileNames(Self.localState(["Default": "Personal", "Profile 1": "Work", "Profile 3": ""]))
        #expect(names == ["Default": "Personal", "Profile 1": "Work"])
    }

    @Test func malformedLocalStateGivesNoNames() {
        #expect(BrowserProfilesScanner.profileNames(Data("not json".utf8)).isEmpty)
        #expect(BrowserProfilesScanner.profileNames(Data("{\"profile\": 3}".utf8)).isEmpty)
        #expect(BrowserProfilesScanner.profileNames(Data()).isEmpty)
    }

    @Test func scansProfilesWithNamesAndFallback() throws {
        let home = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let groups = BrowserProfilesScanner.scan(home: home)
        #expect(groups.map(\.browser.name) == ["Chrome"])
        let profiles = try #require(groups.first).profiles
        #expect(profiles.map(\.directory) == ["Default", "Profile 2"])
        #expect(profiles.map(\.displayName) == ["Work", "Profile 2"])
    }

    @Test func breaksDownSizesAndSafety() throws {
        let home = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let group = try #require(BrowserProfilesScanner.scan(home: home).first)
        let profile = try #require(group.profiles.first)
        let kinds = Set(profile.components.map(\.kind))
        #expect(kinds == [.cache, .codeCache, .gpuCache, .cacheStorage, .scriptCache, .indexedDB, .localStorage, .extensions, .history])
        let cache = try #require(profile.components.first { $0.kind == .cache })
        #expect(cache.paths.count == 2)
        #expect(cache.size >= 100_000)
        #expect(profile.totalSize == profile.components.reduce(0) { $0 + $1.size })
        #expect(profile.size(of: .safe) > profile.size(of: .review))
        #expect(group.modelsSize > 0)
        #expect(group.modelsPath?.hasSuffix("OptGuideOnDeviceModel") == true)
        #expect(group.totalSize == group.modelsSize + group.profiles.reduce(0) { $0 + $1.totalSize })
    }

    @Test func listsServiceWorkerCachesPerSite() throws {
        let home = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let profile = try #require(BrowserProfilesScanner.scan(home: home).first?.profiles.first)
        let storage = try #require(profile.components.first { $0.kind == .cacheStorage })
        #expect(storage.sites.count == 2)
        #expect(storage.sites.first?.origin == "https://example.com")
        #expect(storage.sites.last?.origin == nil)
    }

    @Test func cleanTargetsAreOnlyCaches() throws {
        let home = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let profile = try #require(BrowserProfilesScanner.scan(home: home).first?.profiles.first)
        let paths = profile.cleanTargets.map(\.path)
        #expect(paths.count == 6)
        let names = paths.map { ($0 as NSString).lastPathComponent }
        for forbidden in ["Cookies", "Login Data", "Bookmarks", "Preferences", "History", "Favicons", "IndexedDB", "Local Storage", "Extensions"] {
            #expect(!names.contains(forbidden))
        }
        #expect(paths.allSatisfy { PathGuard.reason($0, home: home) == nil })
    }

    @Test func safetyClasses() {
        for kind in [ProfileComponentKind.cache, .codeCache, .gpuCache, .scriptCache, .cacheStorage] { #expect(kind.safety == .safe) }
        for kind in [ProfileComponentKind.indexedDB, .localStorage, .fileSystem, .webStorage] { #expect(kind.safety == .review) }
        for kind in [ProfileComponentKind.extensions, .history] { #expect(kind.safety == .keep) }
    }

    @Test func missingBrowserIsSkipped() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/" + ChromiumBrowser.all[1].root + "/Local State", bytes: 10)
        #expect(BrowserProfilesScanner.scan(home: home).isEmpty)
    }

    @Test func refusesWhileBrowserRuns() {
        #expect(BrowserProfilesScanner.blockedReason(for: Self.chrome, runningBundleIDs: ["com.google.Chrome"])?.contains("Quit Chrome") == true)
        #expect(BrowserProfilesScanner.blockedReason(for: Self.chrome, runningBundleIDs: ["com.brave.Browser"]) == nil)
        #expect(BrowserProfilesScanner.blockedReason(for: Self.chrome, runningBundleIDs: []) == nil)
    }

    @Test func originParsing() {
        #expect(BrowserProfilesScanner.origin(inIndex: Data("\u{1}\u{2}http://localhost:8080/sw.js\u{0}".utf8)) == "http://localhost:8080")
        #expect(BrowserProfilesScanner.origin(inIndex: Data("chrome-extension://abcdef/\u{0}".utf8)) == "chrome-extension://abcdef")
        #expect(BrowserProfilesScanner.origin(inIndex: Data("https://\u{0}".utf8)) == nil)
        #expect(BrowserProfilesScanner.origin(inIndex: Data()) == nil)
    }

    @Test func cacheRootMirrorsApplicationSupport() {
        #expect(ChromiumBrowser.all.map(\.cacheRoot) == ["Library/Caches/Google/Chrome", "Library/Caches/BraveSoftware/Brave-Browser",
                                                         "Library/Caches/Microsoft Edge", "Library/Caches/Arc/User Data", "Library/Caches/Vivaldi"])
    }
}

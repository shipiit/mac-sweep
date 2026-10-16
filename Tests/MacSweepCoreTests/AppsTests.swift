import Foundation
import Testing
@testable import MacSweepCore

@Suite struct AppsTests {
    @Test func leftoverCandidatesCoverStandardLocations() {
        let paths = Leftovers.candidates(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", home: "/Users/test")
        #expect(paths.contains("/Users/test/Library/Preferences/com.tinyspeck.slackmacgap.plist"))
        #expect(paths.contains("/Users/test/Library/Application Support/Slack"))
        #expect(paths.contains("/Users/test/Library/Containers/com.tinyspeck.slackmacgap"))
        #expect(paths.allSatisfy { PathGuard.canRemove($0, home: "/Users/test") })
    }

    @Test func veryShortNamesAreNotUsedAsFolderNames() {
        let paths = Leftovers.candidates(bundleID: "com.x.y", name: "X", home: "/Users/test")
        #expect(!paths.contains("/Users/test/Library/Application Support/X"))
    }

    @Test func findsLeftoversOnDisk() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/Library/Application Support/Slack/data", bytes: 100)
        try Fixtures.write(home + "/Library/Preferences/com.tinyspeck.slackmacgap.plist", bytes: 10)
        try Fixtures.write(home + "/Library/Group Containers/ABC123.com.tinyspeck.slackmacgap/x", bytes: 10)
        try Fixtures.write(home + "/Library/Application Support/Other/x", bytes: 10)
        let app = InstalledApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", version: "4", path: "/Applications/Slack.app", isAppStore: false)
        let found = Leftovers.find(for: app, home: home).map(\.path)
        #expect(found.count == 3)
        #expect(!found.contains { $0.contains("/Other") })
    }

    @Test func orphanDetectionIsConservative() {
        let installed: Set<String> = ["com.google.Chrome", "com.tinyspeck.slackmacgap"]
        #expect(Leftovers.isOrphan("com.removed.App", installed: installed))
        #expect(!Leftovers.isOrphan("com.google.Keystone", installed: installed))
        #expect(!Leftovers.isOrphan("com.apple.Safari", installed: installed))
        #expect(!Leftovers.isOrphan("Slack", installed: installed))
        #expect(!Leftovers.isOrphan("com.tinyspeck.slackmacgap", installed: installed))
        #expect(!Leftovers.isOrphan("fr.x", installed: installed))
        #expect(!Leftovers.isOrphan("com.vercel.cli", installed: installed))
        #expect(!Leftovers.isOrphan("org.swift.swiftpm", installed: installed))
        #expect(!Leftovers.isOrphan("org.webkit.Playwright", installed: installed))
    }

    @Test func recentlyUsedFoldersAreNeverOrphans() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/Library/Application Support/com.old.App/data", bytes: 2048)
        try Fixtures.write(home + "/Library/Application Support/com.fresh.App/data", bytes: 2048)
        let old = Date().addingTimeInterval(-90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/Library/Application Support/com.old.App")
        let orphans = Leftovers.orphans(installedBundleIDs: [], home: home)
        #expect(orphans.map { ($0.path as NSString).lastPathComponent } == ["com.old.App"])
    }

    @Test func describesRealAppBundleAndSkipsInvalid() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let app = dir + "/Demo.app"
        try FileManager.default.createDirectory(atPath: app + "/Contents/_MASReceipt", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: app + "/Contents/_MASReceipt/receipt"))
        let info: NSDictionary = ["CFBundleIdentifier": "com.demo.app", "CFBundleName": "Demo", "CFBundleShortVersionString": "2.1"]
        info.write(toFile: app + "/Contents/Info.plist", atomically: true)
        let described = try #require(AppInventory.describe(path: app))
        #expect(described.bundleID == "com.demo.app" && described.version == "2.1" && described.isAppStore)
        #expect(AppInventory.describe(path: dir + "/Missing.app") == nil)
        #expect(AppInventory.appBundles(in: dir) == [app])
    }

    @Test func parsesSoftwareUpdate() {
        let output = """
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: macOS Tahoe 26.6-25G5
        \tTitle: macOS Tahoe 26.6, Version: 26.6, Size: 7340032KiB, Recommended: YES, Action: restart,
        * Label: Safari26.1
        \tTitle: Safari, Version: 26.1, Size: 200000KiB, Recommended: YES,
        """
        let updates = Updater.parseSoftwareUpdate(output)
        #expect(updates.map(\.name) == ["macOS Tahoe 26.6", "Safari"])
        #expect(updates[0].needsRestart && !updates[1].needsRestart)
        #expect(updates[0].available == "26.6")
        #expect(Updater.parseSoftwareUpdate("No new software available.").isEmpty)
    }

    @Test func parsesBrewOutdated() {
        let json = #"{"formulae":[{"name":"node","installed_versions":["22.1.0"],"current_version":"22.9.0"}],"casks":[{"name":"visual-studio-code","installed_versions":"1.90","current_version":"1.95"}]}"#
        let updates = Updater.parseBrewOutdated(json)
        #expect(updates.map(\.name) == ["visual-studio-code", "node"])
        #expect(updates[0].source == .homebrewCask && updates[0].installed == "1.90")
        #expect(updates[1].installed == "22.1.0" && updates[1].available == "22.9.0")
        #expect(Updater.parseBrewOutdated("oops").isEmpty)
    }

    @Test func extensionsHubFindsUserPlugins() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try FileManager.default.createDirectory(atPath: home + "/Library/QuickLook/Markdown.qlgenerator", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/Library/QuickLook/notes.txt", withIntermediateDirectories: true)
        let items = ExtensionsHub.scan(home: home).filter(\.isUserInstalled)
        #expect(items.map(\.name) == ["Markdown"])
        #expect(items.first?.kind == .quickLook)
    }
}

@Suite struct SpeedTests {
    let gib: UInt64 = 1 << 30

    @Test func healthyMacGetsOnlyLowImpactTips() {
        let input = AdvisorInput(disk: VolumeStats(total: 500 * gib, available: 200 * gib), uptimeDays: 1, lastScan: Date())
        #expect(Advisor.advise(input).isEmpty)
    }

    @Test func ranksProblemsByImpact() {
        let memory = SystemMemoryStats(total: 16 * gib, app: 10 * gib, wired: 2 * gib, compressed: 3 * gib, cached: 0, free: 1 * gib,
                                       swapUsed: 6 * gib, swapTotal: 8 * gib, pressure: .warning)
        let input = AdvisorInput(memory: memory, heavyProcesses: [(pid: 42, name: "Chrome", memory: 3 * gib, cpu: 95, growing: false),
                                                                  (pid: 43, name: "Leaky", memory: 2 * gib, cpu: 1, growing: true)],
                                 loginItemCount: 20, disk: VolumeStats(total: 500 * gib, available: 20 * gib),
                                 safeCleanupBytes: 12 * gib, trashBytes: 1 * gib, protectionsOff: ["Firewall"], securityFindings: 2,
                                 uptimeDays: 12, lastScan: nil)
        let advice = Advisor.advise(input)
        #expect(advice.first?.impact == .high)
        #expect(zip(advice, advice.dropFirst()).allSatisfy { $0.impact >= $1.impact })
        let ids = Set(advice.map(\.id))
        for id in ["disk-low", "cleanup", "trash", "pressure", "swap", "grow-43", "cpu-42", "login", "protection", "findings", "restart", "scan"] {
            #expect(ids.contains(id), "\(id)")
        }
        #expect(advice.contains { $0.action == .quitProcess(pid: 43, name: "Leaky") })
    }

    @Test func batteryAdviceBelowEightyPercent() throws {
        let battery = try #require(Battery.parse(["CurrentCapacity": 50, "AppleRawMaxCapacity": 70, "DesignCapacity": 100]))
        let advice = Advisor.advise(AdvisorInput(battery: battery, lastScan: Date()))
        #expect(advice.map(\.id) == ["battery"])
    }

    @Test func maintenanceTasksAreFullyDefined() {
        for task in MaintenanceTask.allCases {
            #expect(!task.title.isEmpty && !task.detail.isEmpty)
            #expect((task.adminCommand != nil) == task.requiresAdmin)
            #expect((task.userCommand != nil) == !task.requiresAdmin)
            if let (executable, _) = task.userCommand { #expect(FileManager.default.isExecutableFile(atPath: executable), "\(executable)") }
        }
    }
}

@Suite struct PrivacyAndRemovalTests {
    @Test func privacyScanFindsBrowserTracesButNeverPasswords() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let profile = home + "/Library/Application Support/Google/Chrome/Default"
        for file in ["History", "Cookies", "Login Data", "Bookmarks", "Sessions/s1"] { try Fixtures.write(profile + "/" + file, bytes: 4096) }
        let items = PrivacyScanner.scan(home: home)
        let kinds = Set(items.filter { $0.app == "Chrome" }.map(\.kind))
        #expect(kinds == [.history, .cookies, .sessions])
        let allPaths = items.flatMap(\.paths)
        #expect(!allPaths.contains { $0.hasSuffix("Login Data") || $0.hasSuffix("Bookmarks") })
        #expect(allPaths.allSatisfy { PathGuard.canRemove($0, home: home) })
    }

    @Test func emptyHomeHasNoPrivacyItems() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        #expect(PrivacyScanner.scan(home: home).isEmpty)
    }

    @Test func removalPlanNeverIncludesSystemBinaries() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.hidden/agent", bytes: 10)
        let shell = LaunchItem(label: "com.x.sh", plistPath: home + "/Library/LaunchAgents/com.x.sh.plist", scope: .userAgent,
                               program: "/bin/sh", arguments: [], runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        #expect(LaunchItemRemover.plan(for: shell, home: home).filesToTrash == [shell.plistPath])
        let hidden = LaunchItem(label: "com.x.h", plistPath: home + "/Library/LaunchAgents/com.x.h.plist", scope: .userAgent,
                                program: home + "/.hidden/agent", arguments: [], runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        let plan = LaunchItemRemover.plan(for: hidden, home: home)
        #expect(plan.filesToTrash == [hidden.plistPath, home + "/.hidden/agent"])
        #expect(!plan.needsAdmin)
        let daemon = LaunchItem(label: "com.x.d", plistPath: "/Library/LaunchDaemons/com.x.d.plist", scope: .daemon,
                                program: "/usr/bin/true", arguments: [], runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        let daemonPlan = LaunchItemRemover.plan(for: daemon, home: home)
        #expect(daemonPlan.needsAdmin && daemonPlan.filesToTrash == ["/Library/LaunchDaemons/com.x.d.plist"])
    }
}

@Suite struct AppCategoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func app(_ id: String, size: UInt64? = nil, lastUsed: Date? = nil, store: Bool = false) -> InstalledApp {
        InstalledApp(name: id, bundleID: id, version: "1", path: "/Applications/\(id).app", isAppStore: store, size: size, lastUsed: lastUsed)
    }

    @Test func vendorNames() {
        #expect(AppCategories.vendor(for: "com.google.Chrome") == "Google")
        #expect(AppCategories.vendor(for: "com.tinyspeck.slackmacgap") == "Slack")
        #expect(AppCategories.vendor(for: "org.whispersystems.signal-desktop") == "Whispersystems")
        #expect(AppCategories.vendor(for: "io.x.y") == "Other")
        #expect(AppCategories.vendor(for: "single") == "Other")
    }

    @Test func categoryMatching() {
        let old = app("com.a.old", size: 600 << 20, lastUsed: now.addingTimeInterval(-100 * 86_400))
        let fresh = app("com.a.fresh", size: 10 << 20, lastUsed: now.addingTimeInterval(-86_400), store: true)
        let never = app("com.a.never")
        #expect(AppCategories.matches(old, .unused, now: now))
        #expect(!AppCategories.matches(fresh, .unused, now: now))
        #expect(AppCategories.matches(never, .unused, now: now))
        #expect(AppCategories.matches(old, .large) && !AppCategories.matches(fresh, .large) && !AppCategories.matches(never, .large))
        #expect(AppCategories.matches(fresh, .appStore) && AppCategories.matches(old, .other))
        #expect(AppCategories.matches(old, .all))
        #expect(AppCategories.matches(app("com.google.Chrome"), .vendor("Google")))
    }

    @Test func vendorCountsSorted() {
        let apps = [app("com.google.Chrome"), app("com.google.Drive"), app("com.microsoft.Word")]
        #expect(AppCategories.vendors(apps).map(\.name) == ["Google", "Microsoft"])
        #expect(AppCategories.vendors([]).isEmpty)
    }
}

import Foundation
import Testing
@testable import MacSweepCore

@Suite struct AppFootprintTests {
    private let slack = InstalledApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", version: "4",
                                     path: "/Applications/Slack.app", isAppStore: false, size: 1_000)

    private func withHome(_ body: (String) throws -> Void) throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try body(home)
    }

    private func byteSize(_ path: String) -> UInt64? {
        DiskScanner.measure(path)
    }

    // MARK: Matching

    @Test func matchesByBundleID() throws {
        try withHome { home in
            let lib = home + "/Library"
            try Fixtures.write(lib + "/Caches/com.tinyspeck.slackmacgap/a", bytes: 4096)
            try Fixtures.write(lib + "/HTTPStorages/com.tinyspeck.slackmacgap.binarycookies", bytes: 10)
            try Fixtures.write(lib + "/Application Support/com.tinyspeck.slackmacgap/db", bytes: 10)
            try Fixtures.write(lib + "/Preferences/com.tinyspeck.slackmacgap.plist", bytes: 10)
            try Fixtures.write(lib + "/Logs/com.tinyspeck.slackmacgap/x.log", bytes: 10)
            try Fixtures.write(lib + "/Saved Application State/com.tinyspeck.slackmacgap.savedState/w", bytes: 10)
            try Fixtures.write(lib + "/WebKit/com.tinyspeck.slackmacgap/d", bytes: 10)
            try Fixtures.write(lib + "/Caches/com.other.app/a", bytes: 10)
            let found = AppFootprintLocator.locate(bundleID: slack.bundleID, name: slack.name, home: home)
            let categories = Dictionary(found.map { ($0.path, $0.category) }, uniquingKeysWith: { a, _ in a })
            #expect(found.count == 7)
            #expect(categories[lib + "/Caches/com.tinyspeck.slackmacgap"] == .caches)
            #expect(categories[lib + "/HTTPStorages/com.tinyspeck.slackmacgap.binarycookies"] == .caches)
            #expect(categories[lib + "/Preferences/com.tinyspeck.slackmacgap.plist"] == .preferences)
            #expect(categories[lib + "/Saved Application State/com.tinyspeck.slackmacgap.savedState"] == .savedState)
            #expect(categories[lib + "/WebKit/com.tinyspeck.slackmacgap"] == .webKit)
            #expect(!found.contains { $0.path.contains("com.other.app") })
        }
    }

    @Test func matchesByName() throws {
        try withHome { home in
            try Fixtures.write(home + "/Library/Application Support/Slack/IndexedDB/x", bytes: 10)
            try Fixtures.write(home + "/Library/Logs/Slack/x.log", bytes: 10)
            try Fixtures.write(home + "/Library/Caches/Slack/x", bytes: 10)
            let found = AppFootprintLocator.locate(bundleID: slack.bundleID, name: slack.name, home: home)
            #expect(Set(found.map(\.category)) == [.applicationSupport, .logs, .caches])
        }
    }

    @Test func shortOrUnsafeNamesAreNotMatched() {
        let short = AppFootprintLocator.candidates(bundleID: "com.x.y", name: "X", home: "/Users/test")
        #expect(!short.contains { $0.path.hasSuffix("/X") })
        let traversal = AppFootprintLocator.candidates(bundleID: "com.x.y", name: "../../Documents", home: "/Users/test")
        #expect(!traversal.contains { $0.path.contains("..") })
        #expect(AppFootprintLocator.candidates(bundleID: "../evil", name: "Evil", home: "/Users/test").isEmpty)
    }

    @Test func groupContainersMatchTeamPrefixAndBundleIDOnly() {
        let id = "com.microsoft.Word"
        #expect(AppFootprintLocator.isGroupContainer("UBF8T346G9.com.microsoft.Word", of: id))
        #expect(AppFootprintLocator.isGroupContainer("UBF8T346G9.com.microsoft.word.shared", of: id))
        #expect(AppFootprintLocator.isGroupContainer("group.com.microsoft.Word", of: id))
        #expect(AppFootprintLocator.isGroupContainer("com.microsoft.Word", of: id))
        #expect(!AppFootprintLocator.isGroupContainer("UBF8T346G9.Office", of: id))
        #expect(!AppFootprintLocator.isGroupContainer("UBF8T346G9.com.microsoft.Excel", of: id))
        #expect(!AppFootprintLocator.isGroupContainer("UBF8T346G9.com.microsoft.WordPlus", of: id))
        #expect(!AppFootprintLocator.isGroupContainer("lowercase1.com.microsoft.Word", of: id))
    }

    @Test func missingFoldersAndEmptyHomeYieldOnlyTheBundle() throws {
        try withHome { home in
            #expect(AppFootprintLocator.locate(bundleID: slack.bundleID, name: slack.name, home: home).isEmpty)
            let footprint = AppFootprintScanner.footprint(for: slack, home: home, measure: byteSize)
            #expect(footprint.items.map(\.category) == [.bundle])
            #expect(footprint.total == 1_000 && footprint.dataSize == 0 && footprint.cacheSize == 0)
            #expect(footprint.breakdown.map(\.category) == [.bundle])
        }
    }

    // MARK: Aggregation

    @Test func containerCacheIsCountedOnceAsCache() throws {
        try withHome { home in
            let container = home + "/Library/Containers/com.tinyspeck.slackmacgap"
            try Fixtures.write(container + "/Data/Library/Caches/blob", bytes: 8192)
            try Fixtures.write(container + "/Data/Documents/doc", bytes: 4096)
            try Fixtures.write(home + "/Library/Group Containers/ABCDE12345.com.tinyspeck.slackmacgap/x", bytes: 4096)
            let footprint = AppFootprintScanner.footprint(for: slack, home: home, measure: byteSize)
            let whole = try #require(byteSize(container))
            let groups = try #require(byteSize(home + "/Library/Group Containers/ABCDE12345.com.tinyspeck.slackmacgap"))
            #expect(footprint.cacheSize > 0)
            #expect(footprint.size(of: .containers) + footprint.cacheSize == whole + groups)
            #expect(footprint.total == 1_000 + whole + groups)
        }
    }

    @Test func attributeNestedSubtractsChildren() {
        let items = [
            FootprintItem(path: "/h/C/app", category: .containers, size: 100),
            FootprintItem(path: "/h/C/app/Data/Library/Caches", category: .caches, size: 30),
            FootprintItem(path: "/h/C/app", category: .containers, size: 100),
        ]
        let result = AppFootprintScanner.attributeNested(items)
        #expect(result.count == 2)
        #expect(result.first { $0.category == .containers }?.size == 70)
        #expect(result.first { $0.category == .caches }?.size == 30)
    }

    @Test func scanSortsByTotalAndSkipsAppleAndSelf() {
        let big = InstalledApp(name: "Big", bundleID: "com.big.app", version: "1", path: "/Applications/Big.app", isAppStore: false, size: 900)
        let small = InstalledApp(name: "Small", bundleID: "com.small.app", version: "1", path: "/Applications/Small.app", isAppStore: false, size: 10)
        let apple = InstalledApp(name: "Pages", bundleID: "com.apple.iWork.Pages", version: "1", path: "/Applications/Pages.app", isAppStore: true, size: 5_000)
        let me = InstalledApp(name: "MacSweep", bundleID: "dev.macsweep.app", version: "1", path: "/Applications/MacSweep.app", isAppStore: false, size: 5_000)
        let result = AppFootprintScanner.scan(apps: [small, apple, big, me], home: "/nonexistent-home",
                                              excludedBundleIDs: ["dev.macsweep.app"], measure: { _ in nil })
        #expect(result.map(\.app.name) == ["Big", "Small"])
        #expect(AppFootprintScanner.scan(apps: [], home: "/nonexistent-home").isEmpty)
    }

    // MARK: Plans

    private func sampleFootprint(home: String) -> AppFootprint {
        let lib = home + "/Library"
        return AppFootprint(app: slack, items: [
            FootprintItem(path: slack.path, category: .bundle, size: 1_000),
            FootprintItem(path: lib + "/Caches/com.tinyspeck.slackmacgap", category: .caches, size: 300),
            FootprintItem(path: lib + "/Containers/com.tinyspeck.slackmacgap", category: .containers, size: 200),
            FootprintItem(path: lib + "/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches", category: .caches, size: 50),
            FootprintItem(path: lib + "/Preferences/com.tinyspeck.slackmacgap.plist", category: .preferences, size: 5),
            FootprintItem(path: lib + "/Application Support/Slack", category: .applicationSupport, size: 400),
        ])
    }

    @Test func clearCacheOnlyTouchesCacheLocations() throws {
        let home = "/Users/test"
        let plan = try AppFootprintPlanner.plan(sampleFootprint(home: home), action: .clearCache, home: home).get()
        #expect(Set(plan.targets.map(\.path)) == [
            home + "/Library/Caches/com.tinyspeck.slackmacgap",
            home + "/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches",
        ])
        #expect(plan.total == 350)
        #expect(plan.categories.values.allSatisfy { $0 == .caches })
    }

    @Test func resetRemovesEverythingButTheBundleAndFoldsNested() throws {
        let home = "/Users/test"
        let plan = try AppFootprintPlanner.plan(sampleFootprint(home: home), action: .reset, home: home).get()
        let paths = plan.targets.map(\.path)
        #expect(!paths.contains(slack.path))
        #expect(paths.count == 4)
        #expect(!paths.contains { $0.hasSuffix("/Data/Library/Caches") })
        #expect(plan.targets.first { $0.path.hasSuffix("Containers/com.tinyspeck.slackmacgap") }?.size == 250)
        #expect(plan.total == 955)
        #expect(paths.first == home + "/Library/Application Support/Slack")
    }

    @Test func appleAppsAndSelfAreRefused() {
        let home = "/Users/test"
        let apple = AppFootprint(app: InstalledApp(name: "Xcode", bundleID: "com.apple.dt.Xcode", version: "16",
                                                   path: "/Applications/Xcode.app", isAppStore: true), items: [])
        #expect(AppFootprintPlanner.plan(apple, action: .reset, home: home) == .failure(.appleApp))
        #expect(AppFootprintPlanner.plan(apple, action: .clearCache, home: home) == .failure(.appleApp))
        let me = AppFootprint(app: InstalledApp(name: "MacSweep", bundleID: "dev.macsweep.app", version: "1",
                                                path: "/Applications/MacSweep.app", isAppStore: false), items: [])
        #expect(AppFootprintPlanner.plan(me, action: .reset, home: home, excludedBundleIDs: ["dev.macsweep.app"]) == .failure(.macSweepItself))
        #expect(AppFootprintLocator.refusal(bundleID: "COM.APPLE.Safari") == .appleApp)
        #expect(AppFootprintLocator.refusal(bundleID: "") == .invalidBundleID)
        #expect(AppFootprintLocator.refusal(bundleID: "com.tinyspeck.slackmacgap") == nil)
    }

    @Test func pathGuardRefusalsAreReportedNotTrashed() throws {
        let home = "/Users/test"
        let app = InstalledApp(name: "Odd", bundleID: "com.odd.app", version: "1", path: "/Applications/Odd.app", isAppStore: false)
        let footprint = AppFootprint(app: app, items: [
            FootprintItem(path: home + "/Library/Caches", category: .caches, size: 10),
            FootprintItem(path: "/Library/Caches/com.odd.app", category: .caches, size: 10),
            FootprintItem(path: home + "/Library/Caches/com.odd.app", category: .caches, size: 10),
            FootprintItem(path: "/Applications/Odd.app/Contents/Resources", category: .applicationSupport, size: 10),
        ])
        let plan = try AppFootprintPlanner.plan(footprint, action: .reset, home: home).get()
        #expect(plan.targets.map(\.path) == [home + "/Library/Caches/com.odd.app"])
        #expect(plan.refused.map(\.path) == ["/Library/Caches/com.odd.app", home + "/Library/Caches"])
    }

    @Test func emptyFootprintGivesEmptyPlan() throws {
        let footprint = AppFootprint(app: slack, items: [FootprintItem(path: slack.path, category: .bundle, size: 1)])
        let plan = try AppFootprintPlanner.plan(footprint, action: .reset, home: "/Users/test").get()
        #expect(plan.isEmpty && plan.total == 0 && plan.refused.isEmpty)
    }

    @Test func resetPlanTrashesRealFilesAndKeepsBundle() throws {
        try withHome { home in
            let bundle = home + "/Applications/Slack.app"
            try Fixtures.write(bundle + "/Contents/Info.plist", bytes: 10)
            try Fixtures.write(home + "/Library/Caches/com.tinyspeck.slackmacgap/a", bytes: 10)
            try Fixtures.write(home + "/Library/Preferences/com.tinyspeck.slackmacgap.plist", bytes: 10)
            let app = InstalledApp(name: "Slack", bundleID: slack.bundleID, version: "4", path: bundle, isAppStore: false)
            let footprint = AppFootprintScanner.footprint(for: app, home: home, measure: byteSize)
            let plan = try AppFootprintPlanner.plan(footprint, action: .reset, home: home).get()
            let results = Cleaner.remove(plan.targets, mode: .delete, home: home, extraProtected: [])
            #expect(results.allSatisfy(\.succeeded) && results.count == 2)
            #expect(FileManager.default.fileExists(atPath: bundle))
            #expect(!FileManager.default.fileExists(atPath: home + "/Library/Preferences/com.tinyspeck.slackmacgap.plist"))
        }
    }
}

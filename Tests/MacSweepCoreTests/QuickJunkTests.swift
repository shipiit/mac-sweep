import Foundation
import Testing
@testable import MacSweepCore

@Suite struct VersionedFoldersTests {
    @Test func comparesVersionsNumerically() {
        #expect(VersionedFolders.isNewer("2.1.120", than: "2.1.119"))
        #expect(VersionedFolders.isNewer("2.1.120", than: "2.1.99"))
        #expect(!VersionedFolders.isNewer("2.1.9", than: "2.1.10"))
        #expect(!VersionedFolders.isNewer("1.0", than: "1.0.0"))
        #expect(VersionedFolders.isNewer("1.0-beta", than: "1.0-alpha"))
    }

    @Test func keepsNewestVersions() {
        #expect(VersionedFolders.olderVersions(["2.1.119", "2.1.120", "2.1.99", "notes.txt"], keep: 1) == ["2.1.119", "2.1.99"])
        #expect(VersionedFolders.olderVersions(["2.1.119", "2.1.120"], keep: 2).isEmpty)
        #expect(VersionedFolders.olderVersions(["3.0"], keep: 0).isEmpty, "never removes the only version")
        #expect(VersionedFolders.olderVersions([], keep: 1).isEmpty)
    }

    @Test func findsDuplicateExtensionsPerPlatform() {
        let names = ["anthropic.claude-code-2.1.311-darwin-arm64", "anthropic.claude-code-2.1.312-darwin-arm64",
                     "ms-toolsai.jupyter-2025.1.0", "ms-toolsai.jupyter-2025.2.0", "ms-toolsai.jupyter-2024.9.1",
                     "eamodio.gitlens-15.0.0", "extensions.json", ".obsolete"]
        #expect(VersionedFolders.duplicateExtensions(names) == ["anthropic.claude-code-2.1.311-darwin-arm64",
                                                                "ms-toolsai.jupyter-2024.9.1", "ms-toolsai.jupyter-2025.1.0"])
        #expect(VersionedFolders.duplicateExtensions(["a.b-1.0.0-darwin-arm64", "a.b-1.0.1-linux-x64"]).isEmpty, "different platforms aren't duplicates")
        #expect(VersionedFolders.splitExtension("no-version-here") == nil)
    }
}

@Suite struct QuickJunkScannerTests {
    func make(_ home: String, _ path: String, bytes: Int = 2_000_000) throws {
        let full = home + "/" + path
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: URL(fileURLWithPath: full))
    }

    @Test func rootsDropNestedAndNamedRules() {
        let rules = [
            CleanupRule(id: "a", title: "", detail: "", safety: .safe, category: .caches, target: .paths(["~/Library/Caches/x", "~/Library/Caches"])),
            CleanupRule(id: "b", title: "", detail: "", safety: .safe, category: .caches, target: .named(["node_modules"], idleDays: nil)),
            CleanupRule(id: "c", title: "", detail: "", safety: .safe, category: .caches, target: .olderVersions(in: "~/.local/v", keep: 1)),
        ]
        #expect(QuickJunkScanner.roots(rules: rules, home: "/U") == ["/U/.local/v", "/U/Library/Caches"])
    }

    @Test func findsJunkWithoutAFullScan() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try make(home, "Library/Caches/com.microsoft.VSCode.ShipIt/update.zip")
        try make(home, "Library/Caches/com.apple.keep/data")
        try make(home, ".local/share/claude/versions/2.1.119")
        try make(home, ".local/share/claude/versions/2.1.120")
        try make(home, ".vscode/extensions/ms-toolsai.jupyter-2025.1.0/x")
        try make(home, ".vscode/extensions/ms-toolsai.jupyter-2025.2.0/x")
        try make(home, "work/app/node_modules/lib/index.js")
        let old = Date().addingTimeInterval(-60 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/work/app/node_modules")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/work/app/node_modules/lib")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/work/app/node_modules/lib/index.js")
        let (items, tree) = await QuickJunkScanner.scan(home: home, cache: nil)
        let byRule = Dictionary(uniqueKeysWithValues: items.map { ($0.rule.id, $0.targets.map { String($0.path.dropFirst(home.count)) }) })
        #expect(byRule["update-leftovers"] == ["/Library/Caches/com.microsoft.VSCode.ShipIt"])
        #expect(byRule["old-cli-versions"] == ["/.local/share/claude/versions/2.1.119"])
        #expect(byRule["editor-old-extensions"] == ["/.vscode/extensions/ms-toolsai.jupyter-2025.1.0"])
        #expect(byRule["node-modules"] == ["/work/app/node_modules"])
        #expect(tree.path == home && tree.size > 0)
        #expect(QuickJunkScanner.namedMatches(home: home).map { String($0.dropFirst(home.count)) } == ["/work/app/node_modules"])
    }

    @Test func skipsActiveProjectsAndReusesCachedSizes() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try make(home, "fresh/node_modules/a.js")
        try make(home, "idle/node_modules/a.js", bytes: 3_000_000)
        let old = Date().addingTimeInterval(-60 * 86_400)
        for path in ["idle/node_modules", "idle/node_modules/a.js"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home + "/" + path)
        }
        let cache = SizeCache(url: URL(fileURLWithPath: home + "/cache.json"))
        let first = await QuickJunkScanner.scan(home: home, cache: cache)
        #expect(first.items.first { $0.rule.id == "node-modules" }?.targets.map { String($0.path.dropFirst(home.count)) } == ["/idle/node_modules"])
        #expect(cache.load().keys.map { String($0.dropFirst(home.count)) } == ["/idle/node_modules"], "the active project wasn't measured")
        // A cached size is reused while the folder's date is unchanged.
        try cache.save([home + "/idle/node_modules": .init(size: 42_000_000, modified: old)])
        let second = await QuickJunkScanner.scan(home: home, cache: cache)
        #expect(second.items.first { $0.rule.id == "node-modules" }?.size == 42_000_000)
        #expect(SizeCache(url: URL(fileURLWithPath: home + "/missing.json")).load().isEmpty)
    }

    @Test func emptyHomeFindsNothing() async throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let (items, tree) = await QuickJunkScanner.scan(home: home, cache: nil)
        #expect(items.isEmpty && tree.size == 0)
    }
}

@Suite struct AutoCleanAndSessionsTests {
    @Test func dueWeekly() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(AutoClean.isDue(lastRun: nil, now: now))
        #expect(!AutoClean.isDue(lastRun: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(AutoClean.isDue(lastRun: now.addingTimeInterval(-7 * 86_400), now: now))
    }

    @Test func onlySafeAndNotInUse() {
        let safe = CleanupRule(id: "s", title: "", detail: "", safety: .safe, category: .caches, target: .paths([]))
        let review = CleanupRule(id: "r", title: "", detail: "", safety: .review, category: .caches, target: .paths([]))
        let items = [CleanupItem(rule: safe, targets: [CleanupTarget(path: "/a", size: 1), CleanupTarget(path: "/b", size: 1)]),
                     CleanupItem(rule: review, targets: [CleanupTarget(path: "/c", size: 1)])]
        #expect(AutoClean.targets(items, inUse: ["/b"]).map(\.path) == ["/a"])
        #expect(AutoClean.targets([], inUse: []).isEmpty)
    }

    @Test func keepsNamedSessions() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let folder = root + "/claude/proj"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for name in ["keep-me", "old-one"] {
            try "{}".write(toFile: folder + "/\(name).jsonl", atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: folder + "/\(name).jsonl")
        }
        let sources = AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex")
        #expect(TranscriptCleanup.old(olderThanDays: 30, keeping: ["keep-me"], sources: sources).map { ($0.path as NSString).lastPathComponent } == ["old-one.jsonl"])
        #expect(TranscriptCleanup.old(olderThanDays: 30, sources: sources).count == 2)
    }
}

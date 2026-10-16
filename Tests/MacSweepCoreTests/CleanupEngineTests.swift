import Foundation
import Testing
@testable import MacSweepCore

@Suite struct CleanupEngineTests {
    let home = Fixtures.home
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var old: Date { now.addingTimeInterval(-60 * 86_400) }
    var recent: Date { now.addingTimeInterval(-86_400) }

    func rule(_ id: String, _ target: CleanupTargetSpec, safety: CleanupSafety = .safe) -> CleanupRule {
        CleanupRule(id: id, title: id, detail: "", safety: safety, category: .caches, target: target)
    }

    @Test func pathRuleUsesTreeSize() {
        let tree = Fixtures.dir(home, [Fixtures.dir(home + "/.npm/_cacache", size: 900)])
        let items = CleanupEngine.evaluate(rules: [rule("npm", .paths(["~/.npm/_cacache"]))], tree: tree, home: home)
        #expect(items.count == 1)
        #expect(items.first?.size == 900)
    }

    @Test func pathRuleFallsBackToMeasurement() {
        let tree = Fixtures.dir(home)
        let items = CleanupEngine.evaluate(
            rules: [rule("x", .paths(["/opt/elsewhere"]))], tree: tree, home: home, sizeOf: { $0 == "/opt/elsewhere" ? 42 : nil }
        )
        #expect(items.first?.size == 42)
    }

    @Test func missingAndEmptyTargetsAreDropped() {
        let tree = Fixtures.dir(home, [Fixtures.dir(home + "/.gradle/caches", size: 0)])
        let items = CleanupEngine.evaluate(rules: [rule("g", .paths(["~/.gradle/caches", "~/nope"]))], tree: tree, home: home)
        #expect(items.isEmpty)
    }

    @Test func bytesAreClaimedOnlyOnce() {
        let caches = home + "/Library/Caches"
        let tree = Fixtures.dir(home, [Fixtures.dir(home + "/Library", [Fixtures.dir(caches, [
            Fixtures.dir(caches + "/Homebrew", size: 500),
            Fixtures.dir(caches + "/com.app", size: 200),
        ])])])
        let items = CleanupEngine.evaluate(
            rules: [rule("brew", .paths(["~/Library/Caches/Homebrew"])), rule("all", .contents(of: "~/Library/Caches"))],
            tree: tree, home: home
        )
        #expect(items.map(\.id) == ["brew", "all"])
        #expect(items[1].targets.map(\.path) == [caches + "/com.app"])
    }

    @Test func contentsExcludesNamesAndAggregates() {
        let logs = home + "/Library/Logs"
        let tree = Fixtures.dir(home, [Fixtures.dir(home + "/Library", [Fixtures.dir(logs, [
            Fixtures.dir(logs + "/keep", size: 10),
            Fixtures.dir(logs + "/drop", size: 20),
            FileNode(path: logs, name: "3 smaller items", kind: .aggregate, size: 5),
        ])])])
        let items = CleanupEngine.evaluate(rules: [rule("l", .contents(of: "~/Library/Logs", excluding: ["keep"]))], tree: tree, home: home)
        #expect(items.first?.targets.map(\.path) == [logs + "/drop"])
    }

    @Test func namedRuleHonoursIdleDaysAndSkipsLibrary() {
        let tree = Fixtures.dir(home, [
            Fixtures.dir(home + "/Desktop", [
                Fixtures.dir(home + "/Desktop/old/node_modules", size: 100, modified: old),
                Fixtures.dir(home + "/Desktop/new/node_modules", size: 100, modified: recent),
            ]),
            Fixtures.dir(home + "/Library/x/node_modules", size: 100, modified: old),
        ])
        let items = CleanupEngine.evaluate(rules: [rule("nm", .named(["node_modules"], idleDays: 30))], tree: tree, home: home, now: now)
        #expect(items.first?.targets.map(\.path) == [home + "/Desktop/old/node_modules"])
    }

    @Test func namedRuleDoesNotDescendIntoMatchesOrNodeModules() {
        let tree = Fixtures.dir(home, [Fixtures.dir(home + "/p", [
            Fixtures.dir(home + "/p/.next", [Fixtures.dir(home + "/p/.next/cache/.next", size: 5)]),
            Fixtures.dir(home + "/p/node_modules/pkg/.next", size: 50),
        ])])
        let items = CleanupEngine.evaluate(rules: [rule("n", .named([".next"], idleDays: nil))], tree: tree, home: home)
        #expect(items.first?.targets.map(\.path) == [home + "/p/.next"])
    }

    @Test func namedRuleNeverTouchesEditorExtensions() {
        let tree = Fixtures.dir(home, [
            Fixtures.dir(home + "/.cursor/extensions/codegpt/standalone/.next", size: 30),
            Fixtures.dir(home + "/.vscode/extensions/x/.next", size: 30),
            Fixtures.dir(home + "/tools/extensions/y/.next", size: 30),
            Fixtures.dir(home + "/proj/.next", size: 30),
        ])
        let items = CleanupEngine.evaluate(rules: [rule("n", .named([".next"], idleDays: nil))], tree: tree, home: home)
        #expect(items.first?.targets.map(\.path) == [home + "/proj/.next"])
    }

    @Test func namedRuleMatchesMultiComponentPatterns() {
        let tree = Fixtures.dir(home, [
            Fixtures.dir(home + "/proj/.claude/worktrees", size: 70, modified: old),
            Fixtures.dir(home + "/proj/worktrees", size: 70, modified: old),
        ])
        let items = CleanupEngine.evaluate(rules: [rule("w", .named([".claude/worktrees"], idleDays: 7))], tree: tree, home: home, now: now)
        #expect(items.first?.targets.map(\.path) == [home + "/proj/.claude/worktrees"])
    }

    @Test func filesRuleFiltersExtensionAndAge() {
        let downloads = home + "/Downloads"
        let tree = Fixtures.dir(home, [Fixtures.dir(downloads, [
            Fixtures.file(downloads + "/Old.DMG", size: 10, modified: old),
            Fixtures.file(downloads + "/new.dmg", size: 10, modified: recent),
            Fixtures.file(downloads + "/doc.pdf", size: 10, modified: old),
            Fixtures.file(downloads + "/nodate.zip", size: 10),
        ])])
        let items = CleanupEngine.evaluate(
            rules: [rule("i", .files(in: "~/Downloads", extensions: ["dmg", "zip"], olderThanDays: 14))], tree: tree, home: home, now: now
        )
        #expect(Set(items.first?.targets.map(\.path) ?? []) == [downloads + "/Old.DMG", downloads + "/nodate.zip"])
    }

    @Test func catalogIdsAreUniqueAndPathsStayInHome() {
        let ids = CleanupCatalog.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for rule in CleanupCatalog.rules {
            if case .paths(let paths) = rule.target {
                #expect(paths.allSatisfy { $0.hasPrefix("~/") })
            }
        }
    }

    @Test func catalogTargetsArePermittedByGuard() {
        for rule in CleanupCatalog.rules {
            if case .paths(let paths) = rule.target {
                for path in paths {
                    #expect(PathGuard.canRemove(PathTools.expand(path, home: home), home: home), "\(path)")
                }
            }
        }
    }
}

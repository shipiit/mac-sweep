import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ToolCleanCommandTests {
    let home = "/Users/x"

    @Test func mapsToolCaches() {
        #expect(ToolCleanCommands.command(for: "/Users/x/.npm/_cacache", home: home)?.command == "npm cache clean --force")
        #expect(ToolCleanCommands.command(for: "/Users/x/Library/pnpm/store", home: home)?.tool == "pnpm")
        #expect(ToolCleanCommands.command(for: "/Users/x/Library/Caches/Homebrew", home: home)?.tool == "brew")
        #expect(ToolCleanCommands.command(for: "/Users/x/Library/Containers/com.docker.docker/Data/vms", home: home)?.command == "docker system prune")
        #expect(ToolCleanCommands.command(for: "/Users/x/.npmrc", home: home) == nil, "prefix must match a whole component")
        #expect(ToolCleanCommands.command(for: "/Users/x/Library/Developer/Xcode/DerivedData", home: home) == nil)
        #expect(ToolCleanCommands.command(for: "/opt/.npm", home: home) == nil)
    }

    @Test func scriptUsesToolCommandsOnceAndCommentsReviewItems() {
        let script = CleanupScript.make([
            CleanupTarget(path: "/Users/x/.npm/_cacache", size: 2_000_000_000),
            CleanupTarget(path: "/Users/x/.npm/_npx", size: 1_000_000),
            CleanupTarget(path: "/Users/x/Library/Developer/Xcode/DerivedData", size: 500_000_000),
            CleanupTarget(path: "/Users/x/Library/Containers/com.docker.docker/Data/vms", size: 9_000_000_000),
        ], home: home, reviewFirst: ["/Users/x/Library/Containers/com.docker.docker/Data/vms"])
        #expect(script.components(separatedBy: "npm cache clean --force").count == 2, "one npm command for both npm paths")
        #expect(script.contains("command -v npm >/dev/null && npm cache clean --force"))
        #expect(script.contains("rm -rf -- '/Users/x/Library/Developer/Xcode/DerivedData'"))
        #expect(script.contains("# REVIEW command -v docker >/dev/null && docker system prune"))
        #expect(!script.contains("rm -rf -- '/Users/x/Library/Containers"))
    }

    @Test func emptyScriptAndRefusedPaths() {
        let script = CleanupScript.make([CleanupTarget(path: "/System/Library", size: 1)], home: home)
        #expect(script.contains("0 locations") && !script.contains("rm -rf --"))
    }
}

@Suite struct SizeHistoryTests {
    @Test func recordsAndComparesScans() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let history = SizeHistory(url: URL(fileURLWithPath: root + "/sizes.csv"))
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(86_400)
        #expect(history.previous(before: second).isEmpty)
        try history.record(["/a": 100, "/b,with,commas": 50], at: first)
        try history.record(["/a": 999], at: first)
        try history.record(["/a": 300], at: second)
        #expect(history.previous(before: second) == ["/a": 100, "/b,with,commas": 50])
        #expect(history.previous(before: second.addingTimeInterval(1)) == ["/a": 300, "/b,with,commas": 50])
        #expect(history.previous(before: first).isEmpty)
        try history.record([:], at: second.addingTimeInterval(5))
    }

    @Test func toleratesGarbage() {
        #expect(SizeHistory.parse("nonsense\n2026,abc,/x\n\n,1,\n2026,5,\n", before: "9999").isEmpty)
        #expect(SizeHistory.parse("", before: "9999").isEmpty)
        #expect(SizeHistory.parse("2026-01-01T00:00:00Z,5,/p", before: "2025").isEmpty)
    }
}

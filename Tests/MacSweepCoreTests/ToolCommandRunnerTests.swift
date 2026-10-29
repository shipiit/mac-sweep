import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ToolCommandRunnerTests {
    let home = "/Users/x"

    @Test func plansDistinctNonReviewCommands() {
        let targets = [CleanupTarget(path: "/Users/x/.npm/_cacache", size: 9), CleanupTarget(path: "/Users/x/.npm/_npx", size: 5),
                       CleanupTarget(path: "/Users/x/Library/pnpm/store", size: 7), CleanupTarget(path: "/Users/x/Library/Caches/Homebrew", size: 3),
                       CleanupTarget(path: "/Users/x/Library/Developer/Xcode/DerivedData", size: 100)]
        let plan = ToolCleanCommands.plan(targets, home: home, reviewFirst: ["/Users/x/Library/pnpm/store"])
        #expect(plan.map(\.tool) == ["npm", "brew"])
        #expect(ToolCleanCommands.plan([], home: home, reviewFirst: []).isEmpty)
    }

    @Test func runsAndStreamsLines() async {
        let lines = Collected()
        let outcome = await ToolCommandRunner.run(.init(tool: "printf", command: "printf 'one\\ntwo\\nthree'"), home: NSTemporaryDirectory()) { lines.add($0) }
        #expect(outcome == .finished(status: 0))
        #expect(lines.all == ["one", "two", "three"])
    }

    @Test func reportsMissingToolAndFailures() async {
        #expect(await ToolCommandRunner.run(.init(tool: "definitely-not-a-tool-xyz", command: "definitely-not-a-tool-xyz clean"), home: NSTemporaryDirectory()) { _ in } == .toolMissing)
        #expect(await ToolCommandRunner.run(.init(tool: "sh", command: "exit 3"), home: NSTemporaryDirectory()) { _ in } == .finished(status: 3))
        #expect(await ToolCommandRunner.run(.init(tool: "sleep", command: "sleep 5"), home: NSTemporaryDirectory(), timeout: 0.3) { _ in } == .timedOut)
    }

    @Test func searchPathPrefersNewestNode() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        for version in ["v18.20.0", "v22.15.0", "v20.1.0"] {
            try FileManager.default.createDirectory(atPath: home + "/.nvm/versions/node/\(version)/bin", withIntermediateDirectories: true)
        }
        #expect(ToolCommandRunner.searchPath(home: home).hasPrefix(home + "/.nvm/versions/node/v22.15.0/bin:"))
        #expect(ToolCommandRunner.searchPath(home: "/nowhere").hasPrefix("/opt/homebrew/bin"))
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

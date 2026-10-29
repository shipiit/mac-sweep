import Foundation
import Testing
@testable import MacSweepCore

@Suite struct GitSlimmingRepoTests {
    /// `/usr/bin/git` is only a stub until the developer tools are installed.
    private static let gitAvailable = ((try? Shell.runBlocking("/usr/bin/xcode-select", ["-p"]))?.status ?? 1) == 0

    @Test func findsReposWithoutDescendingIntoThem() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/code/app/.git/HEAD", bytes: 1)
        try Fixtures.write(home + "/code/app/vendor/lib/.git/HEAD", bytes: 1)
        try Fixtures.write(home + "/code/mono/packages/web/.git/HEAD", bytes: 1)
        try Fixtures.write(home + "/.config/nvim/.git/HEAD", bytes: 1)
        try Fixtures.write(home + "/code/worktree/.git", bytes: 1)
        for skipped in ["Library", ".Trash", "node_modules", "Pictures", "Music", "Movies", ".vscode", ".cursor", "Tool.app"] {
            try Fixtures.write(home + "/\(skipped)/repo/.git/HEAD", bytes: 1)
        }
        try Fixtures.write(home + "/a/b/c/d/e/f/g/.git/HEAD", bytes: 1)
        try Fixtures.write(home + "/a/b/c/d/e/f/g/h/.git/HEAD", bytes: 1)
        try FileManager.default.createSymbolicLink(atPath: home + "/link", withDestinationPath: home + "/code")

        let found = GitRepoFinder.find(roots: [home])
        #expect(found == [
            home + "/.config/nvim",
            home + "/a/b/c/d/e/f/g",
            home + "/code/app",
            home + "/code/mono/packages/web",
        ])
        #expect(GitRepoFinder.find(roots: [home], maxDepth: 2) == [home + "/.config/nvim", home + "/code/app"])
    }

    @Test func rootThatIsARepoAndMissingRoots() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/.git/HEAD", bytes: 1)
        try Fixtures.write(root + "/inner/.git/HEAD", bytes: 1)
        #expect(GitRepoFinder.find(roots: [root]) == [root])
        #expect(GitRepoFinder.find(roots: [root + "/missing"]).isEmpty)
        #expect(GitRepoFinder.find(roots: []).isEmpty)
        #expect(GitRepoFinder.find(roots: [root, root]) == [root])
    }

    @Test func detectsIndexLock() throws {
        let repo = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try Fixtures.write(repo + "/.git/HEAD", bytes: 1)
        #expect(!GitRepoFinder.isInUse(repo: repo))
        try Fixtures.write(repo + "/.git/index.lock", bytes: 0)
        #expect(GitRepoFinder.isInUse(repo: repo))
    }

    @Test(.enabled(if: gitAvailable)) func inspectsAndCompactsARealRepo() async throws {
        let repo = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try run(repo, ["init", "--quiet"])
        for index in 0..<3 {
            try Data(repeating: UInt8(index), count: 4096).write(to: URL(fileURLWithPath: repo + "/file\(index).bin"))
            try run(repo, ["add", "."])
            try run(repo, ["commit", "--quiet", "-m", "commit \(index)"])
        }
        try Fixtures.write(repo + "/dirty.txt", bytes: 3)

        let info = await GitClient.inspect(repo: repo)
        #expect(!info.isInUse)
        #expect(info.hasUncommittedWork == true)
        let lastCommit = try #require(info.lastCommit)
        #expect(abs(lastCommit.timeIntervalSinceNow) < 600)
        let objects = try #require(info.objects)
        // Three distinct blobs, three trees, three commits.
        #expect(objects.looseCount == 9)
        #expect(objects.packs == 0)
        #expect((info.gitSize ?? 0) > 0)
        #expect((info.totalSize ?? 0) > (info.gitSize ?? 0))

        let report = try await GitClient.compact(repo: repo)
        #expect(report.before > 0)
        let after = await GitClient.inspect(repo: repo)
        #expect(after.objects?.looseCount == 0)
        #expect(after.objects?.packs == 1)
        #expect(after.lastCommit == info.lastCommit)
    }

    @Test(.enabled(if: gitAvailable)) func emptyRepoHasNoCommitDate() async throws {
        let repo = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try run(repo, ["init", "--quiet"])
        let info = await GitClient.inspect(repo: repo)
        #expect(info.lastCommit == nil)
        #expect(info.hasUncommittedWork == false)
        #expect(info.objects?.looseCount == 0)
    }

    @Test(.enabled(if: gitAvailable)) func skipsRepoWithIndexLock() async throws {
        let repo = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try run(repo, ["init", "--quiet"])
        try Fixtures.write(repo + "/.git/index.lock", bytes: 0)
        let info = await GitClient.inspect(repo: repo)
        #expect(info.isInUse)
        #expect(info.objects == nil)
        #expect(info.hasUncommittedWork == nil)
        #expect((info.gitSize ?? 0) > 0)
        await #expect(throws: GitSlimmingError.inUse((repo as NSString).lastPathComponent)) {
            try await GitClient.compact(repo: repo)
        }
    }

    private func run(_ repo: String, _ arguments: [String]) throws {
        let base = ["-C", repo, "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"]
        let result = try Shell.runBlocking("/usr/bin/git", base + arguments)
        guard result.status == 0 else { throw DevCommandError.failed(result.stderr) }
    }
}

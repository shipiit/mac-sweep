import Foundation
import Testing
@testable import MacSweepCore

@Suite struct GitSlimmingParserTests {
    @Test func parsesCountObjects() throws {
        let output = """
        count: 120
        size: 480
        in-pack: 5321
        packs: 3
        size-pack: 20480
        prune-packable: 0
        garbage: 1
        size-garbage: 4
        """
        let stats = try #require(GitOutputParser.countObjects(output))
        #expect(stats == GitObjectStats(looseCount: 120, looseSize: 480 * 1024, packedCount: 5321, packs: 3,
                                        packSize: 20480 * 1024, garbageCount: 1, garbageSize: 4096))
        #expect(stats.wouldBenefitFromCompact)
    }

    @Test func countObjectsToleratesPartialAndOddOutput() throws {
        let partial = try #require(GitOutputParser.countObjects("warning: something\r\ncount: 2\nsize: abc\n  packs :  1 \nunknown: 9"))
        #expect(partial.looseCount == 2)
        #expect(partial.looseSize == 0)
        #expect(partial.packs == 1)
        #expect(!partial.wouldBenefitFromCompact)
    }

    @Test func countObjectsRejectsEmptyAndGarbage() {
        #expect(GitOutputParser.countObjects("") == nil)
        #expect(GitOutputParser.countObjects("\n\n") == nil)
        #expect(GitOutputParser.countObjects("fatal: not a git repository (or any of the parent directories): .git") == nil)
        #expect(GitOutputParser.countObjects("count: -1\nsize: 1.5") == nil)
        #expect(GitOutputParser.countObjects("unknown: 4") == nil)
    }

    @Test func countObjectsClampsHugeSizes() throws {
        let stats = try #require(GitOutputParser.countObjects("size-pack: \(UInt64.max)"))
        #expect(stats.packSize == UInt64.max)
    }

    @Test func compactBenefitThresholds() {
        #expect(!GitObjectStats().wouldBenefitFromCompact)
        #expect(!GitObjectStats(looseCount: 99, packs: 1).wouldBenefitFromCompact)
        #expect(GitObjectStats(looseCount: 100).wouldBenefitFromCompact)
        #expect(GitObjectStats(packs: 2).wouldBenefitFromCompact)
        #expect(GitObjectStats(garbageCount: 1).wouldBenefitFromCompact)
    }

    @Test func parsesCommitDate() {
        #expect(GitOutputParser.commitDate("1700000000\n") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(GitOutputParser.commitDate("") == nil)
        #expect(GitOutputParser.commitDate("0") == nil)
        #expect(GitOutputParser.commitDate("-5") == nil)
        #expect(GitOutputParser.commitDate("fatal: your current branch 'main' does not have any commits yet") == nil)
    }

    @Test func detectsUncommittedWork() {
        #expect(!GitOutputParser.hasUncommittedWork(""))
        #expect(!GitOutputParser.hasUncommittedWork("\n  \n"))
        #expect(GitOutputParser.hasUncommittedWork(" M Sources/a.swift\n"))
        #expect(GitOutputParser.hasUncommittedWork("?? new.txt"))
    }

    @Test func compactReportNeverNegative() {
        let shrunk = GitCompactReport(before: 1000, after: 400)
        #expect(shrunk.saved == 600)
        #expect(shrunk.savedFraction == 0.6)
        let grew = GitCompactReport(before: 400, after: 1000)
        #expect(grew.saved == 0)
        #expect(grew.savedFraction == 0)
        let empty = GitCompactReport(before: 0, after: 0)
        #expect(empty.saved == 0)
        #expect(empty.savedFraction == 0)
    }

    @Test func ranksByGitSizeWithUnmeasuredLast() {
        let repos = [
            GitRepoInfo(path: "/b", gitSize: 10, totalSize: 20),
            GitRepoInfo(path: "/u"),
            GitRepoInfo(path: "/a", gitSize: 10, totalSize: 50),
            GitRepoInfo(path: "/c", gitSize: 500, totalSize: 600),
            GitRepoInfo(path: "/t"),
        ]
        #expect(GitRepoRanking.sorted(repos).map(\.path) == ["/c", "/a", "/b", "/t", "/u"])
        #expect(GitRepoRanking.top(repos, limit: 2).map(\.path) == ["/c", "/a"])
        #expect(GitRepoRanking.top(repos, limit: 0).isEmpty)
        #expect(GitRepoRanking.top(repos, limit: -1).isEmpty)
        #expect(GitRepoRanking.top([], limit: 5).isEmpty)
        #expect(GitRepoRanking.totalGitSize(repos) == 520)
    }

    @Test func derivesWorkingTreeAndShare() {
        let repo = GitRepoInfo(path: "/Users/test/code/app", gitSize: 300, totalSize: 1200)
        #expect(repo.name == "app")
        #expect(repo.workingTreeSize == 900)
        #expect(repo.gitShare == 0.25)
        #expect(GitRepoInfo(path: "/x", gitSize: 10, totalSize: 5).workingTreeSize == 0)
        #expect(GitRepoInfo(path: "/x", gitSize: 10, totalSize: 5).gitShare == 1)
        #expect(GitRepoInfo(path: "/x", gitSize: 0, totalSize: 0).gitShare == nil)
        #expect(GitRepoInfo(path: "/x", gitSize: 10).workingTreeSize == nil)
        #expect(GitRepoInfo(path: "/x").gitShare == nil)
    }

    @Test func locatesLFSOnlyWhenInstalled() {
        #expect(GitClient.lfsPath(isExecutable: { _ in false }) == nil)
        #expect(GitClient.lfsPath(isExecutable: { $0 == "/usr/local/bin/git-lfs" }) == "/usr/local/bin/git-lfs")
    }
}

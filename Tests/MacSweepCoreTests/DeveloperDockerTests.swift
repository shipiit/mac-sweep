import Foundation
import Testing
@testable import MacSweepCore

@Suite struct HumanSizeTests {
    @Test func parsesDecimalUnits() {
        #expect(HumanSize.parse("0B") == 0)
        #expect(HumanSize.parse("512B") == 512)
        #expect(HumanSize.parse("12.3kB") == 12_300)
        #expect(HumanSize.parse("1.5MB") == 1_500_000)
        #expect(HumanSize.parse("2.2GB") == 2_200_000_000)
        #expect(HumanSize.parse("1TB") == 1_000_000_000_000)
        #expect(HumanSize.parse(" 34.6 MB ") == 34_600_000)
    }

    @Test func parsesBinaryUnitsAndPercentSuffix() {
        #expect(HumanSize.parse("1KiB") == 1024)
        #expect(HumanSize.parse("2GiB") == 2_147_483_648)
        #expect(HumanSize.parse("1.2GB (50%)") == 1_200_000_000)
        #expect(HumanSize.parse("0B (0%)") == 0)
    }

    @Test func rejectsGarbage() {
        #expect(HumanSize.parse("") == nil)
        #expect(HumanSize.parse("GB") == nil)
        #expect(HumanSize.parse("12XB") == nil)
        #expect(HumanSize.parse("-5MB") == nil)
        #expect(HumanSize.parse("N/A") == nil)
        #expect(HumanSize.parse("1e999GB") == nil)
    }
}

@Suite struct ToolLocatorTests {
    @Test func picksFirstExecutable() {
        #expect(ToolLocator.first(["/a", "/b", "/c"]) { $0 != "/a" } == "/b")
        #expect(ToolLocator.first(["/a"]) { _ in false } == nil)
        #expect(ToolLocator.first([]) { _ in true } == nil)
    }

    @Test func safeIdentifiers() {
        #expect(ToolLocator.isSafeIdentifier("postgresql@16"))
        #expect(ToolLocator.isSafeIdentifier("homebrew.mxcl.redis"))
        #expect(!ToolLocator.isSafeIdentifier(""))
        #expect(!ToolLocator.isSafeIdentifier("--all"))
        #expect(!ToolLocator.isSafeIdentifier("redis; rm -rf ~"))
        #expect(!ToolLocator.isSafeIdentifier("name with space"))
        #expect(!ToolLocator.isSafeIdentifier("pöstgres"))
        #expect(!ToolLocator.isSafeIdentifier(String(repeating: "a", count: 201)))
    }

    @Test func brewIsWrappedWithQuietEnvironment() {
        let arguments = DevShell.brewArguments("/opt/homebrew/bin/brew", ["outdated"])
        #expect(arguments.first == "HOMEBREW_NO_AUTO_UPDATE=1")
        #expect(arguments.suffix(2) == ["/opt/homebrew/bin/brew", "outdated"])
    }

    @Test func timeoutFiresForSlowCommand() async {
        await #expect(throws: DevCommandError.timedOut("sleep")) {
            _ = try await DevShell.run("/bin/sleep", ["2"], timeout: 0.1, tool: "sleep")
        }
    }

    @Test func fastCommandReturnsBeforeTimeout() async throws {
        let result = try await DevShell.run("/bin/echo", ["hi"], timeout: 10, tool: "echo")
        #expect(result.stdout == "hi\n" && result.status == 0)
    }
}

@Suite struct DockerParserTests {
    let summary = """
    {"Active":"2","Reclaimable":"1.2GB (50%)","Size":"2.4GB","TotalCount":"5","Type":"Images"}
    {"Active":"1","Reclaimable":"0B (0%)","Size":"12.5kB","TotalCount":"3","Type":"Containers"}
    {"Active":"0","Reclaimable":"300MB (100%)","Size":"300MB","TotalCount":"2","Type":"Local Volumes"}
    {"Active":"0","Reclaimable":"800MB","Size":"800MB","TotalCount":"40","Type":"Build Cache"}
    """

    @Test func parsesSummaryLines() {
        let rows = DockerParser.parseSummary(summary)
        #expect(rows.map(\.kind) == [.images, .containers, .volumes, .buildCache])
        #expect(rows[0].total == 5 && rows[0].active == 2 && rows[0].size == 2_400_000_000 && rows[0].reclaimable == 1_200_000_000)
        let usage = DockerUsage(rows: rows)
        #expect(usage.totalSize == 2_400_000_000 + 12_500 + 300_000_000 + 800_000_000)
        #expect(usage.totalReclaimable == 1_200_000_000 + 300_000_000 + 800_000_000)
        #expect(usage.row(.buildCache)?.total == 40)
    }

    @Test func acceptsArrayFormAndNumericFields() {
        let rows = DockerParser.parseSummary(#"[{"Type":"Build Cache","TotalCount":3,"Active":0,"Size":1000,"Reclaimable":"1kB"}]"#)
        #expect(rows == [DockerUsageRow(kind: .buildCache, total: 3, active: 0, size: 1000, reclaimable: 1000)])
    }

    @Test func summaryIgnoresGarbageAndUnknownTypes() {
        #expect(DockerParser.parseSummary("").isEmpty)
        #expect(DockerParser.parseSummary("not json\n{broken").isEmpty)
        #expect(DockerParser.parseSummary(#"{"Type":"Networks","Size":"1GB"}"#).isEmpty)
        let partial = DockerParser.parseSummary("junk\n" + #"{"Type":"Images"}"#)
        #expect(partial == [DockerUsageRow(kind: .images, total: 0, active: 0, size: 0, reclaimable: 0)])
    }

    @Test func parsesVerbose() {
        let json = """
        {"Images":[{"ID":"sha256:aaa","Repository":"nginx","Tag":"latest","Size":"187MB","Containers":"1","CreatedSince":"2 weeks ago"},
                   {"ID":"sha256:bbbbbbbbbbbbbbbbbbbbbbbb","Repository":"<none>","Tag":"<none>","Size":"1.1GB","Containers":"0","CreatedSince":"3 months ago"}],
         "Containers":[{"ID":"c1","Names":"web","Image":"nginx","State":"running","Status":"Up 2 hours","Size":"2kB"}],
         "Volumes":[{"Name":"pgdata","Links":"0","Size":"300MB"},{"Name":"used","Links":1,"Size":"1MB"}],
         "BuildCache":[]}
        """
        let detail = DockerParser.parseVerbose(json)
        #expect(detail.images.map(\.repository) == ["<none>", "nginx"])
        #expect(detail.images[0].isDangling && !detail.images[1].isDangling)
        #expect(detail.images[1].displayName == "nginx:latest")
        #expect(detail.images[0].displayName.hasPrefix("<untagged> sha256:"))
        #expect(detail.containers.first?.isRunning == true && detail.containers.first?.name == "web")
        #expect(detail.volumes.map(\.name) == ["pgdata", "used"])
        #expect(detail.volumes[0].isUnused && !detail.volumes[1].isUnused)
        let usage = DockerUsage(images: detail.images)
        #expect(usage.danglingImages.count == 1)
    }

    @Test func verboseEmptyAndGarbage() {
        #expect(DockerParser.parseVerbose("").images.isEmpty)
        #expect(DockerParser.parseVerbose("[]").volumes.isEmpty)
        #expect(DockerParser.parseVerbose(#"{"Images":"nope"}"#).images.isEmpty)
    }

    @Test func daemonDownDetection() {
        #expect(DockerParser.isDaemonDown("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"))
        #expect(DockerParser.isDaemonDown("error during connect: connection refused"))
        #expect(!DockerParser.isDaemonDown("permission denied"))
        #expect(!DockerParser.isDaemonDown(""))
    }

    @Test func reclaimedFooter() {
        #expect(DockerClient.parseReclaimed("Deleted Images:\nuntagged: x\n\nTotal reclaimed space: 1.234GB\n") == 1_234_000_000)
        #expect(DockerClient.parseReclaimed("Total: 3") == 0)
        #expect(DockerClient.parseReclaimed("") == 0)
    }

    @Test func pruneArgumentsAreNonInteractive() {
        #expect(DockerPrune.danglingImages.arguments == ["image", "prune", "--force"])
        #expect(DockerPrune.buildCache.arguments == ["builder", "prune", "--force"])
    }

    @Test func socketAndExecutableCandidatesUseHome() {
        #expect(DockerClient.executableCandidates(home: "/Users/t").contains("/Users/t/.orbstack/bin/docker"))
        #expect(DockerClient.hasSocket(home: "/Users/t") { $0 == "/Users/t/.colima/default/docker.sock" })
        #expect(!DockerClient.hasSocket(home: "/Users/t") { _ in false })
    }
}

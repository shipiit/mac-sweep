import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ImpactKnowledgeTests {
    let home = Fixtures.home

    @Test(arguments: [
        ("/Users/test/Library/Application Support/Claude/vm_bundles/claudevm.bundle/sessiondata.img", DeletionRisk.caution, "Claude"),
        ("/Users/test/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/2025.8.8.1141/weights.bin", .safe, "Gemini"),
        ("/Users/test/.claude/projects/-Users-test-proj/4dab2cbb.jsonl", .caution, "Claude Code"),
        ("/Users/test/.nvm/versions/node/v22.15.0/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe", .keep, "Claude Code"),
        ("/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", .keep, "Docker"),
        ("/Users/test/Downloads/Setup.dmg", .safe, "installer"),
        ("/Users/test/Movies/trip.mp4", .caution, "video"),
        ("/Users/test/Library/Caches/com.spotify.client", .safe, "cache"),
        ("/Users/test/proj/.git", .keep, "Git"),
    ])
    func explainsKnownItems(path: String, risk: DeletionRisk, mentions: String) throws {
        let explanation = try #require(ImpactKnowledge.explain(path: path, home: home))
        #expect(explanation.risk == risk)
        #expect((explanation.summary + explanation.ifDeleted).localizedCaseInsensitiveContains(mentions))
        #expect(!explanation.ifDeleted.isEmpty)
    }

    @Test func specificRulesBeatGenericOnes() {
        let path = home + "/Library/Application Support/Claude/vm_bundles/x/rootfs.img"
        #expect(ImpactKnowledge.explain(path: path, home: home)?.summary.contains("Claude") == true)
    }

    @Test func fallsBackToFolderKnowledge() {
        let explanation = ImpactKnowledge.explain(path: home + "/.pyenv", home: home)
        #expect(explanation?.risk == .caution)
        #expect(explanation?.summary.contains("pyenv") == true)
    }

    @Test func unknownReturnsNil() {
        #expect(ImpactKnowledge.explain(path: home + "/random/thing", home: home) == nil)
        #expect(ImpactKnowledge.explain(path: "", home: home) == nil)
    }

    @Test func everyRuleHasContent() {
        for rule in ImpactKnowledge.rules {
            #expect(!rule.explanation.summary.isEmpty && !rule.explanation.ifDeleted.isEmpty)
        }
    }
}

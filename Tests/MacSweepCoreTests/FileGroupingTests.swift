import Testing
@testable import MacSweepCore

@Suite struct FileGroupingTests {
    let home = "/Users/x"

    @Test(arguments: [
        ("/Users/x/.claude/projects/a/b.jsonl", FileGroup.ai),
        ("/Users/x/Library/Application Support/Claude/vm_bundles/x.img", .ai),
        ("/Users/x/work/model.safetensors", .ai),
        ("/Users/x/.vscode/extensions/a/bin", .developer),
        ("/Users/x/Documents/proj/.git/objects/pack/p.pack", .developer),
        ("/Users/x/Library/Developer/Xcode/DerivedData/x", .developer),
        ("/Users/x/Downloads/movie.mp4", .downloads),
        ("/Users/x/Documents/setup.dmg", .downloads),
        ("/Users/x/Library/Caches/Google/x", .system),
        ("/Users/x/Pictures/Photos Library.photoslibrary/database/Photos.sqlite", .media),
        ("/Users/x/Desktop/clip.mov", .media),
        ("/Users/x/Library/Application Support/Slack/x.db", .appData),
        ("/Users/x/Documents/report.pdf", .documents),
        ("/Users/x/random/file.bin", .other),
    ])
    func groups(path: String, group: FileGroup) {
        #expect(FileGroup.of(path: path, home: home) == group)
    }

    @Test func everyGroupHasASymbol() {
        #expect(Set(FileGroup.allCases.map(\.symbol)).count == FileGroup.allCases.count)
    }
}

@Suite struct ToolKnowledgeTests {
    let home = "/Users/x"

    @Test(arguments: [
        ("/Users/x/Documents/p/.git/objects/pack/pack-1.pack", DeletionRisk.keep),
        ("/Users/x/.local/share/claude/versions/2.1.119", .safe),
        ("/Users/x/.cache/codex-runtimes/codex-runtime-install-abc/node.tar.xz", .safe),
        ("/Users/x/.cache/codex-runtimes/codex-primary-runtime/bin", .caution),
        ("/Users/x/.vscode/extensions/anthropic.claude-code-2.1.3/native-binary/claude", .caution),
        ("/Users/x/.roboflow/models/rf-detr-small.pth", .caution),
        ("/Users/x/work/weights.gguf", .caution),
        ("/Users/x/.cache/whatever/blob", .safe),
    ])
    func explains(path: String, risk: DeletionRisk) {
        #expect(ImpactKnowledge.explain(path: path, home: home)?.risk == risk)
    }
}

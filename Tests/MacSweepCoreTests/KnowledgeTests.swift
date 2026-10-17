import Foundation
import Testing
@testable import MacSweepCore

@Suite struct FolderKnowledgeTests {
    let home = Fixtures.home

    @Test func describesWellKnownHomeFolders() {
        #expect(FolderKnowledge.describe(path: home + "/.nvm", home: home)?.contains("nvm") == true)
        #expect(FolderKnowledge.describe(path: home + "/Library/Caches", home: home) != nil)
        #expect(FolderKnowledge.describe(path: home, home: home) == "Your home folder.")
    }

    @Test func fallsBackToFolderName() {
        #expect(FolderKnowledge.describe(path: home + "/Desktop/app/node_modules", home: home)?.contains("npm install") == true)
        #expect(FolderKnowledge.describe(path: "/opt/x/.next", home: home) != nil)
    }

    @Test func describesContainersAndAppSupportChildren() {
        #expect(FolderKnowledge.describe(path: home + "/Library/Containers/com.apple.mail", home: home)?.contains("sandboxed") == true)
        #expect(FolderKnowledge.describe(path: home + "/Library/Application Support/Slack", home: home)?.contains("app keeps") == true)
    }

    @Test func describesBundles() {
        #expect(FolderKnowledge.describe(path: "/Applications/Foo.app", home: home)?.contains("application") == true)
        #expect(FolderKnowledge.describe(path: home + "/Pictures/Photos Library.photoslibrary", home: home)?.contains("Photos") == true)
    }

    @Test func explainsFilesByNameExtensionAndNvmGlobals() {
        let claude = home + "/.nvm/versions/node/v22.15.0/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
        #expect(FolderKnowledge.describe(path: claude, home: home)?.contains("Claude Code") == true)
        #expect(FolderKnowledge.describe(path: home + "/.nvm/versions/node/v22.15.0/lib/node_modules/typescript", home: home)?.contains("global npm") == true)
        #expect(FolderKnowledge.describe(path: home + "/Downloads/Setup.DMG", home: home)?.contains("installer") == true)
        #expect(FolderKnowledge.describe(path: home + "/models/llama.gguf", home: home)?.contains("LLM") == true)
        #expect(FolderKnowledge.describe(path: home + "/x/Docker.raw", home: home)?.contains("Docker") == true)
    }

    @Test func unknownPathReturnsNil() {
        #expect(FolderKnowledge.describe(path: home + "/random/thing", home: home) == nil)
        #expect(FolderKnowledge.describe(path: "", home: home) == nil)
    }
}

@Suite struct NestedRuleTests {
    @Test func matchesNamedGrandchildrenOnly() {
        let support = Fixtures.home + "/Library/Application Support"
        let tree = Fixtures.dir(Fixtures.home, [Fixtures.dir(Fixtures.home + "/Library", [Fixtures.dir(support, [
            Fixtures.dir(support + "/Slack", [
                Fixtures.dir(support + "/Slack/Cache", size: 100),
                Fixtures.dir(support + "/Slack/IndexedDB", size: 100),
            ]),
            Fixtures.dir(support + "/Discord", [Fixtures.dir(support + "/Discord/Code Cache", size: 50)]),
            Fixtures.file(support + "/Cache", size: 10),
        ])])])
        let rule = CleanupRule(id: "e", title: "e", detail: "", safety: .safe, category: .caches,
                               target: .nested(in: "~/Library/Application Support", names: ["Cache", "Code Cache"], signature: []))
        let items = CleanupEngine.evaluate(rules: [rule], tree: tree, home: Fixtures.home)
        #expect(Set(items.first?.targets.map(\.path) ?? []) == [support + "/Slack/Cache", support + "/Discord/Code Cache"])
    }

    @Test func signatureExcludesNonChromiumApps() {
        let support = Fixtures.home + "/Library/Application Support"
        let tree = Fixtures.dir(Fixtures.home, [Fixtures.dir(Fixtures.home + "/Library", [Fixtures.dir(support, [
            Fixtures.dir(support + "/Slack", [Fixtures.dir(support + "/Slack/Cache", size: 100)]),
            Fixtures.dir(support + "/OfflineApp", [Fixtures.dir(support + "/OfflineApp/Cache", size: 100)]),
        ])])])
        let rule = CleanupRule(id: "e", title: "e", detail: "", safety: .safe, category: .caches,
                               target: .nested(in: "~/Library/Application Support", names: ["Cache"], signature: ["Code Cache"]))
        let items = CleanupEngine.evaluate(rules: [rule], tree: tree, home: Fixtures.home,
                                           pathExists: { $0 == support + "/Slack/Code Cache" })
        #expect(items.first?.targets.map(\.path) == [support + "/Slack/Cache"])
    }

    @Test func safeRulesNeverIncludeBrowsersOrHardLinkedStores() {
        let safePaths = CleanupCatalog.rules.filter { $0.safety == .safe }.flatMap { rule -> [String] in
            if case .paths(let paths) = rule.target { return paths }
            return []
        }
        #expect(!safePaths.contains { $0.contains("puppeteer") || $0.contains("playwright") || $0.contains("pnpm") })
    }

    @Test func missingBaseYieldsNothing() {
        let rule = CleanupRule(id: "e", title: "e", detail: "", safety: .safe, category: .caches, target: .nested(in: "~/Nope", names: ["Cache"], signature: []))
        #expect(CleanupEngine.evaluate(rules: [rule], tree: Fixtures.dir(Fixtures.home), home: Fixtures.home).isEmpty)
    }
}

@Suite struct CleanupScriptTests {
    @Test func quotesPathsAndSkipsProtected() {
        let script = CleanupScript.make([
            CleanupTarget(path: Fixtures.home + "/.npm/_cacache", size: 2_000),
            CleanupTarget(path: Fixtures.home + "/it's $(here)", size: 1_000),
            CleanupTarget(path: Fixtures.home + "/.ssh", size: 5_000),
        ], home: Fixtures.home)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("npm cache clean --force"), "tool-managed caches use the tool's command")
        #expect(script.contains("rm -rf -- '/Users/test/it'\\''s $(here)'"))
        #expect(!script.contains(".ssh"))
        #expect(script.contains("2 locations"))
    }

    @Test func emptySelectionStillProducesValidHeader() {
        let script = CleanupScript.make([], home: Fixtures.home)
        #expect(script.contains("0 locations"))
        #expect(!script.contains("rm -rf"))
    }
}

import Foundation
import Testing
@testable import MacSweepCore

@Suite struct PostgresDatabasesTests {
    @Test func findsServersAndDefaultPort() {
        let ps = """
        /opt/homebrew/opt/postgresql@14/bin/postgres -D /opt/homebrew/var/postgresql@14
        /opt/homebrew/Cellar/postgresql@17/17.11/bin/postgres -D /opt/homebrew/var/postgresql@17 -p 5433
        postgres: checkpointer
        /usr/bin/grep postgres
        """
        let servers = PostgresDatabases.servers(psOutput: ps)
        #expect(servers.map(\.port) == [5432, 5433])
        #expect(servers[0].binDirectory == "/opt/homebrew/opt/postgresql@14/bin")
        #expect(servers[1].name == "postgresql@17")
        #expect(PostgresDatabases.servers(psOutput: "").isEmpty)
        #expect(PostgresDatabases.servers(psOutput: "/x/bin/postgres -D").isEmpty)
    }

    @Test func parsesRowsAndMarksSystemAndInUse() {
        let rows = "cache_new\t3570787107\t0\npostgres\t7804595\t1\napp\t100\t2\nbroken\tx\t0\n\t5\t0\n"
        let databases = PostgresDatabases.parse(rows, port: 5432)
        #expect(databases.map(\.name) == ["cache_new", "postgres", "app"])
        #expect(databases[0].kind == .unreferenced && databases[0].size == 3_570_787_107)
        #expect(databases[1].kind == .system && !databases[1].isRemovable)
        #expect(databases[2].kind == .inUse && !databases[2].isRemovable)
    }

    @Test func classifiesReferencedTestAndUnreferenced() {
        let databases = PostgresDatabases.parse("proofline\t10\t0\ntest_proofline\t20\t0\ntest_used\t5\t0\nold_copy\t30\t0\nlive\t1\t3\n", port: 5432)
        let refs = ["proofline": ["work/proofline/.env"], "test_used": ["work/app/settings.py"], "live": ["x/.env"]]
        let kinds = Dictionary(uniqueKeysWithValues: PostgresDatabases.classify(databases, references: refs).map { ($0.name, $0) })
        #expect(kinds["proofline"]?.kind == .referenced && kinds["proofline"]?.referencedBy == ["work/proofline/.env"])
        #expect(kinds["test_proofline"]?.kind == .test)
        #expect(kinds["test_used"]?.kind == .referenced)
        #expect(kinds["old_copy"]?.kind == .unreferenced)
        #expect(kinds["live"]?.kind == .inUse)
        #expect(PostgresDatabases.classify([], references: refs).isEmpty)
    }

    @Test func refusesToDropSystemOrInUseOrWrongServer() async {
        let server = PostgresServer(binDirectory: "/nonexistent", dataDirectory: "/d", port: 5432)
        let system = PostgresDatabase(name: "postgres", size: 1, connections: 0, port: 5432, kind: .system)
        let busy = PostgresDatabase(name: "app", size: 1, connections: 1, port: 5432, kind: .inUse)
        let other = PostgresDatabase(name: "x", size: 1, connections: 0, port: 5433, kind: .test)
        for database in [system, busy, other] {
            await #expect(throws: DevCommandError.invalidName(database.name)) { try await PostgresDatabases.drop(database, on: server) }
        }
    }
}

@Suite struct ConfigReferencesTests {
    @Test func recognisesConfigFiles() {
        for name in [".env", ".env.local", "settings.py", "settings_dev.py", "config.py", "docker-compose.yml", "app.yaml", "pyproject.toml", "alembic.ini", "database.yml"] {
            #expect(ConfigReferences.isConfigFile(name), "\(name)")
        }
        for name in ["models.py", "README.md", "package-lock.json", "photo.png", ""] {
            #expect(!ConfigReferences.isConfigFile(name), "\(name)")
        }
    }

    @Test func wordsSplitURLsAndKeepUnderscoresAndDashes() {
        let words = ConfigReferences.words(in: "DATABASE_URL=postgres://u:p@localhost:5432/proof_line_m4\nNAME='my-db'")
        #expect(words.contains("proof_line_m4") && words.contains("my-db") && words.contains("DATABASE_URL"))
        #expect(!words.contains("proof"))
        #expect(ConfigReferences.words(in: "").isEmpty)
    }

    @Test func findsNamesInConfigFilesAndSkipsLibraryAndNodeModules() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let files = ["work/api/.env": "DB=postgres://localhost/shop_db", "work/api/settings.py": "NAME = 'shop_db'",
                     "Library/app/.env": "DB=hidden_db", "work/web/node_modules/x/.env": "DB=hidden_db",
                     "work/api/models.py": "other_db", "work/big/.env": String(repeating: "a", count: 300_000) + " big_db"]
        for (path, text) in files {
            let full = home + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
        let found = ConfigReferences.find(["shop_db", "hidden_db", "other_db", "big_db", "missing"], home: home)
        #expect(found["shop_db"] == ["work/api/.env", "work/api/settings.py"])
        #expect(found["hidden_db"] == nil && found["other_db"] == nil && found["big_db"] == nil && found["missing"] == nil)
        #expect(ConfigReferences.find([], home: home).isEmpty)
    }
}

@Suite struct CodeSignClonesTests {
    func makeRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        for path in ["X/com.google.Chrome.code_sign_clone/code_sign_clone.AAA/Chrome.app",
                     "X/com.google.Chrome.code_sign_clone/code_sign_clone.BBB",
                     "X/com.google.Chrome.code_sign_clone/other",
                     "X/com.brave.Browser.code_sign_clone/code_sign_clone.CCC",
                     "X/unrelated/code_sign_clone.DDD", "T/keep"] {
            try FileManager.default.createDirectory(atPath: root + "/" + path, withIntermediateDirectories: true)
        }
        return root
    }

    @Test func findsOnlyCloneFolders() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let clones = CodeSignClones.find(tempRoot: root, measure: { _ in 100 })
        #expect(Set(clones.map { ($0.path as NSString).lastPathComponent }) == ["code_sign_clone.AAA", "code_sign_clone.BBB", "code_sign_clone.CCC"])
        #expect(Set(clones.map(\.bundleID)) == ["com.google.Chrome", "com.brave.Browser"])
        #expect(CodeSignClones.find(tempRoot: nil).isEmpty)
        #expect(CodeSignClones.find(tempRoot: root + "/missing").isEmpty)
    }

    @Test func clonePathCheckIsStrict() {
        let root = "/var/folders/ab/cd"
        #expect(CodeSignClones.isClonePath(root + "/X/com.google.Chrome.code_sign_clone/code_sign_clone.AAA", tempRoot: root))
        #expect(!CodeSignClones.isClonePath(root + "/X/com.google.Chrome.code_sign_clone", tempRoot: root))
        #expect(!CodeSignClones.isClonePath(root + "/X/com.google.Chrome.code_sign_clone/code_sign_clone.", tempRoot: root))
        #expect(!CodeSignClones.isClonePath(root + "/X/unrelated/code_sign_clone.AAA", tempRoot: root))
        #expect(!CodeSignClones.isClonePath(root + "/T/com.google.Chrome.code_sign_clone/code_sign_clone.AAA", tempRoot: root))
        #expect(!CodeSignClones.isClonePath(root + "/X/com.google.Chrome.code_sign_clone/code_sign_clone.A/../../../T", tempRoot: root))
        #expect(!CodeSignClones.isClonePath("/Users/me/X/a.code_sign_clone/code_sign_clone.A", tempRoot: root))
    }

    @Test func removesClonesButNotWhileBrowserRunsOrOutsideTheArea() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let clones = CodeSignClones.find(tempRoot: root, measure: { _ in 1 })
        let fake = CodeSignClone(path: root + "/T/keep", bundleID: "com.google.Chrome", size: 1, modified: Date())
        let results = CodeSignClones.remove(clones + [fake], tempRoot: root, isRunning: { $0 == "com.brave.Browser" })
        let byName = Dictionary(uniqueKeysWithValues: results.map { (($0.path as NSString).lastPathComponent, $0.outcome) })
        #expect(byName["code_sign_clone.AAA"] == .removed && byName["code_sign_clone.BBB"] == .removed)
        #expect(byName["code_sign_clone.CCC"] == .refused("Quit the browser first."))
        #expect(byName["keep"] == .refused("Not a browser code-sign copy."))
        #expect(FileManager.default.fileExists(atPath: root + "/T/keep"))
        #expect(FileManager.default.fileExists(atPath: root + "/X/com.brave.Browser.code_sign_clone/code_sign_clone.CCC"))
        #expect(!FileManager.default.fileExists(atPath: root + "/X/com.google.Chrome.code_sign_clone/code_sign_clone.AAA"))
        #expect(CodeSignClones.remove(clones, tempRoot: nil, isRunning: { _ in false }).allSatisfy { !$0.succeeded })
    }

    @Test func realTempRootIsUnderVarFolders() {
        #expect(CodeSignClones.userTempRoot().map { $0.contains("/folders/") } == true)
    }
}

@Suite struct SimulatorRuntimesTests {
    @Test func parsesRuntimeList() {
        let json = """
        {"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE": {"identifier": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
          "version": "26.5", "sizeBytes": 17600000000, "lastUsedAt": "2026-10-01T10:00:00Z", "deletable": true},
         "11111111-2222-3333-4444-555555555555": {"platformIdentifier": "watchOS", "version": "11.0", "sizeBytes": 5000000000, "deletable": false},
         "not-a-uuid": {"sizeBytes": 1}}
        """
        let runtimes = SimulatorRuntimes.parse(Data(json.utf8))
        #expect(runtimes.map(\.name) == ["iOS 26.5", "watchOS 11.0"])
        #expect(runtimes[0].size == 17_600_000_000 && runtimes[0].lastUsed != nil && runtimes[0].isDeletable)
        #expect(!runtimes[1].isDeletable && runtimes[1].lastUsed == nil)
        #expect(SimulatorRuntimes.parse(Data("{}".utf8)).isEmpty)
        #expect(SimulatorRuntimes.parse(Data("garbage".utf8)).isEmpty)
    }

    @Test func refusesUndeletableOrBadIdentifiers() async {
        let protected = SimulatorRuntime(id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", name: "iOS", size: 1, lastUsed: nil, isDeletable: false)
        let bad = SimulatorRuntime(id: "--all", name: "iOS", size: 1, lastUsed: nil, isDeletable: true)
        for runtime in [protected, bad] {
            await #expect(throws: DevCommandError.invalidName(runtime.id)) { try await SimulatorRuntimes.delete(runtime) }
        }
    }
}

@Suite struct SystemSpaceTests {
    @Test func parsesSwapSizes() {
        #expect(SystemSpace.swapBytes(sysctlOutput: "vm.swapusage: total = 10240.00M  used = 8940.69M  free = 1299.31M  (encrypted)") == 10_737_418_240)
        #expect(SystemSpace.swapBytes(sysctlOutput: "vm.swapusage: total = 2.00G  used = 0.00M") == 2_147_483_648)
        #expect(SystemSpace.swapBytes(sysctlOutput: "vm.swapusage: total = 0.00M  used = 0.00M") == 0)
        #expect(SystemSpace.swapBytes(sysctlOutput: "") == nil)
        #expect(SystemSpace.swapBytes(sysctlOutput: "total = 5.00X") == nil)
    }

    @Test func countsOnlyUpdateSnapshots() {
        let output = "Snapshots for volume group containing disk /:\ncom.apple.os.update-182F\ncom.apple.os.update-C192\ncom.apple.TimeMachine.2026-11-01\n"
        #expect(SystemSpace.updateSnapshotCount(tmutilOutput: output) == 2)
        #expect(SystemSpace.updateSnapshotCount(tmutilOutput: "") == 0)
    }

    @Test func everyBucketIsExplained() {
        for kind in SystemSpaceBucket.Kind.allCases {
            #expect(!kind.title.isEmpty && !kind.explanation.isEmpty && !kind.symbol.isEmpty)
        }
    }
}

@Suite struct SessionInventoryTests {
    @Test func listsTopLevelSessionsWithTheirFolders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let project = home + "/.claude/projects/" + home.replacingOccurrences(of: "/", with: "-") + "-work-app"
        try FileManager.default.createDirectory(atPath: project + "/s1/subagents", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/.claude/file-history/s1", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/.codex/sessions/2026/11", withIntermediateDirectories: true)
        try "x".write(toFile: project + "/s1.jsonl", atomically: true, encoding: .utf8)
        try "x".write(toFile: project + "/s1/subagents/agent-1.jsonl", atomically: true, encoding: .utf8)
        try "x".write(toFile: project + "/s2.jsonl", atomically: true, encoding: .utf8)
        try "x".write(toFile: home + "/.codex/sessions/2026/11/rollout-2026-abc.jsonl", atomically: true, encoding: .utf8)
        let sessions = SessionInventory.all(sources: AIUsageSources(home: home), home: home, measure: { _ in 1_000 })
        #expect(Set(sessions.map(\.id)) == ["s1", "s2", "rollout-2026-abc"])
        let s1 = try #require(sessions.first { $0.id == "s1" })
        #expect(s1.paths.count == 3 && s1.size == 2_001)
        #expect(s1.project == "~/work/app" && s1.provider == .claudeCode)
        #expect(sessions.first { $0.id == "rollout-2026-abc" }?.provider == .codex)
        #expect(SessionInventory.all(sources: AIUsageSources(home: home + "/none"), home: home).isEmpty)
    }

    @Test func oldKeepsNamedAndRecentSessions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func session(_ id: String, days: Double) -> AISessionRecord {
            AISessionRecord(id: id, provider: .claudeCode, project: "~", modified: now.addingTimeInterval(-days * 86_400), paths: [], size: 1)
        }
        let sessions = [session("old", days: 40), session("named", days: 90), session("new", days: 5), session("rollout-x-named2", days: 60), session("edge", days: 30)]
        let old = SessionInventory.old(sessions, olderThanDays: 30, keeping: ["named", "named2"], now: now)
        #expect(old.map(\.id) == ["old", "edge"])
        #expect(SessionInventory.old([], olderThanDays: 30, keeping: [], now: now).isEmpty)
        #expect(SessionInventory.old(sessions, olderThanDays: 0, keeping: [], now: now).count == 5)
    }

    @Test func openSessionsAreNeverOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func session(_ id: String, minutes: Double) -> AISessionRecord {
            AISessionRecord(id: id, provider: .claudeCode, project: "~", modified: now.addingTimeInterval(-minutes * 60), paths: [], size: 1)
        }
        let open = session("open", minutes: 2), justClosed = session("closed", minutes: 16), future = session("future", minutes: -5)
        #expect(open.isActive(now: now) && future.isActive(now: now) && !justClosed.isActive(now: now))
        #expect(session("edge", minutes: 15).isActive(now: now) == false)
        #expect(SessionInventory.old([open, justClosed, future], olderThanDays: 0, keeping: [], now: now).map(\.id) == ["closed"])
    }

    @Test func readableProjectNames() {
        #expect(SessionInventory.projectName("-Users-me", home: "/Users/me") == "~")
        #expect(SessionInventory.projectName("-Users-me-Documents-app", home: "/Users/me") == "~/Documents/app")
        #expect(SessionInventory.projectName("-private-tmp-claude-501-x", home: "/Users/me") == "Temporary folder")
        #expect(SessionInventory.projectName("-opt-work", home: "/Users/me") == "/opt/work")
    }
}

@Suite struct HiddenFoldersTests {
    @Test func listsDotFoldersAndLibraryChildrenOnly() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        for path in [".cache", ".npm", ".Trash", "Documents", "Library/Application Support/Claude", "Library/Caches/com.app", "Library/Preferences/x"] {
            try FileManager.default.createDirectory(atPath: home + "/" + path, withIntermediateDirectories: true)
        }
        try "x".write(toFile: home + "/.zshrc", atomically: true, encoding: .utf8)
        let names = Set(HiddenFolders.candidates(home: home).map { String($0.dropFirst(home.count + 1)) })
        #expect(names == [".cache", ".npm", "Library/Application Support/Claude", "Library/Caches/com.app"])
        #expect(HiddenFolders.candidates(home: home + "/missing").isEmpty)
    }

    @Test func keepsLargestAboveMinimumWithExplanations() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        for path in [".big", ".small", ".cache"] { try FileManager.default.createDirectory(atPath: home + "/" + path, withIntermediateDirectories: true) }
        let sizes: [String: UInt64] = [home + "/.big": 900, home + "/.small": 10, home + "/.cache": 500]
        let folders = await HiddenFolders.largest(home: home, limit: 5, minimum: 100, measure: { sizes[$0] })
        #expect(folders.map(\.size) == [900, 500])
        #expect(folders.last?.summary != nil)
        #expect(await HiddenFolders.largest(home: home, limit: 1, minimum: 0, measure: { sizes[$0] }).count == 1)
    }

    @Test func databaseFoldersMarkRunningServers() throws {
        let brew = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: brew) }
        for name in ["postgresql@14", "postgresql@16", "mysql", "redis", "log", "homebrew"] {
            try FileManager.default.createDirectory(atPath: brew + "/var/" + name, withIntermediateDirectories: true)
        }
        let running = [PostgresServer(binDirectory: "/b", dataDirectory: brew + "/var/postgresql@14", port: 5432)]
        let sizes: [String: UInt64] = [brew + "/var/postgresql@14": 11, brew + "/var/postgresql@16": 2, brew + "/var/mysql": 1, brew + "/var/redis": 0]
        let folders = HiddenFolders.databaseFolders(brewPrefix: brew, running: running, measure: { sizes[$0] })
        #expect(folders.map(\.name) == ["postgresql@14", "postgresql@16", "mysql", "redis"])
        #expect(folders[0].isRunning && !folders[1].isRunning)
        #expect(HiddenFolders.databaseFolders(brewPrefix: nil, running: running).isEmpty)
    }
}

@Suite struct AppDataKnowledgeTests {
    @Test func bigAppFoldersGetSpecificExplanations() {
        let home = "/Users/me"
        #expect(ImpactKnowledge.explain(path: home + "/Library/Application Support/Claude", home: home)?.summary.contains("vm_bundles") == true)
        #expect(ImpactKnowledge.explain(path: home + "/Library/Application Support/Google", home: home)?.risk == .keep)
        #expect(ImpactKnowledge.explain(path: home + "/Library/Application Support/Code", home: home)?.summary.contains("VS Code") == true)
        // Only the folder itself: files inside still get their own, more specific explanation.
        #expect(ImpactKnowledge.explain(path: home + "/Library/Application Support/Claude/vm_bundles/x.img", home: home)?.summary.contains("Claude desktop app data") != true)
    }
}

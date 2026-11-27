import Foundation
import Testing
@testable import MacSweepCore

private func temporaryFolder() throws -> String {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return (path as NSString).resolvingSymlinksInPath
}

@Suite struct AppDataBreakdownTests {
    @Test func classifiesCachesSandboxAndData() {
        let home = "/Users/me"
        let claude = home + "/Library/Application Support/Claude"
        #expect(AppDataBreakdown.classify(name: "vm_bundles", in: claude, home: home).kind == .rebuildable)
        #expect(AppDataBreakdown.classify(name: "Code Cache", in: claude, home: home).kind == .cache)
        #expect(AppDataBreakdown.classify(name: "GPUCache", in: claude, home: home).kind == .cache)
        #expect(AppDataBreakdown.classify(name: "IndexedDB", in: claude, home: home).kind == .data)
        #expect(AppDataBreakdown.classify(name: "vm_bundles", in: home + "/Library/Application Support/Other", home: home).kind == .data)
        #expect(AppDataBreakdown.classify(name: "puppeteer", in: home + "/.cache", home: home).kind == .cache)
        #expect(AppDataBreakdown.classify(name: "User", in: home + "/Library/Application Support/Code", home: home).kind == .data)
    }

    @Test func listsPartsBiggestFirstAboveTheMinimum() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let folder = home + "/Library/Application Support/App"
        for name in ["Cache", "User", "tiny", ".DS_Store"] {
            try FileManager.default.createDirectory(atPath: folder + "/" + name, withIntermediateDirectories: true)
        }
        let sizes = [folder + "/Cache": UInt64(300), folder + "/User": 900, folder + "/tiny": 5]
        let parts = AppDataBreakdown.parts(of: folder, home: home, minimum: 100, measure: { sizes[$0] })
        #expect(parts.map(\.name) == ["User", "Cache"])
        #expect(parts[0].kind == .data && !parts[0].isRemovable)
        #expect(parts[1].kind == .cache && parts[1].isRemovable)
        #expect(AppDataBreakdown.parts(of: home + "/missing", home: home).isEmpty)
        try "x".write(toFile: folder + "/big.bin", atomically: true, encoding: .utf8)
        let withFile = AppDataBreakdown.parts(of: folder, home: home, minimum: 100, measure: { $0.hasSuffix("big.bin") ? 5_000 : sizes[$0] })
        #expect(withFile.first?.name == "big.bin" && withFile.first?.isFolder == false && withFile.last?.isFolder == true)
    }

    @Test func bucketsKnowTheirFolders() {
        #expect(SystemSpace.roots(for: .applications) == ["/Applications"])
        #expect(SystemSpace.roots(for: .homebrew, brewPrefix: "/b") == ["/b/Cellar", "/b/Caskroom"])
        #expect(SystemSpace.roots(for: .databases, brewPrefix: nil).isEmpty)
        #expect(SystemSpace.roots(for: .tempFiles, tempRoot: "/t") == ["/t/T", "/t/C"])
        #expect(SystemSpace.roots(for: .browserCopies, tempRoot: "/t") == ["/t/X"])
        #expect(SystemSpace.roots(for: .swap) == ["/private/var/vm"] && SystemSpace.roots(for: .updateSnapshots).isEmpty)
    }

    @Test func picksCandidatesAndOwningApp() {
        let home = "/Users/me"
        let support = home + "/Library/Application Support"
        #expect(AppDataBreakdown.isCandidate(home + "/.cache", size: 1, home: home))
        #expect(AppDataBreakdown.isCandidate(support + "/Claude", size: 600_000_000, home: home))
        #expect(!AppDataBreakdown.isCandidate(support + "/Claude", size: 100, home: home))
        #expect(!AppDataBreakdown.isCandidate(home + "/Library/Caches/x", size: 900_000_000, home: home))
        #expect(AppDataBreakdown.owningApp(of: support + "/Code", home: home) == "Code")
        #expect(AppDataBreakdown.owningApp(of: home + "/.cache", home: home) == nil)
    }
}

@Suite struct SessionHeadTests {
    @Test func readsTitleFolderAndFallsBackToTheFirstPrompt() {
        let lines = """
        {"type":"mode","mode":"x"}
        not json
        {"type":"user","isMeta":true,"message":{"content":"meta text"},"cwd":"/Users/me/app"}
        {"type":"user","message":{"content":"<command-name>/clear</command-name>"}}
        {"type":"user","message":{"content":"Fix the login bug\\nand more"}}
        {"type":"ai-title","aiTitle":"Fix login bug"}
        """
        let head = SessionHead.parse(Data(lines.utf8))
        #expect(head.title == "Fix login bug" && head.workingDirectory == "/Users/me/app")
        let noTitle = SessionHead.parse(Data(lines.split(separator: "\n").dropLast().joined(separator: "\n").utf8))
        #expect(noTitle.title == "Fix the login bug")
        #expect(SessionHead.parse(Data()) == SessionHead())
        #expect(SessionHead.parse(Data(#"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#.utf8)).title == nil)
        #expect(SessionHead.read("/nonexistent/file.jsonl") == SessionHead())
    }

    @Test func cleansLongAndEmptyTitles() {
        #expect(SessionHead.clean("   ") == nil)
        #expect(SessionHead.clean(String(repeating: "a", count: 200))?.count == 91)
        #expect(SessionHead.clean("  one line  \nsecond") == "one line")
    }

    @Test func inventoryCarriesTitleRealFolderAndExtras() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let project = home + "/.claude/projects/-odd-name"
        try FileManager.default.createDirectory(atPath: project + "/s1/subagents", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: project + "/s1/other", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/.claude/file-history/s1", withIntermediateDirectories: true)
        try #"{"type":"ai-title","aiTitle":"Ship it","cwd":"\#(home)/work/my-app"}"#.write(toFile: project + "/s1.jsonl", atomically: true, encoding: .utf8)
        try "{}".write(toFile: project + "/s2.jsonl", atomically: true, encoding: .utf8)
        let sessions = SessionInventory.all(sources: AIUsageSources(home: home), home: home, measure: { _ in 500 })
        let s1 = try #require(sessions.first { $0.id == "s1" })
        #expect(s1.title == "Ship it" && s1.project == "~/work/my-app")
        #expect(s1.extras.count == 2 && s1.extrasSize == 1_000)
        #expect(s1.extras.allSatisfy { !$0.hasSuffix("/other") && $0 != project + "/s1" })
        let s2 = try #require(sessions.first { $0.id == "s2" })
        #expect(s2.title == nil && s2.extras.isEmpty && s2.extrasSize == 0 && s2.project == "/odd/name")
    }
}

@Suite struct PostgresInspectorTests {
    @Test func parsesOidAndStaysCompatibleWithoutIt() {
        let databases = PostgresDatabases.parse("app\t10\t0\t16402\nold\t5\t0\nbad\t5\t0\tx1\n", port: 5432)
        #expect(databases.map(\.oid) == ["16402", nil, nil])
        #expect(databases.allSatisfy { $0.lastWritten == nil })
    }

    @Test func lastWrittenIgnoresBookkeepingFiles() throws {
        let data = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: data) }
        let folder = data + "/base/16402"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let old = Date(timeIntervalSince1970: 1_600_000_000), newer = Date(timeIntervalSince1970: 1_700_000_000)
        for (name, date) in [("1259", old), ("2619_fsm", newer), ("pg_internal.init", Date()), ("PG_VERSION", Date())] {
            try "x".write(toFile: folder + "/" + name, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder + "/" + name)
        }
        #expect(PostgresInspector.lastWritten(dataDirectory: data, oid: "16402") == newer)
        #expect(PostgresInspector.lastWritten(dataDirectory: data, oid: "1") == nil)
    }

    @Test func parsesTables() {
        let tables = PostgresInspector.parseTables("public.events\t2048\t12\npublic.empty\t0\t-1\nbroken\tx\t1\n\t1\t1\n")
        #expect(tables == [PostgresTable(name: "public.events", size: 2_048, rows: 12), PostgresTable(name: "public.empty", size: 0, rows: 0)])
        #expect(PostgresInspector.parseTables("").isEmpty)
    }

    @Test func backupPathIsFileSafeAndDated() {
        let database = PostgresDatabase(name: "my db/../x", size: 1, connections: 0, port: 5433, kind: .unreferenced)
        let path = PostgresInspector.backupPath(for: database, folder: "/b", now: Date(timeIntervalSince1970: 0))
        #expect(path.hasPrefix("/b/my_db____x-5433-19") && path.hasSuffix(".dump"))
        #expect(!path.dropFirst(3).contains("/"))
        #expect(PostgresBackup(path: "/b/x.dump", size: 1).restoreCommand == "pg_restore --create --dbname=postgres '/b/x.dump'")
    }

    @Test func refusesSystemDatabasesAndTheWrongServer() async {
        let server = PostgresServer(binDirectory: "/nonexistent", dataDirectory: "/d", port: 5432)
        let system = PostgresDatabase(name: "postgres", size: 1, connections: 0, port: 5432, kind: .system)
        let other = PostgresDatabase(name: "x", size: 1, connections: 0, port: 5433, kind: .test)
        await #expect(throws: DevCommandError.invalidName("postgres")) { try await PostgresInspector.backup(system, on: server, folder: "/nonexistent") }
        await #expect(throws: DevCommandError.invalidName("x")) { try await PostgresInspector.backup(other, on: server, folder: "/nonexistent") }
        await #expect(throws: DevCommandError.invalidName("x")) { try await PostgresInspector.tables(in: other, on: server) }
    }
}

@Suite struct DataFolderTrashTests {
    @Test func onlyStoppedCleanFoldersUnderBrewVarCanGo() throws {
        let brew = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: brew) }
        for name in ["postgresql@16", "postgresql@14", "crashed"] {
            try FileManager.default.createDirectory(atPath: brew + "/var/" + name, withIntermediateDirectories: true)
        }
        try "1".write(toFile: brew + "/var/postgresql@14/postmaster.pid", atomically: true, encoding: .utf8)
        func folder(_ name: String, running: Bool = false, path: String? = nil) -> DatabaseDataFolder {
            DatabaseDataFolder(name: name, path: path ?? brew + "/var/" + name, size: 1, isRunning: running)
        }
        #expect(HiddenFolders.trashRefusal(folder("postgresql@16"), brewPrefix: brew) == nil)
        #expect(HiddenFolders.trashRefusal(folder("postgresql@16", running: true), brewPrefix: brew) != nil)
        #expect(HiddenFolders.trashRefusal(folder("postgresql@14"), brewPrefix: brew) != nil)
        #expect(HiddenFolders.trashRefusal(folder("crashed"), brewPrefix: brew) != nil)
        #expect(HiddenFolders.trashRefusal(folder("postgresql@16", path: brew + "/var/other"), brewPrefix: brew) != nil)
        #expect(HiddenFolders.trashRefusal(folder("postgresql@16"), brewPrefix: nil) != nil)
        #expect(throws: DevCommandError.self) { try HiddenFolders.trash(folder("postgresql@14"), brewPrefix: brew) }
        #expect(FileManager.default.fileExists(atPath: brew + "/var/postgresql@14"))
    }
}

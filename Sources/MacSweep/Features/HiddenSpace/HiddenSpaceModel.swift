import AppKit
import MacSweepCore
import Observation

/// Everything outside the home folder: what it is, how big, and the safe ways to shrink it.
@MainActor @Observable
final class HiddenSpaceModel {
    static let shared = HiddenSpaceModel()

    private(set) var buckets: [SystemSpaceBucket] = []
    private(set) var clones: [CodeSignClone] = []
    private(set) var runtimes: [SimulatorRuntime] = []
    private(set) var servers: [PostgresServer] = []
    private(set) var databases: [PostgresDatabase] = []
    private(set) var dataFolders: [DatabaseDataFolder] = []
    private(set) var hiddenFolders: [HiddenFolder] = []
    private(set) var isMeasuringFolders = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var busy: String?
    /// Big app-data folders split into caches and data; only folders with something removable.
    private(set) var appData: [AppDataGroup] = []
    private(set) var folderParts: [String: [FolderPart]] = [:]
    private(set) var tables: [String: [PostgresTable]] = [:]
    /// Apps whose memory macOS has compressed the most: what's pushing data into swap.
    private(set) var swapUsers: [(name: String, bytes: UInt64)]?
    var selectedDatabases = Set<String>()
    var selectedParts = Set<String>()
    /// The result of the last action, measured as the change in free disk space.
    var result: ActionResult?

    struct ActionResult: Equatable {
        let title: String
        let freed: Int64
        let failures: [String]
        /// Extra line for actions that don't free space right away (Trash) or that leave something behind (backups).
        var note: String? = nil
        var revealPath: String? = nil
    }

    struct AppDataGroup: Identifiable, Equatable {
        let folder: String
        let parts: [FolderPart]
        /// The app to quit before its files are touched, if the folder belongs to one.
        let app: String?
        var id: String { folder }
        var removable: [FolderPart] { parts.filter(\.isRemovable) }
    }

    var outsideHomeTotal: UInt64 { buckets.reduce(0) { $0 + $1.size } }
    var testLeftovers: [PostgresDatabase] { databases.filter { $0.kind == .test } }
    var selectedDatabaseSize: UInt64 { databases.filter { selectedDatabases.contains($0.id) }.reduce(0) { $0 + $1.size } }
    var clonesSize: UInt64 { clones.reduce(0) { $0 + $1.size } }
    var removableParts: [FolderPart] { appData.flatMap(\.removable) }
    var selectedPartsSize: UInt64 { removableParts.filter { selectedParts.contains($0.id) }.reduce(0) { $0 + $1.size } }
    var reclaimableAppData: UInt64 { removableParts.reduce(0) { $0 + $1.size } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        async let foundClones = Task.detached(priority: .utility) { CodeSignClones.find() }.value
        async let foundRuntimes = SimulatorRuntimes.list()
        async let foundDatabases = loadDatabases()
        clones = await foundClones
        runtimes = await foundRuntimes
        let (servers, databases) = await foundDatabases
        self.servers = servers
        self.databases = databases
        selectedDatabases.formIntersection(Set(databases.map(\.id)))
        let running = servers
        dataFolders = await Task.detached(priority: .utility) { HiddenFolders.databaseFolders(brewPrefix: SystemSpace.homebrewPrefix(), running: running) }.value
        buckets = await SystemSpace.measure(runtimesSize: runtimes.reduce(0) { $0 + $1.size }, clones: clones)
        isLoading = false
        hasLoaded = true
        await measureHiddenFolders()
    }

    /// The slowest part (all of ~/Library's big folders), so it fills in after the rest is shown.
    func measureHiddenFolders() async {
        guard !isMeasuringFolders else { return }
        isMeasuringFolders = true
        hiddenFolders = await HiddenFolders.largest()
        let home = NSHomeDirectory()
        let candidates = hiddenFolders.filter { AppDataBreakdown.isCandidate($0.path, size: $0.size, home: home) }.map(\.path)
        appData = await Task.detached(priority: .utility) {
            candidates.map { folder in
                AppDataGroup(folder: folder, parts: AppDataBreakdown.parts(of: folder, home: home), app: AppDataBreakdown.owningApp(of: folder, home: home))
            }
            .filter { $0.removable.reduce(0) { $0 + $1.size } >= 50_000_000 }
        }.value
        selectedParts.formIntersection(Set(removableParts.map(\.id)))
        isMeasuringFolders = false
    }

    /// What's inside one hidden folder, measured the first time its row is opened.
    func loadParts(of folder: String) async {
        guard folderParts[folder] == nil else { return }
        folderParts[folder] = await Task.detached(priority: .userInitiated) { AppDataBreakdown.parts(of: folder) }.value
    }

    func loadSwapUsers() async {
        swapUsers = await SystemSpace.compressedMemory()
    }

    func loadTables(of database: PostgresDatabase) async {
        guard tables[database.id] == nil, let server = servers.first(where: { $0.port == database.port }) else { return }
        tables[database.id] = (try? await PostgresInspector.tables(in: database, on: server)) ?? []
    }

    func isAppRunning(_ name: String?) -> Bool {
        guard let name else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
    }

    func selectCaches() {
        selectedParts = Set(appData.filter { !isAppRunning($0.app) }.flatMap(\.removable).filter { $0.kind == .cache }.map(\.id))
    }

    /// Moves the ticked caches to the Trash, skipping any whose app is open.
    func trashSelectedParts() async {
        let chosen = appData.filter { !isAppRunning($0.app) }.flatMap(\.removable).filter { selectedParts.contains($0.id) }
        guard !chosen.isEmpty else { return }
        var moved: UInt64 = 0
        await act("\(chosen.count) app-data item\(chosen.count == 1 ? "" : "s")", note: { "Moved \(Format.bytes(moved)) to the Trash. Empty the Trash to get the space back." }) {
            let targets = chosen.map { CleanupTarget(path: $0.path, size: $0.size) }
            let results = await Task.detached { Cleaner.remove(targets, mode: .trash) }.value
            moved = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
            return results.filter { !$0.succeeded }.map { ($0.path as NSString).lastPathComponent + ": " + Self.describe($0) }
        }
        selectedParts.removeAll()
        folderParts.removeAll()
    }

    func trashDataFolder(_ folder: DatabaseDataFolder) async {
        await act(folder.name, note: { "Moved to the Trash. Empty the Trash to get the space back." }) {
            do { try HiddenFolders.trash(folder, brewPrefix: SystemSpace.homebrewPrefix()); return [] } catch { return [error.localizedDescription] }
        }
    }

    private func loadDatabases() async -> ([PostgresServer], [PostgresDatabase]) {
        let servers = await PostgresDatabases.runningServers()
        var all: [PostgresDatabase] = []
        for server in servers { all += await PostgresDatabases.list(server) }
        let names = Set(all.filter { $0.kind != .system }.map(\.name))
        let references = await Task.detached(priority: .utility) { ConfigReferences.find(names) }.value
        return (servers, PostgresDatabases.classify(all, references: references))
    }

    func runningBrowsers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func removeClones() async {
        let running = runningBrowsers()
        await act("Browser code-sign copies") {
            let targets = await MainActor.run { self.clones }
            return await Task.detached { CodeSignClones.remove(targets, isRunning: running.contains) }.value
                .compactMap { result in result.succeeded ? nil : Self.describe(result) }
        }
    }

    func deleteRuntime(_ runtime: SimulatorRuntime) async {
        await act(runtime.name) {
            do { try await SimulatorRuntimes.delete(runtime); return [] } catch { return [error.localizedDescription] }
        }
    }

    /// Drops the ticked databases. With `backUp`, each is dumped and the dump read back first; a failed backup skips the drop.
    func dropSelectedDatabases(backUp: Bool) async {
        let chosen = databases.filter { selectedDatabases.contains($0.id) && $0.isRemovable }
        let servers = servers
        var saved = 0
        await act("\(chosen.count) database\(chosen.count == 1 ? "" : "s")",
                  note: { saved > 0 ? "\(saved) backup\(saved == 1 ? "" : "s") saved in ~/MacSweep Backups/Postgres. Restore one with pg_restore --create --dbname=postgres <file>." : nil },
                  revealPath: backUp ? PostgresInspector.backupFolder() : nil) {
            var failures: [String] = []
            for database in chosen {
                guard let server = servers.first(where: { $0.port == database.port }) else {
                    failures.append("\(database.name): its server on port \(database.port) is no longer running")
                    continue
                }
                do {
                    if backUp { _ = try await PostgresInspector.backup(database, on: server); saved += 1 }
                    try await PostgresDatabases.drop(database, on: server)
                } catch { failures.append("\(database.name): \(error.localizedDescription)") }
            }
            return failures
        }
        selectedDatabases.removeAll()
        tables.removeAll()
    }

    /// Ticks databases nobody has written to for `days` and that no project config names.
    func selectUntouched(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        selectedDatabases = Set(databases.filter { ($0.kind == .unreferenced || $0.kind == .test) && ($0.lastWritten ?? .distantFuture) < cutoff }.map(\.id))
    }

    func selectTestLeftovers() { selectedDatabases = Set(testLeftovers.map(\.id)) }

    /// Runs an action, then re-measures, and reports the real change in free space.
    private func act(_ title: String, note: () -> String? = { nil }, revealPath: String? = nil, _ work: () async -> [String]) async {
        guard busy == nil else { return }
        busy = title
        let before = Self.freeBytes()
        let failures = await work()
        try? await Task.sleep(for: .seconds(2))
        let after = Self.freeBytes()
        result = ActionResult(title: title, freed: after - before, failures: failures, note: note(), revealPath: revealPath)
        busy = nil
        await refresh()
    }

    static func freeBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    nonisolated static func describe(_ result: RemovalResult) -> String {
        switch result.outcome {
        case .removed: ""
        case .refused(let reason), .failed(let reason): reason
        }
    }
}

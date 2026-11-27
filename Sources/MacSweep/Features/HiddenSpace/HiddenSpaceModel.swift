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
    var selectedDatabases = Set<String>()
    /// The result of the last action, measured as the change in free disk space.
    var result: ActionResult?

    struct ActionResult: Equatable {
        let title: String
        let freed: Int64
        let failures: [String]
    }

    var outsideHomeTotal: UInt64 { buckets.reduce(0) { $0 + $1.size } }
    var testLeftovers: [PostgresDatabase] { databases.filter { $0.kind == .test } }
    var selectedDatabaseSize: UInt64 { databases.filter { selectedDatabases.contains($0.id) }.reduce(0) { $0 + $1.size } }
    var clonesSize: UInt64 { clones.reduce(0) { $0 + $1.size } }

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
        isMeasuringFolders = false
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

    func dropSelectedDatabases() async {
        let chosen = databases.filter { selectedDatabases.contains($0.id) && $0.isRemovable }
        let servers = servers
        await act("\(chosen.count) database\(chosen.count == 1 ? "" : "s")") {
            var failures: [String] = []
            for database in chosen {
                guard let server = servers.first(where: { $0.port == database.port }) else {
                    failures.append("\(database.name): its server on port \(database.port) is no longer running")
                    continue
                }
                do { try await PostgresDatabases.drop(database, on: server) } catch { failures.append("\(database.name): \(error.localizedDescription)") }
            }
            return failures
        }
        selectedDatabases.removeAll()
    }

    func selectTestLeftovers() { selectedDatabases = Set(testLeftovers.map(\.id)) }

    /// Runs an action, then re-measures, and reports the real change in free space.
    private func act(_ title: String, _ work: @escaping () async -> [String]) async {
        guard busy == nil else { return }
        busy = title
        let before = Self.freeBytes()
        let failures = await work()
        try? await Task.sleep(for: .seconds(2))
        let after = Self.freeBytes()
        result = ActionResult(title: title, freed: after - before, failures: failures)
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

import Foundation
import os

/// A local Postgres server found from its running `postgres -D <dir> [-p <port>]` process.
public struct PostgresServer: Sendable, Equatable, Identifiable {
    public let binDirectory: String
    public let dataDirectory: String
    public let port: Int
    public var id: Int { port }
    /// "postgresql@14" from the data directory, for display.
    public var name: String { (dataDirectory as NSString).lastPathComponent }
}

public struct PostgresDatabase: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// postgres / template databases: never offered for removal.
        case system
        /// Has open connections right now.
        case inUse = "In use"
        /// Named in one of your projects' config files.
        case referenced = "Used by a project"
        /// A test_* database no project names: test runners recreate these.
        case test = "Test leftover"
        /// Not named anywhere we looked; your call.
        case unreferenced = "Not referenced"
    }

    public let name: String
    public let size: UInt64
    public let connections: Int
    public let port: Int
    public var kind: Kind
    /// Config files that mention it (relative to home), for the "used by" detail.
    public var referencedBy: [String] = []
    /// Postgres's internal id: the name of this database's folder under `base/`.
    public var oid: String? = nil
    /// When any of its table files last changed on disk. Approximate: background vacuuming also counts.
    public var lastWritten: Date? = nil
    public var id: String { "\(port)/\(name)" }
    public var isRemovable: Bool { kind != .system && kind != .inUse }
}

public enum PostgresDatabases {
    private static let log = Logger(subsystem: Log.subsystem, category: "postgres")
    static let systemNames: Set<String> = ["postgres", "template0", "template1"]
    static let query = "select d.datname, pg_database_size(d.datname), (select count(*) from pg_stat_activity a where a.datname = d.datname), d.oid from pg_database d where d.datallowconn order by 2 desc"

    /// Parses `ps -axo command` lines for running postgres servers.
    public static func servers(psOutput: String) -> [PostgresServer] {
        psOutput.split(separator: "\n").compactMap { line -> PostgresServer? in
            let parts = line.split(separator: " ").map(String.init)
            guard let executable = parts.first, executable.hasSuffix("/bin/postgres"),
                  let dataIndex = parts.firstIndex(of: "-D"), dataIndex + 1 < parts.count else { return nil }
            let port = parts.firstIndex(of: "-p").flatMap { $0 + 1 < parts.count ? Int(parts[$0 + 1]) : nil } ?? 5432
            return PostgresServer(binDirectory: (executable as NSString).deletingLastPathComponent,
                                  dataDirectory: parts[dataIndex + 1], port: port)
        }
    }

    /// Parses `psql -XAtF '\t'` rows of name, size, connection count and (optionally) oid.
    public static func parse(_ output: String, port: Int) -> [PostgresDatabase] {
        output.split(separator: "\n").compactMap { line -> PostgresDatabase? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 || fields.count == 4, !fields[0].isEmpty, let size = UInt64(fields[1]), let connections = Int(fields[2]) else { return nil }
            let kind: PostgresDatabase.Kind = systemNames.contains(fields[0]) ? .system : connections > 0 ? .inUse : .unreferenced
            let oid = fields.count == 4 && !fields[3].isEmpty && fields[3].allSatisfy(\.isNumber) ? fields[3] : nil
            return PostgresDatabase(name: fields[0], size: size, connections: connections, port: port, kind: kind, oid: oid)
        }
    }

    /// Fills in kinds from where each name appears in project config files.
    public static func classify(_ databases: [PostgresDatabase], references: [String: [String]]) -> [PostgresDatabase] {
        databases.map { database in
            var database = database
            database.referencedBy = references[database.name] ?? []
            guard database.kind == .unreferenced else { return database }
            if !database.referencedBy.isEmpty { database.kind = .referenced }
            else if database.name.hasPrefix("test_") { database.kind = .test }
            return database
        }
    }

    public static func runningServers() async -> [PostgresServer] {
        guard let result = try? await Shell.run("/bin/ps", ["-axo", "command"]) else { return [] }
        return servers(psOutput: result.stdout)
    }

    public static func list(_ server: PostgresServer) async -> [PostgresDatabase] {
        let psql = server.binDirectory + "/psql"
        guard let result = try? await DevShell.run(psql, ["-X", "-A", "-t", "-F", "\t", "-p", String(server.port), "-d", "postgres", "-c", query],
                                                   timeout: 20, tool: "psql"), result.status == 0 else {
            log.warning("could not list databases on port \(server.port)")
            return []
        }
        return parse(result.stdout, port: server.port).map { database in
            var database = database
            database.lastWritten = database.oid.flatMap { PostgresInspector.lastWritten(dataDirectory: server.dataDirectory, oid: $0) }
            return database
        }
    }

    /// Drops one database with `dropdb`, which takes the name as an argument (no SQL to quote).
    /// Postgres itself refuses while anyone is connected, so an in-use database can't go by accident.
    public static func drop(_ database: PostgresDatabase, on server: PostgresServer) async throws {
        guard database.isRemovable, !systemNames.contains(database.name), database.port == server.port else {
            throw DevCommandError.invalidName(database.name)
        }
        let result = try await DevShell.run(server.binDirectory + "/dropdb", ["-p", String(server.port), "--", database.name], timeout: 60, tool: "dropdb")
        guard result.status == 0 else { throw DevCommandError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        log.info("dropped database on port \(server.port) (\(database.size) bytes)")
    }
}

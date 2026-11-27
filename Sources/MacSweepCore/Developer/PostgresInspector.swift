import Foundation
import os

public struct PostgresTable: Sendable, Equatable, Identifiable {
    public let name: String
    /// Table plus its indexes and TOAST data.
    public let size: UInt64
    public let rows: Int
    public var id: String { name }
}

/// A verified `pg_dump` file, so a dropped database can be brought back.
public struct PostgresBackup: Sendable, Equatable {
    public let path: String
    public let size: UInt64
    /// The command that restores it, for the user to copy.
    public var restoreCommand: String { "pg_restore --create --dbname=postgres '\(path)'" }
}

/// Looks inside one database: when it last changed, its biggest tables, and a backup before it's dropped.
public enum PostgresInspector {
    private static let log = Logger(subsystem: Log.subsystem, category: "postgres")
    static let tablesQuery = "select schemaname || '.' || relname, pg_total_relation_size(relid), n_live_tup from pg_stat_user_tables order by 2 desc limit 12"

    /// Newest change among a database's table files. Postgres rewrites bookkeeping files on connect, so those are skipped.
    public static func lastWritten(dataDirectory: String, oid: String) -> Date? {
        let folder = dataDirectory + "/base/" + oid
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.first?.isNumber == true }
        return files.compactMap { (try? FileManager.default.attributesOfItem(atPath: folder + "/" + $0))?[.modificationDate] as? Date }.max()
    }

    static func parseTables(_ output: String) -> [PostgresTable] {
        output.split(separator: "\n").compactMap { line -> PostgresTable? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, !fields[0].isEmpty, let size = UInt64(fields[1]), let rows = Int(fields[2]) else { return nil }
            return PostgresTable(name: fields[0], size: size, rows: max(rows, 0))
        }
    }

    public static func tables(in database: PostgresDatabase, on server: PostgresServer) async throws -> [PostgresTable] {
        guard database.port == server.port else { throw DevCommandError.invalidName(database.name) }
        let result = try await DevShell.run(server.binDirectory + "/psql",
                                            ["-X", "-A", "-t", "-F", "\t", "-p", String(server.port), "-d", database.name, "-c", tablesQuery],
                                            timeout: 20, tool: "psql")
        guard result.status == 0 else { throw DevCommandError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parseTables(result.stdout)
    }

    public static func backupFolder(home: String = NSHomeDirectory()) -> String { home + "/MacSweep Backups/Postgres" }

    /// `<folder>/<name>-<port>-<yyyyMMdd-HHmmss>.dump`; names are reduced to file-safe characters.
    static func backupPath(for database: PostgresDatabase, folder: String, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safe = String(database.name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
        return "\(folder)/\(safe)-\(database.port)-\(formatter.string(from: now)).dump"
    }

    /// Dumps the database in Postgres's compressed format, then has `pg_restore` read it back, so only a usable backup is returned.
    public static func backup(_ database: PostgresDatabase, on server: PostgresServer, folder: String = backupFolder()) async throws -> PostgresBackup {
        guard database.port == server.port, !PostgresDatabases.systemNames.contains(database.name) else {
            throw DevCommandError.invalidName(database.name)
        }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = backupPath(for: database, folder: folder)
        let dump = try await DevShell.run(server.binDirectory + "/pg_dump", ["-F", "c", "-p", String(server.port), "-f", path, "-d", database.name],
                                          timeout: 1_800, tool: "pg_dump")
        guard dump.status == 0 else {
            try? FileManager.default.removeItem(atPath: path)
            throw DevCommandError.failed(dump.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let check = try await DevShell.run(server.binDirectory + "/pg_restore", ["--list", path], timeout: 120, tool: "pg_restore")
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        guard check.status == 0, size > 0 else {
            try? FileManager.default.removeItem(atPath: path)
            throw DevCommandError.failed("The backup of \(database.name) could not be read back, so nothing was dropped.")
        }
        log.info("backed up a database on port \(server.port) (\(size) bytes)")
        return PostgresBackup(path: path, size: size)
    }
}

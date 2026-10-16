import Foundation

public enum TCCDatabase: String, Sendable, CaseIterable {
    case user
    case system

    public var title: String {
        switch self {
        case .user: "Your account"
        case .system: "System-wide"
        }
    }
}

public enum TCCAuthorization: Sendable, Equatable {
    case denied
    case allowed
    case limited
    case other(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .denied
        case 2: self = .allowed
        case 3: self = .limited
        default: self = .other(rawValue)
        }
    }

    public var title: String {
        switch self {
        case .denied: "Denied"
        case .allowed: "Allowed"
        case .limited: "Limited"
        case .other: "Unknown"
        }
    }

    public var isGranted: Bool { self == .allowed || self == .limited }
}

public struct TCCEntry: Identifiable, Sendable, Equatable {
    public enum Client: Sendable, Equatable, Hashable {
        case bundleID(String)
        case path(String)

        public var raw: String {
            switch self {
            case .bundleID(let id): id
            case .path(let path): path
            }
        }
    }

    public let database: TCCDatabase
    public let serviceKey: String
    public let client: Client
    public let authorization: TCCAuthorization
    /// Target app for Automation grants (which app this client may control).
    public let target: String?
    public let lastModified: Date?

    public var id: String { [database.rawValue, serviceKey, client.raw, target ?? ""].joined(separator: "|") }

    public var service: TCCService { TCCServiceCatalog.service(for: serviceKey) ?? TCCServiceCatalog.fallback(for: serviceKey) }

    public init(database: TCCDatabase, serviceKey: String, client: Client, authorization: TCCAuthorization,
                target: String? = nil, lastModified: Date? = nil) {
        self.database = database
        self.serviceKey = serviceKey
        self.client = client
        self.authorization = authorization
        self.target = target
        self.lastModified = lastModified
    }
}

public enum TCCReadResult: Sendable, Equatable {
    case entries([TCCEntry])
    /// The database exists but this app can't open it; only Full Disk Access unlocks it.
    case needsFullDiskAccess
    case failed(String)

    public var entries: [TCCEntry] {
        if case .entries(let entries) = self { return entries }
        return []
    }
}

/// Parses `sqlite3 -readonly -json` output from TCC.db's `access` table.
public enum TCCParser {
    public static let query = """
        SELECT service, client, client_type, auth_value, indirect_object_identifier, last_modified FROM access
        """

    public static func classify(_ result: ShellResult, database: TCCDatabase) -> TCCReadResult {
        guard result.status == 0 else {
            let message = result.stderr.lowercased()
            let deniedMarkers = ["authorization denied", "unable to open", "operation not permitted", "not authorized"]
            if deniedMarkers.contains(where: message.contains) { return .needsFullDiskAccess }
            return .failed("sqlite3 exited with status \(result.status)")
        }
        guard let entries = parse(result.stdout, database: database) else {
            return .failed("The privacy database returned unreadable output")
        }
        return .entries(entries)
    }

    /// Returns nil for malformed output. sqlite3 prints nothing at all for a query with zero rows.
    public static func parse(_ json: String, database: TCCDatabase) -> [TCCEntry]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return rows.compactMap { entry(from: $0, database: database) }
    }

    static func entry(from row: [String: Any], database: TCCDatabase) -> TCCEntry? {
        guard let service = row["service"] as? String, !service.isEmpty,
              let rawClient = row["client"] as? String, !rawClient.isEmpty,
              let authValue = integer(row["auth_value"])
        else { return nil }
        let client: TCCEntry.Client = integer(row["client_type"]) == 1 ? .path(rawClient) : .bundleID(rawClient)
        let target = (row["indirect_object_identifier"] as? String).flatMap { $0.isEmpty || $0 == "UNUSED" ? nil : $0 }
        let modified = integer(row["last_modified"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        return TCCEntry(database: database, serviceKey: service, client: client,
                        authorization: TCCAuthorization(rawValue: authValue), target: target, lastModified: modified)
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

public enum TCCReader {
    public static func databasePath(_ database: TCCDatabase, home: String = NSHomeDirectory()) -> String {
        switch database {
        case .user: home + "/Library/Application Support/com.apple.TCC/TCC.db"
        case .system: "/Library/Application Support/com.apple.TCC/TCC.db"
        }
    }

    /// Opens the database read-only via sqlite3's `-readonly` flag; MacSweep never writes to TCC.
    public static func read(_ database: TCCDatabase, home: String = NSHomeDirectory()) async -> TCCReadResult {
        do {
            let result = try await Shell.run("/usr/bin/sqlite3", ["-readonly", "-json", databasePath(database, home: home), TCCParser.query])
            return TCCParser.classify(result, database: database)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

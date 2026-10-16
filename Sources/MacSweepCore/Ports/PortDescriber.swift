import Foundation

public enum PortCategory: String, CaseIterable, Sendable, Identifiable {
    case devServer = "Dev servers"
    case database = "Databases & caches"
    case app = "Apps"
    case system = "System"

    public var id: String { rawValue }
}

/// Turns a listening process into something a human recognises: what kind of server it is and
/// a short version of the command that started it.
public enum PortDescriber {
    static let databases = ["postgres", "mysqld", "mariadbd", "mongod", "redis-server", "memcached", "clickhouse", "elasticsearch",
                            "opensearch", "influxd", "valkey-server", "etcd", "nats-server", "minio", "rabbitmq"]
    static let runtimes = ["node", "python", "python3", "ruby", "go", "java", "deno", "bun", "php", "uvicorn", "gunicorn", "dotnet",
                           "beam.smp", "rails", "next-server", "vite", "esbuild", "air", "cargo", "streamlit", "jupyter"]
    static let systemProcesses = ["ControlCenter", "rapportd", "sharingd", "mDNSResponder", "launchd", "AirPlayXPCHelper", "WiFiAgent",
                                  "remoted", "identityservicesd", "cupsd", "netbiosd", "UserEventAgent", "SystemUIServer", "configd"]

    public static func category(command: String, executable: String?) -> PortCategory {
        let name = command.lowercased()
        if databases.contains(where: { name.hasPrefix($0) }) { return .database }
        if systemProcesses.contains(command) || executable?.hasPrefix("/System/") == true || executable?.hasPrefix("/usr/libexec/") == true {
            return .system
        }
        if executable?.contains(".app/") == true { return .app }
        if runtimes.contains(where: { name.hasPrefix($0) }) { return .devServer }
        return .app
    }

    /// "node /Users/me/app/node_modules/.bin/next dev --port 3000" → "next dev --port 3000".
    public static func summary(_ arguments: [String], limit: Int = 70) -> String? {
        guard !arguments.isEmpty else { return nil }
        var parts = arguments
        let interpreters = ["node", "python", "python3", "ruby", "deno", "bun", "php", "java"]
        if let first = parts.first, interpreters.contains(where: { (first as NSString).lastPathComponent.hasPrefix($0) }), parts.count > 1 {
            parts.removeFirst()
            if parts.first == "-m", parts.count > 1 { parts.removeFirst() }
        }
        let shortened = parts.map { part -> String in
            part.hasPrefix("/") ? (part as NSString).lastPathComponent : part
        }
        let text = shortened.joined(separator: " ")
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

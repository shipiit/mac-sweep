import Foundation

public enum DevServiceSource: String, Sendable {
    case homebrew = "Homebrew"
    case launchd = "launchd"
}

public enum DevServiceState: String, Sendable, Equatable {
    case running = "Running"
    case stopped = "Stopped"
    case error = "Error"
    case scheduled = "Scheduled"
    case unknown = "Unknown"

    /// Maps brew's `status` field: started, none, stopped, error, scheduled, unknown, other.
    static func fromBrew(_ status: String, exitCode: Int?) -> DevServiceState {
        switch status.lowercased() {
        case "started": .running
        case "none", "stopped": .stopped
        case "error": .error
        case "scheduled": .scheduled
        default: (exitCode ?? 0) != 0 ? .error : .unknown
        }
    }
}

public enum DevServiceAction: String, Sendable, CaseIterable {
    case start = "Start"
    case stop = "Stop"
    case restart = "Restart"
}

public struct DevService: Sendable, Equatable, Identifiable {
    public let name: String
    public let source: DevServiceSource
    public let state: DevServiceState
    public let plistPath: String?
    public let pid: Int32?
    public let exitCode: Int?
    /// Brew services run as root are listed but can't be controlled without sudo.
    public let isUserDomain: Bool

    public var id: String { source.rawValue + "/" + name }

    public init(name: String, source: DevServiceSource, state: DevServiceState, plistPath: String?, pid: Int32? = nil,
                exitCode: Int? = nil, isUserDomain: Bool = true) {
        self.name = name
        self.source = source
        self.state = state
        self.plistPath = plistPath
        self.pid = pid
        self.exitCode = exitCode
        self.isUserDomain = isUserDomain
    }
}

public enum DevServiceParser {
    /// Parses `brew services list --json`.
    public static func parseBrewServices(_ json: String, currentUser: String) -> [DevService] {
        guard let data = json.data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            let exitCode = (entry["exit_code"] as? NSNumber)?.intValue
            let user = entry["user"] as? String
            return DevService(name: name, source: .homebrew,
                              state: DevServiceState.fromBrew(entry["status"] as? String ?? "", exitCode: exitCode),
                              plistPath: entry["file"] as? String, exitCode: exitCode,
                              isUserDomain: user == nil || user == currentUser)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Keywords that mark a launchd agent as a local development server rather than an updater or helper.
    public static let devKeywords = [
        "postgres", "redis", "valkey", "mysql", "mariadb", "mongo", "memcached", "elasticsearch", "opensearch",
        "rabbitmq", "nginx", "httpd", "caddy", "minio", "kafka", "zookeeper", "ollama", "clickhouse", "cassandra",
        "influxdb", "etcd", "consul", "vault", "nats", "meilisearch", "typesense", "dnsmasq", "php-fpm", "unbound",
    ]

    /// Labels Homebrew owns; those already appear through `brew services`.
    public static func isBrewManaged(label: String) -> Bool {
        label.hasPrefix("homebrew.mxcl.") || label.hasPrefix("sh.brew.")
    }

    public static func isDevService(label: String, executable: String?) -> Bool {
        guard !isBrewManaged(label: label) else { return false }
        let haystack = (label + " " + ((executable ?? "") as NSString).lastPathComponent).lowercased()
        return devKeywords.contains { haystack.contains($0) }
    }

    /// Picks dev servers out of the user's launch agents and attaches their live status.
    public static func launchdServices(_ items: [LaunchItem], statuses: [String: LaunchStatus]) -> [DevService] {
        items.filter { $0.scope == .userAgent && isDevService(label: $0.label, executable: $0.executable) }.map { item in
            let status = statuses[item.label]
            let state: DevServiceState
            if status?.pid != nil {
                state = .running
            } else if let exit = status?.lastExitStatus, exit != 0 {
                state = .error
            } else {
                state = .stopped
            }
            return DevService(name: item.label, source: .launchd, state: state, plistPath: item.plistPath, pid: status?.pid,
                              exitCode: status?.lastExitStatus.map(Int.init))
        }
    }

    /// `StandardOutPath` / `StandardErrorPath` from a launchd plist, de-duplicated, stderr first.
    public static func logPaths(plist data: Data) -> [String] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return [] }
        var paths: [String] = []
        for key in ["StandardErrorPath", "StandardOutPath"] {
            if let path = dictionary[key] as? String, path.hasPrefix("/"), !paths.contains(path) { paths.append(path) }
        }
        return paths
    }
}

public enum DevServiceCommands {
    /// Arguments for `brew services …`. Names are checked so nothing odd reaches the command line.
    public static func brew(_ action: DevServiceAction, name: String) throws -> [String] {
        guard ToolLocator.isSafeIdentifier(name) else { throw DevCommandError.invalidName(name) }
        return ["services", action.rawValue.lowercased(), name]
    }

    /// launchctl invocations for a user agent. Restart uses kickstart -k, which kills and relaunches.
    public static func launchctl(_ action: DevServiceAction, label: String, plistPath: String, uid: UInt32) throws -> [[String]] {
        guard ToolLocator.isSafeIdentifier(label) else { throw DevCommandError.invalidName(label) }
        guard plistPath.hasPrefix("/"), plistPath.hasSuffix(".plist") else { throw DevCommandError.invalidName(plistPath) }
        let domain = "gui/\(uid)"
        switch action {
        case .start: return [["bootstrap", domain, plistPath], ["kickstart", "\(domain)/\(label)"]]
        case .stop: return [["bootout", domain, plistPath]]
        case .restart: return [["kickstart", "-k", "\(domain)/\(label)"]]
        }
    }
}

public enum LogTail {
    /// The last `count` non-empty lines of `data`, decoding leniently since logs may be cut mid-character.
    /// `startsMidLine` drops the first line, which is partial when reading began part-way through a file.
    public static func lastLines(_ data: Data, count: Int, startsMidLine: Bool = false) -> [String] {
        guard count > 0 else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if startsMidLine, !lines.isEmpty { lines.removeFirst() }
        let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(kept.suffix(count))
    }

    /// Reads only the end of the file so multi-gigabyte logs stay cheap.
    public static func read(path: String, lines: Int = 200, maxBytes: UInt64 = 64 * 1024) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            try handle.seek(toOffset: end > maxBytes ? end - maxBytes : 0)
            let data = try handle.readToEnd() ?? Data()
            return lastLines(data, count: lines, startsMidLine: end > maxBytes)
        } catch {
            return nil
        }
    }
}

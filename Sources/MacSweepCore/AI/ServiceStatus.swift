import Foundation

/// A provider's public status page (Atlassian Statuspage). Only the public summary is fetched; nothing about the user is sent.
public struct ServiceStatus: Sendable, Equatable {
    public enum Level: String, Sendable {
        case operational, degraded, outage, unknown
    }

    public struct Component: Sendable, Equatable, Identifiable {
        public let name: String
        public let level: Level
        public let detail: String
        public var id: String { name }
    }

    public struct Incident: Sendable, Equatable, Identifiable {
        public let name: String
        public let impact: Level
        public let state: String
        public let link: URL?
        public var id: String { name }
    }

    public let level: Level
    public let description: String
    public let components: [Component]
    public let incidents: [Incident]

    /// Where each tool's status page and usage dashboard live.
    public struct Links: Sendable {
        public let statusPage: URL?
        public let summary: URL?
        public let dashboard: URL?

        public static func of(_ provider: AIProvider) -> Links {
            switch provider {
            case .claudeCode:
                return Links(statusPage: URL(string: "https://status.claude.com"), summary: URL(string: "https://status.claude.com/api/v2/summary.json"),
                             dashboard: URL(string: "https://claude.ai/settings/usage"))
            case .codex:
                return Links(statusPage: URL(string: "https://status.openai.com"), summary: URL(string: "https://status.openai.com/api/v2/summary.json"),
                             dashboard: URL(string: "https://chatgpt.com/codex/settings/usage"))
            }
        }
    }

    public static func parse(_ data: Data) -> ServiceStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any] else { return nil }
        let components = (json["components"] as? [[String: Any]] ?? []).compactMap { item -> Component? in
            guard item["group"] as? Bool != true, let name = item["name"] as? String, let state = item["status"] as? String else { return nil }
            return Component(name: name, level: componentLevel(state), detail: state.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        let incidents = (json["incidents"] as? [[String: Any]] ?? []).compactMap { item -> Incident? in
            guard let name = item["name"] as? String else { return nil }
            let state = (item["status"] as? String ?? "").replacingOccurrences(of: "_", with: " ").capitalized
            return Incident(name: name, impact: indicatorLevel(item["impact"] as? String), state: state,
                            link: (item["shortlink"] as? String).flatMap(URL.init(string:)))
        }
        return ServiceStatus(level: indicatorLevel(status["indicator"] as? String), description: status["description"] as? String ?? "Unknown",
                             components: components, incidents: incidents)
    }

    static func indicatorLevel(_ indicator: String?) -> Level {
        switch indicator {
        case "none": return .operational
        case "minor", "maintenance": return .degraded
        case "major", "critical": return .outage
        default: return .unknown
        }
    }

    static func componentLevel(_ status: String) -> Level {
        switch status {
        case "operational": return .operational
        case "degraded_performance", "partial_outage", "under_maintenance": return .degraded
        case "major_outage": return .outage
        default: return .unknown
        }
    }

    public static func fetch(_ provider: AIProvider, session: URLSession = .shared) async throws -> ServiceStatus {
        guard let url = Links.of(provider).summary else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let status = parse(data) else { throw URLError(.cannotParseResponse) }
        return status
    }
}

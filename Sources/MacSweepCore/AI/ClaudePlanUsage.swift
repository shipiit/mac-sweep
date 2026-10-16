import Foundation
import os
import Security

/// Claude subscription limits from Anthropic's usage endpoint, read with Claude Code's own sign-in.
/// Opt-in and read-only: the token is read from the Keychain (or ~/.claude/.credentials.json), used for one GET,
/// never refreshed, written, logged or kept beyond the request.
public struct ClaudePlanUsage: Sendable, Equatable {
    public struct Window: Sendable, Equatable, Identifiable {
        public let name: String
        /// Percent used, 0...100.
        public let utilization: Double
        public let resetsAt: Date?
        public var id: String { name }
        public var percentLeft: Int { Int((100 - min(max(utilization, 0), 100)).rounded()) }
    }

    public struct ExtraUsage: Sendable, Equatable {
        public let isEnabled: Bool
        public let usedCredits: Double
        public let monthlyLimit: Double?
    }

    public let session: Window?
    public let weekly: Window?
    /// Per-model weekly windows (e.g. "Opus", "Fable"), largest use first.
    public let modelWeekly: [Window]
    public let extra: ExtraUsage?
    public var plan: String?

    public enum FetchError: Error, Equatable {
        case notSignedIn, expired, unavailable
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")
    private static let log = Logger(subsystem: Log.subsystem, category: "claude-plan")

    public static func parse(_ data: Data) -> ClaudePlanUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let models = json.keys.filter { $0.hasPrefix("seven_day_") }.compactMap { key -> Window? in
            let suffix = key.dropFirst("seven_day_".count)
            guard !suffix.isEmpty, !suffix.contains("oauth") else { return nil }
            return window(json[key], name: suffix.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " "))
        }
        .sorted { ($0.utilization, $1.name) > ($1.utilization, $0.name) }
        let extra = (json["extra_usage"] as? [String: Any]).map {
            ExtraUsage(isEnabled: $0["is_enabled"] as? Bool ?? false, usedCredits: number($0["used_credits"]) ?? 0, monthlyLimit: number($0["monthly_limit"]))
        }
        let usage = ClaudePlanUsage(session: window(json["five_hour"], name: "Session"), weekly: window(json["seven_day"], name: "Weekly"),
                                    modelWeekly: models, extra: extra, plan: nil)
        return usage.session == nil && usage.weekly == nil && models.isEmpty ? nil : usage
    }

    static func window(_ value: Any?, name: String) -> Window? {
        guard let object = value as? [String: Any], let utilization = number(object["utilization"]) else { return nil }
        return Window(name: name, utilization: utilization, resetsAt: UsageTime.parse(object["resets_at"] as? String) ?? plainDate(object["resets_at"] as? String))
    }

    static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func plainDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    // MARK: Credentials

    struct Credentials: Equatable {
        let accessToken: String
        let expiresAt: Date?
        let plan: String?
    }

    static func parseCredentials(_ data: Data) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1_000) }
        return Credentials(accessToken: token, expiresAt: expires, plan: planName(tier: oauth["rateLimitTier"] as? String, type: oauth["subscriptionType"] as? String))
    }

    /// "default_claude_max_20x" → "Max 20x"; falls back to the subscription type.
    static func planName(tier: String?, type: String?) -> String? {
        if let tier, let range = tier.range(of: "claude_") {
            let words = tier[range.upperBound...].split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            if !words.isEmpty { return words.joined(separator: " ") }
        }
        return type.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    static func keychainData() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func readCredentials(home: String = NSHomeDirectory(), keychain: () -> Data? = keychainData) -> Credentials? {
        if let credentials = keychain().flatMap(parseCredentials) { return credentials }
        return FileManager.default.contents(atPath: home + "/.claude/.credentials.json").flatMap(parseCredentials)
    }

    public static func fetch(session: URLSession = .shared, now: Date = Date()) async throws -> ClaudePlanUsage {
        guard let credentials = readCredentials() else { throw FetchError.notSignedIn }
        if let expires = credentials.expiresAt, expires <= now { throw FetchError.expired }
        guard let url = endpoint else { throw FetchError.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw FetchError.expired }
        guard status == 200, var usage = parse(data) else {
            log.error("Claude plan usage request failed with HTTP \(status)")
            throw FetchError.unavailable
        }
        usage.plan = credentials.plan
        return usage
    }
}

import Foundation

public struct TokenTotals: Codable, Sendable, Equatable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheWrite5m: Int = 0
    public var cacheWrite1h: Int = 0
    public var cacheRead: Int = 0
    public var requests: Int = 0

    public init() {}

    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    /// Every token billed in some form, including cheap cache reads.
    public var total: Int { input + output + cacheWrite + cacheRead }
    /// Share of prompt tokens served from cache (higher is cheaper).
    public var cacheHitRate: Double {
        let prompt = input + cacheWrite + cacheRead
        return prompt > 0 ? Double(cacheRead) / Double(prompt) : 0
    }

    public static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        var sum = lhs
        sum.input += rhs.input
        sum.output += rhs.output
        sum.cacheWrite5m += rhs.cacheWrite5m
        sum.cacheWrite1h += rhs.cacheWrite1h
        sum.cacheRead += rhs.cacheRead
        sum.requests += rhs.requests
        return sum
    }
}

public struct ModelPrice: Sendable, Equatable {
    /// USD per million tokens.
    public let input: Double
    public let output: Double
    public let cacheRead: Double
}

/// Anthropic first-party API list prices (cached 2026-10-06). Cache writes cost 1.25x input for the
/// 5-minute TTL and 2x for 1 hour. Claude Code on a subscription isn't billed per token, so these are
/// "API-equivalent" estimates. Codex models use OpenAI's standard short-context (≤272K input) rates from
/// developers.openai.com/api/docs/pricing (checked 2026-10-16); OpenAI also bills cache writes at 1.25x input.
/// Unknown models return nil rather than a guessed price.
public enum AIPricing {
    static let table: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        "claude-mythos-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.10),
        "gpt-6.1-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.10),
        "gpt-6-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "gpt-6-astra": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        // Promotional rate, published as available at least through 2026-11-21.
        "gpt-5.6-sol": ModelPrice(input: 4, output: 20, cacheRead: 0.40),
    ]

    /// Matches exact ids and ids with a trailing date or variant suffix (`claude-opus-4-6-20260101`, `…[1m]`).
    public static func price(for model: String) -> ModelPrice? {
        let normalized = model.lowercased().replacingOccurrences(of: "[1m]", with: "")
        if let exact = table[normalized] { return exact }
        return table.keys.sorted { $0.count > $1.count }.first { normalized.hasPrefix($0 + "-") }.flatMap { table[$0] }
    }

    public static func cost(_ totals: TokenTotals, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        let perToken = 1.0 / 1_000_000
        return (Double(totals.input) * price.input
            + Double(totals.output) * price.output
            + Double(totals.cacheWrite5m) * price.input * 1.25
            + Double(totals.cacheWrite1h) * price.input * 2
            + Double(totals.cacheRead) * price.cacheRead) * perToken
    }

    public static func displayName(_ model: String) -> String {
        if model.lowercased().hasPrefix("gpt-") {
            let parts = model.split(separator: "-").dropFirst()
            guard let version = parts.first else { return model.uppercased() }
            let variant = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return "GPT-\(version)" + (variant.isEmpty ? "" : " " + variant)
        }
        let trimmed = model.replacingOccurrences(of: "claude-", with: "")
        let parts = trimmed.split(separator: "-")
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }.joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }
}

import Foundation

/// Reads only the usage fields of Claude Code and Codex transcripts. Message text is never decoded
/// into the result and nothing leaves the Mac.
public enum TranscriptParsers {
    /// Claude Code: one JSON object per line; assistant lines carry `message.usage`. Streaming writes the
    /// same message several times, so lines are de-duplicated by message id + request id.
    public static func parseClaude(path: String, now: Date = Date(), calendar: Calendar = .current) -> ([UsageEntry], [UsageEvent]) {
        let (entries, events, _) = parseClaudeWithTitles(path: path, now: now, calendar: calendar)
        return (entries, events)
    }

    /// Also collects session titles: `custom-title` (set with /rename) wins over `ai-title`.
    public static func parseClaudeWithTitles(path: String, now: Date = Date(), calendar: Calendar = .current)
        -> ([UsageEntry], [UsageEvent], [String: String]) {
        let result = parseClaude(path: path, from: 0, recentKeys: [], now: now, calendar: calendar)
        return (result.entries, result.events, result.titles)
    }

    public struct ClaudeChunk: Sendable {
        public var entries: [UsageEntry]
        public var events: [UsageEvent]
        public var titles: [String: String]
        /// Where the next incremental read starts.
        public var endOffset: UInt64
        /// Last de-duplication keys, carried over so a message split across reads isn't counted twice.
        public var recentKeys: [String]
    }

    /// Reads from `offset` (0 = whole file). Streaming duplicates sit next to each other, so the last few
    /// hundred keys are enough to de-duplicate across reads.
    public static func parseClaude(path: String, from offset: UInt64, recentKeys: [String], now: Date = Date(),
                                   calendar: Calendar = .current) -> ClaudeChunk {
        var accumulator = EntryAccumulator(recentCutoff: now.addingTimeInterval(-24 * 3_600))
        var seen = Set(recentKeys)
        var order = recentKeys
        var aiTitles: [String: String] = [:]
        var customTitles: [String: String] = [:]
        LineReader.forEachLine(path: path, from: offset, containing: Array("-title\"".utf8)) { line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let session = json["sessionId"] as? String else { return }
            if let title = json["customTitle"] as? String, !title.isEmpty { customTitles[session] = title }
            if let title = json["aiTitle"] as? String, !title.isEmpty { aiTitles[session] = title }
        }
        let fallbackProject = ProjectNames.fromClaudeFolder((path as NSString).deletingLastPathComponent)
        let end = LineReader.forEachLine(path: path, from: offset, containing: Array("\"usage\"".utf8)) { line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String, model != "<synthetic>",
                  let time = UsageTime.parse(json["timestamp"] as? String)
            else { return }
            let key = (message["id"] as? String ?? "") + ":" + (json["requestId"] as? String ?? "")
            guard key == ":" || seen.insert(key).inserted else { return }
            if key != ":" { order.append(key) }
            let project = (json["cwd"] as? String).map(ProjectNames.short) ?? fallbackProject
            let session = json["sessionId"] as? String ?? (path as NSString).lastPathComponent
            accumulator.add(provider: .claudeCode, time: time, model: model, project: project, session: session,
                            totals: claudeTotals(usage), calendar: calendar)
            // Advisor sub-calls are billed separately and are not part of the top-level usage numbers.
            for iteration in usage["iterations"] as? [[String: Any]] ?? [] where iteration["type"] as? String == "advisor_message" {
                var advisor = claudeTotals(iteration)
                advisor.requests = 0
                accumulator.add(provider: .claudeCode, time: time, model: iteration["model"] as? String ?? model, project: project,
                                session: session, totals: advisor, calendar: calendar)
            }
        }
        return ClaudeChunk(entries: accumulator.all, events: accumulator.events, titles: aiTitles.merging(customTitles) { _, custom in custom },
                           endOffset: end, recentKeys: Array(order.suffix(256)))
    }

    static func claudeTotals(_ usage: [String: Any]) -> TokenTotals {
        var totals = TokenTotals()
        totals.input = usage["input_tokens"] as? Int ?? 0
        totals.output = usage["output_tokens"] as? Int ?? 0
        totals.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        if let creation = usage["cache_creation"] as? [String: Any] {
            totals.cacheWrite5m = creation["ephemeral_5m_input_tokens"] as? Int ?? 0
            totals.cacheWrite1h = creation["ephemeral_1h_input_tokens"] as? Int ?? 0
        } else {
            totals.cacheWrite5m = usage["cache_creation_input_tokens"] as? Int ?? 0
        }
        totals.requests = 1
        return totals
    }

    /// Codex: `token_count` events carry per-turn usage (`last_token_usage`) and the account's rate limits.
    public static func parseCodex(path: String, now: Date = Date(), calendar: Calendar = .current)
        -> ([UsageEntry], [UsageEvent], CodexRateLimits?) {
        var accumulator = EntryAccumulator(recentCutoff: now.addingTimeInterval(-24 * 3_600))
        var model = "codex"
        var project = "Codex"
        var session = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var limits: CodexRateLimits?
        LineReader.forEachLine(path: path, containing: []) { line in
            guard line.range(of: Data("token_count".utf8)) != nil
                    || line.range(of: Data("turn_context".utf8)) != nil
                    || line.range(of: Data("session_meta".utf8)) != nil,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = json["payload"] as? [String: Any]
            else { return }
            switch json["type"] as? String {
            case "session_meta":
                if let cwd = payload["cwd"] as? String { project = ProjectNames.short(cwd) }
                if let id = payload["id"] as? String { session = id }
            case "turn_context":
                if let name = payload["model"] as? String { model = name }
            default:
                guard payload["type"] as? String == "token_count", let time = UsageTime.parse(json["timestamp"] as? String) else { return }
                if let rate = payload["rate_limits"] as? [String: Any] {
                    // Some events carry empty windows; keep the latest real value for each.
                    let primary = window(rate["primary"]) ?? limits?.primary
                    let secondary = window(rate["secondary"]) ?? limits?.secondary
                    if primary != nil || secondary != nil {
                        limits = CodexRateLimits(observedAt: time, primary: primary, secondary: secondary)
                    }
                }
                guard let info = payload["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] else { return }
                var totals = TokenTotals()
                let cached = last["cached_input_tokens"] as? Int ?? 0
                totals.input = max((last["input_tokens"] as? Int ?? 0) - cached, 0)
                totals.cacheRead = cached
                totals.cacheWrite5m = last["cache_write_input_tokens"] as? Int ?? 0
                totals.output = last["output_tokens"] as? Int ?? 0
                totals.requests = 1
                accumulator.add(provider: .codex, time: time, model: model, project: project, session: session,
                                totals: totals, calendar: calendar)
            }
        }
        return (accumulator.all, accumulator.events, limits)
    }

    static func window(_ value: Any?) -> RateLimitWindow? {
        guard let dictionary = value as? [String: Any], let used = (dictionary["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let resets = (dictionary["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return RateLimitWindow(usedPercent: used, windowMinutes: dictionary["window_minutes"] as? Int ?? 0, resetsAt: resets)
    }
}

public enum ProjectNames {
    /// Last two path components of a working directory: "/Users/me/work/api" -> "work/api".
    public static func short(_ cwd: String) -> String {
        let parts = cwd.split(separator: "/")
        return parts.suffix(2).joined(separator: "/").isEmpty ? cwd : parts.suffix(2).joined(separator: "/")
    }

    /// Claude Code folder names encode the path with dashes ("-Users-me-work-api").
    static func fromClaudeFolder(_ folder: String) -> String {
        let name = (folder as NSString).lastPathComponent
        let parts = name.split(separator: "-")
        return parts.suffix(2).joined(separator: "/")
    }
}

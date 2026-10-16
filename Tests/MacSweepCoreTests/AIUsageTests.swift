import Foundation
import Testing
@testable import MacSweepCore

@Suite struct AIPricingTests {
    @Test func pricesKnownModelsIncludingSuffixes() {
        #expect(AIPricing.price(for: "claude-opus-5-5")?.input == 4)
        #expect(AIPricing.price(for: "claude-opus-4-6-20260101")?.output == 25)
        #expect(AIPricing.price(for: "claude-sonnet-5-5[1m]")?.cacheRead == 0.20)
        #expect(AIPricing.price(for: "claude-opus-5")?.input == 5)
        #expect(AIPricing.price(for: "gpt-6.1-sol")?.cacheRead == 0.10)
        #expect(AIPricing.price(for: "gpt-6-astra")?.output == 50)
        #expect(AIPricing.price(for: "gpt-4o") == nil)
        #expect(AIPricing.price(for: "claude-3-opus") == nil)
    }

    @Test func costUsesCacheMultipliers() throws {
        var totals = TokenTotals()
        totals.input = 1_000_000
        totals.output = 1_000_000
        totals.cacheWrite5m = 1_000_000
        totals.cacheWrite1h = 1_000_000
        totals.cacheRead = 1_000_000
        let cost = try #require(AIPricing.cost(totals, model: "claude-opus-5-5"))
        #expect(abs(cost - (4 + 20 + 5 + 8 + 0.20)) < 0.0001)
        #expect(AIPricing.cost(totals, model: "unknown") == nil)
    }

    @Test func totalsAndCacheHitRate() {
        var totals = TokenTotals()
        totals.input = 100
        totals.cacheRead = 300
        #expect(totals.cacheHitRate == 0.75)
        #expect(TokenTotals().cacheHitRate == 0)
        #expect((totals + totals).total == 800)
    }

    @Test func displayNames() {
        #expect(AIPricing.displayName("claude-opus-5-5") == "Opus 5.5")
        #expect(AIPricing.displayName("claude-sonnet-4-6-20260101") == "Sonnet 4.6")
        #expect(AIPricing.displayName("gpt-6.1-sol") == "GPT-6.1 Sol")
        #expect(AIPricing.displayName("gpt-6") == "GPT-6")
        #expect(AIPricing.displayName("gpt-") == "GPT-")
    }
}

@Suite struct TranscriptParserTests {
    let now = Date(timeIntervalSince1970: 1_791_500_000)

    func write(_ lines: [String], name: String) throws -> String {
        let dir = try Fixtures.makeTempDir()
        let path = dir + "/" + name
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func parsesClaudeWithDedupeAndCacheSplit() throws {
        let line = #"{"type":"assistant","timestamp":"2026-10-03T10:00:00.000Z","cwd":"/Users/x/work/api","sessionId":"s1","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_1h_input_tokens":50,"ephemeral_5m_input_tokens":0}}}}"#
        let second = line.replacingOccurrences(of: "\"m1\"", with: "\"m2\"").replacingOccurrences(of: "\"r1\"", with: "\"r2\"")
        let synthetic = second.replacingOccurrences(of: "claude-opus-5-5", with: "<synthetic>").replacingOccurrences(of: "\"m2\"", with: "\"m3\"")
        let user = #"{"type":"user","message":{"content":"hello \"usage\""}}"#
        let path = try write([line, line, second, synthetic, user, "not json"], name: "s1.jsonl")
        let (entries, events) = TranscriptParsers.parseClaude(path: path, now: now)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.totals.requests == 2)
        #expect(entry.totals.input == 20 && entry.totals.output == 40 && entry.totals.cacheWrite1h == 100 && entry.totals.cacheRead == 600)
        #expect(entry.project == "work/api" && entry.session == "s1" && entry.model == "claude-opus-5-5")
        #expect(events.isEmpty, "events older than 24h are not kept")
        let (_, recent) = TranscriptParsers.parseClaude(path: path, now: Date(timeIntervalSince1970: 1_791_028_800))
        #expect(recent.count == 2)
    }

    @Test func parsesCodexUsageAndRateLimits() throws {
        let lines = [
            #"{"timestamp":"2026-10-03T09:00:00Z","type":"session_meta","payload":{"id":"cx1","cwd":"/Users/x/work/web"}}"#,
            #"{"timestamp":"2026-10-03T09:00:01Z","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#,
            #"{"timestamp":"2026-10-03T09:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":50,"cache_write_input_tokens":0}},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1791558668},"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1791900000}}}}"#,
            #"{"timestamp":"2026-10-03T09:01:05Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":13,"window_minutes":300}}}}"#,
        ]
        let path = try write(lines, name: "rollout.jsonl")
        let (entries, _, limits) = TranscriptParsers.parseCodex(path: path, now: now)
        let entry = try #require(entries.first)
        #expect(entry.model == "gpt-6.1-sol" && entry.project == "work/web" && entry.session == "cx1")
        #expect(entry.totals.input == 600 && entry.totals.cacheRead == 400 && entry.totals.output == 50)
        #expect(limits?.primary?.usedPercent == 13)
        #expect(limits?.secondary?.usedPercent == 45, "a later event without the weekly window keeps the last known value")
    }

    @Test func readsSessionTitlesPreferringCustom() throws {
        let lines = [
            #"{"type":"ai-title","aiTitle":"Fix login bug","sessionId":"s1"}"#,
            #"{"type":"custom-title","customTitle":"Auth refactor","sessionId":"s1"}"#,
            #"{"type":"ai-title","aiTitle":"Speed up scans","sessionId":"s2"}"#,
        ]
        let path = try write(lines, name: "titles.jsonl")
        let (_, _, titles) = TranscriptParsers.parseClaudeWithTitles(path: path, now: now)
        #expect(titles == ["s1": "Auth refactor", "s2": "Speed up scans"])
    }

    @Test func codexKeepsLastNonEmptyWindows() throws {
        let lines = [
            #"{"timestamp":"2026-10-03T09:00:05Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20,"window_minutes":300},"secondary":{"used_percent":45,"window_minutes":10080}}}}"#,
            #"{"timestamp":"2026-10-03T09:05:05Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":null,"secondary":null}}}"#,
        ]
        let path = try write(lines, name: "codex.jsonl")
        let (_, _, limits) = TranscriptParsers.parseCodex(path: path, now: now)
        #expect(limits?.primary?.usedPercent == 20 && limits?.secondary?.usedPercent == 45)
    }

    @Test func projectNames() {
        #expect(ProjectNames.short("/Users/x/work/api") == "work/api")
        #expect(ProjectNames.fromClaudeFolder("/root/.claude/projects/-Users-x-work-api") == "work/api")
    }
}

@Suite struct AIUsageIndexTests {
    @Test func refreshReusesUnchangedFilesAndDropsDeletedOnes() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let claude = root + "/claude/proj"
        try FileManager.default.createDirectory(atPath: claude, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","timestamp":"2026-01-03T10:00:00Z","sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"output_tokens":5}}}"#
        try line.write(toFile: claude + "/a.jsonl", atomically: true, encoding: .utf8)
        let old = Date().addingTimeInterval(-3 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: claude + "/a.jsonl")
        let sources = AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex")

        let first = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        #expect(first.entries.count == 1)
        var tampered = first
        tampered.files[claude + "/a.jsonl"]?.entries[0].totals.output = 999
        let second = AIUsageScanner.refresh(tampered, sources: sources)
        #expect(second.entries.first?.totals.output == 999)

        try FileManager.default.removeItem(atPath: claude + "/a.jsonl")
        #expect(AIUsageScanner.refresh(second, sources: sources).files.isEmpty)
    }

    @Test func mergesCodexWindowsAcrossFiles() {
        var index = AIUsageIndex()
        let early = CodexRateLimits(observedAt: Date(timeIntervalSince1970: 100), primary: nil,
                                    secondary: RateLimitWindow(usedPercent: 40, windowMinutes: 10080, resetsAt: nil))
        let late = CodexRateLimits(observedAt: Date(timeIntervalSince1970: 200),
                                   primary: RateLimitWindow(usedPercent: 5, windowMinutes: 300, resetsAt: nil), secondary: nil)
        index.files["/a"] = FileUsage(size: 1, modified: .distantPast, entries: [], events: [], rateLimits: early)
        index.files["/b"] = FileUsage(size: 1, modified: .distantPast, entries: [], events: [], rateLimits: late, titles: ["s": "T"])
        #expect(index.latestCodexLimits?.primary?.usedPercent == 5 && index.latestCodexLimits?.secondary?.usedPercent == 40)
        #expect(index.sessionTitles == ["s": "T"])
    }

    @Test func storeRoundTrip() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = AIUsageStore(url: URL(fileURLWithPath: dir + "/i.plist"))
        #expect(store.load() == AIUsageIndex())
        var index = AIUsageIndex()
        index.files["/x"] = FileUsage(size: 1, modified: Date(timeIntervalSince1970: 1), entries: [], events: [], rateLimits: nil)
        try store.save(index)
        #expect(store.load() == index)
    }
}

@Suite struct AIUsageSummaryTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    func entry(_ day: Int, _ provider: AIProvider = .claudeCode, model: String = "claude-opus-5-5", project: String = "p", output: Int = 1_000_000) -> UsageEntry {
        var totals = TokenTotals()
        totals.output = output
        totals.requests = 1
        return UsageEntry(provider: provider, day: String(format: "2026-10-%02d", day), model: model, project: project, session: "s\(day)",
                          totals: totals, first: date(day, 9), last: date(day, 10))
    }

    @Test func filtersByRangeAndProvider() {
        let entries = [entry(8), entry(14), entry(16), entry(16, .codex, model: "gpt-6")]
        #expect(AIUsageSummary.filter(entries, provider: nil, days: 1, now: date(16, 12), calendar: calendar).count == 2)
        #expect(AIUsageSummary.filter(entries, provider: .claudeCode, days: 7, now: date(16, 12), calendar: calendar).count == 2)
        #expect(AIUsageSummary.filter(entries, provider: nil, days: 30, now: date(16, 12), calendar: calendar).count == 4)
    }

    @Test func costsAndGroups() {
        let entries = [entry(16), entry(16, project: "q"), entry(16, .codex, model: "gpt-6")]
        let cost = AIUsageSummary.cost(of: entries)
        #expect(cost.known == 40 && cost.hasUnknown)
        let byProject = AIUsageSummary.group(entries, by: \.project)
        #expect(byProject.first?.key == "p" && byProject.first?.totals.output == 2_000_000)
        #expect(AIUsageSummary.daily(entries, days: 3, now: date(16, 12), calendar: calendar).map(\.tokens) == [0, 0, 3_000_000])
    }

    @Test func currentBlockStartsOnTheHourAndTracksBurn() throws {
        func event(_ hour: Int, _ minute: Int) -> UsageEvent {
            var totals = TokenTotals()
            totals.output = 1_000
            return UsageEvent(provider: .claudeCode, time: date(16, hour, minute), model: "claude-opus-5-5", totals: totals)
        }
        let events = [event(1, 30), event(9, 20), event(10, 5), event(11, 50)]
        let block = try #require(AIUsageSummary.currentBlock(events, now: date(16, 12), calendar: calendar))
        #expect(block.start == date(16, 9) && block.end == date(16, 14))
        #expect(block.totals.output == 3_000 && block.isActive)
        #expect(block.burnPerHour == 1_000)
        #expect(AIUsageSummary.currentBlock([], now: date(16, 12)) == nil)
        let later = try #require(AIUsageSummary.currentBlock(events, now: date(16, 20), calendar: calendar))
        #expect(!later.isActive)
    }
}

@Suite struct TranscriptCleanupTests {
    @Test func findsOnlyOldTranscripts() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Fixtures.write(root + "/claude/p/old.jsonl", bytes: 100)
        try Fixtures.write(root + "/claude/p/new.jsonl", bytes: 100)
        try Fixtures.write(root + "/codex/2026/01/01/old.jsonl", bytes: 50)
        try Fixtures.write(root + "/claude/p/notes.txt", bytes: 10)
        let old = Date().addingTimeInterval(-100 * 86_400)
        for path in ["/claude/p/old.jsonl", "/codex/2026/01/01/old.jsonl", "/claude/p/notes.txt"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: root + path)
        }
        let targets = TranscriptCleanup.old(olderThanDays: 90, sources: AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex"))
        #expect(targets.map { ($0.path as NSString).lastPathComponent } == ["old.jsonl", "old.jsonl"])
        #expect(TranscriptCleanup.old(olderThanDays: 200, sources: AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex")).isEmpty)
    }
}

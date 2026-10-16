import Foundation
import Testing
@testable import MacSweepCore

@Suite struct AdvisorUsageTests {
    let line = #"{"type":"assistant","timestamp":"2026-01-03T10:00:00Z","sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"output_tokens":7,"iterations":[{"type":"message","input_tokens":5,"output_tokens":7},{"type":"advisor_message","model":"claude-opus-5-5","input_tokens":1000,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":0}},{"type":"advisor_message","input_tokens":10,"output_tokens":1}]}}}"#

    func makeTranscript() throws -> (root: String, file: String) {
        let root = try Fixtures.makeTempDir()
        let folder = root + "/claude/proj"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let file = folder + "/a.jsonl"
        try line.write(toFile: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: file)
        return (root, file)
    }

    @Test func countsAdvisorCallsUnderTheirOwnModel() throws {
        let (root, file) = try makeTranscript()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let (entries, _) = TranscriptParsers.parseClaude(path: file)
        let sonnet = try #require(entries.first { $0.model == "claude-sonnet-5-5" })
        let opus = try #require(entries.first { $0.model == "claude-opus-5-5" })
        #expect(sonnet.totals.input == 15 && sonnet.totals.output == 8, "advisor without a model falls back to the message model")
        #expect(sonnet.totals.requests == 1, "only the top-level message counts as a request")
        #expect(opus.totals.input == 1000 && opus.totals.output == 100 && opus.totals.cacheWrite5m == 20)
        #expect(opus.totals.requests == 0)
    }

    @Test func noIterationsLeavesTotalsUnchanged() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let plain = #"{"type":"assistant","timestamp":"2026-01-03T10:00:00Z","sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","usage":{"input_tokens":3,"output_tokens":4,"iterations":[]}}}"#
        try plain.write(toFile: root + "/p.jsonl", atomically: true, encoding: .utf8)
        let (entries, _) = TranscriptParsers.parseClaude(path: root + "/p.jsonl")
        #expect(entries.count == 1 && entries[0].totals.input == 3 && entries[0].totals.output == 4)
    }

    @Test func outdatedParserVersionIsReparsed() throws {
        let (root, file) = try makeTranscript()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let sources = AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex")
        let first = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        #expect(first.files[file]?.parserVersion == FileUsage.currentParserVersion)

        var stale = first
        stale.files[file]?.entries = []
        stale.files[file]?.parserVersion = nil
        #expect(AIUsageScanner.refresh(stale, sources: sources).entries.count == 2)

        var current = first
        current.files[file]?.entries = []
        #expect(AIUsageScanner.refresh(current, sources: sources).entries.isEmpty, "up-to-date records are reused")
    }
}

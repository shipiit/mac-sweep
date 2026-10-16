import Foundation
import Testing
@testable import MacSweepCore

@Suite struct IncrementalIndexTests {
    func line(_ id: String, input: Int, time: String = "2026-01-03T10:00:00Z") -> String {
        #"{"type":"assistant","timestamp":"\#(time)","sessionId":"s","requestId":"r\#(id)","message":{"id":"m\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"output_tokens":1}}}"#
    }

    func setUp() throws -> (root: String, file: String, sources: AIUsageSources) {
        let root = try Fixtures.makeTempDir()
        let folder = root + "/claude/proj"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return (root, folder + "/a.jsonl", AIUsageSources(claudeRoot: root + "/claude", codexRoot: root + "/codex"))
    }

    func append(_ text: String, to file: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func appendedLinesAreReadIncrementallyWithoutDoubleCounting() throws {
        let (root, file, sources) = try setUp()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try (line("1", input: 10) + "\n" + line("1", input: 10) + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        let first = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        #expect(first.entries.first?.totals.input == 10)
        let offset = try #require(first.files[file]?.offset)
        #expect(offset == UInt64(try Data(contentsOf: URL(fileURLWithPath: file)).count))

        // A streaming duplicate of message 1 plus a new message 2.
        try append(line("1", input: 10) + "\n" + line("2", input: 5) + "\n", to: file)
        let second = AIUsageScanner.refresh(first, sources: sources)
        #expect(second.entries.count == 1)
        #expect(second.entries.first?.totals.input == 15 && second.entries.first?.totals.requests == 2)
        #expect((second.files[file]?.offset ?? 0) > offset)
    }

    @Test func partialTrailingLineIsNotConsumed() throws {
        let (root, file, sources) = try setUp()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try (line("1", input: 10) + "\n" + line("2", input: 7)).write(toFile: file, atomically: true, encoding: .utf8)
        let first = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        #expect(first.entries.first?.totals.input == 17, "complete trailing JSON is still counted")
        try append("\n" + line("3", input: 1) + "\n", to: file)
        let second = AIUsageScanner.refresh(first, sources: sources)
        #expect(second.entries.first?.totals.input == 18, "the trailing line is de-duplicated when re-read")
    }

    @Test func shrunkFileIsFullyReparsed() throws {
        let (root, file, sources) = try setUp()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try (line("1", input: 10) + "\n" + line("2", input: 10) + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        let first = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        try (line("3", input: 4) + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        let second = AIUsageScanner.refresh(first, sources: sources)
        #expect(second.entries.first?.totals.input == 4)
    }

    @Test func unchangedFilesAreNotReadAndOldEventsArePruned() throws {
        let (root, file, sources) = try setUp()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try (line("1", input: 10) + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        var index = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        index.files[file]?.entries[0].totals.input = 999
        index.files[file]?.events = [UsageEvent(provider: .claudeCode, time: .distantPast, model: "m", totals: TokenTotals())]
        let again = AIUsageScanner.refresh(index, sources: sources)
        #expect(again.entries.first?.totals.input == 999)
        #expect(again.files[file]?.events.isEmpty == true)
    }

    @Test func parallelParseHandlesManyFilesAndEmptyWork() throws {
        let (root, _, sources) = try setUp()
        defer { try? FileManager.default.removeItem(atPath: root) }
        for number in 0..<9 {
            try (line("\(number)", input: 1) + "\n").write(toFile: root + "/claude/proj/f\(number).jsonl", atomically: true, encoding: .utf8)
        }
        let index = AIUsageScanner.refresh(AIUsageIndex(), sources: sources)
        #expect(index.files.count == 9 && index.entries.reduce(0) { $0 + $1.totals.input } == 9)
        #expect(AIUsageScanner.parse([], now: Date(), progress: nil).isEmpty)
    }
}

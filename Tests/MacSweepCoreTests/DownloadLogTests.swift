import Foundation
import Testing
@testable import MacSweepCore

@Suite struct DownloadLogTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func outcomes() {
        let doc = DownloadRecord.make(path: "/d/report.pdf", size: 10, date: date, facts: nil, verdict: nil)
        #expect(doc.outcome == .safeType && doc.kind == "Document" && doc.signer == nil)
        let appFacts = FileFacts(path: "/d/Tool.app", kind: .app, signature: .developer(teamID: "ABC"), origin: "https://example.com/dl/tool.zip")
        let passed = DownloadRecord.make(path: "/d/Tool.app", size: 5, date: date, facts: appFacts, verdict: nil)
        #expect(passed.outcome == .passed && passed.originHost == "example.com" && passed.signer?.contains("ABC") == true)
        let bad = ThreatVerdict(facts: appFacts, severity: .high, reasons: ["Disguised"])
        #expect(DownloadRecord.make(path: "/d/Tool.app", size: 5, date: date, facts: appFacts, verdict: bad).outcome == .quarantined)
        let meh = ThreatVerdict(facts: appFacts, severity: .medium, reasons: ["Unsigned"])
        let flagged = DownloadRecord.make(path: "/d/Tool.app", size: 5, date: date, facts: appFacts, verdict: meh)
        #expect(flagged.outcome == .flagged && flagged.reasons == ["Unsigned"])
        let archive = FileFacts(path: "/d/x.zip", kind: .archive, signature: nil)
        #expect(DownloadRecord.make(path: "/d/x.zip", size: 1, date: date, facts: archive, verdict: nil).outcome == .safeType)
    }

    @Test func keepsNewestTwentyAndReplacesSamePath() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let log = DownloadLog(url: URL(fileURLWithPath: root + "/d.json"))
        #expect(log.load().isEmpty)
        for index in 0..<25 {
            try log.append([DownloadRecord.make(path: "/d/f\(index)", size: 1, date: date.addingTimeInterval(Double(index)), facts: nil, verdict: nil)])
        }
        try log.append([DownloadRecord.make(path: "/d/f24", size: 99, date: date.addingTimeInterval(100), facts: nil, verdict: nil)])
        let records = log.load()
        #expect(records.count == DownloadLog.limit)
        #expect(records.first?.size == 99 && records.filter { $0.path == "/d/f24" }.count == 1)
        #expect(records.last?.name == "f5", "replacing f24 in place keeps the oldest of the 20")
    }

    @Test func originHostFallsBackToRawText() {
        let record = DownloadRecord(name: "a", path: "/a", size: 0, date: date, origin: "not a url", kind: "File", signer: nil, outcome: .safeType, reasons: [])
        #expect(record.originHost == "not a url")
        #expect(DeepScanRoots.contains("/Applications"))
    }

    private var DeepScanRoots: [String] { ThreatScanKind.deep.roots(home: "/U") }
}

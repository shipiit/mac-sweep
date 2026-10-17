import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ThreatHistoryTests {
    @Test func appendsNewestFirstAndCaps() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let history = ThreatScanHistory(url: URL(fileURLWithPath: root + "/h.json"))
        #expect(history.load().isEmpty)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<35 {
            try history.append(ThreatScanRecord(kind: .quick, scope: "x", date: base.addingTimeInterval(Double(index)), duration: 1, filesChecked: index, threats: 0))
        }
        let loaded = history.load()
        #expect(loaded.count == ThreatScanHistory.limit)
        #expect(loaded.first?.filesChecked == 34 && loaded.last?.filesChecked == 5)
        #expect(loaded.filter { !$0.isClean }.isEmpty)
    }

    @Test func corruptFileReadsEmpty() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "nope".write(toFile: root + "/h.json", atomically: true, encoding: .utf8)
        #expect(ThreatScanHistory(url: URL(fileURLWithPath: root + "/h.json")).load().isEmpty)
    }

    @Test func kindsHaveRootsAndScopes() {
        #expect(ThreatScanKind.quick.roots(home: "/U") == ["/U/Downloads", "/U/Desktop"])
        #expect(ThreatScanKind.full.roots(home: "/U").contains("/Applications"))
        #expect(ThreatScanKind.custom.roots(home: "/U").isEmpty)
        #expect(Set(ThreatScanKind.allCases.map(\.scopeTitle)).count == ThreatScanKind.allCases.count)
    }

    @Test func readsXProtectInfo() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/X.bundle/Contents", withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "5367"], format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: root + "/X.bundle/Contents/Info.plist"))
        let info = try #require(XProtectInfo.read(bundle: root + "/X.bundle"))
        #expect(info.version == "5367" && info.isCurrent())
        #expect(!XProtectInfo(version: "1", updated: Date(timeIntervalSince1970: 0)).isCurrent())
        #expect(!XProtectInfo(version: "1", updated: nil).isCurrent())
        #expect(XProtectInfo.read(bundle: root + "/missing") == nil)
    }
}

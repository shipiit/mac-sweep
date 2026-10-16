import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ServiceStatusTests {
    @Test func parsesSummary() throws {
        let json = #"""
        {"status":{"indicator":"minor","description":"Partially Degraded Service"},
         "components":[{"name":"claude.ai","status":"operational"},{"name":"Claude Code","status":"partial_outage"},
                       {"name":"Group","status":"operational","group":true},{"name":"API","status":"major_outage"},{"name":"Odd","status":"new_state"}],
         "incidents":[{"name":"Elevated errors on Claude Code","impact":"major","status":"investigating","shortlink":"https://stspg.io/x"},{"name":"No details"},{"impact":"minor"}]}
        """#
        let status = try #require(ServiceStatus.parse(Data(json.utf8)))
        #expect(status.level == .degraded && status.description == "Partially Degraded Service")
        #expect(status.components.map(\.name) == ["claude.ai", "Claude Code", "API", "Odd"])
        #expect(status.components.map(\.level) == [.operational, .degraded, .outage, .unknown])
        #expect(status.components[1].detail == "Partial Outage")
        #expect(status.incidents.map(\.name) == ["Elevated errors on Claude Code", "No details"])
        #expect(status.incidents[0].impact == .outage && status.incidents[0].state == "Investigating")
        #expect(status.incidents[0].link?.host == "stspg.io")
        #expect(status.incidents[1].impact == .unknown && status.incidents[1].link == nil && status.incidents[1].state.isEmpty)
    }

    @Test func indicatorLevels() {
        #expect(ServiceStatus.indicatorLevel("none") == .operational)
        #expect(ServiceStatus.indicatorLevel("maintenance") == .degraded)
        #expect(ServiceStatus.indicatorLevel("critical") == .outage)
        #expect(ServiceStatus.indicatorLevel(nil) == .unknown)
        #expect(ServiceStatus.componentLevel("under_maintenance") == .degraded)
    }

    @Test func rejectsBadPayloads() {
        #expect(ServiceStatus.parse(Data()) == nil)
        #expect(ServiceStatus.parse(Data("[]".utf8)) == nil)
        #expect(ServiceStatus.parse(Data(#"{"components":[]}"#.utf8)) == nil)
        let minimal = ServiceStatus.parse(Data(#"{"status":{}}"#.utf8))
        #expect(minimal?.level == .unknown && minimal?.components.isEmpty == true && minimal?.description == "Unknown")
    }

    @Test func linksAreValid() {
        let claude = ServiceStatus.Links.of(.claudeCode)
        #expect(claude.statusPage?.host == "status.claude.com" && claude.dashboard?.host == "claude.ai")
        #expect(claude.summary?.path == "/api/v2/summary.json")
        let codex = ServiceStatus.Links.of(.codex)
        #expect(codex.statusPage?.host == "status.openai.com" && codex.dashboard?.host == "chatgpt.com")
    }
}

@Suite struct RateLimitWindowTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func usedFractionClampsAndResets() {
        #expect(RateLimitWindow(usedPercent: 40, windowMinutes: 300, resetsAt: now.addingTimeInterval(60)).usedFraction(now: now) == 0.4)
        #expect(RateLimitWindow(usedPercent: 140, windowMinutes: 300, resetsAt: nil).usedFraction(now: now) == 1)
        #expect(RateLimitWindow(usedPercent: -5, windowMinutes: 300, resetsAt: nil).usedFraction(now: now) == 0)
        let stale = RateLimitWindow(usedPercent: 100, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1))
        #expect(stale.hasReset(now: now) && stale.usedFraction(now: now) == 0)
        #expect(!RateLimitWindow(usedPercent: 100, windowMinutes: 300, resetsAt: nil).hasReset(now: now))
    }
}

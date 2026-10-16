import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ClaudePlanUsageTests {
    @Test func parsesWindowsModelsAndExtraUsage() throws {
        let json = #"""
        {"five_hour":{"utilization":7.0,"resets_at":"2026-10-16T15:00:00.123+00:00"},
         "seven_day":{"utilization":100,"resets_at":"2026-10-19T08:00:00Z"},
         "seven_day_fable":{"utilization":11,"resets_at":null},
         "seven_day_opus":null,
         "seven_day_oauth_apps":{"utilization":50},
         "seven_day_claude_design":{"utilization":30},
         "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":0}}
        """#
        let usage = try #require(ClaudePlanUsage.parse(Data(json.utf8)))
        #expect(usage.session?.percentLeft == 93 && usage.session?.resetsAt != nil)
        #expect(usage.weekly?.percentLeft == 0 && usage.weekly?.resetsAt != nil)
        #expect(usage.modelWeekly.map(\.name) == ["Claude Design", "Fable"])
        #expect(usage.modelWeekly[1].resetsAt == nil)
        #expect(usage.extra == ClaudePlanUsage.ExtraUsage(isEnabled: false, usedCredits: 0, monthlyLimit: nil))
    }

    @Test func percentLeftClamps() {
        #expect(ClaudePlanUsage.Window(name: "x", utilization: 140, resetsAt: nil).percentLeft == 0)
        #expect(ClaudePlanUsage.Window(name: "x", utilization: -3, resetsAt: nil).percentLeft == 100)
    }

    @Test func rejectsEmptyOrInvalid() {
        #expect(ClaudePlanUsage.parse(Data()) == nil)
        #expect(ClaudePlanUsage.parse(Data("{}".utf8)) == nil)
        #expect(ClaudePlanUsage.parse(Data(#"{"five_hour":{"resets_at":"x"}}"#.utf8)) == nil)
        #expect(ClaudePlanUsage.parse(Data(#"{"error":{"type":"authentication_error"}}"#.utf8)) == nil)
    }

    @Test func parsesCredentialsAndPlan() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1791000000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        let credentials = try #require(ClaudePlanUsage.parseCredentials(Data(json.utf8)))
        #expect(credentials.accessToken == "tok" && credentials.plan == "Max 20x")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_000_000))
        #expect(ClaudePlanUsage.parseCredentials(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(ClaudePlanUsage.parseCredentials(Data(#"{"other":{}}"#.utf8)) == nil)
        #expect(ClaudePlanUsage.parseCredentials(Data("nope".utf8)) == nil)
    }

    @Test func planNames() {
        #expect(ClaudePlanUsage.planName(tier: "default_claude_max_5x", type: "max") == "Max 5x")
        #expect(ClaudePlanUsage.planName(tier: nil, type: "pro") == "Pro")
        #expect(ClaudePlanUsage.planName(tier: "weird", type: nil) == nil)
        #expect(ClaudePlanUsage.planName(tier: nil, type: nil) == nil)
    }

    @Test func credentialsFallBackToFile() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let json = #"{"claudeAiOauth":{"accessToken":"file-token","subscriptionType":"pro"}}"#
        try json.write(toFile: home + "/.claude/.credentials.json", atomically: true, encoding: .utf8)
        let fromFile = ClaudePlanUsage.readCredentials(home: home) { nil }
        #expect(fromFile?.accessToken == "file-token" && fromFile?.plan == "Pro")
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"keychain-token"}}"#
        #expect(ClaudePlanUsage.readCredentials(home: home) { Data(keychainJSON.utf8) }?.accessToken == "keychain-token")
        #expect(ClaudePlanUsage.readCredentials(home: home + "/missing") { nil } == nil)
    }
}

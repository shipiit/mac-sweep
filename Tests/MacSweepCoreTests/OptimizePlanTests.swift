import Foundation
import Testing
@testable import MacSweepCore

@Suite struct OptimizePlanTests {
    @Test func ordersEnabledSteps() {
        #expect(OptimizePlan.steps(enabled: [.flushDNSAndRAM, .systemJunk, .trashBins]) == [.systemJunk, .trashBins, .flushDNSAndRAM])
        #expect(OptimizePlan.steps(enabled: []).isEmpty)
    }

    @Test func progressCountsRunningAsHalf() {
        let steps: [OptimizeStep] = [.systemJunk, .trashBins, .maintenance, .flushDNSAndRAM]
        #expect(OptimizePlan.progress([:], steps: steps) == 0)
        #expect(OptimizePlan.progress([.systemJunk: .done(freed: 1, note: nil), .trashBins: .running], steps: steps) == 0.375)
        let finished: [OptimizeStep: OptimizeStepState] = [.systemJunk: .done(freed: 0, note: nil), .trashBins: .warning("x"),
                                                           .maintenance: .skipped("y"), .flushDNSAndRAM: .done(freed: 0, note: nil)]
        #expect(OptimizePlan.progress(finished, steps: steps) == 1)
        #expect(OptimizePlan.progress(finished, steps: []) == 0)
    }

    @Test func sumsFreedSpaceFromDoneStepsOnly() {
        let states: [OptimizeStep: OptimizeStepState] = [.systemJunk: .done(freed: 300, note: nil), .trashBins: .done(freed: 200, note: "x"),
                                                         .maintenance: .warning("failed"), .flushDNSAndRAM: .skipped("cancelled")]
        #expect(OptimizePlan.freed(states) == 500)
        #expect(OptimizePlan.freed([:]) == 0)
    }

    @Test func stateFlags() {
        #expect(!OptimizeStepState.pending.isFinished && !OptimizeStepState.running.isFinished)
        #expect(OptimizeStepState.skipped("x").isFinished && OptimizeStepState.warning("y").isFinished)
        #expect(OptimizeStep.flushDNSAndRAM.requiresAdmin && !OptimizeStep.systemJunk.requiresAdmin)
        #expect(OptimizeStep.trashBins.isPermanent && !OptimizeStep.systemJunk.isPermanent)
        #expect(Set(OptimizeStep.allCases.map(\.title)).count == OptimizeStep.allCases.count)
    }

    @Test func junkSkipsInUsePathsAndChildren() {
        let targets = ["/c/app", "/c/app/sub", "/c/apple", "/c/other"].map { CleanupTarget(path: $0, size: 1, modified: nil) }
        #expect(OptimizePlan.junkTargets(targets, inUse: ["/c/app"]).map(\.path) == ["/c/apple", "/c/other"])
        #expect(OptimizePlan.junkTargets(targets, inUse: []).count == 4)
        #expect(OptimizePlan.junkTargets([], inUse: ["/c"]).isEmpty)
    }
}

@Suite struct SmartFindingsTests {
    @Test func aCleanMacHasNoFindings() {
        #expect(SmartFindings.build(SmartScanInput()).isEmpty)
        var tiny = SmartScanInput()
        tiny.safeJunk = 1_000
        tiny.trash = 19_999_999
        #expect(SmartFindings.build(tiny).isEmpty)
    }

    @Test func ranksSecurityFirstThenSafeSpaceThenReview() {
        var input = SmartScanInput()
        input.safeJunk = 5_000_000_000
        input.appCaches = 9_000_000_000
        input.trash = 50_000_000_000
        input.reviewJunk = 80_000_000_000
        input.unusedDatabases = 8_000_000_000
        input.unusedDatabaseCount = 64
        input.fixableSettings = ["Stealth mode"]
        input.manualSettings = ["Password after sleep", "Automatic login"]
        input.securityUpdates = ["macOS 27.2.1"]
        input.suspiciousItems = 1
        input.otherUpdates = 12
        input.speedTips = 2
        input.leftovers = 1
        let findings = SmartFindings.build(input)
        #expect(findings.prefix(4).allSatisfy { $0.level == .urgent })
        #expect(findings.dropFirst(4).prefix(2).map(\.id) == ["app-caches", "junk"])
        #expect(findings.dropFirst(6).first?.id == "review-junk")
        #expect(findings.first { $0.id == "databases" }?.title == "64 databases no project uses")
        #expect(findings.first { $0.id == "suspicious" }?.title == "1 suspicious startup item or program")
        #expect(findings.first { $0.id == "settings-manual" }?.step == nil)
        #expect(findings.first { $0.id == "leftovers" }?.title == "1 leftover from deleted apps")
        #expect(Set(findings.map(\.id)).count == findings.count)
    }

    @Test func defaultsTickSafeAndSecurityButNeverTheTrash() {
        var input = SmartScanInput()
        input.safeJunk = 1_000_000_000
        input.browserCopies = 2_000_000_000
        input.sessionExtras = 3_000_000_000
        input.trash = 9_000_000_000
        input.fixableSettings = ["Firewall"]
        let findings = SmartFindings.build(input)
        let steps = SmartFindings.defaultSteps(findings)
        #expect(steps == [.systemJunk, .browserCopies, .sessionExtras, .hardening])
        #expect(SmartFindings.bytes(findings, steps: steps) == 6_000_000_000)
        #expect(SmartFindings.bytes(findings, steps: [.trashBins]) == 9_000_000_000)
        #expect(SmartFindings.bytes(findings, steps: []) == 0)
    }

    @Test func newStepsRunInASafeOrder() {
        #expect(OptimizePlan.steps(enabled: [.hardening, .trashBins, .appCaches, .systemJunk]) == [.systemJunk, .appCaches, .trashBins, .hardening])
        #expect(OptimizeStep.hardening.requiresAdmin && OptimizeStep.browserCopies.isPermanent && !OptimizeStep.sessionExtras.isPermanent)
    }
}

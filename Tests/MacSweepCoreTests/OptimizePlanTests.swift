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

import Testing
@testable import MacSweepCore

@Suite struct MacHealthTests {
    @Test func grades() {
        #expect(MacHealth.grade(securityScore: 95, highFindings: 0, tips: 0, freeFraction: 0.4) == .excellent)
        #expect(MacHealth.grade(securityScore: 90, highFindings: 0, tips: 2, freeFraction: 0.27) == .veryGood)
        #expect(MacHealth.grade(securityScore: 80, highFindings: 0, tips: 5, freeFraction: 0.2) == .good)
        #expect(MacHealth.grade(securityScore: 70, highFindings: 0, tips: 9, freeFraction: 0.1) == .needsAttention)
    }

    @Test func hardStopsAlwaysNeedAttention() {
        #expect(MacHealth.grade(securityScore: 100, highFindings: 1, tips: 0, freeFraction: 0.9) == .needsAttention)
        #expect(MacHealth.grade(securityScore: 59, highFindings: 0, tips: 0, freeFraction: 0.9) == .needsAttention)
        #expect(MacHealth.grade(securityScore: 100, highFindings: 0, tips: 0, freeFraction: 0.04) == .needsAttention)
        #expect(MacHealth.grade(securityScore: 60, highFindings: 0, tips: 0, freeFraction: 0.05) == .good)
    }

    @Test func summariesDiffer() {
        let all: [MacHealth] = [.excellent, .veryGood, .good, .needsAttention]
        #expect(Set(all.map(\.summary)).count == 4)
    }
}

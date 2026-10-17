import Testing
@testable import MacSweepCore

@Suite struct SecurityAdvisorTests {
    func check(_ id: String, _ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: id, title: id.capitalized, state: state, detail: "d", settingsURL: "x-apple.systempreferences:\(id)")
    }

    @Test func recommendsFromAuditResults() {
        let list = SecurityAdvisor.recommendations(protections: [check("firewall", .off), check("filevault", .off), check("sip", .on), check("gatekeeper", .unknown)],
                                                   findings: 2, highRiskExtensions: 5, downloadProtection: false)
        #expect(list.map(\.id) == ["firewall", "filevault", "findings", "extensions", "downloads"])
        #expect(list[0].action == .enableFirewall)
        #expect(list[1].action == .openSettings("x-apple.systempreferences:filevault"))
        #expect(list[2].title == "Review 2 suspicious items")
        #expect(list[3].severity == .medium)
    }

    @Test func nothingToDoWhenAllGood() {
        #expect(SecurityAdvisor.recommendations(protections: [check("firewall", .on)], findings: 0, highRiskExtensions: 0, downloadProtection: true).isEmpty)
        let other = SecurityAdvisor.recommendations(protections: [check("sip", .off)], findings: 1, highRiskExtensions: 1, downloadProtection: true)
        #expect(other.first?.title == "Turn on Sip" && other.count == 3)
    }

    @Test func badge() {
        #expect(SecurityAdvisor.badge(hasRun: false, protectionsOff: 3, findings: 3) == nil)
        #expect(SecurityAdvisor.badge(hasRun: true, protectionsOff: 0, findings: 0) == "Secure")
        #expect(SecurityAdvisor.badge(hasRun: true, protectionsOff: 1, findings: 0) == "1 issue")
        #expect(SecurityAdvisor.badge(hasRun: true, protectionsOff: 1, findings: 2) == "3 issues")
    }
}

import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class SharingAuditModel {
    struct Section: Identifiable {
        let category: SharingFinding.Category
        let findings: [SharingFinding]

        var id: String { category.rawValue }
    }

    private(set) var findings: [SharingFinding] = []
    private(set) var isLoading = false
    private(set) var checkedAt: Date?

    var sections: [Section] {
        SharingFinding.Category.allCases.compactMap { category in
            let items = findings.filter { $0.category == category }
            return items.isEmpty ? nil : Section(category: category, findings: items)
        }
    }

    var issueCount: Int { findings.filter { $0.severity > .info }.count }
    var highCount: Int { findings.filter { $0.severity >= .medium }.count }
    var passedCount: Int { findings.filter { $0.severity == .info }.count }

    func load() async {
        isLoading = true
        let snapshot = await SharingReader.read()
        findings = SharingAudit.findings(snapshot)
        checkedAt = Date()
        isLoading = false
    }
}

extension SharingFinding.Category {
    var symbol: String {
        switch self {
        case .wireless: "wifi"
        case .sharing: "person.2.wave.2"
        case .protection: "shield.lefthalf.filled"
        }
    }
}

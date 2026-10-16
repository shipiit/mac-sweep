import Foundation
import MacSweepCore
import Observation
import os

@MainActor
@Observable
final class SecurityModel {
    private(set) var protections: [ProtectionCheck] = []
    private(set) var findings: [SecurityFinding] = []
    private(set) var extensions: [BrowserExtension] = []
    private(set) var isRunning = false
    private(set) var lastRun: Date?
    private(set) var checkedItems = 0

    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "security")

    var protectionsOff: Int { protections.filter { $0.state == .off }.count }
    var highFindings: Int { findings.filter { $0.severity >= .medium }.count }
    var uniqueExtensionCount: Int { ExtensionGroup.group(extensions).count }
    var highAccessExtensions: Int { ExtensionGroup.group(extensions).filter { $0.risk == .high }.count }

    /// 0–100 summary. Penalties are capped per category so one noisy category can't zero the score.
    /// Extensions are informational and don't affect it.
    var score: Int {
        guard lastRun != nil else { return 0 }
        func count(_ severity: FindingSeverity) -> Int { findings.filter { $0.severity == severity }.count }
        let penalty = min(protectionsOff * 10, 30)
            + min(count(.high) * 15, 45)
            + min(count(.medium) * 5, 20)
            + min(count(.low), 5)
        return max(0, 100 - penalty)
    }

    /// One row per extension, listing every browser profile it's installed in.
    static func mergeProfiles(_ extensions: [BrowserExtension]) -> [BrowserExtension] {
        let grouped = Dictionary(grouping: extensions) { $0.browser + "/" + $0.extensionID }
        return grouped.values.compactMap { copies -> BrowserExtension? in
            guard let first = copies.first else { return nil }
            let profiles = copies.map(\.profile).sorted().joined(separator: ", ")
            var merged = BrowserExtension(browser: first.browser, profile: profiles, extensionID: first.extensionID, name: first.name,
                                          version: first.version, permissions: first.permissions, path: first.path,
                                          iconPath: first.iconPath, fromStore: first.fromStore)
            merged.state = first.state
            merged.state.installed = copies.compactMap(\.state.installed).min()
            merged.state.lastActivity = copies.compactMap(\.state.lastActivity).max()
            merged.state.enabled = copies.contains { $0.state.enabled }
            return merged
        }
        .sorted { ($0.isHighAccess ? 0 : 1, $0.name) < ($1.isHighAccess ? 0 : 1, $1.name) }
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        log.info("security audit started")
        async let protections = ProtectionStatus.checkAll()
        let audit = await Task.detached(priority: .utility) { () -> ([SecurityFinding], [BrowserExtension], Int) in
            let items = LaunchItemScanner.scan()
            let processes = ProcessSampler.sample()
            let findings = SecurityAudit.auditLaunchItems(items) + SecurityAudit.auditProcesses(processes)
            return (findings.sorted { $0.severity > $1.severity }, BrowserExtensions.scan(), items.count + processes.count)
        }.value
        self.protections = await protections
        findings = audit.0
        extensions = Self.mergeProfiles(audit.1 + (await SafariExtensions.scan()))
        checkedItems = audit.2
        lastRun = Date()
        log.info("security audit finished: \(self.findings.count) findings")
    }
}

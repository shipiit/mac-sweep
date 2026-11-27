import Foundation
import MacSweepCore
import Observation

/// The hardening checklist: reads each setting, and applies the fixes that need the administrator password.
@MainActor @Observable
final class HardeningModel {
    static let shared = HardeningModel()

    private(set) var checks: [HardeningCheck] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isFixing = false
    var error: String?

    var score: Int { Hardening.score(checks) }
    var failing: [HardeningCheck] { checks.filter { $0.state == .fail }.sorted { $0.severity > $1.severity } }
    var passing: [HardeningCheck] { checks.filter { $0.state != .fail } }
    /// Failing checks MacSweep can fix itself, all under one password prompt.
    var oneClickFixes: [String] {
        failing.compactMap { check in if case .admin(let id) = check.fix { return id } else { return nil } }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        checks = Hardening.checks(await Hardening.snapshot())
        isLoading = false
        hasLoaded = true
    }

    func fix(_ ids: [String]) async {
        guard !ids.isEmpty, !isFixing else { return }
        isFixing = true
        do {
            try await Hardening.applyFixes(ids)
            error = nil
        } catch AdminRunner.AdminError.cancelled {
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isFixing = false
        await refresh()
    }
}

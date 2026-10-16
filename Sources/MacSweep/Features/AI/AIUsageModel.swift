import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class AIUsageModel {
    private(set) var index: AIUsageIndex
    private(set) var isRefreshing = false
    private(set) var progress: AIUsageScanner.Progress?
    private(set) var lastRefreshed: Date?
    /// Each tool's public status page; missing until fetched, listed in `unavailableStatus` when offline.
    private(set) var serviceStatus: [AIProvider: ServiceStatus] = [:]
    private(set) var unavailableStatus: Set<AIProvider> = []
    /// Real Claude plan limits; only fetched when the user turned the option on in Settings.
    private(set) var planUsage: ClaudePlanUsage?
    private(set) var planError: ClaudePlanUsage.FetchError?
    @ObservationIgnored private var planCheckedAt: Date?

    @ObservationIgnored private let store = AIUsageStore.standard
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        index = AIUsageStore.standard.load()
    }

    /// Re-indexes changed transcripts every 2 minutes in the background; unchanged files cost nothing.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                await self?.refreshPlan()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    func refreshServiceStatus() async {
        for provider in AIProvider.allCases {
            do {
                serviceStatus[provider] = try await ServiceStatus.fetch(provider)
                unavailableStatus.remove(provider)
            } catch {
                unavailableStatus.insert(provider)
            }
        }
    }

    /// At most every 5 minutes unless forced; clears everything when the option is off.
    func refreshPlan(force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.claudePlanLimits) else {
            planUsage = nil
            planError = nil
            return
        }
        if !force, let checked = planCheckedAt, Date().timeIntervalSince(checked) < 300 { return }
        planCheckedAt = Date()
        do {
            planUsage = try await Task.detached(priority: .utility) { try await ClaudePlanUsage.fetch() }.value
            planError = nil
        } catch let error as ClaudePlanUsage.FetchError {
            planError = error
        } catch {
            planError = .unavailable
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let current = index
        let store = store
        let box = ProgressBox()
        let poller = Task { [weak self] in
            while !Task.isCancelled {
                self?.progress = box.value
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        let updated = await Task.detached(priority: .utility) {
            let result = AIUsageScanner.refresh(current) { box.value = $0 }
            try? store.save(result)
            return result
        }.value
        poller.cancel()
        index = updated
        progress = nil
        lastRefreshed = Date()
        MemoryRelief.release()
    }

    // MARK: Convenience for the menu bar, notch and dashboard

    var todayEntries: [UsageEntry] { AIUsageSummary.filter(index.entries, provider: nil, days: 1) }
    var todayTotals: TokenTotals { AIUsageSummary.totals(todayEntries) }
    var todayCost: Double { AIUsageSummary.cost(of: todayEntries).known }
    var claudeBlock: UsageBlock? { AIUsageSummary.currentBlock(index.events, provider: .claudeCode) }
    var codexLimits: CodexRateLimits? { index.latestCodexLimits }
}

enum TokenFormat {
    static func compact(_ value: Int) -> String {
        let number = Double(value)
        switch number {
        case 1_000_000_000...: return String(format: "%.2fB", number / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", number / 1_000_000)
        case 1_000...: return String(format: "%.1fK", number / 1_000)
        default: return "\(value)"
        }
    }

    static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(value < 10 ? 2 : 0)))
    }
}

/// Thread-safe handoff of scan progress from the background reader to the UI poller.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AIUsageScanner.Progress?

    var value: AIUsageScanner.Progress? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

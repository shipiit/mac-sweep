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
    @ObservationIgnored private var credentials: ClaudePlanUsage.Credentials?
    @ObservationIgnored private var keychainReadAt: Date?

    @ObservationIgnored private let store = AIUsageStore.standard
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var watcher: DirectoryWatcher?
    /// A change arrived while a refresh was running; run once more afterwards.
    @ObservationIgnored private var isRefreshQueued = false

    init() {
        index = AIUsageStore.standard.load()
    }

    /// Re-indexes when transcripts change (within ~2 s) and every 2 minutes as a fallback; only appended bytes are read.
    func start() {
        guard loop == nil else { return }
        let sources = AIUsageSources()
        watcher = DirectoryWatcher(paths: [sources.claudeRoot, sources.codexRoot], latency: 3) { [weak self] in
            Task { await self?.refresh() }
        }
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

    /// At most every 5 minutes unless forced. The Keychain is read once and the sign-in kept in memory, so macOS
    /// asks at most once per launch (and again only after Claude Code's token rotates). Deny stops all requests
    /// until the option is switched off and on.
    func refreshPlan(force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.claudePlanLimits) else {
            planUsage = nil
            planError = nil
            credentials = nil
            return
        }
        if planError == .denied, !force { return }
        if !force, let checked = planCheckedAt, Date().timeIntervalSince(checked) < 300 { return }
        planCheckedAt = Date()
        if credentials == nil || credentials?.isExpired() == true {
            // An expired token is only re-read every 30 minutes, so a stale sign-in can't cause a prompt every cycle.
            if !force, let read = keychainReadAt, Date().timeIntervalSince(read) < 1_800, credentials != nil {
                planError = .expired
                return
            }
            keychainReadAt = Date()
            let loaded = await Task.detached(priority: .utility) { ClaudePlanUsage.loadCredentials() }.value
            switch loaded {
            case .success(let loaded): credentials = loaded
            case .failure(let error):
                planError = error
                return
            }
        }
        guard let credentials else { return }
        do {
            planUsage = try await ClaudePlanUsage.fetch(with: credentials)
            planError = nil
        } catch let error as ClaudePlanUsage.FetchError {
            planError = error
        } catch {
            planError = .unavailable
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            isRefreshQueued = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if isRefreshQueued {
                isRefreshQueued = false
                Task { await refresh() }
            }
        }
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

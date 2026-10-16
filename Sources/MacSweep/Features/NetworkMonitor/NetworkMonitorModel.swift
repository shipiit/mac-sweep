import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class NetworkMonitorModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case internet = "Internet"
        case flagged = "Flagged"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: "list.bullet"
            case .internet: "globe"
            case .flagged: "exclamationmark.triangle"
            }
        }
    }

    static let interval: Duration = .seconds(5)

    private(set) var sample: NetworkSample?
    private(set) var hostNames: [String: String] = [:]
    var filter: Filter = .all
    var search = ""

    @ObservationIgnored private let signatures = SignatureCache()
    @ObservationIgnored private let dns = ReverseDNSCache()

    var activity: [AppNetworkActivity] { sample?.activity ?? [] }

    var visible: [AppNetworkActivity] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return activity.filter { app in
            guard matches(app, filter) else { return false }
            guard !query.isEmpty else { return true }
            return app.name.lowercased().contains(query)
                || app.connections.contains { connection in
                    guard let remote = connection.remote else { return false }
                    return remote.address.contains(query) || (hostNames[remote.address]?.lowercased().contains(query) ?? false)
                }
        }
    }

    func count(for filter: Filter) -> Int { activity.filter { matches($0, filter) }.count }

    var outboundTotal: Int { activity.reduce(0) { $0 + $1.outboundCount } }
    var listeningTotal: Int { activity.reduce(0) { $0 + $1.listeningCount } }

    /// Remote hosts this app talks to most, by number of established sockets.
    func topHosts(_ app: AppNetworkActivity, limit: Int = 3) -> [String] {
        let remotes = app.connections.filter { $0.kind == .established }.compactMap { $0.remote?.address }
        let counts = Dictionary(remotes.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(limit).map { hostNames[$0.key] ?? $0.key }
    }

    func displayHost(_ endpoint: NetEndpoint) -> String {
        hostNames[endpoint.address].map { "\($0):\(endpoint.port)" } ?? endpoint.display
    }

    /// Samples until the calling task is cancelled, i.e. while the view is on screen.
    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.interval)
        }
    }

    func refresh() async {
        let next = await NetworkSampler.sample(signatures: signatures)
        guard !Task.isCancelled else { return }
        sample = next
        let addresses = next.activity.flatMap(\.connections).filter(\.isOutboundInternet).compactMap { $0.remote?.address }
        let names = await dns.resolve(addresses)
        guard !Task.isCancelled else { return }
        hostNames.merge(names) { _, new in new }
    }

    private func matches(_ app: AppNetworkActivity, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .internet: app.outboundCount > 0
        case .flagged: app.flag != nil
        }
    }
}

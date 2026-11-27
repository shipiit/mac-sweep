import Foundation
import MacSweepCore
import Observation

/// Which filtering DNS this Mac uses, with one-step switching and a way back to what it had before.
@MainActor @Observable
final class DNSShieldModel {
    static let shared = DNSShieldModel()
    private static let previousKey = "dnsShieldPrevious"

    private(set) var services: [DNSServiceState] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isApplying = false
    /// Whether the active profile's test name is really refused; nil when it has no test or hasn't run.
    private(set) var isBlocking: Bool?
    private(set) var usesTailscaleDNS = false
    var error: String?

    /// The profile every configured service agrees on.
    var active: DNSProfile? {
        let profiles = services.filter { !$0.servers.isEmpty }.map { DNSShield.profile(for: $0.servers) }
        guard let first = profiles.first, let profile = first, profiles.allSatisfy({ $0 == profile }) else { return nil }
        return profile
    }

    /// Servers of the service people actually browse on, for the "now using" line.
    var currentServers: [String] { (services.first { $0.service == "Wi-Fi" && !$0.servers.isEmpty } ?? services.first { !$0.servers.isEmpty })?.servers ?? [] }
    var hasPrevious: Bool { UserDefaults.standard.data(forKey: Self.previousKey) != nil }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        services = await DNSShield.current()
        usesTailscaleDNS = (try? await Shell.run("/usr/sbin/scutil", ["--dns"])).map { DNSShield.usesTailscaleDNS(scutilOutput: $0.stdout) } ?? false
        isBlocking = nil
        if let active { isBlocking = await DNSShield.isBlocking(active) }
        isLoading = false
        hasLoaded = true
    }

    func turnOn(_ profile: DNSProfile) async {
        await change {
            // Remember the servers from before the first profile, so Off puts back exactly those.
            if self.active == nil, let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: self.services.map { ($0.service, $0.servers) })) {
                UserDefaults.standard.set(data, forKey: Self.previousKey)
            }
            try await DNSShield.apply(profile, to: self.services.map(\.service))
        }
    }

    func turnOff() async {
        await change {
            let saved = UserDefaults.standard.data(forKey: Self.previousKey).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
            try await DNSShield.restore(self.services.map { DNSServiceState(service: $0.service, servers: saved[$0.service] ?? []) })
            UserDefaults.standard.removeObject(forKey: Self.previousKey)
        }
    }

    private func change(_ work: () async throws -> Void) async {
        guard !isApplying else { return }
        isApplying = true
        do {
            try await work()
            error = nil
        } catch AdminRunner.AdminError.cancelled {
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isApplying = false
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }
}

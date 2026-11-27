import Foundation
import os

/// A public DNS service that refuses to resolve known-bad (and optionally adult) sites.
public struct DNSProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let provider: String
    public let blocks: String
    public let servers: [String]
    /// A harmless test name this provider is known to block, used to prove the filter is live.
    public let testDomain: String?
}

/// DNS servers set on one network service ("Wi-Fi"); empty means it takes them from the router.
public struct DNSServiceState: Sendable, Equatable, Identifiable {
    public let service: String
    public let servers: [String]
    public var id: String { service }

    public init(service: String, servers: [String]) {
        self.service = service
        self.servers = servers
    }
}

/// Points every network service at a filtering DNS provider, and puts the old servers back.
public enum DNSShield {
    private static let log = Logger(subsystem: Log.subsystem, category: "dns-shield")
    static let networksetup = "/usr/sbin/networksetup"

    public static let profiles: [DNSProfile] = [
        DNSProfile(id: "quad9", title: "Malware blocking", provider: "Quad9",
                   blocks: "Known malware, phishing and scam sites.",
                   servers: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"], testDomain: nil),
        DNSProfile(id: "cloudflare-security", title: "Malware blocking (fast)", provider: "Cloudflare 1.1.1.2",
                   blocks: "Known malware and phishing sites.",
                   servers: ["1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"], testDomain: "malware.testcategory.com"),
        DNSProfile(id: "cloudflare-family", title: "Malware and adult content", provider: "Cloudflare for Families",
                   blocks: "Malware, phishing and adult sites.",
                   servers: ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"], testDomain: "nudity.testcategory.com"),
        DNSProfile(id: "cleanbrowsing-family", title: "Strict family filter", provider: "CleanBrowsing Family",
                   blocks: "Adult sites, malware, phishing, proxies and VPN sites used to get around the filter. Forces safe search.",
                   servers: ["185.228.168.168", "185.228.169.168", "2a0d:2a00:1::", "2a0d:2a00:2::"], testDomain: nil),
    ]

    /// Enabled services from `networksetup -listallnetworkservices` (the first line is a note; `*` marks disabled ones).
    static func parseServices(_ output: String) -> [String] {
        output.split(separator: "\n").dropFirst().map(String.init).filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    /// Servers from `networksetup -getdnsservers`; the "There aren't any DNS Servers set" sentence means none.
    static func parseServers(_ output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter(isAddress)
    }

    static func isAddress(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }

    /// The profile whose servers a service is using, if it uses only that profile's servers.
    public static func profile(for servers: [String]) -> DNSProfile? {
        guard !servers.isEmpty else { return nil }
        return profiles.first { profile in servers.allSatisfy(profile.servers.contains) }
    }

    public static func current() async -> [DNSServiceState] {
        guard let list = try? await Shell.run(networksetup, ["-listallnetworkservices"]) else { return [] }
        var states: [DNSServiceState] = []
        for service in parseServices(list.stdout) {
            let servers = (try? await Shell.run(networksetup, ["-getdnsservers", service])).map { parseServers($0.stdout) } ?? []
            states.append(DNSServiceState(service: service, servers: servers))
        }
        return states
    }

    /// The one shell line that sets `servers` on each service (empty → back to the router's) and flushes the cache.
    /// Returns nil when any server isn't an IP address; services with unusual names are left out rather than quoted.
    static func command(servers: [String: [String]]) -> String? {
        guard servers.values.allSatisfy({ $0.allSatisfy(isAddress) }) else { return nil }
        let parts = servers.keys.sorted().filter(AdminRunner.isSafeToken).map { service in
            networksetup + " -setdnsservers " + AdminRunner.quote(service) + " " + (servers[service]?.isEmpty == false ? servers[service]!.joined(separator: " ") : "Empty")
        }
        guard !parts.isEmpty else { return nil }
        return (parts + ["/usr/bin/dscacheutil -flushcache", "/usr/bin/killall -HUP mDNSResponder"]).joined(separator: "; ")
    }

    /// Turns a profile on for every listed service. Asks for the administrator password once.
    public static func apply(_ profile: DNSProfile, to services: [String]) async throws {
        try await set(Dictionary(uniqueKeysWithValues: services.map { ($0, profile.servers) }))
        log.info("dns profile applied: \(profile.id, privacy: .public)")
    }

    /// Puts back the servers each service had before (or the router's, when it had none).
    public static func restore(_ previous: [DNSServiceState]) async throws {
        try await set(Dictionary(uniqueKeysWithValues: previous.map { ($0.service, $0.servers) }))
        log.info("dns servers restored")
    }

    private static func set(_ servers: [String: [String]]) async throws {
        guard let command = command(servers: servers) else { throw AdminRunner.AdminError.invalidInput }
        _ = try await AdminRunner.runFixed(command)
    }

    /// True when the Mac's own resolver refuses the profile's test name (filtering DNS answers 0.0.0.0 or nothing).
    public static func isBlocking(_ profile: DNSProfile) async -> Bool? {
        guard let domain = profile.testDomain,
              let result = try? await DevShell.run("/usr/bin/dig", ["+short", "+time=3", "+tries=1", domain], timeout: 8, tool: "dig") else { return nil }
        return blocked(digOutput: result.stdout)
    }

    static func blocked(digOutput: String) -> Bool {
        let answers = digOutput.split(separator: "\n").map(String.init).filter(isAddress)
        return answers.isEmpty || answers.allSatisfy { $0 == "0.0.0.0" || $0 == "::" }
    }

    /// Tailscale's MagicDNS (100.100.100.100) as the first resolver means lookups go through it, not the filter, while it's connected.
    public static func usesTailscaleDNS(scutilOutput: String) -> Bool {
        guard let first = scutilOutput.components(separatedBy: "resolver #").dropFirst().first else { return false }
        return first.split(separator: "\n").contains { $0.contains("nameserver[") && $0.hasSuffix("100.100.100.100") }
    }
}

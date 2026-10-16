import Darwin
import Foundation
import IOKit

public struct NetworkDetails: Sendable, Equatable {
    public var interface: String?
    public var gateway: String?
    public var dnsServers: [String] = []
    public var macAddress: String?
    public var ipv6: [String] = []

    public init() {}
}

public enum NetworkDetailsReader {
    public static func read() async -> NetworkDetails {
        var details = NetworkDetails()
        if let route = try? await Shell.run("/sbin/route", ["-n", "get", "default"]) {
            let parsed = parseRoute(route.stdout)
            details.gateway = parsed.gateway
            details.interface = parsed.interface
        }
        if let dns = try? await Shell.run("/usr/sbin/scutil", ["--dns"]) {
            details.dnsServers = parseDNS(dns.stdout)
        }
        if let interface = details.interface {
            details.macAddress = macAddress(interface: interface)
            details.ipv6 = ipv6Addresses(interface: interface)
        }
        return details
    }

    /// Fetches the public IP only when the user asks; this is MacSweep's one call to an outside service.
    public static func publicIP() async throws -> String {
        guard let url = URL(string: "https://api.ipify.org") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isIPAddress(text) else { throw URLError(.cannotParseResponse) }
        return text
    }

    public static func parseRoute(_ output: String) -> (gateway: String?, interface: String?) {
        var gateway: String?
        var interface: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "gateway" { gateway = parts[1] }
            if parts[0] == "interface" { interface = parts[1] }
        }
        return (gateway, interface)
    }

    /// Unique nameservers in resolver order from `scutil --dns`.
    public static func parseDNS(_ output: String) -> [String] {
        var servers: [String] = []
        for line in output.split(whereSeparator: \.isNewline) where line.contains("nameserver[") {
            guard let value = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
                  !servers.contains(value)
            else { continue }
            servers.append(value)
        }
        return servers
    }

    static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }

    static func macAddress(interface: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK)
            else { continue }
            return address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { link -> String? in
                let length = Int(link.pointee.sdl_alen)
                guard length == 6 else { return nil }
                let offset = Int(link.pointee.sdl_nlen)
                return withUnsafeBytes(of: link.pointee.sdl_data) { raw in
                    (0..<length).map { String(format: "%02x", raw[offset + $0]) }.joined(separator: ":")
                }
            }
        }
        return nil
    }

    static func ipv6Addresses(interface: String) -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET6)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !text.hasPrefix("fe80") { result.append(text) }
        }
        return result
    }
}

public enum HardwareInfo {
    /// Serial number from the platform expert; shown masked in the UI until revealed.
    public static func serialNumber() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    public static func masked(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - 4) + value.suffix(4)
    }
}

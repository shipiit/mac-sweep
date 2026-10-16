import CoreWLAN
import Darwin
import Foundation

public struct NetworkStatus: Sendable, Equatable {
    public let interface: String?
    public let ipv4: String?
    /// Requires Location Services permission on recent macOS; nil when not granted.
    public let wifiName: String?
    public let isWiFi: Bool
}

public struct SpeedTestResult: Sendable, Equatable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    /// Round-trips per minute under load; higher is better.
    public let responsivenessRPM: Int?
}

public enum NetworkInfo {
    public static func status() -> NetworkStatus {
        let wifi = CWWiFiClient.shared().interface()
        let wifiInterface = wifi?.interfaceName
        let addresses = ipv4Addresses()
        let primary = wifiInterface.flatMap { name in addresses[name].map { (name, $0) } }
            ?? addresses.sorted { $0.key < $1.key }.first { $0.key.hasPrefix("en") }.map { ($0.key, $0.value) }
        return NetworkStatus(
            interface: primary?.0,
            ipv4: primary?.1,
            wifiName: wifi?.ssid(),
            isWiFi: primary?.0 == wifiInterface && wifiInterface != nil
        )
    }

    /// Runs Apple's built-in `networkQuality` (about 15–20 seconds).
    public static func speedTest() async throws -> SpeedTestResult? {
        let result = try await Shell.run("/usr/bin/networkQuality", ["-c", "-s"])
        return parseSpeedTest(result.stdout)
    }

    public static func parseSpeedTest(_ json: String) -> SpeedTestResult? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let download = (root["dl_throughput"] as? NSNumber)?.doubleValue,
              let upload = (root["ul_throughput"] as? NSNumber)?.doubleValue
        else { return nil }
        let rpm = (root["responsiveness"] as? NSNumber)?.intValue
            ?? (root["dl_responsiveness"] as? NSNumber)?.intValue
        return SpeedTestResult(downloadMbps: download / 1_000_000, uploadMbps: upload / 1_000_000, responsivenessRPM: rpm)
    }

    static func ipv4Addresses() -> [String: String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [:] }
        defer { freeifaddrs(head) }
        var result: [String: String] = [:]
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            result[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return result
    }
}

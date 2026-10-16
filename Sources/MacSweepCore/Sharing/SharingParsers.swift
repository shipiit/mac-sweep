import Foundation

public enum ServiceState: Sendable, Equatable {
    case on
    case off
    case unknown

    public var title: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .unknown: "Unknown"
        }
    }
}

public enum AirDropMode: Sendable, Equatable {
    case off
    case contactsOnly
    case everyone
    case unknown

    public var title: String {
        switch self {
        case .off: "Receiving off"
        case .contactsOnly: "Contacts only"
        case .everyone: "Everyone"
        case .unknown: "Unknown"
        }
    }
}

public struct FirewallStatus: Sendable, Equatable {
    public let enabled: ServiceState
    public let blockAll: Bool
    public let stealth: ServiceState
}

public enum SharingParsers {
    public static let netstatArguments = ["-an", "-p", "tcp"]

    /// TCP ports listening on a non-loopback address, from `netstat -an -p tcp`. Unlike lsof without
    /// root, netstat sees launchd's sockets for SSH, Screen Sharing and SMB.
    public static func exposedTCPPorts(_ netstat: String) -> Set<Int> {
        var ports = Set<Int>()
        for line in netstat.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 6, columns[0].hasPrefix("tcp"), columns.last == "LISTEN" else { continue }
            let local = String(columns[3])
            guard let dot = local.lastIndex(of: "."), let port = Int(local[local.index(after: dot)...]) else { continue }
            let address = String(local[..<dot])
            if address.hasPrefix("127.") || address == "::1" || address.hasPrefix("fe80::1%lo") { continue }
            ports.insert(port)
        }
        return ports
    }

    /// `socketfilterfw --getglobalstate --getstealthmode`: "Firewall is enabled. (State = 1)" and
    /// "Firewall stealth mode is on". State 2 means "block all incoming connections".
    public static func firewall(_ output: String) -> FirewallStatus {
        var enabled = ServiceState.unknown
        var blockAll = false
        var stealth = ServiceState.unknown
        for line in output.lowercased().split(whereSeparator: \.isNewline) {
            if line.contains("stealth") {
                if line.contains("is on") || line.contains("enabled") { stealth = .on }
                if line.contains("is off") || line.contains("disabled") { stealth = .off }
            } else if line.contains("firewall is") || line.contains("state =") {
                if line.contains("state = 0") || line.contains("disabled") {
                    enabled = .off
                } else if line.contains("state = 1") || line.contains("state = 2") || line.contains("enabled") || line.contains("blocking all") {
                    enabled = .on
                    blockAll = line.contains("state = 2") || line.contains("blocking all")
                }
            }
        }
        return FirewallStatus(enabled: enabled, blockAll: blockAll, stealth: stealth)
    }

    /// `defaults read com.apple.sharingd DiscoverableMode`. A missing key prints an error and means unknown.
    public static func airDrop(_ output: String, status: Int32) -> AirDropMode {
        guard status == 0 else { return .unknown }
        switch output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off": return .off
        case "contacts only": return .contactsOnly
        case let value where value.hasPrefix("everyone"): return .everyone
        default: return .unknown
        }
    }
}

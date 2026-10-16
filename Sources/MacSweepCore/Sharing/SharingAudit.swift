import Foundation

public struct SharingFinding: Identifiable, Sendable, Equatable {
    public enum Category: String, Sendable, CaseIterable {
        case wireless = "Wi-Fi & Bluetooth"
        case sharing = "Sharing services"
        case protection = "Firewall & AirDrop"
    }

    public let id: String
    public let category: Category
    public let title: String
    public let status: String
    public let detail: String
    /// `.info` means nothing to fix.
    public let severity: FindingSeverity
    public let symbol: String
    public let settingsURL: String
}

public struct SharingSnapshot: Sendable, Equatable {
    public var wifi: WiFiStatus?
    public var bluetooth: BluetoothStatus?
    /// nil when netstat couldn't run, so sharing services are reported as unknown rather than off.
    public var exposedPorts: Set<Int>?
    public var firewall: FirewallStatus
    public var airDrop: AirDropMode

    public init(wifi: WiFiStatus?, bluetooth: BluetoothStatus?, exposedPorts: Set<Int>?, firewall: FirewallStatus, airDrop: AirDropMode) {
        self.wifi = wifi
        self.bluetooth = bluetooth
        self.exposedPorts = exposedPorts
        self.firewall = firewall
        self.airDrop = airDrop
    }
}

public enum SharingAudit {
    struct Service {
        let id: String
        let title: String
        let ports: [Int]
        let symbol: String
        let severity: FindingSeverity
        let risk: String
    }

    static let services = [
        Service(id: "ssh", title: "Remote Login (SSH)", ports: [22], symbol: "terminal", severity: .medium,
                risk: "Anyone on your network can try to log in with a password. Turn off unless you use SSH."),
        Service(id: "screen", title: "Screen Sharing", ports: [5900], symbol: "rectangle.on.rectangle", severity: .medium,
                risk: "Lets others view and control this Mac's screen."),
        Service(id: "files", title: "File Sharing (SMB)", ports: [445, 548], symbol: "folder.badge.person.crop", severity: .low,
                risk: "Shared folders are reachable from your network."),
        Service(id: "ard", title: "Remote Management", ports: [3283], symbol: "desktopcomputer.and.arrow.down", severity: .medium,
                risk: "Apple Remote Desktop can control and change this Mac."),
    ]

    public static func findings(_ snapshot: SharingSnapshot) -> [SharingFinding] {
        var result = wireless(snapshot)
        for service in services {
            let state: ServiceState = snapshot.exposedPorts.map { ports in service.ports.contains(where: ports.contains) ? .on : .off } ?? .unknown
            result.append(SharingFinding(
                id: service.id, category: .sharing, title: service.title, status: state.title,
                detail: state == .on ? service.risk : state == .off ? "Not listening on the network." : "Couldn't check listening ports.",
                severity: state == .on ? service.severity : .info, symbol: service.symbol, settingsURL: SettingsLinks.sharing))
        }
        result += protection(snapshot)
        return result
    }

    static func wireless(_ snapshot: SharingSnapshot) -> [SharingFinding] {
        var result: [SharingFinding] = []
        if let wifi = snapshot.wifi {
            let (severity, detail) = wifiRisk(wifi)
            result.append(SharingFinding(id: "wifi", category: .wireless, title: "Wi-Fi security",
                                         status: wifi.isConnected ? (wifi.security?.title ?? "Unknown") : "Not connected",
                                         detail: detail, severity: severity, symbol: "wifi", settingsURL: SettingsLinks.wifi))
        }
        if let bluetooth = snapshot.bluetooth {
            let discoverable = bluetooth.isDiscoverable == true
            let status = bluetooth.isPoweredOn == false ? "Off" : discoverable ? "Discoverable" : "Not discoverable"
            let devices = bluetooth.connectedDevices.isEmpty ? "No devices connected" : "Connected: " + bluetooth.connectedDevices.joined(separator: ", ")
            result.append(SharingFinding(
                id: "bluetooth", category: .wireless, title: "Bluetooth", status: status,
                detail: discoverable ? "Nearby devices can see this Mac. It's normal while Bluetooth settings are open. \(devices)." : devices + ".",
                severity: discoverable ? .low : .info, symbol: "dot.radiowaves.left.and.right", settingsURL: SettingsLinks.bluetooth))
        }
        return result
    }

    static func wifiRisk(_ wifi: WiFiStatus) -> (FindingSeverity, String) {
        guard wifi.isConnected, let security = wifi.security else {
            return (.info, "Not connected to a Wi-Fi network.")
        }
        switch security {
        case .open: return (.high, "Anyone nearby can read unencrypted traffic on this network. Use a VPN or a secured network.")
        case .wep: return (.high, "WEP can be cracked in minutes. Change the router to WPA2 or WPA3.")
        case .wpa: return (.high, "WPA (TKIP) is outdated and breakable. Change the router to WPA2 or WPA3.")
        case .wpaWPA2Mixed: return (.medium, "The router still allows old WPA clients. Switch it to WPA2 or WPA3 only.")
        case .enhancedOpen: return (.low, "Encrypted, but anyone can join. Treat it like public Wi-Fi.")
        case .wpa2, .wpa2WPA3, .wpa3, .enterprise: return (.info, "Encrypted with a modern standard.")
        case .unknown: return (.low, "Couldn't identify how this network is secured.")
        }
    }

    static func protection(_ snapshot: SharingSnapshot) -> [SharingFinding] {
        let firewall = snapshot.firewall
        let firewallFinding: (FindingSeverity, String, String) = switch firewall.enabled {
        case .on: (.info, firewall.blockAll ? "On, blocking all incoming" : "On", "Unwanted incoming connections are blocked.")
        case .off: (.medium, "Off", "Apps can accept connections from your network without asking. Turn it on, especially on public Wi-Fi.")
        case .unknown: (.low, "Unknown", "Couldn't read the firewall state.")
        }
        let stealth: (FindingSeverity, String) = switch firewall.stealth {
        case .on: (.info, "This Mac ignores pings and probes from the network.")
        case .off: (.low, "This Mac answers pings, so scanners can find it. Turn on in the firewall's options.")
        case .unknown: (.info, "Couldn't read stealth mode.")
        }
        let airDrop: (FindingSeverity, String) = switch snapshot.airDrop {
        case .everyone: (.medium, "Anyone nearby can send you files and see this Mac. Use Contacts Only.")
        case .contactsOnly: (.info, "Only people in your contacts can send you files.")
        case .off: (.info, "AirDrop receiving is off.")
        case .unknown: (.info, "Couldn't read the AirDrop setting.")
        }
        return [
            SharingFinding(id: "firewall", category: .protection, title: "Firewall", status: firewallFinding.1, detail: firewallFinding.2,
                           severity: firewallFinding.0, symbol: "flame", settingsURL: SettingsLinks.firewall),
            SharingFinding(id: "stealth", category: .protection, title: "Stealth mode", status: firewall.stealth.title, detail: stealth.1,
                           severity: firewall.enabled == .off ? .info : stealth.0, symbol: "eye.slash", settingsURL: SettingsLinks.firewall),
            SharingFinding(id: "airdrop", category: .protection, title: "AirDrop", status: snapshot.airDrop.title, detail: airDrop.1,
                           severity: airDrop.0, symbol: "airplayaudio", settingsURL: SettingsLinks.airDrop),
        ]
    }
}

public enum SharingReader {
    public static func read() async -> SharingSnapshot {
        async let wifi = try? Shell.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json", "-detailLevel", "basic"])
        async let bluetooth = try? Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        async let netstat = try? Shell.run("/usr/sbin/netstat", SharingParsers.netstatArguments)
        async let firewall = try? Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate", "--getstealthmode"])
        async let airDrop = try? Shell.run("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"])
        let netstatResult = await netstat
        let airDropResult = await airDrop
        return SharingSnapshot(
            wifi: WirelessParser.wifi(await wifi?.stdout ?? ""),
            bluetooth: WirelessParser.bluetooth(await bluetooth?.stdout ?? ""),
            exposedPorts: netstatResult.flatMap { $0.status == 0 ? SharingParsers.exposedTCPPorts($0.stdout) : nil },
            firewall: SharingParsers.firewall(await firewall?.stdout ?? ""),
            airDrop: airDropResult.map { SharingParsers.airDrop($0.stdout, status: $0.status) } ?? .unknown
        )
    }
}

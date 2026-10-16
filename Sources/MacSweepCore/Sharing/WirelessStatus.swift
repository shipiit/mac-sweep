import Foundation

public enum WiFiSecurity: Sendable, Equatable {
    case open
    case enhancedOpen
    case wep
    case wpa
    /// WPA/WPA2 mixed mode: modern devices use WPA2, but the network still accepts WPA1 clients.
    case wpaWPA2Mixed
    case wpa2
    case wpa2WPA3
    case wpa3
    case enterprise(String)
    case unknown(String)

    public var title: String {
        switch self {
        case .open: "Open (no password)"
        case .enhancedOpen: "Enhanced Open (OWE)"
        case .wep: "WEP"
        case .wpa: "WPA"
        case .wpaWPA2Mixed: "WPA/WPA2 mixed"
        case .wpa2: "WPA2"
        case .wpa2WPA3: "WPA2/WPA3"
        case .wpa3: "WPA3"
        case .enterprise(let version): "\(version) Enterprise"
        case .unknown: "Unknown"
        }
    }

    /// Maps `spairport_security_mode_*` values. Order matters: "wpa3_transition" contains "wpa3".
    public static func from(mode raw: String) -> WiFiSecurity {
        let mode = raw.lowercased().replacingOccurrences(of: "spairport_security_mode_", with: "")
        if mode == "none" || mode == "open" { return .open }
        if mode.contains("owe") { return .enhancedOpen }
        if mode.contains("wep") { return .wep }
        if mode.contains("enterprise") {
            let version = mode.contains("wpa3") ? "WPA3" : mode.contains("wpa2") ? "WPA2" : "WPA"
            return .enterprise(version)
        }
        if mode.contains("wpa3_transition") || (mode.contains("wpa2") && mode.contains("wpa3")) { return .wpa2WPA3 }
        if mode.contains("wpa3") { return .wpa3 }
        if mode.contains("wpa2") { return .wpa2 }
        if mode.contains("wpa") && mode.contains("mixed") { return .wpaWPA2Mixed }
        if mode.contains("wpa") { return .wpa }
        return .unknown(raw)
    }
}

public struct WiFiStatus: Sendable, Equatable {
    public let isConnected: Bool
    /// Shown in the UI only; never logged.
    public let networkName: String?
    public let security: WiFiSecurity?
    public let phyMode: String?
}

public struct BluetoothStatus: Sendable, Equatable {
    public let isPoweredOn: Bool?
    public let isDiscoverable: Bool?
    public let connectedDevices: [String]
    public let pairedCount: Int
}

public enum WirelessParser {
    /// Parses `system_profiler SPAirPortDataType -json`. nil when the JSON is unusable or there's no Wi-Fi.
    public static func wifi(_ json: String) -> WiFiStatus? {
        guard let root = object(json),
              let interfaces = (root["SPAirPortDataType"] as? [[String: Any]])?.first?["spairport_airport_interfaces"] as? [[String: Any]],
              let primary = interfaces.first(where: { $0["spairport_current_network_information"] != nil }) ?? interfaces.first
        else { return nil }
        let current = primary["spairport_current_network_information"] as? [String: Any]
        let status = primary["spairport_status_information"] as? String
        let connected = current != nil && (status == nil || status == "spairport_status_connected")
        return WiFiStatus(
            isConnected: connected,
            networkName: current?["_name"] as? String,
            security: (current?["spairport_security_mode"] as? String).map(WiFiSecurity.from(mode:)),
            phyMode: current?["spairport_network_phymode"] as? String
        )
    }

    /// Parses `system_profiler SPBluetoothDataType -json`. Device names stay on screen; they're never logged.
    public static func bluetooth(_ json: String) -> BluetoothStatus? {
        guard let root = object(json), let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else { return nil }
        let properties = controller["controller_properties"] as? [String: Any]
        func flag(_ key: String) -> Bool? {
            switch properties?[key] as? String {
            case "attrib_on": true
            case "attrib_off": false
            default: nil
            }
        }
        func names(_ key: String) -> [String] {
            (controller[key] as? [[String: Any]] ?? []).flatMap(\.keys).sorted()
        }
        let connected = names("device_connected")
        return BluetoothStatus(isPoweredOn: flag("controller_state"), isDiscoverable: flag("controller_discoverable"),
                               connectedDevices: connected, pairedCount: connected.count + names("device_not_connected").count)
    }

    static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

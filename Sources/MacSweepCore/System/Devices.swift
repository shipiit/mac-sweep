import Foundation

public struct ConnectedDevice: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case bluetooth = "Bluetooth"
        case usb = "USB"
    }

    public let name: String
    public let kind: Kind
    public let detail: String?

    public var id: String { kind.rawValue + ":" + name }
}

public enum Devices {
    public static func connected() async -> [ConnectedDevice] {
        guard let result = try? await Shell.run(
            "/usr/sbin/system_profiler", ["SPBluetoothDataType", "SPUSBHostDataType", "SPUSBDataType", "-json", "-detailLevel", "mini"]
        ) else { return [] }
        return parse(result.stdout)
    }

    public static func parse(_ json: String) -> [ConnectedDevice] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var devices: [ConnectedDevice] = []

        for controller in root["SPBluetoothDataType"] as? [[String: Any]] ?? [] {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    let properties = value as? [String: Any]
                    let battery = properties?["device_batteryLevelMain"] as? String
                        ?? properties?["device_batteryLevel"] as? String
                    let minorType = properties?["device_minorType"] as? String
                    let detail = [minorType, battery.map { "Battery \($0)" }].compactMap { $0 }.joined(separator: " · ")
                    devices.append(ConnectedDevice(name: name, kind: .bluetooth, detail: detail.isEmpty ? nil : detail))
                }
            }
        }

        func walkUSB(_ items: [[String: Any]]) {
            for item in items {
                let name = item["_name"] as? String ?? ""
                let isHub = name.localizedCaseInsensitiveContains("hub") || name.localizedCaseInsensitiveContains("bus")
                    || name.hasPrefix("USB3") || name.hasPrefix("USB31") || name.contains("Root")
                if !name.isEmpty, !isHub {
                    devices.append(ConnectedDevice(name: name, kind: .usb, detail: item["manufacturer"] as? String ?? item["USBDeviceKeyVendorName"] as? String))
                }
                walkUSB(item["_items"] as? [[String: Any]] ?? [])
            }
        }
        walkUSB(root["SPUSBHostDataType"] as? [[String: Any]] ?? [])
        walkUSB(root["SPUSBDataType"] as? [[String: Any]] ?? [])

        var seen = Set<String>()
        return devices.filter { seen.insert($0.id).inserted }
    }
}

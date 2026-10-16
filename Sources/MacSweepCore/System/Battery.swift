import Foundation
import IOKit

public struct BatteryInfo: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let cycleCount: Int?
    /// Current full-charge capacity as a fraction of the design capacity.
    public let health: Double?
    public let temperatureCelsius: Double?
    public let minutesRemaining: Int?
    public let adapterWatts: Int?
}

public enum Battery {
    /// Nil on Macs without a battery.
    public static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return parse(dictionary)
    }

    /// Parses AppleSmartBattery registry properties. On Apple silicon CurrentCapacity/MaxCapacity are
    /// percentages; raw mAh values live in AppleRawCurrentCapacity / AppleRawMaxCapacity.
    public static func parse(_ properties: [String: Any]) -> BatteryInfo? {
        guard let current = int(properties["CurrentCapacity"]) else { return nil }
        let maxCapacity = int(properties["MaxCapacity"]) ?? 100
        let percent = maxCapacity > 100
            ? Int((Double(current) / Double(max(maxCapacity, 1)) * 100).rounded())
            : current
        let rawMax = int(properties["AppleRawMaxCapacity"]) ?? (maxCapacity > 100 ? maxCapacity : nil)
        let design = int(properties["DesignCapacity"])
        let health = rawMax.flatMap { raw in design.map { Double(raw) / Double(max($0, 1)) } }
        let temperature = int(properties["Temperature"]).map { Double($0) / 100 }
        let remaining = int(properties["TimeRemaining"]).flatMap { $0 > 0 && $0 < 65_535 ? $0 : nil }
        let watts = (properties["AdapterDetails"] as? [String: Any]).flatMap { int($0["Watts"]) }
        return BatteryInfo(
            percent: min(max(percent, 0), 100),
            isCharging: properties["IsCharging"] as? Bool ?? false,
            isPluggedIn: properties["ExternalConnected"] as? Bool ?? false,
            cycleCount: int(properties["CycleCount"]),
            health: health.map { min($0, 1.0) },
            temperatureCelsius: temperature,
            minutesRemaining: remaining,
            adapterWatts: watts
        )
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as NSNumber: number.intValue
        default: nil
        }
    }
}

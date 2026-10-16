import Darwin
import Foundation

public struct MacInfo: Sendable, Equatable {
    public var modelName: String
    public var chip: String
    public var memory: UInt64
    public var serialHidden = true
    public var osVersion: String
    public var modelIdentifier: String

    public static func basic() -> MacInfo {
        MacInfo(
            modelName: "Mac",
            chip: sysctlString("machdep.cpu.brand_string") ?? "Apple silicon",
            memory: ProcessInfo.processInfo.physicalMemory,
            osVersion: osVersionString(),
            modelIdentifier: sysctlString("hw.model") ?? ""
        )
    }

    /// Adds the marketing name ("MacBook Pro") and chip from system_profiler.
    public static func detailed() async -> MacInfo {
        var info = basic()
        guard let result = try? await Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"]),
              let parsed = parseHardware(result.stdout)
        else { return info }
        info.modelName = parsed.modelName ?? info.modelName
        info.chip = parsed.chip ?? info.chip
        return info
    }

    public static func parseHardware(_ json: String) -> (modelName: String?, chip: String?)? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPHardwareDataType"] as? [[String: Any]],
              let first = items.first
        else { return nil }
        return (first["machine_name"] as? String, first["chip_type"] as? String)
    }

    static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

public enum ThermalLevel: String, Sendable {
    case nominal = "Cool"
    case fair = "Warm"
    case serious = "Hot"
    case critical = "Throttling"

    public static func current() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}

public enum Uptime {
    public static func formatted(_ seconds: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

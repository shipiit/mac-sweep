import Foundation

public struct ProtectionCheck: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case on
        case off
        case unknown
    }

    public let id: String
    public let title: String
    public let state: State
    public let detail: String
    public let settingsURL: String?
}

/// macOS's built-in defences. Read-only: MacSweep reports them and links to System Settings.
public enum ProtectionStatus {
    public static func checkAll() async -> [ProtectionCheck] {
        async let sip = try? Shell.run("/usr/bin/csrutil", ["status"])
        async let gatekeeper = try? Shell.run("/usr/sbin/spctl", ["--status"])
        async let fileVault = try? Shell.run("/usr/bin/fdesetup", ["status"])
        async let firewall = try? Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        let xprotect = xprotectVersion()
        return [
            ProtectionCheck(id: "sip", title: "System Integrity Protection", state: parseSIP(await sip?.stdout ?? ""),
                            detail: "Stops anything, even admin, from modifying macOS system files.", settingsURL: nil),
            ProtectionCheck(id: "gatekeeper", title: "Gatekeeper", state: parseGatekeeper(await gatekeeper?.stdout ?? ""),
                            detail: "Only lets apps from the App Store and identified developers open.",
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Security"),
            ProtectionCheck(id: "filevault", title: "FileVault", state: parseFileVault(await fileVault?.stdout ?? ""),
                            detail: "Encrypts your disk so a lost Mac can't be read.",
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?FileVault"),
            ProtectionCheck(id: "firewall", title: "Firewall", state: parseFirewall(await firewall?.stdout ?? ""),
                            detail: "Blocks unwanted incoming connections.",
                            settingsURL: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"),
            ProtectionCheck(id: "xprotect", title: "XProtect malware definitions", state: xprotect == nil ? .unknown : .on,
                            detail: xprotect.map { "Apple's built-in malware scanner, definitions version \($0)." } ?? "Apple's built-in malware scanner.",
                            settingsURL: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
        ]
    }

    static func parseSIP(_ output: String) -> ProtectionCheck.State {
        if output.contains("status: enabled") { return .on }
        if output.contains("status: disabled") { return .off }
        return .unknown
    }

    static func parseGatekeeper(_ output: String) -> ProtectionCheck.State {
        if output.contains("assessments enabled") { return .on }
        if output.contains("assessments disabled") { return .off }
        return .unknown
    }

    static func parseFileVault(_ output: String) -> ProtectionCheck.State {
        if output.contains("FileVault is On") { return .on }
        if output.contains("FileVault is Off") { return .off }
        return .unknown
    }

    static func parseFirewall(_ output: String) -> ProtectionCheck.State {
        if output.contains("enabled") || output.contains("State = 1") || output.contains("State = 2") { return .on }
        if output.contains("disabled") || output.contains("State = 0") { return .off }
        return .unknown
    }

    static func xprotectVersion() -> String? {
        let paths = [
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
            "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
        ]
        for path in paths {
            if let plist = NSDictionary(contentsOfFile: path), let version = plist["CFBundleShortVersionString"] as? String {
                return version
            }
        }
        return nil
    }
}

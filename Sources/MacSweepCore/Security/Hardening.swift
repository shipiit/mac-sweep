import Foundation

/// One setting that makes the Mac harder to break into, with whether it's set and how to set it.
public struct HardeningCheck: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable { case pass, fail, unknown }

    public enum Fix: Sendable, Equatable {
        /// One of `Hardening.fixCommands`, run with the administrator password.
        case admin(String)
        case openSettings(String)
        case openDNSShield
    }

    public let id: String
    public let title: String
    public let state: State
    /// What the setting protects against, in one sentence.
    public let detail: String
    /// What it is right now ("Off", "5 minutes").
    public let status: String
    public let severity: FindingSeverity
    public let fix: Fix?
}

/// Everything the checklist needs, read once without the administrator password.
public struct HardeningSnapshot: Sendable, Equatable {
    public var firewall: Bool?
    public var stealthMode: Bool?
    /// Keys from /Library/Preferences/com.apple.SoftwareUpdate; a missing key means macOS's default (on).
    public var softwareUpdate: [String: Bool] = [:]
    /// Seconds before a password is needed after sleep; 0 is immediately, nil is unknown, -1 means never.
    public var screenLockDelay: Int?
    public var guestEnabled: Bool?
    public var autoLoginUser: String?
    public var exposedPorts: Set<Int>?
    public var protections: [ProtectionCheck] = []
    public var dnsFiltered = false

    public init() {}
}

public enum Hardening {
    static let updateKeys = ["AutomaticCheckEnabled", "AutomaticDownload", "CriticalUpdateInstall", "ConfigDataInstall"]
    static let softwareUpdateSettings = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    static let lockScreenSettings = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
    static let usersSettings = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
    static let firewallTool = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    /// Fixed commands only: nothing from outside is ever put into a privileged shell line.
    static let fixCommands: [String: String] = [
        "firewall": firewallTool + " --setglobalstate on",
        "stealth": firewallTool + " --setglobalstate on; " + firewallTool + " --setstealthmode on",
        "auto-updates": updateKeys.map { "/usr/bin/defaults write /Library/Preferences/com.apple.SoftwareUpdate \($0) -bool true" }.joined(separator: "; "),
        "guest": "/usr/sbin/sysadminctl -guestAccount off",
    ]

    public static func checks(_ snapshot: HardeningSnapshot) -> [HardeningCheck] {
        var list: [HardeningCheck] = []
        func add(_ id: String, _ title: String, _ passed: Bool?, _ detail: String, _ status: String, _ severity: FindingSeverity, _ fix: HardeningCheck.Fix?) {
            let state: HardeningCheck.State = passed.map { $0 ? .pass : .fail } ?? .unknown
            list.append(HardeningCheck(id: id, title: title, state: state, detail: detail, status: state == .unknown ? "Couldn't check" : status,
                                       severity: severity, fix: state == .fail ? fix : nil))
        }
        for protection in snapshot.protections where protection.id != "firewall" {
            add(protection.id, protection.title, protection.state == .unknown ? nil : protection.state == .on, protection.detail,
                protection.state == .on ? "On" : "Off", .high, protection.settingsURL.map(HardeningCheck.Fix.openSettings))
        }
        add("firewall", "Firewall", snapshot.firewall, "Blocks unwanted incoming connections.", snapshot.firewall == true ? "On" : "Off", .high, .admin("firewall"))
        add("stealth", "Stealth mode", snapshot.stealthMode, "Your Mac doesn't answer probes, so scanners on a café or hotel network can't see it.",
            snapshot.stealthMode == true ? "On" : "Off", .medium, .admin("stealth"))
        let updatesOff = updateKeys.filter { snapshot.softwareUpdate[$0] == false }
        add("auto-updates", "Automatic security updates", updatesOff.isEmpty,
            "Apple's security fixes and malware definitions install by themselves, usually within a day of release.",
            updatesOff.isEmpty ? "On" : "\(updatesOff.count) of \(updateKeys.count) switched off", .high, .admin("auto-updates"))
        add("screen-lock", "Password after sleep", snapshot.screenLockDelay.map { $0 >= 0 && $0 <= 300 },
            "Someone who picks up your sleeping Mac needs your password.", lockStatus(snapshot.screenLockDelay), .high, .openSettings(lockScreenSettings))
        add("auto-login", "Automatic login", snapshot.autoLoginUser == nil, "With automatic login, anyone who restarts the Mac is signed in as you.",
            snapshot.autoLoginUser == nil ? "Off" : "On", .high, .openSettings(usersSettings))
        add("guest", "Guest account", snapshot.guestEnabled.map { !$0 }, "A guest can use your network and any shared folders without a password.",
            snapshot.guestEnabled == true ? "On" : "Off", .low, .admin("guest"))
        for service in SharingAudit.services {
            let exposed = snapshot.exposedPorts.map { ports in service.ports.contains(where: ports.contains) }
            add("sharing-" + service.id, service.title, exposed.map { !$0 }, service.risk, exposed == true ? "On" : "Off", service.severity, .openSettings(SettingsLinks.sharing))
        }
        add("dns", "Malware-blocking DNS", snapshot.dnsFiltered, "Known malware, phishing and scam sites fail to load before anything is downloaded.",
            snapshot.dnsFiltered ? "On" : "Off", .medium, .openDNSShield)
        return list
    }

    static func lockStatus(_ delay: Int?) -> String {
        switch delay {
        case nil: "Couldn't check"
        case .some(let seconds) where seconds < 0: "Never asks"
        case 0: "Immediately"
        case .some(let seconds) where seconds < 60: "After \(seconds) seconds"
        case .some(let seconds): "After \(seconds / 60) minute\(seconds / 60 == 1 ? "" : "s")"
        }
    }

    /// 0–100: each failed check costs points by severity; unknown ones cost nothing.
    public static func score(_ checks: [HardeningCheck]) -> Int {
        let penalty = checks.filter { $0.state == .fail }.reduce(0) { total, check in
            total + (check.severity == .high ? 15 : check.severity == .medium ? 8 : 3)
        }
        return max(0, 100 - penalty)
    }

    /// `sysadminctl -screenLock status`: "screenLock delay is immediate", "… is 300 seconds" or "screenLock is off".
    static func parseScreenLock(_ output: String) -> Int? {
        if output.contains("screenLock is off") { return -1 }
        if output.contains("delay is immediate") { return 0 }
        guard let range = output.range(of: "delay is ") else { return nil }
        return Int(output[range.upperBound...].prefix { $0.isNumber })
    }

    static func parseStealth(_ output: String) -> Bool? {
        let text = output.lowercased()
        if text.contains("mode is on") || text.contains("stealth mode enabled") || text.contains("mode is enabled") { return true }
        if text.contains("mode is off") || text.contains("stealth mode disabled") || text.contains("mode is disabled") { return false }
        return nil
    }

    public static func snapshot() async -> HardeningSnapshot {
        var snapshot = HardeningSnapshot()
        async let protections = ProtectionStatus.checkAll()
        async let stealth = try? Shell.run(firewallTool, ["--getstealthmode"])
        async let lock = try? Shell.run("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        async let netstat = try? Shell.run("/usr/sbin/netstat", SharingParsers.netstatArguments)
        async let dns = DNSShield.current()
        snapshot.protections = await protections
        snapshot.firewall = snapshot.protections.first { $0.id == "firewall" }.flatMap { $0.state == .unknown ? nil : $0.state == .on }
        snapshot.stealthMode = (await stealth).flatMap { parseStealth($0.stdout) }
        snapshot.screenLockDelay = (await lock).flatMap { parseScreenLock($0.stdout + $0.stderr) }
        snapshot.exposedPorts = (await netstat).flatMap { $0.status == 0 ? SharingParsers.exposedTCPPorts($0.stdout) : nil }
        let updates = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") as? [String: Any] ?? [:]
        snapshot.softwareUpdate = updates.compactMapValues { $0 as? Bool }
        let login = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.loginwindow.plist") as? [String: Any]
        snapshot.guestEnabled = login.map { $0["GuestEnabled"] as? Bool ?? false }
        snapshot.autoLoginUser = login?["autoLoginUser"] as? String
        let services = await dns
        snapshot.dnsFiltered = services.contains { DNSShield.profile(for: $0.servers) != nil }
        return snapshot
    }

    /// Runs the fixed commands for these checks under one administrator password prompt.
    public static func applyFixes(_ ids: [String]) async throws {
        let commands = ids.compactMap { fixCommands[$0] }
        guard !commands.isEmpty, commands.count == ids.count else { throw AdminRunner.AdminError.invalidInput }
        _ = try await AdminRunner.runFixed(commands.joined(separator: "; "))
    }
}

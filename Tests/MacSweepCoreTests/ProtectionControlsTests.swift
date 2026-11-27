import Foundation
import Testing
@testable import MacSweepCore

@Suite struct DNSShieldTests {
    @Test func parsesServicesAndServers() {
        let services = "An asterisk (*) denotes that a network service is disabled.\nThunderbolt Bridge\nWi-Fi\n*Old VPN\niPhone USB\n"
        #expect(DNSShield.parseServices(services) == ["Thunderbolt Bridge", "Wi-Fi", "iPhone USB"])
        #expect(DNSShield.parseServices("") == [])
        #expect(DNSShield.parseServers("1.1.1.1\n1.0.0.1\n2606:4700:4700::1111\n") == ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"])
        #expect(DNSShield.parseServers("There aren't any DNS Servers set on Wi-Fi.\n").isEmpty)
    }

    @Test func recognisesAddressesOnly() {
        #expect(DNSShield.isAddress("9.9.9.9") && DNSShield.isAddress("2620:fe::fe") && DNSShield.isAddress("2a0d:2a00:1::"))
        for bad in ["", "9.9.9", "1.1.1.1; rm -rf /", "example.com", "1.1.1.1 2.2.2.2", "$(id)"] { #expect(!DNSShield.isAddress(bad)) }
        #expect(DNSShield.profiles.allSatisfy { $0.servers.allSatisfy(DNSShield.isAddress) && $0.servers.count == 4 })
        #expect(Set(DNSShield.profiles.map(\.id)).count == DNSShield.profiles.count)
    }

    @Test func matchesAProfileOnlyWhenEveryServerIsItsOwn() {
        #expect(DNSShield.profile(for: ["1.1.1.3", "1.0.0.3"])?.id == "cloudflare-family")
        #expect(DNSShield.profile(for: ["9.9.9.9"])?.id == "quad9")
        #expect(DNSShield.profile(for: ["1.1.1.1", "1.0.0.1"]) == nil)
        #expect(DNSShield.profile(for: ["1.1.1.3", "8.8.8.8"]) == nil)
        #expect(DNSShield.profile(for: []) == nil)
    }

    @Test func buildsOneValidatedCommand() throws {
        let command = try #require(DNSShield.command(servers: ["Wi-Fi": ["1.1.1.3", "1.0.0.3"], "Thunderbolt Bridge": []]))
        #expect(command.contains("/usr/sbin/networksetup -setdnsservers 'Wi-Fi' 1.1.1.3 1.0.0.3"))
        #expect(command.contains("-setdnsservers 'Thunderbolt Bridge' Empty"))
        #expect(command.hasSuffix("/usr/bin/killall -HUP mDNSResponder"))
        #expect(DNSShield.command(servers: ["Wi-Fi": ["1.1.1.3; reboot"]]) == nil)
        #expect(DNSShield.command(servers: ["Evil'; reboot; '": ["1.1.1.3"]]) == nil)
        #expect(DNSShield.command(servers: [:]) == nil)
        let mixed = try #require(DNSShield.command(servers: ["Wi-Fi": ["9.9.9.9"], "Bad $(x)": ["9.9.9.9"]]))
        #expect(!mixed.contains("Bad"))
    }

    @Test func readsBlockedAnswersAndTailscale() {
        #expect(DNSShield.blocked(digOutput: "0.0.0.0\n"))
        #expect(DNSShield.blocked(digOutput: ""))
        #expect(DNSShield.blocked(digOutput: "::\n"))
        #expect(!DNSShield.blocked(digOutput: "104.18.5.35\n104.18.4.35\n"))
        #expect(!DNSShield.blocked(digOutput: "0.0.0.0\n104.18.5.35\n"))
        let tailscale = "DNS configuration\n\nresolver #1\n  nameserver[0] : 100.100.100.100\n\nresolver #2\n  nameserver[0] : 1.1.1.1\n"
        #expect(DNSShield.usesTailscaleDNS(scutilOutput: tailscale))
        #expect(!DNSShield.usesTailscaleDNS(scutilOutput: "resolver #1\n  nameserver[0] : 1.1.1.1\nresolver #2\n  nameserver[0] : 100.100.100.100\n"))
        #expect(!DNSShield.usesTailscaleDNS(scutilOutput: ""))
    }
}

@Suite struct HardeningTests {
    private func secure() -> HardeningSnapshot {
        var snapshot = HardeningSnapshot()
        snapshot.firewall = true
        snapshot.stealthMode = true
        snapshot.screenLockDelay = 0
        snapshot.guestEnabled = false
        snapshot.exposedPorts = []
        snapshot.dnsFiltered = true
        snapshot.protections = [ProtectionCheck(id: "sip", title: "SIP", state: .on, detail: "d", settingsURL: nil),
                                ProtectionCheck(id: "firewall", title: "Firewall", state: .on, detail: "d", settingsURL: nil)]
        return snapshot
    }

    @Test func aLockedDownMacPassesEverything() {
        let checks = Hardening.checks(secure())
        #expect(checks.allSatisfy { $0.state == .pass && $0.fix == nil })
        #expect(checks.filter { $0.id == "firewall" }.count == 1)
        #expect(Hardening.score(checks) == 100)
        #expect(Set(checks.map(\.id)).count == checks.count)
    }

    @Test func eachWeakSettingFailsWithItsFix() {
        var snapshot = secure()
        snapshot.firewall = false
        snapshot.stealthMode = false
        snapshot.softwareUpdate = ["CriticalUpdateInstall": false, "AutomaticDownload": true]
        snapshot.screenLockDelay = 900
        snapshot.autoLoginUser = "me"
        snapshot.guestEnabled = true
        snapshot.exposedPorts = [22, 5900]
        snapshot.dnsFiltered = false
        snapshot.protections = [ProtectionCheck(id: "filevault", title: "FileVault", state: .off, detail: "d", settingsURL: "x:fv")]
        let checks = Dictionary(uniqueKeysWithValues: Hardening.checks(snapshot).map { ($0.id, $0) })
        #expect(checks["firewall"]?.fix == .admin("firewall") && checks["stealth"]?.fix == .admin("stealth"))
        #expect(checks["auto-updates"]?.state == .fail && checks["auto-updates"]?.status == "1 of 4 switched off")
        #expect(checks["screen-lock"]?.state == .fail && checks["screen-lock"]?.status == "After 15 minutes")
        #expect(checks["auto-login"]?.state == .fail && checks["guest"]?.fix == .admin("guest"))
        #expect(checks["sharing-ssh"]?.state == .fail && checks["sharing-screen"]?.state == .fail && checks["sharing-files"]?.state == .pass)
        #expect(checks["dns"]?.fix == .openDNSShield)
        #expect(checks["filevault"]?.fix == .openSettings("x:fv"))
        #expect(Hardening.score(Array(checks.values)) < 30)
    }

    @Test func unknownSettingsNeitherPassNorCostPoints() {
        var snapshot = HardeningSnapshot()
        snapshot.dnsFiltered = true
        let checks = Hardening.checks(snapshot)
        let unknown = checks.filter { $0.state == .unknown }
        #expect(unknown.map(\.id).contains("firewall") && unknown.map(\.id).contains("screen-lock") && unknown.map(\.id).contains("sharing-ssh"))
        #expect(unknown.allSatisfy { $0.fix == nil && $0.status == "Couldn't check" })
        #expect(Hardening.score(checks) == 100)
        #expect(Hardening.score([]) == 100)
    }

    @Test func parsesScreenLockAndStealthOutput() {
        #expect(Hardening.parseScreenLock("sysadminctl[1:2] screenLock delay is immediate") == 0)
        #expect(Hardening.parseScreenLock("screenLock delay is 300 seconds") == 300)
        #expect(Hardening.parseScreenLock("screenLock is off") == -1)
        #expect(Hardening.parseScreenLock("garbage") == nil)
        #expect(Hardening.lockStatus(-1) == "Never asks" && Hardening.lockStatus(5) == "After 5 seconds" && Hardening.lockStatus(60) == "After 1 minute")
        #expect(Hardening.parseStealth("Firewall stealth mode is off") == false)
        #expect(Hardening.parseStealth("Firewall stealth mode is on") == true)
        #expect(Hardening.parseStealth("Stealth mode enabled") == true && Hardening.parseStealth("Stealth mode disabled") == false)
        #expect(Hardening.parseStealth("") == nil)
    }

    @Test func fixesAreFixedCommandsOnly() async {
        #expect(Set(Hardening.fixCommands.keys) == ["firewall", "stealth", "auto-updates", "guest"])
        #expect(Hardening.fixCommands.values.allSatisfy { !$0.contains("$") && !$0.contains("`") })
        await #expect(throws: AdminRunner.AdminError.self) { try await Hardening.applyFixes(["rm -rf /"]) }
        await #expect(throws: AdminRunner.AdminError.self) { try await Hardening.applyFixes(["firewall", "unknown"]) }
        await #expect(throws: AdminRunner.AdminError.self) { try await Hardening.applyFixes([]) }
    }
}

@Suite struct SecurityPatchesTests {
    private func update(_ name: String, _ source: AvailableUpdate.Source, restart: Bool = false) -> AvailableUpdate {
        AvailableUpdate(name: name, installed: "1", available: "2", source: source, needsRestart: restart)
    }

    @Test func ranksSystemSecurityUpdatesFirst() {
        let ranked = SecurityPatches.ranked([
            update("jq", .homebrewFormula), update("openssl@3", .homebrewFormula), update("macOS 27.2.1", .macOS, restart: true),
            update("Command Line Tools for Xcode 27.2", .macOS), update("firefox", .homebrewCask), update("Safari", .macOS),
        ])
        #expect(ranked.prefix(2).map(\.update.name).sorted() == ["Safari", "macOS 27.2.1"])
        #expect(ranked.prefix(2).allSatisfy { $0.severity == .high })
        #expect(ranked.last?.update.name == "jq" && ranked.last?.severity == .low)
        #expect(ranked.first { $0.update.name == "openssl@3" }?.severity == .medium)
        #expect(ranked.first { $0.update.name == "Command Line Tools for Xcode 27.2" }?.severity == .medium)
        #expect(SecurityPatches.ranked([]).isEmpty)
    }

    @Test func readsMalwareDefinitionsFromTheFirstPlistThatExists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let plist = folder + "/Info.plist"
        #expect((["CFBundleShortVersionString": "5290"] as NSDictionary).write(toFile: plist, atomically: true))
        let found = try #require(SecurityPatches.malwareDefinitions(paths: [folder + "/missing.plist", plist]))
        #expect(found.version == "5290" && found.updated != nil)
        #expect(SecurityPatches.malwareDefinitions(paths: [folder + "/missing.plist"]) == nil)
    }
}

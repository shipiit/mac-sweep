import Foundation
import Testing
@testable import MacSweepCore

@Suite struct SharingAuditTests {
    static func snapshot(
        wifi: WiFiStatus? = WiFiStatus(isConnected: true, networkName: "Home", security: .wpa3, phyMode: nil),
        bluetooth: BluetoothStatus? = BluetoothStatus(isPoweredOn: true, isDiscoverable: false, connectedDevices: [], pairedCount: 0),
        ports: Set<Int>? = [],
        firewall: FirewallStatus = FirewallStatus(enabled: .on, blockAll: false, stealth: .on),
        airDrop: AirDropMode = .contactsOnly
    ) -> SharingSnapshot {
        SharingSnapshot(wifi: wifi, bluetooth: bluetooth, exposedPorts: ports, firewall: firewall, airDrop: airDrop)
    }

    static func finding(_ id: String, in snapshot: SharingSnapshot) -> SharingFinding? {
        SharingAudit.findings(snapshot).first { $0.id == id }
    }

    @Test func secureMacHasNothingToFix() {
        let findings = SharingAudit.findings(Self.snapshot())
        #expect(findings.map(\.id) == ["wifi", "bluetooth", "ssh", "screen", "files", "ard", "firewall", "stealth", "airdrop"])
        #expect(findings.allSatisfy { $0.severity == .info })
        #expect(findings.map(\.category) == [.wireless, .wireless, .sharing, .sharing, .sharing, .sharing, .protection, .protection, .protection])
        #expect(findings.allSatisfy { SettingsLinks.all.contains($0.settingsURL) })
    }

    @Test func missingWirelessInfoDropsThoseFindings() {
        let findings = SharingAudit.findings(Self.snapshot(wifi: nil, bluetooth: nil))
        #expect(!findings.contains { $0.category == .wireless })
        #expect(findings.count == 7)
    }

    @Test func listeningServicesAreFlaggedBySeverity() throws {
        let snapshot = Self.snapshot(ports: [22, 5900, 548, 3283])
        #expect(Self.finding("ssh", in: snapshot)?.severity == .medium)
        #expect(Self.finding("screen", in: snapshot)?.severity == .medium)
        #expect(Self.finding("files", in: snapshot)?.severity == .low)
        #expect(Self.finding("ard", in: snapshot)?.severity == .medium)
        let ssh = try #require(Self.finding("ssh", in: snapshot))
        #expect(ssh.status == "On")
        #expect(ssh.detail.contains("log in"))
    }

    @Test func servicesOffWhenPortsClosed() throws {
        let files = try #require(Self.finding("files", in: Self.snapshot(ports: [8080])))
        #expect(files.status == "Off")
        #expect(files.severity == .info)
        #expect(files.detail == "Not listening on the network.")
    }

    @Test func servicesUnknownWhenNetstatFailed() {
        let findings = SharingAudit.findings(Self.snapshot(ports: nil)).filter { $0.category == .sharing }
        #expect(findings.count == 4)
        #expect(findings.allSatisfy { $0.status == "Unknown" && $0.severity == .info })
    }

    @Test(arguments: [
        (WiFiSecurity.open, FindingSeverity.high),
        (.wep, .high),
        (.wpa, .high),
        (.wpaWPA2Mixed, .medium),
        (.enhancedOpen, .low),
        (.unknown("x"), .low),
        (.wpa2, .info),
        (.wpa2WPA3, .info),
        (.wpa3, .info),
        (.enterprise("WPA2"), .info),
    ])
    func wifiSecuritySeverity(security: WiFiSecurity, expected: FindingSeverity) throws {
        let wifi = WiFiStatus(isConnected: true, networkName: "Net", security: security, phyMode: nil)
        let finding = try #require(Self.finding("wifi", in: Self.snapshot(wifi: wifi)))
        #expect(finding.severity == expected)
        #expect(finding.status == security.title)
    }

    @Test func disconnectedWiFiIsInfo() throws {
        let wifi = WiFiStatus(isConnected: false, networkName: nil, security: nil, phyMode: nil)
        let finding = try #require(Self.finding("wifi", in: Self.snapshot(wifi: wifi)))
        #expect(finding.severity == .info)
        #expect(finding.status == "Not connected")
    }

    @Test func bluetoothStates() throws {
        let discoverable = BluetoothStatus(isPoweredOn: true, isDiscoverable: true, connectedDevices: ["AirPods"], pairedCount: 1)
        let visible = try #require(Self.finding("bluetooth", in: Self.snapshot(bluetooth: discoverable)))
        #expect(visible.severity == .low)
        #expect(visible.status == "Discoverable")
        #expect(visible.detail.contains("Connected: AirPods"))

        let off = BluetoothStatus(isPoweredOn: false, isDiscoverable: nil, connectedDevices: [], pairedCount: 0)
        let poweredOff = try #require(Self.finding("bluetooth", in: Self.snapshot(bluetooth: off)))
        #expect(poweredOff.status == "Off")
        #expect(poweredOff.severity == .info)
        #expect(poweredOff.detail == "No devices connected.")
    }

    @Test func firewallOffIsMediumAndHidesStealthAdvice() throws {
        let snapshot = Self.snapshot(firewall: FirewallStatus(enabled: .off, blockAll: false, stealth: .off))
        let firewall = try #require(Self.finding("firewall", in: snapshot))
        #expect(firewall.severity == .medium)
        #expect(firewall.status == "Off")
        #expect(Self.finding("stealth", in: snapshot)?.severity == .info)
    }

    @Test func firewallOnWithoutStealthIsLow() throws {
        let snapshot = Self.snapshot(firewall: FirewallStatus(enabled: .on, blockAll: true, stealth: .off))
        #expect(Self.finding("firewall", in: snapshot)?.status == "On, blocking all incoming")
        #expect(Self.finding("stealth", in: snapshot)?.severity == .low)
    }

    @Test func firewallUnknownIsLow() {
        let snapshot = Self.snapshot(firewall: FirewallStatus(enabled: .unknown, blockAll: false, stealth: .unknown))
        #expect(Self.finding("firewall", in: snapshot)?.severity == .low)
        #expect(Self.finding("firewall", in: snapshot)?.status == "Unknown")
        #expect(Self.finding("stealth", in: snapshot)?.severity == .info)
    }

    @Test(arguments: [
        (AirDropMode.everyone, FindingSeverity.medium),
        (.contactsOnly, .info),
        (.off, .info),
        (.unknown, .info),
    ])
    func airDropSeverity(mode: AirDropMode, expected: FindingSeverity) throws {
        let finding = try #require(Self.finding("airdrop", in: Self.snapshot(airDrop: mode)))
        #expect(finding.severity == expected)
        #expect(finding.status == mode.title)
    }
}

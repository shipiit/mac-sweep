import Foundation
import Testing
@testable import MacSweepCore

@Suite struct SharingParsersTests {
    static let netstat = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
        tcp4       0      0  *.22                   *.*                    LISTEN
        tcp6       0      0  *.5900                 *.*                    LISTEN
        tcp4       0      0  127.0.0.1.631          *.*                    LISTEN
        tcp6       0      0  ::1.8080               *.*                    LISTEN
        tcp6       0      0  fe80::1%lo0.7000       *.*                    LISTEN
        tcp4       0      0  192.168.1.5.445        *.*                    LISTEN
        tcp4       0      0  192.168.1.5.50000      17.1.1.1.443           ESTABLISHED
        udp4       0      0  *.5353                 *.*
        """

    @Test func exposedPortsSkipLoopbackAndNonListening() {
        #expect(SharingParsers.exposedTCPPorts(Self.netstat) == [22, 5900, 445])
    }

    @Test func exposedPortsEmptyAndGarbage() {
        #expect(SharingParsers.exposedTCPPorts("").isEmpty)
        #expect(SharingParsers.exposedTCPPorts("netstat: sysctl: Operation not permitted").isEmpty)
        #expect(SharingParsers.exposedTCPPorts("tcp4 0 0 *.abc *.* LISTEN").isEmpty)
    }

    @Test func firewallEnabledWithStealth() {
        let status = SharingParsers.firewall("Firewall is enabled. (State = 1)\nFirewall stealth mode is on\n")
        #expect(status == FirewallStatus(enabled: .on, blockAll: false, stealth: .on))
    }

    @Test func firewallBlockingAll() {
        let status = SharingParsers.firewall("Firewall is blocking all non-essential incoming connections. (State = 2)\nStealth mode disabled")
        #expect(status == FirewallStatus(enabled: .on, blockAll: true, stealth: .off))
    }

    @Test func firewallDisabled() {
        let status = SharingParsers.firewall("Firewall is disabled. (State = 0)\nFirewall stealth mode is off")
        #expect(status == FirewallStatus(enabled: .off, blockAll: false, stealth: .off))
    }

    @Test func firewallEmptyOrGarbageIsUnknown() {
        let unknown = FirewallStatus(enabled: .unknown, blockAll: false, stealth: .unknown)
        #expect(SharingParsers.firewall("") == unknown)
        #expect(SharingParsers.firewall("zsh: command not found") == unknown)
    }

    @Test(arguments: [
        ("Off\n", Int32(0), AirDropMode.off),
        ("Contacts Only\n", 0, .contactsOnly),
        ("Everyone\n", 0, .everyone),
        ("Everyone (10 minutes)", 0, .everyone),
        ("Something new", 0, .unknown),
        ("", 0, .unknown),
        ("The domain/default pair of (com.apple.sharingd, DiscoverableMode) does not exist", 1, .unknown),
    ])
    func airDrop(output: String, status: Int32, expected: AirDropMode) {
        #expect(SharingParsers.airDrop(output, status: status) == expected)
    }
}

@Suite struct WirelessParserTests {
    static let connectedWiFi = """
        {"SPAirPortDataType":[{"spairport_airport_interfaces":[
          {"_name":"awdl0"},
          {"_name":"en0","spairport_status_information":"spairport_status_connected",
           "spairport_current_network_information":{"_name":"Home","spairport_security_mode":"spairport_security_mode_wpa3_transition",
           "spairport_network_phymode":"802.11ax"}}]}]}
        """

    @Test func parsesConnectedWiFi() throws {
        let wifi = try #require(WirelessParser.wifi(Self.connectedWiFi))
        #expect(wifi.isConnected)
        #expect(wifi.networkName == "Home")
        #expect(wifi.security == .wpa2WPA3)
        #expect(wifi.phyMode == "802.11ax")
    }

    @Test func parsesDisconnectedWiFi() throws {
        let json = #"{"SPAirPortDataType":[{"spairport_airport_interfaces":[{"_name":"en0","spairport_status_information":"spairport_status_disconnected"}]}]}"#
        let wifi = try #require(WirelessParser.wifi(json))
        #expect(!wifi.isConnected)
        #expect(wifi.security == nil)
        #expect(wifi.networkName == nil)
    }

    @Test func wifiEmptyOrGarbageIsNil() {
        #expect(WirelessParser.wifi("") == nil)
        #expect(WirelessParser.wifi("not json") == nil)
        #expect(WirelessParser.wifi("{}") == nil)
        #expect(WirelessParser.wifi(#"{"SPAirPortDataType":[{"spairport_airport_interfaces":[]}]}"#) == nil)
    }

    @Test func parsesBluetooth() throws {
        let json = """
            {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on","controller_discoverable":"attrib_off"},
             "device_connected":[{"AirPods":{"device_minorType":"Headphones"}}],
             "device_not_connected":[{"Mouse":{}},{"Keyboard":{}}]}]}
            """
        let bluetooth = try #require(WirelessParser.bluetooth(json))
        #expect(bluetooth.isPoweredOn == true)
        #expect(bluetooth.isDiscoverable == false)
        #expect(bluetooth.connectedDevices == ["AirPods"])
        #expect(bluetooth.pairedCount == 3)
    }

    @Test func bluetoothMissingPropertiesAreUnknown() throws {
        let bluetooth = try #require(WirelessParser.bluetooth(#"{"SPBluetoothDataType":[{}]}"#))
        #expect(bluetooth.isPoweredOn == nil)
        #expect(bluetooth.isDiscoverable == nil)
        #expect(bluetooth.connectedDevices.isEmpty)
        #expect(bluetooth.pairedCount == 0)
    }

    @Test func bluetoothEmptyOrGarbageIsNil() {
        #expect(WirelessParser.bluetooth("") == nil)
        #expect(WirelessParser.bluetooth("[1,2]") == nil)
        #expect(WirelessParser.bluetooth(#"{"SPBluetoothDataType":[]}"#) == nil)
    }

    @Test(arguments: [
        ("spairport_security_mode_none", WiFiSecurity.open),
        ("open", .open),
        ("spairport_security_mode_owe", .enhancedOpen),
        ("spairport_security_mode_wep", .wep),
        ("spairport_security_mode_wpa_personal", .wpa),
        ("spairport_security_mode_wpa_personal_mixed", .wpaWPA2Mixed),
        ("spairport_security_mode_wpa2_personal", .wpa2),
        ("spairport_security_mode_wpa3_transition", .wpa2WPA3),
        ("spairport_security_mode_wpa3_personal", .wpa3),
        ("spairport_security_mode_wpa2_enterprise", .enterprise("WPA2")),
        ("spairport_security_mode_wpa3_enterprise", .enterprise("WPA3")),
        ("spairport_security_mode_wpa_enterprise", .enterprise("WPA")),
        ("something_else", .unknown("something_else")),
    ])
    func securityModes(raw: String, expected: WiFiSecurity) {
        #expect(WiFiSecurity.from(mode: raw) == expected)
    }
}

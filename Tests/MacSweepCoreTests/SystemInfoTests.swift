import Foundation
import Testing
@testable import MacSweepCore

@Suite struct SystemInfoTests {
    @Test func parsesAppleSiliconBattery() throws {
        let info = try #require(Battery.parse([
            "CurrentCapacity": 79, "MaxCapacity": 100, "AppleRawMaxCapacity": 4_200, "DesignCapacity": 5_000,
            "IsCharging": true, "ExternalConnected": true, "CycleCount": 312, "Temperature": 3_050,
            "TimeRemaining": 95, "AdapterDetails": ["Watts": 70],
        ]))
        #expect(info.percent == 79)
        #expect(info.isCharging && info.isPluggedIn)
        #expect(info.cycleCount == 312)
        #expect(abs((info.health ?? 0) - 0.84) < 0.001)
        #expect(info.temperatureCelsius == 30.5)
        #expect(info.minutesRemaining == 95)
        #expect(info.adapterWatts == 70)
    }

    @Test func parsesIntelStyleBatteryInMah() throws {
        let info = try #require(Battery.parse(["CurrentCapacity": 2_500, "MaxCapacity": 5_000, "DesignCapacity": 5_000]))
        #expect(info.percent == 50)
        #expect(info.health == 1.0)
    }

    @Test func batteryEdgeCases() {
        #expect(Battery.parse([:]) == nil)
        let info = Battery.parse(["CurrentCapacity": 50, "TimeRemaining": 65_535])
        #expect(info?.minutesRemaining == nil)
        #expect(info?.health == nil)
        #expect(info?.isCharging == false)
    }

    @Test func parsesHardwareProfile() {
        let json = #"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","chip_type":"Apple M3 Pro"}]}"#
        let parsed = MacInfo.parseHardware(json)
        #expect(parsed?.modelName == "MacBook Pro")
        #expect(parsed?.chip == "Apple M3 Pro")
        #expect(MacInfo.parseHardware("not json") == nil)
        #expect(MacInfo.parseHardware("{}") == nil)
    }

    @Test func basicInfoIsPopulated() {
        let info = MacInfo.basic()
        #expect(info.osVersion.hasPrefix("macOS"))
        #expect(info.memory > 0)
        #expect(!info.modelIdentifier.isEmpty)
    }

    @Test func parsesSpeedTest() throws {
        let json = #"{"dl_throughput": 245000000, "ul_throughput": 41000000, "responsiveness": 1200}"#
        let result = try #require(NetworkInfo.parseSpeedTest(json))
        #expect(result.downloadMbps == 245)
        #expect(result.uploadMbps == 41)
        #expect(result.responsivenessRPM == 1200)
        #expect(NetworkInfo.parseSpeedTest("{}") == nil)
        #expect(NetworkInfo.parseSpeedTest("") == nil)
    }

    @Test func parsesDevicesSkippingHubs() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_minorType":"Headphones","device_batteryLevelMain":"80%"}}],
          "device_not_connected":[{"Old Mouse":{}}]}],
         "SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"USB2.0 HUB","_items":[{"_name":"Keychron K2","manufacturer":"Keychron"}]}]}]}
        """
        let devices = Devices.parse(json)
        #expect(devices.map(\.name) == ["AirPods Pro", "Keychron K2"])
        #expect(devices[0].detail == "Headphones · Battery 80%")
        #expect(devices[1].kind == .usb)
        #expect(Devices.parse("garbage").isEmpty)
    }

    @Test func uptimeFormatting() {
        #expect(Uptime.formatted(59) == "0m")
        #expect(Uptime.formatted(3_700) == "1h 1m")
        #expect(Uptime.formatted(90_000) == "1d 1h")
    }
}

@Suite struct NetworkDetailsTests {
    @Test func parsesDefaultRoute() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.0.1
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """
        let parsed = NetworkDetailsReader.parseRoute(output)
        #expect(parsed.gateway == "192.168.0.1" && parsed.interface == "en0")
        #expect(NetworkDetailsReader.parseRoute("").gateway == nil)
    }

    @Test func parsesDNSUniqueInOrder() {
        let output = """
        resolver #1
          nameserver[0] : 1.1.1.1
          nameserver[1] : 8.8.8.8
        resolver #2
          nameserver[0] : 1.1.1.1
          nameserver[1] : fe80::1%en0
        """
        #expect(NetworkDetailsReader.parseDNS(output) == ["1.1.1.1", "8.8.8.8", "fe80::1%en0"])
        #expect(NetworkDetailsReader.parseDNS("").isEmpty)
    }

    @Test func validatesIPAddresses() {
        #expect(NetworkDetailsReader.isIPAddress("203.0.113.9"))
        #expect(NetworkDetailsReader.isIPAddress("2001:db8::1"))
        #expect(!NetworkDetailsReader.isIPAddress("<html>"))
        #expect(!NetworkDetailsReader.isIPAddress(""))
    }

    @Test func masksSerial() {
        #expect(HardwareInfo.masked("C02XG123JHD5") == "••••••••JHD5")
        #expect(HardwareInfo.masked("AB") == "••")
    }

    @Test func liveReadsDoNotCrash() async {
        let details = await NetworkDetailsReader.read()
        if let mac = details.macAddress { #expect(mac.split(separator: ":").count == 6) }
        _ = HardwareInfo.serialNumber()
    }
}

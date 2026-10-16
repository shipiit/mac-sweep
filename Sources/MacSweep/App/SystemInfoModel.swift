import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class SystemInfoModel {
    enum SpeedTest: Equatable {
        case idle
        case running
        case done(SpeedTestResult)
        case failed(String)
    }

    private(set) var mac = MacInfo.basic()
    private(set) var battery: BatteryInfo?
    private(set) var network: NetworkStatus?
    private(set) var devices: [ConnectedDevice] = []
    private(set) var thermal = ThermalLevel.current()
    private(set) var uptime = Uptime.formatted()
    var speedTest: SpeedTest = .idle
    private(set) var details = NetworkDetails()
    private(set) var serial: String?
    var publicIP: PublicIP = .hidden

    enum PublicIP: Equatable {
        case hidden
        case loading
        case shown(String)
        case failed(String)
    }

    func loadDetails() async {
        details = await NetworkDetailsReader.read()
        if serial == nil { serial = HardwareInfo.serialNumber() }
    }

    /// Only on request: the public IP is the one value that needs an outside service.
    func revealPublicIP() {
        publicIP = .loading
        Task {
            do { publicIP = .shown(try await NetworkDetailsReader.publicIP()) } catch { publicIP = .failed(error.localizedDescription) }
        }
    }

    @ObservationIgnored private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        Task { mac = await MacInfo.detailed() }
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshFast()
                if tick % 4 == 0 { self.devices = await Devices.connected() }
                tick += 1
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func refreshFast() {
        battery = Battery.read()
        network = NetworkInfo.status()
        thermal = ThermalLevel.current()
        uptime = Uptime.formatted()
    }

    func runSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        Task {
            do {
                if let result = try await NetworkInfo.speedTest() {
                    speedTest = .done(result)
                } else {
                    speedTest = .failed("No result. Are you online?")
                }
            } catch {
                speedTest = .failed(error.localizedDescription)
            }
        }
    }
}

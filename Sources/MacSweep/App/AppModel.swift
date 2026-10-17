import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class AppModel {
    let home = NSHomeDirectory()
    let disk: DiskModel
    let cleanup: CleanupModel
    let processes = ProcessModel()
    let ports = PortsModel()
    let startup = StartupModel()
    let monitor = SystemMonitor()
    let system = SystemInfoModel()
    let security = SecurityModel()
    let apps = AppsModel()
    let updates = UpdaterModel()
    let privacy = PrivacyModel()
    let maintenance = MaintenanceModel()
    let addOns = ExtensionsModel()
    let usage = UsageModel()
    let ai = AIUsageModel()
    let insights = InsightsCenter()
    /// Pages that show per-process numbers and so need 3-second sampling.
    static let liveProcessPages: Set<SidebarSection> = [.processes, .overview, .ports, .optimization]
    let threats = ThreatCenter()
    /// Reopens on the page used last (`-lastSection "Developer"` on the command line also works).
    var section: SidebarSection? = UserDefaults.standard.string(forKey: "lastSection").flatMap(SidebarSection.init(rawValue:)) ?? .smartScan {
        didSet {
            UserDefaults.standard.set(section?.rawValue, forKey: "lastSection")
            processes.isLive = Self.liveProcessPages.contains(section ?? .smartScan)
        }
    }
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess()
    /// Set by the menu bar label, which lives in a scene and can open windows.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private var portLoop: Task<Void, Never>?
    @ObservationIgnored private var scheduleLoop: Task<Void, Never>?

    init() {
        disk = DiskModel(home: home)
        cleanup = CleanupModel(home: home)
        disk.onResultChange = { [cleanup] result in cleanup.evaluate(result) }
        cleanup.onRemoved = { [disk] paths in disk.apply(removed: paths) }
        monitor.start()
        system.start()
        usage.start()
        ai.start()
        insights.start(app: self)
        threats.start()
        // A quiet audit shortly after launch keeps the sidebar's security badge current.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.security.lastRun == nil, !self.security.isRunning else { return }
            await self.security.run()
        }
        Task { [security] in await security.run() }
        processes.isLive = Self.liveProcessPages.contains(section ?? .smartScan)
        processes.start()
        portLoop = Task { [ports] in
            while !Task.isCancelled {
                await ports.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        scheduleLoop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                self?.runScheduledScanIfDue()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    var schedule: ScanSchedule {
        ScanSchedule(rawValue: UserDefaults.standard.string(forKey: "scanSchedule") ?? "") ?? .nightly
    }

    /// Scheduled scans skip when the battery is low and unplugged, so they never drain a laptop.
    private func runScheduledScanIfDue() {
        guard !disk.isScanning, schedule.isDue(lastScan: disk.result?.finishedAt) else { return }
        if let battery = Battery.read(), !battery.isPluggedIn, battery.percent < 30 { return }
        disk.scan(root: disk.result?.root.path ?? home, isBackground: true)
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess(home: home)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case smartScan = "Smart Scan"
    case overview = "Dashboard"
    case systemInfo = "System Info"
    case storage = "Space & Junk"
    case files = "Large & Hidden Files"
    case mail = "Mail Attachments"
    case trash = "Trash Bins"
    case shredder = "Shredder"
    case privacy = "Privacy"
    case security = "Security Audit"
    case extensions = "Extensions"
    case optimization = "Optimization"
    case maintenance = "Maintenance"
    case processes = "Processes & Memory"
    case ports = "Ports"
    case startup = "Startup Items"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case ai = "AI Usage"
    case usage = "App Usage"
    case alerts = "Smart Alerts"
    case duplicates = "Duplicates & Archive"
    case developer = "Developer"
    case malware = "Malware Scan"
    case permissions = "App Permissions"
    case network = "Network Monitor"
    case sharing = "Sharing & Wi-Fi"
    case backups = "Backups"
    case timeline = "Timeline"
    case growth = "What Grew"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles.rectangle.stack"
        case .overview: "gauge.with.dots.needle.67percent"
        case .systemInfo: "info.circle"
        case .ai: "flame"
        case .usage: "hourglass"
        case .alerts: "bell.badge"
        case .duplicates: "doc.on.doc"
        case .developer: "hammer"
        case .malware: "shield.checkered"
        case .permissions: "hand.raised.square"
        case .network: "point.3.connected.trianglepath.dotted"
        case .sharing: "person.2.wave.2"
        case .backups: "clock.arrow.circlepath"
        case .timeline: "chart.xyaxis.line"
        case .growth: "chart.bar.doc.horizontal"
        case .storage: "internaldrive"
        case .files: "doc.text.magnifyingglass"
        case .mail: "paperclip"
        case .trash: "trash"
        case .shredder: "doc.badge.ellipsis"
        case .privacy: "hand.raised"
        case .security: "checkmark.shield"
        case .extensions: "puzzlepiece.extension"
        case .optimization: "slider.horizontal.3"
        case .maintenance: "wrench.and.screwdriver"
        case .processes: "memorychip"
        case .ports: "network"
        case .startup: "power"
        case .uninstaller: "trash.square"
        case .updater: "arrow.down.app"
        }
    }

    static let groups: [(title: String, sections: [SidebarSection])] = [
        ("", [.smartScan, .overview, .ai]),
        ("Cleanup", [.storage, .files, .duplicates, .mail, .trash, .shredder, .privacy]),
        ("Protection", [.malware, .security, .permissions, .network, .sharing, .backups, .extensions]),
        ("Performance", [.optimization, .maintenance, .processes, .startup]),
        ("Developer", [.developer, .ports]),
        ("Applications", [.uninstaller, .updater, .usage]),
        ("Insights", [.systemInfo, .alerts, .timeline, .growth]),
    ]
}

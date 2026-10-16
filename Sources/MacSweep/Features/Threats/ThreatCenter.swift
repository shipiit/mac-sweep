import Foundation
import MacSweepCore
import Observation
import UserNotifications

/// Full-Mac malware scans plus Download Protection: every finished download is checked; clear threats are
/// moved to quarantine automatically and anything suspicious raises a notification.
@MainActor
@Observable
final class ThreatCenter {
    private(set) var verdicts: [ThreatVerdict] = []
    private(set) var isScanning = false
    private(set) var progress: ThreatScanner.Progress?
    private(set) var lastScan: Date?
    private(set) var quarantined: [QuarantinedItem] = []
    /// Download Protection events, newest first.
    private(set) var events: [GuardEvent] = []
    var message: String?
    var isProtectionOn: Bool {
        didSet {
            UserDefaults.standard.set(isProtectionOn, forKey: Self.protectionKey)
            isProtectionOn ? startGuard() : stopGuard()
        }
    }

    struct GuardEvent: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let verdict: ThreatVerdict
        let action: String
    }

    @ObservationIgnored private let store = QuarantineStore.standard
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var checked: [String: Date] = [:]
    static let protectionKey = "downloadProtection"
    nonisolated static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "tmp"]
    private var downloads: String { NSHomeDirectory() + "/Downloads" }

    init() {
        isProtectionOn = UserDefaults.standard.object(forKey: Self.protectionKey) as? Bool ?? true
        quarantined = store.items()
    }

    func start() {
        if isProtectionOn { startGuard() }
    }

    // MARK: Full scan

    func scan(roots: [String] = ThreatScanner.defaultRoots()) {
        guard !isScanning else { return }
        isScanning = true
        message = nil
        scanTask = Task { [weak self] in
            let found = await ThreatScanner.scan(roots: roots) { progress in
                Task { @MainActor in self?.progress = progress }
            }
            guard let self else { return }
            verdicts = found
            isScanning = false
            progress = nil
            lastScan = Date()
            MemoryRelief.release()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        progress = nil
    }

    func quarantine(_ verdict: ThreatVerdict) {
        do {
            try store.quarantine(verdict)
            verdicts.removeAll { $0.id == verdict.id }
            quarantined = store.items()
            message = "Moved \(verdict.facts.name) to quarantine. It can't run there, and you can restore it."
        } catch {
            message = "Couldn't quarantine \(verdict.facts.name): \(error.localizedDescription)"
        }
    }

    func ignore(_ verdict: ThreatVerdict) {
        verdicts.removeAll { $0.id == verdict.id }
    }

    func restore(_ item: QuarantinedItem) {
        do {
            try store.restore(item)
            message = "Restored \(item.name)."
        } catch {
            message = "Couldn't restore \(item.name): \(error.localizedDescription)"
        }
        quarantined = store.items()
    }

    func discard(_ item: QuarantinedItem) {
        do { try store.discard(item) } catch { message = error.localizedDescription }
        quarantined = store.items()
    }

    // MARK: Download Protection

    private func startGuard() {
        guard watcher == nil else { return }
        watcher = DirectoryWatcher(paths: [downloads], latency: 2) { [weak self] in
            Task { await self?.checkDownloads() }
        }
    }

    private func stopGuard() {
        watcher = nil
    }

    /// Looks at files that appeared or changed in Downloads in the last 10 minutes and are fully written.
    private func checkDownloads() async {
        let folder = downloads
        let since = Date().addingTimeInterval(-600)
        let alreadyChecked = checked
        let found = await Task.detached(priority: .utility) { () -> [(String, Date, ThreatVerdict?)] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return names.compactMap { name -> (String, Date, ThreatVerdict?)? in
                let path = folder + "/" + name
                guard !name.hasPrefix("."), !ThreatCenter.partialExtensions.contains((name as NSString).pathExtension.lowercased()),
                      let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      modified > since, alreadyChecked[path] != modified, ThreatScanner.isCandidate(path) else { return nil }
                return (path, modified, ThreatScanner.facts(for: path).flatMap(ThreatRules.assess))
            }
        }.value
        for (path, modified, verdict) in found {
            checked[path] = modified
            guard let verdict else { continue }
            if verdict.isAutoQuarantine, (try? store.quarantine(verdict)) != nil {
                quarantined = store.items()
                record(verdict, action: "Blocked and quarantined")
            } else {
                record(verdict, action: "Flagged, review it before opening")
            }
        }
    }

    private func record(_ verdict: ThreatVerdict, action: String) {
        events.insert(GuardEvent(date: Date(), verdict: verdict, action: action), at: 0)
        events = Array(events.prefix(100))
        let title = "\(action): \(verdict.facts.name)"
        let body = verdict.reasons.joined(separator: " · ")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

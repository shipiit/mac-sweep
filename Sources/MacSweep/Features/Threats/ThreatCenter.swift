import AppKit
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
    var lastScan: Date? { history.first?.date }
    /// Past scans and download checks, newest first.
    private(set) var history: [ThreatScanRecord] = []
    private(set) var xprotect: XProtectInfo?
    private(set) var scanningKind: ThreatScanKind?
    private(set) var quarantined: [QuarantinedItem] = []
    /// Download Protection events, newest first.
    private(set) var events: [GuardEvent] = []
    /// The last 20 downloads checked, with what was found; kept across restarts.
    private(set) var downloadsLog: [DownloadRecord] = []
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
    @ObservationIgnored private var isRecheckPending = false
    static let protectionKey = "downloadProtection"
    static let holdKey = "downloadHoldMode"
    /// Whether clean downloads wait for approval; threats are stopped in every mode.
    var holdMode: DownloadHoldMode = DownloadHoldMode(rawValue: UserDefaults.standard.string(forKey: ThreatCenter.holdKey) ?? "") ?? .off {
        didSet { UserDefaults.standard.set(holdMode.rawValue, forKey: Self.holdKey) }
    }
    var held: [QuarantinedItem] { quarantined.filter(DownloadHold.isHeld) }
    nonisolated static let ignoredNames: Set<String> = [".DS_Store", ".localized"]
    nonisolated static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "tmp"]
    private var downloads: String { NSHomeDirectory() + "/Downloads" }

    init() {
        isProtectionOn = UserDefaults.standard.object(forKey: Self.protectionKey) as? Bool ?? true
        quarantined = store.items()
        history = ThreatScanHistory.standard.load()
        downloadsLog = DownloadLog.standard.load()
        xprotect = XProtectInfo.read()
    }

    func start() {
        if isProtectionOn { startGuard() }
    }

    // MARK: Full scan

    func scan(_ kind: ThreatScanKind = .full, roots custom: [String]? = nil) {
        guard !isScanning else { return }
        let roots = custom ?? kind.roots()
        isScanning = true
        scanningKind = kind
        message = nil
        let started = Date()
        scanTask = Task { [weak self] in
            let seen = ProgressCounter()
            let found = await ThreatScanner.scan(roots: roots, maxFiles: kind == .deep ? 10_000_000 : 400_000) { progress in
                seen.value = progress.filesSeen
                Task { @MainActor in self?.progress = progress }
            }
            guard let self, !Task.isCancelled else { return }
            verdicts = found
            isScanning = false
            scanningKind = nil
            progress = nil
            let scope = custom.map { $0.map(Format.path).joined(separator: ", ") } ?? kind.scopeTitle
            let record = ThreatScanRecord(kind: kind, scope: scope, date: started, duration: Date().timeIntervalSince(started),
                                          filesChecked: seen.value, threats: found.count)
            history = (try? ThreatScanHistory.standard.append(record)) ?? [record] + history
            xprotect = XProtectInfo.read()
            MemoryRelief.release()
        }
    }

    /// Lets the user pick folders for a one-off scan.
    func scanCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        scan(.custom, roots: panel.urls.map(\.path))
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanningKind = nil
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
            // An allowed download keeps its original date, so without this the guard would hold it again.
            if let modified = (try? FileManager.default.attributesOfItem(atPath: item.originalPath))?[.modificationDate] as? Date {
                checked[item.originalPath] = modified
            }
            message = DownloadHold.isHeld(item) ? "Allowed \(item.name). It's back in \(Format.path((item.originalPath as NSString).deletingLastPathComponent))." : "Restored \(item.name)."
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
    /// Checks files that appeared or changed in Downloads in the last 10 minutes and are fully written. Every new
    /// download is logged; only programs, installers, click-to-run scripts and disguised files need a deeper look.
    private func checkDownloads() async {
        let folder = downloads
        let since = Date().addingTimeInterval(-600)
        let alreadyChecked = checked
        let mode = holdMode
        let found = await Task.detached(priority: .utility) { () -> [(Date, DownloadRecord, ThreatVerdict?)] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return names.compactMap { name -> (Date, DownloadRecord, ThreatVerdict?)? in
                let path = folder + "/" + name
                guard !ThreatCenter.ignoredNames.contains(name),
                      !ThreatCenter.partialExtensions.contains((name as NSString).pathExtension.lowercased()),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let modified = attributes[.modificationDate] as? Date,
                      modified > since, alreadyChecked[path] != modified else { return nil }
                let facts = ThreatScanner.isCandidate(path) ? ThreatScanner.facts(for: path) : nil
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let record = DownloadRecord.make(path: path, size: size, date: Date(), facts: facts, verdict: facts.flatMap(ThreatRules.assess))
                var verdict = facts.flatMap(ThreatRules.assess)
                // A clean file that the chosen mode holds: it waits in quarantine until the user allows it.
                let kind = facts?.kind ?? FileKind.classify(name: name, isExecutable: false, isMachO: false)
                if verdict == nil, DownloadHold.shouldHold(kind: kind, mode: mode) {
                    guard DownloadHold.isSettled(modified: modified) else { return nil }
                    verdict = DownloadHold.verdict(path: path, kind: kind, origin: facts?.origin ?? ThreatScanner.facts(for: path)?.origin, size: size)
                }
                return (modified, record, verdict)
            }
        }.value
        // A file still being written was skipped above; look again once it has had time to finish.
        if mode != .off, !isRecheckPending {
            let stillWriting = await Task.detached(priority: .utility) { () -> Bool in
                ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).contains { name in
                    guard let modified = (try? FileManager.default.attributesOfItem(atPath: folder + "/" + name))?[.modificationDate] as? Date else { return false }
                    return !DownloadHold.isSettled(modified: modified) && modified <= Date()
                }
            }.value
            if stillWriting {
                isRecheckPending = true
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.isRecheckPending = false
                    await self?.checkDownloads()
                }
            }
        }
        guard !found.isEmpty else { return }
        for (modified, record, verdict) in found {
            checked[record.path] = modified
            guard let verdict else { continue }
            if verdict.reasons == [DownloadHold.reason] {
                if (try? store.quarantine(verdict)) != nil {
                    quarantined = store.items()
                    self.record(verdict, action: "Holding until you allow it")
                }
            } else if verdict.isAutoQuarantine, (try? store.quarantine(verdict)) != nil {
                quarantined = store.items()
                self.record(verdict, action: "Blocked and quarantined")
            } else {
                self.record(verdict, action: "Flagged, review it before opening")
            }
        }
        let records = found.map(\.1)
        downloadsLog = (try? DownloadLog.standard.append(records)) ?? Array((records + downloadsLog).prefix(DownloadLog.limit))
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

/// Last file count reported by the scanner's progress callback.
private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

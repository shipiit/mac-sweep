import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class BackupStatusModel {
    private(set) var report: BackupReport?
    private(set) var isLoading = false

    var severity: FindingSeverity { report.map { BackupAssessment.ageSeverity($0.status) } ?? .info }
    var excluded: [String] { report.map { BackupAssessment.excludedImportant($0.folders) } ?? [] }
    var checkedFolders: [String] { report?.folders.keys.sorted() ?? [] }

    var headline: String {
        switch report?.status {
        case nil: "Checking Time Machine…"
        case .notConfigured?: "Time Machine isn't set up"
        case .needsFullDiskAccess?: "Backup status is hidden"
        case .neverCompleted?: "No backup has finished yet"
        case .backedUp(let date)?: "Last backed up \(Format.relative(date))"
        }
    }

    var explanation: String {
        switch report?.status {
        case nil: "Reading backup destinations and the latest snapshot."
        case .notConfigured?: "Nothing on this Mac is being backed up. Add a backup disk so a failed drive or a stolen laptop doesn't cost you your files."
        case .needsFullDiskAccess?: "macOS only shares the latest backup date with apps that have Full Disk Access."
        case .neverCompleted?: "A backup disk is set up, but no backup has completed. Connect the disk and let a backup finish."
        case .backedUp?:
            switch severity {
            case .info: "Backups are up to date."
            case .low: "A few days old. Connect your backup disk soon."
            case .medium: "Over a week old. Anything you changed since then isn't protected."
            case .high: "Over two weeks old. Connect your backup disk and back up now."
            }
        }
    }

    func load() async {
        isLoading = true
        report = await BackupReader.read()
        isLoading = false
    }
}

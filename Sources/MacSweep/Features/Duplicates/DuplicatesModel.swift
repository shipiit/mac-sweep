import AppKit
import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class DuplicatesModel {
    enum Mode: String, CaseIterable, Identifiable {
        case exact = "Duplicates"
        case photos = "Similar Photos"
        case archive = "Archive & Offload"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .exact: "doc.on.doc"
            case .photos: "photo.on.rectangle.angled"
            case .archive: "archivebox"
            }
        }
    }

    var mode: Mode = .exact
    var roots: [String] = ScanRoots.defaults(home: NSHomeDirectory())
    private(set) var duplicates: DuplicateScanResult?
    private(set) var photos: SimilarPhotoResult?
    private(set) var candidates: [ArchiveCandidate]?
    private(set) var progress: FinderProgress.Snapshot?
    private(set) var isWorking = false
    private(set) var message: String?
    /// Paths chosen for the Trash. Core refuses any plan that would remove every copy in a group.
    var selected: Set<String> = []
    private(set) var archived: [String: VerifiedArchive] = [:]
    private(set) var archivingPath: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    func scan() {
        cancel()
        let mode = mode
        let roots = roots
        let tracker = FinderProgress()
        isWorking = true
        message = nil
        selected = []
        task = Task { [weak self] in
            let poller = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = tracker.snapshot()
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { poller.cancel() }
            do {
                switch mode {
                case .exact:
                    let result = try await DuplicateFinder.find(roots: roots, progress: tracker)
                    self?.duplicates = result
                    self?.selected = Set(result.groups.flatMap { $0.files.dropFirst().map(\.path) })
                case .photos:
                    let result = try await SimilarPhotoFinder.find(roots: roots, progress: tracker)
                    self?.photos = result
                    self?.selected = Set(result.clusters.flatMap { $0.photos.dropFirst().map(\.path) })
                case .archive:
                    self?.candidates = try await ArchiveFinder.find(roots: ArchiveFinder.defaultRoots(home: NSHomeDirectory()), progress: tracker)
                }
            } catch is CancellationError {
                self?.message = "Stopped"
            } catch {
                self?.message = error.localizedDescription
            }
            self?.isWorking = false
            self?.progress = nil
            MemoryRelief.release()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isWorking = false
    }

    /// Moves the selected copies to the Trash; groups where everything is selected are left alone.
    func trashSelected() {
        let groups: [[FileStat]] = mode == .photos ? (photos?.clusters.map(\.photos) ?? []) : (duplicates?.groups.map(\.files) ?? [])
        let selection = selected
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { KeepOneTrash.trash(groups: groups, selected: selection) }.value
            let removed = outcome.removedPaths
            duplicates?.groups = duplicates?.groups.compactMap { $0.removing(removed) } ?? []
            photos?.clusters = photos?.clusters.compactMap { $0.removing(removed) } ?? []
            selected.subtract(removed)
            message = "Moved \(removed.count) files (\(Format.bytes(outcome.freed))) to the Trash"
                + (outcome.blockedGroups > 0 ? " · \(outcome.blockedGroups) groups skipped because every copy was selected" : "")
        }
    }

    func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        roots = Array(Set(roots + panel.urls.map(\.path))).sorted()
    }

    /// Zips to a folder the user picks, verifies the archive by extracting it, and only then allows trashing the original.
    func archive(_ candidate: ArchiveCandidate) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Archive Here"
        panel.message = "Choose an external drive or iCloud Drive folder"
        guard panel.runModal() == .OK, let destination = panel.url?.path else { return }
        archivingPath = candidate.id
        Task {
            do {
                let verified = try await Archiver.archiveAndVerify(source: candidate.facts.path, destination: destination,
                                                                   estimatedSize: candidate.facts.estimatedArchiveSize)
                archived[candidate.id] = verified
                message = "Archived and verified \(candidate.facts.name) (\(Format.bytes(verified.archiveSize)))"
            } catch {
                message = "Couldn't archive \(candidate.facts.name): \(error.localizedDescription)"
            }
            archivingPath = nil
        }
    }

    func trashOriginal(_ candidate: ArchiveCandidate) {
        guard let verified = archived[candidate.id] else { return }
        let result = Archiver.trashOriginal(verified)
        if result.succeeded {
            candidates?.removeAll { $0.id == candidate.id }
            archived[candidate.id] = nil
            message = "Moved \(candidate.facts.name) to the Trash; the archive is at \(Format.path(verified.archivePath))"
        } else {
            message = "Kept \(candidate.facts.name): it changed since archiving or couldn't be moved"
        }
    }
}

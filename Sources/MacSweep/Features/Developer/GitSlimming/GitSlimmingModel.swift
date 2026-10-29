import Foundation
import MacSweepCore
import Observation

enum GitRepoAction: String, Identifiable, Sendable {
    case compact = "Compact"
    case pruneLFS = "Prune LFS cache"

    var id: String { rawValue }
}

struct PendingGitAction: Identifiable {
    let action: GitRepoAction
    let repo: GitRepoInfo

    var id: String { action.rawValue + repo.path }
}

enum GitScanPhase: Equatable {
    case idle
    case finding
    case measuring(done: Int, total: Int)
    case finished
    case gitMissing
}

/// Finds repositories, measures them and runs the per-repo maintenance actions one confirmation at a time.
@MainActor @Observable
final class GitSlimmingModel {
    private(set) var repos: [GitRepoInfo] = []
    private(set) var phase: GitScanPhase = .idle
    /// Repositories with a maintenance command running, and which one.
    private(set) var running: [String: GitRepoAction] = [:]
    /// Last outcome per repository, shown on its card.
    private(set) var outcomes: [String: String] = [:]
    private(set) var isLFSInstalled = GitClient.lfsPath() != nil
    var pending: PendingGitAction?
    var errorMessage: String?

    private static let measuringWidth = 3

    var isScanning: Bool {
        switch phase {
        case .finding, .measuring: true
        case .idle, .finished, .gitMissing: false
        }
    }

    var totalGitSize: UInt64 { GitRepoRanking.totalGitSize(repos) }
    var totalLFSSize: UInt64 { repos.reduce(0) { $0 &+ $1.lfsSize } }
    var dirtyCount: Int { repos.filter { $0.hasUncommittedWork == true }.count }
    var compactCandidates: [GitRepoInfo] { repos.filter { $0.objects?.wouldBenefitFromCompact == true } }

    func scan(home: String = NSHomeDirectory()) async {
        guard !isScanning else { return }
        phase = .finding
        errorMessage = nil
        isLFSInstalled = GitClient.lfsPath() != nil
        guard await GitClient.isAvailable() else {
            phase = .gitMissing
            return
        }
        let paths = await Task.detached(priority: .utility) { GitRepoFinder.find(roots: [home]) }.value
        repos = paths.map { GitRepoInfo(path: $0) }
        phase = .measuring(done: 0, total: paths.count)
        await withTaskGroup(of: GitRepoInfo.self) { group in
            var queue = paths.makeIterator()
            for _ in 0..<Self.measuringWidth {
                if let path = queue.next() { group.addTask { await GitClient.inspect(repo: path) } }
            }
            var done = 0
            for await info in group {
                done += 1
                replace(info)
                phase = .measuring(done: done, total: paths.count)
                if let path = queue.next() { group.addTask { await GitClient.inspect(repo: path) } }
            }
        }
        phase = .finished
    }

    func ask(_ action: GitRepoAction, for repo: GitRepoInfo) {
        pending = PendingGitAction(action: action, repo: repo)
    }

    func perform(_ request: PendingGitAction) async {
        let path = request.repo.path
        guard running[path] == nil else { return }
        running[path] = request.action
        outcomes[path] = nil
        defer { running[path] = nil }
        do {
            let report = switch request.action {
            case .compact: try await GitClient.compact(repo: path)
            case .pruneLFS: try await GitClient.pruneLFS(repo: path)
            }
            outcomes[path] = Self.describe(report, action: request.action)
            replace(await GitClient.inspect(repo: path))
        } catch {
            errorMessage = "\(request.action.rawValue) failed for \(request.repo.name): \(error.localizedDescription)"
        }
    }

    private func replace(_ info: GitRepoInfo) {
        var updated = repos.filter { $0.path != info.path }
        updated.append(info)
        repos = GitRepoRanking.sorted(updated)
    }

    static func describe(_ report: GitCompactReport, action: GitRepoAction) -> String {
        let change = "\(Format.bytes(report.before)) → \(Format.bytes(report.after))"
        guard report.saved > 0 else { return "\(action.rawValue): already compact (\(change))" }
        let percent = Int((report.savedFraction * 100).rounded())
        return "\(action.rawValue): saved \(Format.bytes(report.saved)) (\(percent)%), \(change)"
    }
}

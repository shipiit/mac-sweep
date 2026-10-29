import Foundation
import os

public enum GitSlimmingError: Error, LocalizedError, Equatable {
    case inUse(String)
    case lfsNotInstalled

    public var errorDescription: String? {
        switch self {
        case .inUse(let name): "\(name) is in use by another git process (index.lock). Try again when it finishes."
        case .lfsNotInstalled: "Git LFS isn't installed."
        }
    }
}

/// Runs read-only git queries and the two non-destructive maintenance commands (gc, lfs prune).
/// Nothing here rewrites history: no rebase, filter-branch, reflog expiry or reset is ever issued.
public enum GitClient {
    public static let gitPath = "/usr/bin/git"
    static let lfsCandidates = ["/opt/homebrew/bin/git-lfs", "/usr/local/bin/git-lfs", "/usr/bin/git-lfs"]
    static let queryTimeout: Double = 30
    static let maintenanceTimeout: Double = 900
    /// At most two git processes at once, across scans and actions.
    static let limiter = AsyncLimiter(limit: 2)
    private static let log = Logger(subsystem: Log.subsystem, category: "git-slimming")

    /// `/usr/bin/git` is a stub that prompts to install the developer tools when they're missing.
    public static func isAvailable() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: gitPath) else { return false }
        let result = try? await DevShell.run("/usr/bin/xcode-select", ["-p"], timeout: 10, tool: "xcode-select")
        return result?.status == 0
    }

    public static func lfsPath(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile) -> String? {
        ToolLocator.first(lfsCandidates, isExecutable: isExecutable)
    }

    /// Sizes from disk plus git's own view of the repository. Git is not run on a repository in use.
    public static func inspect(repo: String) async -> GitRepoInfo {
        var info = await measure(repo: repo)
        info.isInUse = GitRepoFinder.isInUse(repo: repo)
        guard !info.isInUse else { return info }
        let log = try? await git(repo, ["log", "-1", "--format=%ct"], timeout: queryTimeout)
        info.lastCommit = log.flatMap { $0.status == 0 ? GitOutputParser.commitDate($0.stdout) : nil }
        let status = try? await git(repo, ["--no-optional-locks", "status", "--porcelain"], timeout: queryTimeout)
        info.hasUncommittedWork = status.flatMap { $0.status == 0 ? GitOutputParser.hasUncommittedWork($0.stdout) : nil }
        let objects = try? await git(repo, ["count-objects", "-v"], timeout: queryTimeout)
        info.objects = objects.flatMap { $0.status == 0 ? GitOutputParser.countObjects($0.stdout) : nil }
        return info
    }

    /// Folder sizes only, measured off the caller's thread.
    public static func measure(repo: String) async -> GitRepoInfo {
        await Task.detached(priority: .utility) {
            var info = GitRepoInfo(path: repo, gitSize: DiskScanner.measure(repo + "/.git"), totalSize: DiskScanner.measure(repo))
            info.lfsSize = DiskScanner.measure(repo + "/.git/lfs") ?? 0
            return info
        }.value
    }

    /// `git gc --prune=now`: repacks and drops unreachable objects. Commits, branches, tags and reflogs stay.
    public static func compact(repo: String) async throws -> GitCompactReport {
        try await maintain(repo: repo, measuring: repo + "/.git") {
            // gc expires old reflog entries (including stashes) by default; keep them all.
            try await git(repo, ["-c", "gc.reflogExpire=never", "-c", "gc.reflogExpireUnreachable=never",
                                 "gc", "--prune=now", "--quiet"], timeout: maintenanceTimeout)
        }
    }

    /// `git lfs prune`: removes local LFS files that are neither checked out nor recent, and are already pushed.
    public static func pruneLFS(repo: String) async throws -> GitCompactReport {
        guard let lfs = lfsPath() else { throw GitSlimmingError.lfsNotInstalled }
        let path = (lfs as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
        return try await maintain(repo: repo, measuring: repo + "/.git") {
            try await limited {
                try await DevShell.run("/usr/bin/env", ["PATH=\(path)", gitPath] + safetyArguments + ["-C", repo, "lfs", "prune"],
                                       timeout: maintenanceTimeout, tool: "git lfs")
            }
        }
    }

    static func maintain(repo: String, measuring folder: String,
                         _ command: () async throws -> ShellResult) async throws -> GitCompactReport {
        let name = (repo as NSString).lastPathComponent
        guard !GitRepoFinder.isInUse(repo: repo) else { throw GitSlimmingError.inUse(name) }
        let before = await sizeOf(folder)
        let result = try await command()
        guard result.status == 0 else {
            log.error("git maintenance failed in \(repo, privacy: .private): status \(result.status)")
            throw DevCommandError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let report = GitCompactReport(before: before, after: await sizeOf(folder))
        log.info("git maintenance in \(repo, privacy: .private) saved \(report.saved) bytes")
        return report
    }

    static func git(_ repo: String, _ arguments: [String], timeout: Double) async throws -> ShellResult {
        try await limited { try await DevShell.run(gitPath, safetyArguments + ["-C", repo] + arguments, timeout: timeout, tool: "git") }
    }

    /// A scanned repository's own config must not be able to launch programs (fsmonitor hooks, pagers).
    static let safetyArguments = ["-c", "core.fsmonitor=false", "--no-pager"]

    static func limited(_ body: () async throws -> ShellResult) async throws -> ShellResult {
        await limiter.acquire()
        do {
            let result = try await body()
            await limiter.release()
            return result
        } catch {
            await limiter.release()
            throw error
        }
    }

    static func sizeOf(_ path: String) async -> UInt64 {
        await Task.detached(priority: .utility) { DiskScanner.measure(path) ?? 0 }.value
    }
}

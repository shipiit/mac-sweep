import Foundation

/// One Claude Code or Codex session with everything it left on disk.
public struct AISessionRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: AIProvider
    /// Readable project folder, e.g. "~/Documents/app".
    public let project: String
    public let modified: Date
    /// Transcript plus its subagent / tool-output folder and file-history backups.
    public let paths: [String]
    public let size: UInt64
    /// What the session was about: the title Claude gave it, or its first prompt.
    public var title: String? = nil
    /// Subagent logs, saved tool output and file backups: removable while keeping the conversation.
    public var extras: [String] = []
    public var extrasSize: UInt64 = 0

    public func age(now: Date = Date()) -> Int { max(0, Int(now.timeIntervalSince(modified) / 86_400)) }

    /// Written to in the last 15 minutes: most likely a session that is still open, so it's never removed.
    public func isActive(now: Date = Date()) -> Bool { now.timeIntervalSince(modified) < SessionInventory.activeWindow }
}

public enum SessionInventory {
    static let activeWindow: TimeInterval = 15 * 60

    /// Every session under ~/.claude/projects and ~/.codex/sessions, largest first.
    public static func all(sources: AIUsageSources = AIUsageSources(), home: String = NSHomeDirectory(),
                           measure: (String) -> UInt64? = DiskScanner.measure) -> [AISessionRecord] {
        let fileHistory = home + "/.claude/file-history"
        let claude = AIUsageScanner.transcripts(under: sources.claudeRoot).compactMap { path -> AISessionRecord? in
            // Subagent transcripts live inside a session's folder and are counted with that session.
            guard ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent == sources.claudeRoot else { return nil }
            let id = stem(path)
            let folder = (path as NSString).deletingPathExtension
            let projectFolder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let head = SessionHead.read(path)
            let project = head.workingDirectory.map { PathTools.isDescendant($0, of: home) || $0 == home ? "~" + $0.dropFirst(home.count) : $0 }
            guard var session = record(id: id, provider: .claudeCode, project: project ?? projectName(projectFolder, home: home), transcript: path,
                                       extras: [folder, fileHistory + "/" + id], measure: measure) else { return nil }
            session.title = head.title
            session.extras = [folder + "/subagents", folder + "/tool-results", fileHistory + "/" + id].filter { FileManager.default.fileExists(atPath: $0) }
            session.extrasSize = session.extras.reduce(0) { $0 + (measure($1) ?? 0) }
            return session
        }
        let codex = AIUsageScanner.transcripts(under: sources.codexRoot).compactMap { path -> AISessionRecord? in
            record(id: stem(path), provider: .codex, project: "Codex", transcript: path, extras: [], measure: measure)
        }
        return (claude + codex).sorted { $0.size > $1.size }
    }

    /// Sessions older than `days`, never an open one or one whose id is in `keeping` (sessions the user named).
    public static func old(_ sessions: [AISessionRecord], olderThanDays days: Int, keeping: Set<String>, now: Date = Date()) -> [AISessionRecord] {
        sessions.filter { $0.age(now: now) >= days && !$0.isActive(now: now) && !isKept($0.id, keeping: keeping) }
    }

    /// Codex rollout files end with the session id; Claude transcripts are named by it.
    public static func isKept(_ id: String, keeping: Set<String>) -> Bool {
        keeping.contains { id == $0 || id.hasSuffix("-" + $0) }
    }

    /// "-Users-me-Documents-app" → "~/Documents/app". Dashes inside folder names can't be told apart from
    /// separators, so this is a readable label, not a path to act on.
    public static func projectName(_ folder: String, home: String) -> String {
        let homeKey = home.replacingOccurrences(of: "/", with: "-")
        if folder == homeKey { return "~" }
        if folder.hasPrefix(homeKey + "-") {
            return "~/" + folder.dropFirst(homeKey.count + 1).replacingOccurrences(of: "-", with: "/")
        }
        if folder.hasPrefix("-private-tmp") || folder.hasPrefix("-tmp") { return "Temporary folder" }
        return folder.replacingOccurrences(of: "-", with: "/")
    }

    static func stem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private static func record(id: String, provider: AIProvider, project: String, transcript: String, extras: [String],
                               measure: (String) -> UInt64?) -> AISessionRecord? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: transcript),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        var paths = [transcript]
        var size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        for extra in extras where FileManager.default.fileExists(atPath: extra) {
            paths.append(extra)
            size += measure(extra) ?? 0
        }
        return AISessionRecord(id: id, provider: provider, project: project, modified: modified, paths: paths, size: size)
    }
}

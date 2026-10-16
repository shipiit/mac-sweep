import Foundation
import os

/// Per-file usage cache: only transcripts whose size or modification time changed are re-read,
/// so after the first pass a refresh over gigabytes of history takes moments.
public struct AIUsageIndex: Codable, Sendable, Equatable {
    public var files: [String: FileUsage] = [:]

    public init() {}

    public var entries: [UsageEntry] { files.values.flatMap(\.entries) }
    public var events: [UsageEvent] { files.values.flatMap(\.events) }
    /// Latest known value for each Codex window, even if they were observed in different sessions.
    public var latestCodexLimits: CodexRateLimits? {
        let all = files.values.compactMap(\.rateLimits).sorted { $0.observedAt < $1.observedAt }
        guard let newest = all.last else { return nil }
        return CodexRateLimits(observedAt: newest.observedAt,
                               primary: all.last { $0.primary != nil }?.primary,
                               secondary: all.last { $0.secondary != nil }?.secondary)
    }

    public var sessionTitles: [String: String] {
        files.values.reduce(into: [:]) { result, file in result.merge(file.titles ?? [:]) { current, _ in current } }
    }
}

public struct AIUsageSources: Sendable {
    public let claudeRoot: String
    public let codexRoot: String

    public init(home: String = NSHomeDirectory()) {
        claudeRoot = home + "/.claude/projects"
        codexRoot = home + "/.codex/sessions"
    }

    public init(claudeRoot: String, codexRoot: String) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
    }
}

public enum AIUsageScanner {
    private static let log = Logger(subsystem: Log.subsystem, category: "ai-usage")

    public struct Progress: Sendable {
        public var filesDone: Int
        public var filesTotal: Int
    }

    /// Brings `index` up to date with the transcripts on disk. Deleted transcripts drop out.
    public static func refresh(_ index: AIUsageIndex, sources: AIUsageSources = AIUsageSources(), now: Date = Date(),
                               progress: (@Sendable (Progress) -> Void)? = nil) -> AIUsageIndex {
        let claude = transcripts(under: sources.claudeRoot)
        let codex = transcripts(under: sources.codexRoot)
        var updated = AIUsageIndex()
        let all = claude.map { ($0, AIProvider.claudeCode) } + codex.map { ($0, AIProvider.codex) }
        for (offset, (path, provider)) in all.enumerated() {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            // Recent files are re-read so their 24-hour event window stays current.
            if let cached = index.files[path], cached.size == size, cached.modified == modified,
               provider == .codex || (cached.titles != nil && cached.parserVersion == FileUsage.currentParserVersion),
               now.timeIntervalSince(modified) > 24 * 3_600 || cached.events.isEmpty {
                updated.files[path] = cached
            } else {
                switch provider {
                case .claudeCode:
                    let (entries, events, titles) = TranscriptParsers.parseClaudeWithTitles(path: path, now: now)
                    updated.files[path] = FileUsage(size: size, modified: modified, entries: entries, events: events, rateLimits: nil, titles: titles,
                                                       parserVersion: FileUsage.currentParserVersion)
                case .codex:
                    let (entries, events, limits) = TranscriptParsers.parseCodex(path: path, now: now)
                    updated.files[path] = FileUsage(size: size, modified: modified, entries: entries, events: events, rateLimits: limits, titles: [:],
                                                       parserVersion: FileUsage.currentParserVersion)
                }
            }
            if offset % 25 == 0 { progress?(Progress(filesDone: offset, filesTotal: all.count)) }
        }
        log.info("AI usage index: \(updated.files.count) transcripts")
        return updated
    }

    static func transcripts(under root: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var paths: [String] = []
        while let relative = enumerator.nextObject() as? String {
            if relative.hasSuffix(".jsonl") { paths.append(root + "/" + relative) }
        }
        return paths
    }
}

public struct AIUsageStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var standard: AIUsageStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return AIUsageStore(url: base.appendingPathComponent("MacSweep/ai-usage-index.plist"))
    }

    public func load() -> AIUsageIndex {
        guard let data = try? Data(contentsOf: url), let index = try? PropertyListDecoder().decode(AIUsageIndex.self, from: data) else {
            return AIUsageIndex()
        }
        return index
    }

    public func save(_ index: AIUsageIndex) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(index).write(to: url, options: .atomic)
    }
}

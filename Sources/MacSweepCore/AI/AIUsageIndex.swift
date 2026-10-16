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
        let all = claude.map { ($0, AIProvider.claudeCode) } + codex.map { ($0, AIProvider.codex) }
        let cutoff = now.addingTimeInterval(-24 * 3_600)
        var updated = AIUsageIndex()
        var work: [Job] = []
        // Unchanged files cost one stat; only new or grown files are parsed.
        for (path, provider) in all {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            let cached = index.files[path]
            if var cached, cached.size == size, cached.modified == modified,
               provider == .codex || (cached.titles != nil && cached.parserVersion == FileUsage.currentParserVersion) {
                cached.events.removeAll { $0.time < cutoff }
                updated.files[path] = cached
            } else {
                work.append(Job(path: path, provider: provider, size: size, modified: modified, cached: cached))
            }
        }
        let results = parse(work, now: now, progress: progress)
        for (path, usage) in results { updated.files[path] = usage }
        log.info("AI usage index: \(updated.files.count) transcripts, \(work.count) read")
        return updated
    }

    struct Job: Sendable {
        let path: String
        let provider: AIProvider
        let size: UInt64
        let modified: Date
        let cached: FileUsage?
    }

    /// Parses on 4 threads: fast first index without pinning every core.
    static func parse(_ jobs: [Job], now: Date, progress: (@Sendable (Progress) -> Void)?) -> [(String, FileUsage)] {
        guard !jobs.isEmpty else { return [] }
        let lock = NSLock()
        var results: [(String, FileUsage)] = []
        var done = 0
        let stripes = min(4, jobs.count)
        DispatchQueue.concurrentPerform(iterations: stripes) { stripe in
            for index in stride(from: stripe, to: jobs.count, by: stripes) {
                let usage = autoreleasepool { read(jobs[index], now: now) }
                lock.withLock {
                    results.append((jobs[index].path, usage))
                    done += 1
                    if done % 25 == 0 || done == jobs.count { progress?(Progress(filesDone: done, filesTotal: jobs.count)) }
                }
            }
        }
        return results
    }

    static func read(_ job: Job, now: Date) -> FileUsage {
        let version = FileUsage.currentParserVersion
        switch job.provider {
        case .claudeCode:
            if let cached = job.cached, cached.parserVersion == version, cached.titles != nil,
               let offset = cached.offset, job.size > cached.size {
                let chunk = TranscriptParsers.parseClaude(path: job.path, from: offset, recentKeys: cached.recentKeys ?? [], now: now)
                return cached.appending(chunk, size: job.size, modified: job.modified, now: now)
            }
            let chunk = TranscriptParsers.parseClaude(path: job.path, from: 0, recentKeys: [], now: now)
            return FileUsage(size: job.size, modified: job.modified, entries: chunk.entries, events: chunk.events, rateLimits: nil,
                             titles: chunk.titles, parserVersion: version, offset: chunk.endOffset, recentKeys: chunk.recentKeys)
        case .codex:
            let (entries, events, limits) = TranscriptParsers.parseCodex(path: job.path, now: now)
            return FileUsage(size: job.size, modified: job.modified, entries: entries, events: events, rateLimits: limits,
                             titles: [:], parserVersion: version)
        }
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

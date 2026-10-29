import Foundation

/// Old Claude Code / Codex transcripts: they power `/resume` and history search, and grow to gigabytes.
public enum TranscriptCleanup {
    /// Transcripts untouched for `days`, except sessions in `keeping` (named sessions the user wants to keep).
    /// A transcript's session id is its file name without the extension (Codex rollouts end with it).
    public static func old(olderThanDays days: Int, keeping: Set<String> = [], sources: AIUsageSources = AIUsageSources(),
                           now: Date = Date()) -> [CleanupTarget] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return (AIUsageScanner.transcripts(under: sources.claudeRoot) + AIUsageScanner.transcripts(under: sources.codexRoot))
            .compactMap { path -> CleanupTarget? in
                let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                guard !keeping.contains(where: { stem == $0 || stem.hasSuffix("-" + $0) }),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let modified = attributes[.modificationDate] as? Date, modified < cutoff
                else { return nil }
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                return CleanupTarget(path: path, size: size, modified: modified)
            }
            .sorted { $0.size > $1.size }
    }
}

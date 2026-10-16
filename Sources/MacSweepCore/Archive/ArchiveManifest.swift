import Darwin
import Foundation

public enum ArchiveError: Error, LocalizedError, Equatable {
    case sourceRefused(String)
    case destinationInsideSource
    case destinationMissing
    case notEnoughSpace(needed: UInt64, available: UInt64)
    case unreadable(String)
    case toolFailed(String)
    case verificationFailed(String)
    case changedSinceArchiving

    public var errorDescription: String? {
        switch self {
        case .sourceRefused(let reason): "This folder can't be archived: \(reason)"
        case .destinationInsideSource: "Choose a destination outside the folder being archived."
        case .destinationMissing: "The destination folder is not available. Is the drive connected?"
        case .notEnoughSpace(let needed, let available):
            "Not enough free space: about \(ByteCountFormatter.string(fromByteCount: Int64(clamping: needed), countStyle: .file)) needed, \(ByteCountFormatter.string(fromByteCount: Int64(clamping: available), countStyle: .file)) available."
        case .unreadable(let path): "Some items can't be read, so the archive would be incomplete: \((path as NSString).lastPathComponent)"
        case .toolFailed(let message): "Archiving failed: \(message)"
        case .verificationFailed(let message): "The archive did not verify, so the original was left alone. \(message)"
        case .changedSinceArchiving: "The folder or archive changed after verification. Archive it again before removing it."
        }
    }
}

/// Every file, symlink and folder below a root, keyed by relative path, with sizes.
/// Comparing a source's manifest to the extracted archive's proves nothing was dropped or truncated.
public struct ArchiveManifest: Sendable, Equatable {
    public var entries: [String: UInt64]

    public init(entries: [String: UInt64]) { self.entries = entries }

    public var fileCount: Int { entries.keys.filter { !$0.hasSuffix("/") }.count }
    public var totalBytes: UInt64 { entries.values.reduce(0, +) }

    /// Fails on anything unreadable: a folder that can't be listed would be silently missing from both sides.
    public static func build(root: String) throws -> ArchiveManifest {
        guard let cPath = strdup(root) else { throw ArchiveError.unreadable(root) }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { throw ArchiveError.unreadable(root) }
        defer { fts_close(fts) }
        var entries: [String: UInt64] = [:]
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            switch info {
            case FTS_DNR, FTS_ERR, FTS_NS:
                throw ArchiveError.unreadable(path)
            case FTS_DP, FTS_DC:
                continue
            default:
                guard entry.pointee.fts_level > FTS_ROOTLEVEL, let stat = entry.pointee.fts_statp?.pointee else { continue }
                let relative = String(path.dropFirst(root.count + 1)).precomposedStringWithCanonicalMapping
                if isMetadata(relative) { continue }
                if info == FTS_D {
                    entries[relative + "/"] = 0
                } else {
                    entries[relative] = UInt64(max(stat.st_size, 0))
                }
            }
        }
        return ArchiveManifest(entries: entries)
    }

    /// Differences that mean the archive is not a faithful copy, as readable lines; empty when it matches.
    public func problems(comparedTo extracted: ArchiveManifest) -> [String] {
        var problems: [String] = []
        for (path, size) in entries.sorted(by: { $0.key < $1.key }) {
            guard let other = extracted.entries[path] else {
                problems.append("Missing: \(path)")
                continue
            }
            if other != size { problems.append("Size differs: \(path)") }
        }
        let extra = extracted.entries.keys.filter { entries[$0] == nil }.sorted()
        problems += extra.map { "Unexpected: \($0)" }
        return problems
    }

    /// AppleDouble and resource-fork side files that ditto adds or folds back in.
    static func isMetadata(_ relative: String) -> Bool {
        relative.hasPrefix("__MACOSX") || (relative as NSString).lastPathComponent.hasPrefix("._")
    }
}

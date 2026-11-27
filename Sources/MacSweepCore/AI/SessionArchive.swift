import Foundation
import os

/// A transcript that was compressed out of the way, with what's needed to put it back.
public struct ArchivedSession: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let originalPath: String
    public let project: String
    public let title: String?
    public let originalSize: UInt64
    public var archivedSize: UInt64
    public let modified: Date
    public var saved: UInt64 { originalSize > archivedSize ? originalSize - archivedSize : 0 }
}

/// Compresses a session's transcript into MacSweep's archive and restores it byte for byte.
/// The original is removed only after the compressed copy has been decompressed and compared with it.
public enum SessionArchive {
    private static let log = Logger(subsystem: Log.subsystem, category: "session-archive")

    public static func root(home: String = NSHomeDirectory()) -> String { home + "/Library/Application Support/MacSweep/SessionArchive" }

    static func archivePath(_ id: String, root: String) -> String { root + "/" + id + ".jsonl.gz" }
    static func recordPath(_ id: String, root: String) -> String { root + "/" + id + ".json" }

    /// Session ids are UUIDs or Codex rollout names; anything else never becomes part of a path.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." } && !id.contains("..")
    }

    public static func list(root: String = root()) -> [ArchivedSession] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasSuffix(".json") }
            .compactMap { name -> ArchivedSession? in
                guard let data = FileManager.default.contents(atPath: root + "/" + name),
                      let record = try? JSONDecoder().decode(ArchivedSession.self, from: data),
                      FileManager.default.fileExists(atPath: archivePath(record.id, root: root)) else { return nil }
                return record
            }
            .sorted { $0.originalSize > $1.originalSize }
    }

    /// Compresses the transcript (the first path), proves the copy is identical, then deletes the original.
    public static func archive(_ session: AISessionRecord, root: String = root(), home: String = NSHomeDirectory()) async throws -> ArchivedSession {
        guard let transcript = session.paths.first, isValidID(session.id), PathGuard.reason(transcript, home: home) == nil,
              !session.isActive() else { throw DevCommandError.invalidName(session.id) }
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let archive = archivePath(session.id, root: root)
        guard !FileManager.default.fileExists(atPath: archive) else { throw DevCommandError.failed("This session is already archived.") }
        let partial = archive + ".partial"
        defer { try? FileManager.default.removeItem(atPath: partial) }
        let packed = try await Shell.run("/bin/sh", ["-c", "/usr/bin/gzip -c \"$1\" > \"$2\"", "sh", transcript, partial])
        guard packed.status == 0 else { throw DevCommandError.failed(packed.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let same = try await Shell.run("/bin/sh", ["-c", "/usr/bin/gzip -dc \"$1\" | /usr/bin/cmp -s - \"$2\"", "sh", partial, transcript])
        guard same.status == 0 else { throw DevCommandError.failed("The compressed copy didn't match the original, so nothing was removed.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: transcript)
        let record = ArchivedSession(
            id: session.id, originalPath: transcript, project: session.project, title: session.title,
            originalSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            archivedSize: ((try? FileManager.default.attributesOfItem(atPath: partial))?[.size] as? NSNumber)?.uint64Value ?? 0,
            modified: attributes[.modificationDate] as? Date ?? session.modified)
        try JSONEncoder().encode(record).write(to: URL(fileURLWithPath: recordPath(session.id, root: root)), options: .atomic)
        try FileManager.default.moveItem(atPath: partial, toPath: archive)
        try FileManager.default.removeItem(atPath: transcript)
        log.info("archived a session transcript (\(record.originalSize) → \(record.archivedSize) bytes)")
        return record
    }

    /// Puts the transcript back where it was, with its original date, and removes the archive.
    public static func restore(_ record: ArchivedSession, root: String = root(), home: String = NSHomeDirectory()) async throws {
        let archive = archivePath(record.id, root: root)
        guard isValidID(record.id), PathGuard.reason(record.originalPath, home: home) == nil else { throw DevCommandError.invalidName(record.id) }
        guard !FileManager.default.fileExists(atPath: record.originalPath) else {
            throw DevCommandError.failed("A transcript already exists at the original location.")
        }
        try FileManager.default.createDirectory(atPath: (record.originalPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let partial = record.originalPath + ".restoring"
        defer { try? FileManager.default.removeItem(atPath: partial) }
        let unpacked = try await Shell.run("/bin/sh", ["-c", "/usr/bin/gzip -dc \"$1\" > \"$2\"", "sh", archive, partial])
        let size = ((try? FileManager.default.attributesOfItem(atPath: partial))?[.size] as? NSNumber)?.uint64Value
        guard unpacked.status == 0, size == record.originalSize else { throw DevCommandError.failed("The archive couldn't be read back in full, so it was left as it is.") }
        try FileManager.default.setAttributes([.modificationDate: record.modified], ofItemAtPath: partial)
        try FileManager.default.moveItem(atPath: partial, toPath: record.originalPath)
        try? FileManager.default.removeItem(atPath: archive)
        try? FileManager.default.removeItem(atPath: recordPath(record.id, root: root))
        log.info("restored a session transcript (\(record.originalSize) bytes)")
    }
}

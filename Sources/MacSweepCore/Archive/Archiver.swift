import Foundation
import os

/// Proof that an archive was checked against its source. Only `Archiver` can create one, so the
/// original can never be trashed without a successful verification first.
public struct VerifiedArchive: Sendable, Equatable {
    public let source: String
    public let archivePath: String
    public let archiveSize: UInt64
    public let fileCount: Int
    public let totalBytes: UInt64
    let manifest: ArchiveManifest
}

/// Zips a folder with `ditto`, verifies the zip, and only then lets the original go to the Trash.
public enum Archiver {
    private static let log = Logger(subsystem: Log.subsystem, category: "archive")

    /// `<name>.zip`, or `<name> 2.zip`… so an existing archive is never overwritten.
    public static func archivePath(for source: String, in destination: String, exists: (String) -> Bool) -> String {
        let name = (source as NSString).lastPathComponent
        var candidate = destination + "/" + name + ".zip"
        var counter = 2
        while exists(candidate) {
            candidate = destination + "/\(name) \(counter).zip"
            counter += 1
        }
        return candidate
    }

    /// Checks that run before anything is written.
    public static func validate(source: String, destination: String, home: String, needed: UInt64, available: UInt64?) throws {
        if let reason = PathGuard.reason(source, home: home) { throw ArchiveError.sourceRefused(reason) }
        if destination == source || PathTools.isDescendant(destination, of: source) { throw ArchiveError.destinationInsideSource }
        guard let available else { throw ArchiveError.destinationMissing }
        if available < needed { throw ArchiveError.notEnoughSpace(needed: needed, available: available) }
    }

    public static func archiveAndVerify(
        source: String, destination: String, estimatedSize: UInt64, home: String = NSHomeDirectory()
    ) async throws -> VerifiedArchive {
        let source = (source as NSString).standardizingPath
        let destination = URL(fileURLWithPath: destination).resolvingSymlinksInPath().path
        // Headroom for the zip itself; extraction for verification is checked separately.
        try validate(source: source, destination: destination, home: home, needed: estimatedSize + estimatedSize / 10 + (50 << 20),
                     available: freeSpace(destination))
        let manifest = try ArchiveManifest.build(root: source)
        let finalPath = archivePath(for: source, in: destination) { FileManager.default.fileExists(atPath: $0) }
        let partial = destination + "/.\(UUID().uuidString).zip.partial"
        defer { try? FileManager.default.removeItem(atPath: partial) }

        log.info("archiving \(source, privacy: .private) to \(destination, privacy: .private)")
        let created = try await ProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source, partial])
        guard created.status == 0 else { throw ArchiveError.toolFailed(created.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        // moveItem refuses to replace an existing file, so a zip that appeared meanwhile is never clobbered.
        do {
            try FileManager.default.moveItem(atPath: partial, toPath: finalPath)
        } catch {
            throw ArchiveError.toolFailed(error.localizedDescription)
        }
        do {
            return try await verify(archive: finalPath, source: source, sourceManifest: manifest)
        } catch {
            log.error("verification failed for \(finalPath, privacy: .private): \(error.localizedDescription, privacy: .public)")
            // An archive that didn't verify must not be mistaken for a good backup later.
            try? FileManager.default.removeItem(atPath: finalPath)
            throw error
        }
    }

    /// CRC-checks the zip, extracts it to a scratch folder and compares every entry with the source.
    static func verify(archive: String, source: String, sourceManifest: ArchiveManifest) async throws -> VerifiedArchive {
        let integrity = try await ProcessRunner.run("/usr/bin/unzip", ["-tqq", archive])
        guard integrity.status == 0 else { throw ArchiveError.verificationFailed("The zip failed its integrity test.") }

        let scratch = try scratchDirectory(near: archive, needed: sourceManifest.totalBytes)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let extracted = try await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", archive, scratch.path])
        guard extracted.status == 0 else { throw ArchiveError.verificationFailed("The zip could not be extracted.") }

        let root = scratch.appendingPathComponent((source as NSString).lastPathComponent).path
        let copy = try ArchiveManifest.build(root: root)
        let problems = sourceManifest.problems(comparedTo: copy)
        guard problems.isEmpty else {
            throw ArchiveError.verificationFailed("\(problems.count) differences, e.g. \(problems[0]).")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: archive)[.size] as? NSNumber)?.uint64Value ?? 0
        log.info("verified \(archive, privacy: .private): \(sourceManifest.fileCount) files")
        return VerifiedArchive(source: source, archivePath: archive, archiveSize: size, fileCount: sourceManifest.fileCount,
                               totalBytes: sourceManifest.totalBytes, manifest: sourceManifest)
    }

    /// Trashes the original only if the verified zip is still in place and the folder hasn't changed since.
    public static func trashOriginal(
        _ verified: VerifiedArchive, home: String = NSHomeDirectory(), extraProtected: [String] = [Bundle.main.bundlePath]
    ) -> RemovalResult {
        let archiveSize = (try? FileManager.default.attributesOfItem(atPath: verified.archivePath)[.size] as? NSNumber)?.uint64Value
        let current = try? ArchiveManifest.build(root: verified.source)
        guard archiveSize == verified.archiveSize, current == verified.manifest else {
            let reason = ArchiveError.changedSinceArchiving.errorDescription ?? ""
            return RemovalResult(path: verified.source, size: verified.totalBytes, outcome: .refused(reason))
        }
        let target = CleanupTarget(path: verified.source, size: verified.totalBytes)
        return Cleaner.remove([target], mode: .trash, home: home, extraProtected: extraProtected)[0]
    }

    static func freeSpace(_ path: String) -> UInt64? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
        return values?.volumeAvailableCapacity.map { UInt64(max($0, 0)) }
    }

    /// A temporary folder on the archive's volume, or the system temp volume if that one is too full.
    private static func scratchDirectory(near archive: String, needed: UInt64) throws -> URL {
        let destination = URL(fileURLWithPath: (archive as NSString).deletingLastPathComponent)
        let options = [destination.appendingPathComponent(".macsweep-verify-\(UUID().uuidString)"),
                       FileManager.default.temporaryDirectory.appendingPathComponent("macsweep-verify-\(UUID().uuidString)")]
        for option in options {
            let parent = option.deletingLastPathComponent().path
            guard let free = freeSpace(parent), free > needed + needed / 10 else { continue }
            do {
                try FileManager.default.createDirectory(at: option, withIntermediateDirectories: false)
                return option
            } catch {
                continue
            }
        }
        throw ArchiveError.verificationFailed("There isn't enough free space to unpack the archive for checking.")
    }
}

import Foundation
import os

/// Chromium browsers copy their whole app into the per-user temp folder at launch to check its code signature,
/// and leave the copy behind whenever they don't quit cleanly (crash, force-quit, restart with the browser open,
/// self-update). Hundreds pile up in `/var/folders/…/X/<bundle id>.code_sign_clone/`.
public struct CodeSignClone: Sendable, Equatable, Identifiable {
    public let path: String
    public let bundleID: String
    /// Allocated size. Copies of the same browser version share blocks on APFS, so the real gain can be smaller.
    public let size: UInt64
    public let modified: Date
    public var id: String { path }
}

public enum CodeSignClones {
    private static let log = Logger(subsystem: Log.subsystem, category: "code-sign-clones")
    static let containerSuffix = ".code_sign_clone"
    static let clonePrefix = "code_sign_clone."

    /// `/var/folders/xx/yyyy/` — the parent of the per-user temp (T) and cache (C) folders.
    public static func userTempRoot() -> String? {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) > 0 else { return nil }
        let temp = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return ((temp as NSString).standardizingPath as NSString).deletingLastPathComponent
    }

    public static func find(tempRoot: String? = userTempRoot(), measure: (String) -> UInt64? = DiskScanner.measure) -> [CodeSignClone] {
        guard let tempRoot else { return [] }
        let base = tempRoot + "/X"
        let containers = ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []).filter { $0.hasSuffix(containerSuffix) }
        return containers.flatMap { container -> [CodeSignClone] in
            let bundleID = String(container.dropLast(containerSuffix.count))
            let folder = base + "/" + container
            let clones = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasPrefix(clonePrefix) }
            return clones.compactMap { name -> CodeSignClone? in
                let path = folder + "/" + name
                let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
                return autoreleasepool { CodeSignClone(path: path, bundleID: bundleID, size: measure(path) ?? 0, modified: modified) }
            }
        }
        .sorted { $0.modified < $1.modified }
    }

    /// Only exact `<tempRoot>/X/<id>.code_sign_clone/code_sign_clone.*` folders: nothing else in the temp area.
    public static func isClonePath(_ path: String, tempRoot: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let name = (standardized as NSString).lastPathComponent
        let container = (standardized as NSString).deletingLastPathComponent
        return name.hasPrefix(clonePrefix) && name.count > clonePrefix.count && !name.contains("/")
            && (container as NSString).lastPathComponent.hasSuffix(containerSuffix)
            && (container as NSString).deletingLastPathComponent == tempRoot + "/X"
    }

    /// Deletes clones (they are throwaway copies; the browser makes a fresh one at its next launch).
    /// Refuses anything that isn't a clone folder and any clone of a browser that's running.
    public static func remove(_ clones: [CodeSignClone], tempRoot: String? = userTempRoot(), isRunning: (String) -> Bool) -> [RemovalResult] {
        clones.map { clone in
            guard let tempRoot, isClonePath(clone.path, tempRoot: tempRoot) else {
                return RemovalResult(path: clone.path, size: clone.size, outcome: .refused("Not a browser code-sign copy."))
            }
            guard !isRunning(clone.bundleID) else {
                return RemovalResult(path: clone.path, size: clone.size, outcome: .refused("Quit the browser first."))
            }
            do {
                try FileManager.default.removeItem(atPath: clone.path)
                return RemovalResult(path: clone.path, size: clone.size, outcome: .removed)
            } catch {
                log.error("could not remove a code-sign copy: \(error.localizedDescription, privacy: .public)")
                return RemovalResult(path: clone.path, size: clone.size, outcome: .failed(error.localizedDescription))
            }
        }
    }
}

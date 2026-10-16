import Foundation
import os

/// Permanent deletion for files the user picks, including ones Finder refuses because they're locked.
/// On SSDs and APFS no app can guarantee old blocks are overwritten; FileVault encryption is what
/// keeps deleted data unreadable. The UI says so plainly.
public enum Shredder {
    private static let log = Logger(subsystem: Log.subsystem, category: "shredder")

    public struct Outcome: Sendable, Equatable {
        public let path: String
        public let error: String?
    }

    public static func shred(_ paths: [String], home: String = NSHomeDirectory()) -> [Outcome] {
        paths.map { path in
            if let reason = PathGuard.reason(path, home: home, extraProtected: [Bundle.main.bundlePath]) {
                return Outcome(path: path, error: reason)
            }
            do {
                try unlock(path)
                try FileManager.default.removeItem(atPath: path)
                log.info("shredded \(path, privacy: .private)")
                return Outcome(path: path, error: nil)
            } catch {
                return Outcome(path: path, error: error.localizedDescription)
            }
        }
    }

    /// Clears the user-immutable ("Locked" in Finder) flag on a file or every item in a folder.
    static func unlock(_ path: String) throws {
        let fm = FileManager.default
        try? fm.setAttributes([.immutable: false], ofItemAtPath: path)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              let enumerator = fm.enumerator(atPath: path)
        else { return }
        while let relative = enumerator.nextObject() as? String {
            try? fm.setAttributes([.immutable: false], ofItemAtPath: path + "/" + relative)
        }
    }
}

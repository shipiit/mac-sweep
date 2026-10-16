import Darwin
import Foundation

public struct TrashBin: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let size: UInt64
    public let itemCount: Int

    public var id: String { path }
}

/// Every Trash the user owns: home Trash plus per-volume `.Trashes/<uid>` on external drives.
public enum TrashBins {
    public static func list(home: String = NSHomeDirectory(), volumesRoot: String = "/Volumes", uid: uid_t = getuid()) -> [TrashBin] {
        var bins: [TrashBin] = []
        if let bin = bin(name: "Mac Trash", path: home + "/.Trash") { bins.append(bin) }
        for volume in (try? FileManager.default.contentsOfDirectory(atPath: volumesRoot)) ?? [] {
            let path = "\(volumesRoot)/\(volume)/.Trashes/\(uid)"
            if let bin = bin(name: volume, path: path) { bins.append(bin) }
        }
        return bins
    }

    static func bin(name: String, path: String) -> TrashBin? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        let visible = entries.filter { $0 != ".DS_Store" }
        let size = visible.reduce(UInt64(0)) { $0 + (DiskScanner.measure(path + "/" + $1) ?? 0) }
        return TrashBin(name: name, path: path, size: size, itemCount: visible.count)
    }

    /// Permanently deletes a bin's contents (never the bin folder itself).
    public static func empty(_ bin: TrashBin) -> (removed: Int, failed: [String]) {
        let fm = FileManager.default
        var removed = 0
        var failed: [String] = []
        for entry in (try? fm.contentsOfDirectory(atPath: bin.path)) ?? [] where entry != ".DS_Store" {
            let path = bin.path + "/" + entry
            do {
                try Shredder.unlock(path)
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                failed.append(entry)
            }
        }
        return (removed, failed)
    }
}

public struct MailStorageItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// Copies Mail saves when you open or Quick Look an attachment.
        case downloads = "Opened attachment copies"
        /// Cached attachments of messages; IMAP/Exchange accounts re-download them, POP accounts may not.
        case cachedAttachments = "Cached attachments"
    }

    public let kind: Kind
    public let path: String
    public let size: UInt64

    public var id: String { path }
}

public enum MailAttachments {
    public static func scan(home: String = NSHomeDirectory()) -> [MailStorageItem] {
        var items: [MailStorageItem] = []
        let downloads = home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        if let size = DiskScanner.measure(downloads), size > 0 {
            items.append(MailStorageItem(kind: .downloads, path: downloads, size: size))
        }
        let mailRoot = home + "/Library/Mail"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: mailRoot)) ?? []).filter { $0.hasPrefix("V") }
        for version in versions {
            let base = mailRoot + "/" + version
            guard let enumerator = FileManager.default.enumerator(atPath: base) else { continue }
            while let relative = enumerator.nextObject() as? String {
                guard (relative as NSString).lastPathComponent == "Attachments" else { continue }
                enumerator.skipDescendants()
                let path = base + "/" + relative
                if let size = DiskScanner.measure(path), size > 0 {
                    items.append(MailStorageItem(kind: .cachedAttachments, path: path, size: size))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}

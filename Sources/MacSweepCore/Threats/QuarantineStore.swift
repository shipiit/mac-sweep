import Foundation

public struct QuarantinedItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public let storedPath: String
    public let date: Date
    public let reasons: [String]
    public let origin: String?
    /// Files (relative to the item, "" for the item itself) that were executable, so restore puts back exactly those bits.
    public let executables: [String]

    public var name: String { (originalPath as NSString).lastPathComponent }
}

/// Moves suspicious files into MacSweep's quarantine folder (no execute permission), where they can be
/// restored or deleted. Nothing is ever deleted without the user asking.
public struct QuarantineStore: Sendable {
    public let root: String

    public enum StoreError: Error, LocalizedError, Equatable {
        case missing, destinationTaken(String), moveFailed(String)
        public var errorDescription: String? {
            switch self {
            case .missing: "The file is no longer there."
            case .destinationTaken(let path): "Something already exists at \(path)."
            case .moveFailed(let reason): reason
            }
        }
    }

    public init(root: String) { self.root = root }

    public static var standard: QuarantineStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory() + "/Library/Application Support"
        return QuarantineStore(root: base + "/MacSweep/Quarantine")
    }

    private var manifestPath: String { root + "/manifest.json" }

    public func items() -> [QuarantinedItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let items = try? decoder.decode([QuarantinedItem].self, from: data) else { return [] }
        return items.sorted { $0.date > $1.date }
    }

    @discardableResult
    public func quarantine(_ verdict: ThreatVerdict, now: Date = Date()) throws -> QuarantinedItem {
        let source = verdict.facts.path
        let manager = FileManager.default
        guard manager.fileExists(atPath: source) else { throw StoreError.missing }
        let id = UUID()
        let folder = root + "/" + id.uuidString
        let stored = folder + "/" + verdict.facts.name
        do {
            try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try manager.moveItem(atPath: source, toPath: stored)
        } catch {
            try? manager.removeItem(atPath: folder)
            throw StoreError.moveFailed(error.localizedDescription)
        }
        let executables = removeExecute(stored)
        let item = QuarantinedItem(id: id, originalPath: source, storedPath: stored, date: now, reasons: verdict.reasons,
                                   origin: verdict.facts.origin, executables: executables)
        try save(items() + [item])
        return item
    }

    public func restore(_ item: QuarantinedItem) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: item.storedPath) else { throw StoreError.missing }
        guard !manager.fileExists(atPath: item.originalPath) else { throw StoreError.destinationTaken(item.originalPath) }
        do {
            try manager.moveItem(atPath: item.storedPath, toPath: item.originalPath)
        } catch {
            throw StoreError.moveFailed(error.localizedDescription)
        }
        for relative in item.executables {
            let path = relative.isEmpty ? item.originalPath : item.originalPath + "/" + relative
            if let mode = (try? manager.attributesOfItem(atPath: path))?[.posixPermissions] as? Int {
                try? manager.setAttributes([.posixPermissions: mode | 0o111], ofItemAtPath: path)
            }
        }
        try? manager.removeItem(atPath: (item.storedPath as NSString).deletingLastPathComponent)
        try save(items().filter { $0.id != item.id })
    }

    /// Moves the quarantined copy to the Trash (still recoverable from there).
    public func discard(_ item: QuarantinedItem) throws {
        let folder = (item.storedPath as NSString).deletingLastPathComponent
        if FileManager.default.fileExists(atPath: folder) {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: folder), resultingItemURL: nil)
        }
        try save(items().filter { $0.id != item.id })
    }

    private func save(_ items: [QuarantinedItem]) throws {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: URL(fileURLWithPath: manifestPath), options: .atomic)
    }

    /// Clears execute bits on the file, or on every file inside a bundle; returns which ones had them.
    private func removeExecute(_ path: String) -> [String] {
        var relatives = [""]
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let child as String in enumerator { relatives.append(child) }
        }
        var executables: [String] = []
        for relative in relatives {
            let item = relative.isEmpty ? path : path + "/" + relative
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let mode = (try? FileManager.default.attributesOfItem(atPath: item))?[.posixPermissions] as? Int,
                  mode & 0o111 != 0 else { continue }
            executables.append(relative)
            try? FileManager.default.setAttributes([.posixPermissions: mode & ~0o111], ofItemAtPath: item)
        }
        return executables
    }
}
